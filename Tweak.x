// WeidianGrab — 微店买家版抓包/抢单 tweak
//
// 设计依据（2026-11-01 实测）：
//   * 业务 API 走原生 NSURLSession，域名 thor.weidian.com / logtake.weidian.com
//   * 内置 Flutter 只有 spine_flutter（动画），业务不经过 dart:io
//   * 第三方 SDK 噪音大（bugly/sigmob/getui/qiyukf/fengkongcloud），默认按域名过滤
//
// 刻意不用 Logos / substrate：
//   Theos 会给 tweak 自动加 `-framework CydiaSubstrate`，而 roothide 没有这个框架
//   （它用 libhooker 的 libsubstrate.dylib），导致 dlopen 失败、libhooker 静默跳过。
//   这里用 method_setImplementation 手写 swizzle，只依赖 Foundation/UIKit。

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define GRAB_LOG_PATH   @"/var/mobile/Library/Logs/WeidianGrab.log"
#define GRAB_CONF_PATH  @"/var/mobile/Library/Preferences/com.koudai.weidian.grab.json"

static NSMutableDictionary *gConf = nil;
static NSLock *gLock = nil;
static BOOL gReplaying = NO;
static BOOL gDone = NO;
static NSURLSession *gOwnSession = nil;

#pragma mark - 日志

static void grab_log(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                      [df stringFromDate:[NSDate date]], msg];

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
        @"mode": @"capture",
        @"match": @"",
        @"repeat": @200,
        @"intervalMs": @80,
        @"successContains": @"",
        @"maxBodyLog": @4096,
        @"hostFilter": @"weidian.com",
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
    grab_log(@"config: mode=%@ match=%@", conf[@"mode"], conf[@"match"]);
}

static id grab_conf(NSString *key) {
    [gLock lock];
    id v = gConf[key];
    [gLock unlock];
    return v;
}

static NSString *grab_str(id v, NSUInteger cap) {
    if (!v) return @"";
    NSString *s = [v isKindOfClass:[NSString class]] ? v : [v description];
    if (s.length > cap) s = [[s substringToIndex:cap] stringByAppendingString:@"…"];
    return s;
}

static BOOL grab_is_api(NSString *url) {
    NSString *f = grab_conf(@"hostFilter");
    if (![f isKindOfClass:[NSString class]] || f.length == 0) return YES;
    return [url containsString:f];
}

static BOOL grab_hit(NSString *url, NSString *body) {
    NSString *m = grab_conf(@"match");
    if (![m isKindOfClass:[NSString class]] || m.length == 0) return NO;
    if ([url containsString:m]) return YES;
    if ([body isKindOfClass:[NSString class]] && [body containsString:m]) return YES;
    return NO;
}

#pragma mark - 重放

static void grab_fire(NSURLRequest *tpl, NSInteger attempt) {
    if (gDone) return;
    if (!gOwnSession) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 8;
        cfg.HTTPShouldSetCookies = NO;
        cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
        gOwnSession = [NSURLSession sessionWithConfiguration:cfg];
    }
    NSURLSessionDataTask *t =
        [gOwnSession dataTaskWithRequest:tpl completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (gDone) return;
        NSInteger code = [(NSHTTPURLResponse *)r statusCode];
        NSString *body = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        NSString *marker = grab_conf(@"successContains");
        BOOL hit = marker.length && body && [body containsString:marker];
        grab_log(@"try %ld code=%ld len=%lu hit=%d %@",
                 (long)attempt, (long)code, (unsigned long)d.length, hit,
                 hit ? grab_str(body, 300) : (e ? e.localizedDescription : @""));
        if (hit) {
            gDone = YES;
            grab_log(@"*** SUCCESS at attempt %ld ***", (long)attempt);
            [gOwnSession invalidateAndCancel];
        }
    }];
    [t resume];
}

