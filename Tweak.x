// WeidianGrab — 微店买家版抢单/抓包 tweak
//
// 两条抓取通路，因为微店是 ObjC + Flutter 混合体：
//   1. NSURLSession  —— 原生页面的网络请求
//   2. SSL_write     —— Flutter(dart:io) 走 BoringSSL，NSURLSession 看不到
//
// 工作模式由 /var/mobile/Library/Preferences/com.koudai.weidian.grab.json 控制：
//   capture  只记录
//   replay   命中 match 后按 repeat/intervalMs 高频重放，直到响应含 successContains
//
// 重放走自己的 NSURLSession，不依赖 App 内部状态，所以只要能抓到一次完整的
// 请求（URL + 方法 + 头 + body），就能脱离页面反复打。

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

#define GRAB_LOG_PATH   @"/var/mobile/Library/Logs/WeidianGrab.log"
#define GRAB_CONF_PATH  @"/var/mobile/Library/Preferences/com.koudai.weidian.grab.json"

static NSMutableDictionary *gConf = nil;
static NSLock *gLock = nil;
static BOOL gReplaying = NO;
static BOOL gDone = NO;
static NSInteger gSent = 0;

#pragma mark - 日志

static void grab_log(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], msg];

    [gLock lock];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:GRAB_LOG_PATH];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:GRAB_LOG_PATH contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:GRAB_LOG_PATH];
    }
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
    [gLock unlock];
}

#pragma mark - 配置

static NSDictionary *grab_defaults(void) {
    return @{
        @"enabled": @YES,
        @"mode": @"capture",              // capture | replay
        @"match": @"",                     // URL 或 body 里的子串，空=不重放
        @"repeat": @200,
        @"intervalMs": @80,
        @"successContains": @"",
        @"stopOnSuccess": @YES,
        @"maxBodyLog": @8192,
    };
}

static void grab_reload_conf(void) {
    NSMutableDictionary *conf = [grab_defaults() mutableCopy];
    NSData *data = [NSData dataWithContentsOfFile:GRAB_CONF_PATH];
    if (data) {
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([parsed isKindOfClass:[NSDictionary class]]) [conf addEntriesFromDictionary:parsed];
    }

    [gLock lock];
    gConf = conf;
    [gLock unlock];

    grab_log(@"config loaded: mode=%@ match=%@ repeat=%@ interval=%@",
             conf[@"mode"], conf[@"match"], conf[@"repeat"], conf[@"intervalMs"]);
}

static id grab_conf(NSString *key) {
    [gLock lock];
    id v = gConf[key];
    [gLock unlock];
    return v;
}

static BOOL grab_hit(NSString *url, NSString *body) {
    NSString *m = grab_conf(@"match");
    if (![m isKindOfClass:[NSString class]] || m.length == 0) return NO;
    if ([url containsString:m]) return YES;
    if ([body isKindOfClass:[NSString class]] && [body containsString:m]) return YES;
    return NO;
}

#pragma mark - 重放

static NSURLSession *gOwnSession = nil;

static NSString *grab_str(id v, NSUInteger cap) {
    if (!v) return @"";
    NSString *s = [v isKindOfClass:[NSString class]] ? v : [v description];
    if (s.length > cap) s = [[s substringToIndex:cap] stringByAppendingString:@"…"];
    return s;
}

static void grab_fire_once(NSURLRequest *req, NSInteger attempt);

static void grab_replay(NSURLRequest *req) {
    if (gDone) return;
    NSInteger repeat = [grab_conf(@"repeat") integerValue];
    if (repeat <= 0) repeat = 200;
    grab_log(@"=== REPLAY start: %@ (%ld 次) ===", req.URL.absoluteString, (long)repeat);

    for (NSInteger i = 0; i < repeat && !gDone; i++) {
        double delay = i * ([grab_conf(@"intervalMs") doubleValue] / 1000.0);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            grab_fire_once(req, i + 1);
        });
    }
}

static void grab_fire_once(NSURLRequest *req, NSInteger attempt) {
    if (gDone) return;
    if (!gOwnSession) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 10;
        cfg.HTTPShouldSetCookies = NO;       // 用抓到的原始 Cookie 头
        gOwnSession = [NSURLSession sessionWithConfiguration:cfg];
    }

    __block NSInteger a = attempt;
    NSURLSessionDataTask *task =
        [gOwnSession dataTaskWithRequest:req
                      completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (gDone) return;
        gSent++;
        NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];

        NSString *marker = grab_conf(@"successContains");
        BOOL hit = marker.length > 0 && body &&
                   [body rangeOfString:marker].location != NSNotFound;

        grab_log(@"attempt %ld code=%ld len=%lu hit=%d body=%@",
                 (long)a, (long)code, (unsigned long)data.length, hit,
                 grab_str(body, [grab_conf(@"maxBodyLog") unsignedIntegerValue]));

        if (hit) {
            gDone = YES;
            grab_log(@"*** SUCCESS at attempt %ld ***", (long)a);
            [gOwnSession invalidateAndCancel];
        } else if (err) {
            grab_log(@"attempt %ld error: %@", (long)a, err.localizedDescription);
        } else if (code != 200) {
            // 限流/风控通常不是 200，放慢一点避免被打死
            [NSThread sleepForTimeInterval:0.15];
        }
    }];
    [task resume];
}

#pragma mark - NSURLSession 抓取

static void grab_handle_request(NSURLRequest *req) {
    if (![grab_conf(@"enabled") boolValue]) return;
    if (![req isKindOfClass:[NSURLRequest class]]) return;

    NSString *url = req.URL.absoluteString ?: @"";
    NSString *method = req.HTTPMethod ?: @"GET";
    NSData *bodyData = req.HTTPBody;
    if (!bodyData && req.HTTPBodyStream) {
        // body 走 stream 的情况读不到，标记一下
        bodyData = nil;
    }
    NSString *body = bodyData ? [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding] : nil;

    grab_log(@"REQ %@ %@\n  headers=%@\n  body=%@",
             method, grab_str(url, 512),
             grab_str(req.allHTTPHeaderFields, 1024),
             grab_str(body, [grab_conf(@"maxBodyLog") unsignedIntegerValue]));

    if (!gReplaying && grab_hit(url, body)) {
        NSString *mode = grab_conf(@"mode");
        if ([mode isEqualToString:@"replay"] || [mode isEqualToString:@"both"]) {
            gReplaying = YES;
            gDone = NO;
            grab_replay(req);
        }
    }
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    grab_handle_request(request);
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    grab_handle_request(request);
    return %orig;
}

%end

#pragma mark - BoringSSL 抓取（Flutter 通路）

typedef int (*SSL_write_t)(void *ssl, const void *buf, int num);
static SSL_write_t orig_SSL_write = NULL;

static int hook_SSL_write(void *ssl, const void *buf, int num) {
    if (buf && num > 0 && num < 65536) {
        const char *p = (const char *)buf;
        // 只认 HTTP 请求行开头，避免把一堆二进制垃圾写进日志
        if (num > 8 && (strncmp(p, "GET ", 4) == 0 || strncmp(p, "POST ", 5) == 0 ||
                        strncmp(p, "PUT ", 4) == 0 || strncmp(p, "HEAD ", 5) == 0)) {
            NSString *text = [[NSString alloc] initWithBytes:buf length:num encoding:NSUTF8StringEncoding];
            if (text) {
                grab_log(@"TLS %@", grab_str(text, [grab_conf(@"maxBodyLog") unsignedIntegerValue]));
                NSString *first = [text componentsSeparatedByString:@"\r\n"].firstObject ?: @"";
                if (!gReplaying && grab_hit(first, text)) {
                    NSString *mode = grab_conf(@"mode");
                    if ([mode isEqualToString:@"replay"] || [mode isEqualToString:@"both"]) {
                        grab_log(@"命中 TLS 请求，但 Flutter 通路暂不支持自动重放（见 README）");
                    }
                }
            }
        }
    }
    return orig_SSL_write ? orig_SSL_write(ssl, buf, num) : -1;
}

#pragma mark - 通知重载

static void grab_on_reload(CFNotificationCenterRef c, void *obs, CFStringRef name,
                           const void *obj, CFDictionaryRef info) {
    grab_reload_conf();
    gDone = NO;
    gReplaying = NO;
    gSent = 0;
    grab_log(@"reloaded via darwin notification");
}

#pragma mark - 构造

%ctor {
    gLock = [[NSLock alloc] init];
    grab_reload_conf();

    // BoringSSL：符号在 libboringssl / 主二进制里都可能
    MSHookFunction((void *)dlsym(RTLD_DEFAULT, "SSL_write"),
                   (void *)hook_SSL_write, (void **)&orig_SSL_write);
    grab_log(@"loaded; SSL_write hook = %s", orig_SSL_write ? "ok" : "missing");

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL, grab_on_reload,
                                    CFSTR("com.koudai.weidian.grab/reload"),
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