static void grab_start_replay(NSURLRequest *tpl) {
    NSInteger repeat = [grab_conf(@"repeat") integerValue] ?: 200;
    double gap = ([grab_conf(@"intervalMs") doubleValue] ?: 80) / 1000.0;
    grab_log(@"=== REPLAY %@ x%ld gap=%.0fms ===", tpl.URL.absoluteString, (long)repeat, gap * 1000);
    for (NSInteger i = 0; i < repeat; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * gap * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            grab_fire(tpl, i + 1);
        });
    }
}

#pragma mark - 抓取入口

static void grab_handle(NSURLRequest *req) {
    if (![req isKindOfClass:[NSURLRequest class]]) return;
    if (![grab_conf(@"enabled") boolValue]) return;

    NSString *url = req.URL.absoluteString ?: @"";
    if (!grab_is_api(url)) return;

    NSString *body = nil;
    if (req.HTTPBody) body = [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding];

    grab_log(@"REQ %@ %@\n  hdr=%@\n  body=%@",
             req.HTTPMethod ?: @"?",
             grab_str(url, 400),
             grab_str(req.allHTTPHeaderFields, 900),
             grab_str(body, [grab_conf(@"maxBodyLog") unsignedIntegerValue]));

    if (gReplaying || gDone) return;
    NSString *mode = grab_conf(@"mode");
    if (![mode isEqualToString:@"replay"] && ![mode isEqualToString:@"both"]) return;
    if (!grab_hit(url, body)) return;

    gReplaying = YES;
    grab_start_replay(req);
}

#pragma mark - 手写 swizzle（不依赖 substrate）

typedef NSURLSessionDataTask *(*ReqHandlerFn)(id, SEL, NSURLRequest *,
                                              void (^)(NSData *, NSURLResponse *, NSError *));
typedef NSURLSessionDataTask *(*ReqFn)(id, SEL, NSURLRequest *);

static ReqHandlerFn gOrigReqHandler = NULL;
static ReqFn gOrigReq = NULL;

static NSURLSessionDataTask *my_dataTaskWithRequest_handler(id self, SEL _cmd, NSURLRequest *req,
                                                            void (^h)(NSData *, NSURLResponse *, NSError *)) {
    @try { grab_handle(req); } @catch (__unused NSException *e) {}
    return gOrigReqHandler(self, _cmd, req, h);
}

static NSURLSessionDataTask *my_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *req) {
    @try { grab_handle(req); } @catch (__unused NSException *e) {}
    return gOrigReq(self, _cmd, req);
}

static void grab_install_hooks(void) {
    Class cls = objc_getClass("NSURLSession");
    if (!cls) return;

    SEL s1 = @selector(dataTaskWithRequest:completionHandler:);
    Method m1 = class_getInstanceMethod(cls, s1);
    if (m1) {
        gOrigReqHandler = (ReqHandlerFn)method_getImplementation(m1);
        method_setImplementation(m1, (IMP)my_dataTaskWithRequest_handler);
        grab_log(@"hooked -dataTaskWithRequest:completionHandler:");
    }

    SEL s2 = @selector(dataTaskWithRequest:);
    Method m2 = class_getInstanceMethod(cls, s2);
    if (m2) {
        gOrigReq = (ReqFn)method_getImplementation(m2);
        method_setImplementation(m2, (IMP)my_dataTaskWithRequest);
        grab_log(@"hooked -dataTaskWithRequest:");
    }
}

#pragma mark - 热重载

static void grab_reload_cb(CFNotificationCenterRef c, void *o, CFStringRef n,
                           const void *obj, CFDictionaryRef info) {
    grab_reload_conf();
    gDone = NO;
    gReplaying = NO;
    grab_log(@"reloaded");
}

#pragma mark - 构造

__attribute__((constructor))
static void grab_init(void) {
    @autoreleasepool {
        gLock = [[NSLock alloc] init];
        grab_reload_conf();
        grab_install_hooks();
        grab_log(@"loaded WeidianGrab 0.3.0 (no substrate)");

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL, grab_reload_cb,
                                        CFSTR("com.koudai.weidian.grab/reload"),
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
