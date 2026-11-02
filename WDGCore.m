#import "WDGCore.h"
#import "WDGBuild.h"
#import "WDGTaskGate.h"
#import "WDGOrderService.h"
#import "WDGCart.h"
#import "WDGClock.h"
#import "WDGAds.h"
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>

NSString * const WDGStateDidChange = @"WDGStateDidChange";
NSString * const WDGVersion = @"0.9.17";
#ifndef WDG_BUILD_ID
#define WDG_BUILD_ID "local-unbuilt"
#endif
NSString * const WDGBuildID = @WDG_BUILD_ID;

static NSError *WGDError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"WeidianGrab" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}

static BOOL WDGNativeClockMode(NSDictionary *sample) {
    return [sample[@"valid"] isKindOfClass:NSNumber.class] && [sample[@"valid"] boolValue] && [sample[@"status"] isEqual:@"native_recent"] &&
        [sample[@"offsetMs"] isKindOfClass:NSNumber.class] && isfinite([sample[@"offsetMs"] doubleValue]);
}
static BOOL WDGClockOffsetsMatch(NSDictionary *a, NSDictionary *b) {
    if(!WDGNativeClockMode(a)||!WDGNativeClockMode(b)||![a[@"offsetMs"] isEqualToNumber:b[@"offsetMs"]])return NO;
    if(![(a[@"clockGeneration"]?:@0) isEqual:(b[@"clockGeneration"]?:@0)])return NO;
    NSNumber *rawA=[a[@"rawOffsetMs"] isKindOfClass:NSNumber.class]?a[@"rawOffsetMs"]:a[@"offsetMs"];
    NSNumber *rawB=[b[@"rawOffsetMs"] isKindOfClass:NSNumber.class]?b[@"rawOffsetMs"]:b[@"offsetMs"];
    return [rawA isEqualToNumber:rawB];
}
// Age the cached observation without touching the native clock. The pure
// converter also detects a wall/uptime discrepancy since the observation.
static NSDictionary *WDGCachedClockStatus(NSDictionary *sample) {
    if(!sample)return @{@"valid":@NO,@"status":@"unavailable",@"offsetMs":NSNull.null,
        @"reason":@"尚无有效校准样本",@"source":@"none",@"updatedAtServerMs":NSNull.null,
        @"sampledAt":@0,@"sampledUptime":@0,@"ageMs":NSNull.null};
    NSMutableDictionary *result=[sample mutableCopy];
    double elapsed=NSProcessInfo.processInfo.systemUptime-[sample[@"sampledUptime"] doubleValue];
    if([sample[@"ageMs"] isKindOfClass:NSNumber.class]&&isfinite(elapsed))
        result[@"ageMs"]=@([sample[@"ageMs"] doubleValue]+MAX(0,elapsed)*1000);
    NSString *reason=nil;
    if(WDGNativeClockMode(sample)&&!WDGLocalDeadlineFromClock(NSDate.date,sample,&reason)){
        result[@"valid"]=@NO;result[@"offsetMs"]=NSNull.null;
        result[@"status"]=elapsed>5?@"stale":@"clock_changed";
        result[@"reason"]=reason?:@"时钟样本已失效，请重新读取";
    }
    return [result copy];
}

// Detail-page direct purchase. Everything below is read-only introspection of
// the app's own controller: it never sends a request, and the only action the
// task ever performs is the page's own handlePurchaseOperation.
static const char *WDGDetailUnqualifiedType(const char *type) {
    if(!type)return "";
    while(*type&&strchr("rnNoORVA",*type))++type;
    return type;
}
static BOOL WDGDetailExactType(const char *encoded,char expected) {
    const char *type=WDGDetailUnqualifiedType(encoded);
    return type[0]==expected&&type[1]=='\0';
}
static BOOL WDGDetailObjectType(const char *encoded) {
    const char *type=WDGDetailUnqualifiedType(encoded);
    return type[0]=='@'&&(type[1]=='\0'||type[1]=='"');
}
static Method WDGDetailInstanceMethod(id receiver,SEL selector,unsigned int count) {
    if(!receiver||object_isClass(receiver))return NULL;
    Method method=class_getInstanceMethod(object_getClass(receiver),selector);
    if(!method||method_getNumberOfArguments(method)!=count)return NULL;
    return method;
}
static BOOL WDGDetailMethodReturns(Method method,char type) {
    if(!method)return NO;
    char result[256]={0};
    method_getReturnType(method,result,sizeof(result));
    return WDGDetailExactType(result,type);
}
static BOOL WDGDetailMethodArgument(Method method,unsigned int index,char type) {
    if(!method||index>=method_getNumberOfArguments(method))return NO;
    char argument[256]={0};
    method_getArgumentType(method,index,argument,sizeof(argument));
    return type=='@'?WDGDetailObjectType(argument):WDGDetailExactType(argument,type);
}
static BOOL WDGDetailIsPage(id value) {
    Class cls=NSClassFromString(@"WDBGoodsDetailController");
    if(!cls||!value||object_isClass(value))return NO;
    @try{return [value isKindOfClass:cls];}
    @catch(__unused NSException *exception){return NO;}
}
// UIApplication.windows is deprecated for iOS 15+ and rejected by -Werror, so
// union every connected scene's windows: the same application-owned window set.
static NSArray<UIWindow *> *WDGDetailWindows(void) {
    NSMutableArray<UIWindow *> *windows=[NSMutableArray array];
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class])continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows)
            if(window&&![windows containsObject:window])[windows addObject:window];
    }
    return windows;
}
static BOOL WDGDetailPageVisible(id page) {
    if(!WDGDetailIsPage(page))return NO;
    UIViewController *controller=page;
    UIView *view=controller.viewIfLoaded;
    if(!view||!view.window||view.window.hidden||view.window.alpha<=0.01)return NO;
    if(view.window.windowScene&&view.window.windowScene.activationState!=UISceneActivationStateForegroundActive)return NO;
    if(controller.isBeingDismissed||controller.isMovingFromParentViewController)return NO;
    return YES;
}
static id WDGDetailFind(UIViewController *controller,NSUInteger depth) {
    if(!controller||depth>6)return nil;
    if(WDGDetailPageVisible(controller))return controller;
    UIViewController *presented=controller.presentedViewController;
    if(presented&&!presented.isBeingDismissed){id found=WDGDetailFind(presented,depth+1);if(found)return found;}
    for(UIViewController *child in controller.childViewControllers){id found=WDGDetailFind(child,depth+1);if(found)return found;}
    return nil;
}
static id WDGDetailController(NSString **reason) {
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){if(reason)*reason=@"请保持微店在前台";return nil;}
    if(!NSClassFromString(@"WDBGoodsDetailController")){if(reason)*reason=@"当前版本未提供商品详情页控制器";return nil;}
    for(UIWindow *window in WDGDetailWindows()) {
        if(!window||window.hidden||window.alpha<=0.01)continue;
        id found=WDGDetailFind(window.rootViewController,0);
        if(found){if(reason)*reason=nil;return found;}
    }
    if(reason)*reason=@"请先打开商品详情页";
    return nil;
}
static NSString *WDGDetailItemID(id controller,NSString **reason) {
    SEL selector=NSSelectorFromString(@"itemId");
    Method method=WDGDetailInstanceMethod(controller,selector,2);
    if(!method||!WDGDetailMethodReturns(method,'@')||!WDGDetailMethodArgument(method,1,':')){
        if(reason)*reason=@"详情页 itemId 读取 ABI 不匹配，未设置任务";return nil;
    }
    id value=nil;
    @try{value=((id(*)(id,SEL))objc_msgSend)(controller,selector);}
    @catch(__unused NSException *exception){if(reason)*reason=@"详情页 itemId 读取异常，未设置任务";return nil;}
    if(![value isKindOfClass:NSString.class]||![(NSString *)value length]){if(reason)*reason=@"详情页商品信息尚未加载完成，请稍后重试";return nil;}
    return [(NSString *)value copy];
}
// Both the arm-time check and the fire-time check use this exact ABI gate:
// handlePurchaseOperation must be void(id,SEL) on the instance.
static BOOL WDGDetailPurchaseReady(id controller) {
    Method method=WDGDetailInstanceMethod(controller,NSSelectorFromString(@"handlePurchaseOperation"),2);
    return method&&WDGDetailMethodReturns(method,'v')&&WDGDetailMethodArgument(method,0,'@')&&WDGDetailMethodArgument(method,1,':');
}
static id WDGDetailTarget(NSString **itemIDOut,NSString **reason) {
    NSString *why=nil;
    id controller=WDGDetailController(&why);
    if(!controller){if(reason)*reason=why?:@"请先打开商品详情页";return nil;}
    NSString *itemID=WDGDetailItemID(controller,&why);
    if(!itemID){if(reason)*reason=why?:@"详情页商品信息尚未加载完成";return nil;}
    if(!WDGDetailPurchaseReady(controller)){if(reason)*reason=@"立即购买方法 ABI 不是 void(id,SEL)，未设置任务";return nil;}
    if(itemIDOut)*itemIDOut=itemID;
    if(reason)*reason=nil;
    return controller;
}
id WDGVisibleDetailController(NSString **reason) {
    if(!NSThread.isMainThread){
        __block id found=nil;__block NSString *why=nil;
        dispatch_sync(dispatch_get_main_queue(),^{found=WDGVisibleDetailController(&why);});
        if(reason)*reason=why;
        return found;
    }
    id found=nil;NSString *why=nil;
    @try{found=WDGDetailController(&why);}
    @catch(__unused NSException *exception){why=@"读取详情页状态异常";}
    if(reason)*reason=found?nil:(why?:@"请先打开商品详情页");
    return found;
}

@interface WDGCore ()
@property (nonatomic) BOOL captureEnabled;
@property (nonatomic, copy) NSDictionary *snapshot;
@property (nonatomic, strong) NSMutableDictionary *task;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *recent;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, copy) NSString *storagePath;
@property (nonatomic, copy) NSString *ioError;
@property (nonatomic) NSUInteger firedCount;
@property (nonatomic,strong) WDGOrderService *preparedService;
@property (nonatomic,strong) NSTimer *replyTimeout;
@property (nonatomic,copy) NSDictionary *lastReceipt;
@property (nonatomic,strong) NSDecimalNumber *cartMaximum;
@property (nonatomic) NSUInteger cartLanes;
@property (nonatomic) BOOL cartRetryEnabled;
@property (nonatomic) NSUInteger cartRetryAttempts;
@property (nonatomic,copy) NSDictionary *serverClock;
@property (nonatomic,copy) NSDictionary *cartClockSnapshot;
@property (nonatomic,strong) NSDate *cartLocalDue;
@property (nonatomic) BOOL cancellingTask;
// detailOnce only. The controller is held weakly and is never persisted: a
// restarted process must not resume a page-bound task.
@property (nonatomic,weak) id detailController;
@property (nonatomic,strong) NSTimer *detailPoll;
@property (nonatomic) NSUInteger detailPollAttempts;
@property (nonatomic) NSTimeInterval detailFiredAt;
@end

@implementation WDGCore {
    WDGTaskGate _taskGate;
}
+ (instancetype)shared {
    static WDGCore *core;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ core = [WDGCore new]; });
    return core;
}
- (instancetype)init {
    if ((self=[super init])) {
        _captureEnabled=YES;
        [WDGOrderService setExecutionAllowedCheck:^BOOL{return UIApplication.sharedApplication.applicationState==UIApplicationStateActive;}];
        _snapshot=@{};
        _recent=[NSMutableArray array];
        _task=[@{@"id":@"",@"state":@"idle",@"action":@"",@"sampleKey":@"",@"payType":[NSNull null],@"dueAt":@0} mutableCopy];
        NSString *support=[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES) firstObject];
        if (!support) support=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
        _storagePath=[support stringByAppendingPathComponent:@"WeidianGrab"];
        NSError *error=nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:_storagePath withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:&error];
        if (error) _ioError=[NSString stringWithFormat:@"storage create error %ld",(long)error.code];
        NSData *saved=[NSData dataWithContentsOfFile:[_storagePath stringByAppendingPathComponent:@"state.json"]];
        NSDictionary *prior=saved?[NSJSONSerialization JSONObjectWithData:saved options:0 error:NULL]:nil;
        if ([prior isKindOfClass:[NSDictionary class]]) {
            NSNumber *enabled=prior[@"captureEnabled"];
            if ([enabled isKindOfClass:NSNumber.class]) _captureEnabled=enabled.boolValue;
            NSNumber *ads=prior[@"adsEnabled"];
            if ([ads isKindOfClass:NSNumber.class]) WDGAdsSetEnabled(ads.boolValue);
            // Never resume a transaction after process restart: UI bindings are gone.
            NSDictionary *task=prior[@"task"];
            if ([task isKindOfClass:NSDictionary.class] && [@[@"armed",@"firing",@"preheating",@"waitingSale",@"sending",@"unknown"] containsObject:task[@"state"]]) {
                _task=[task mutableCopy];
                BOOL sent=[@[@"sending",@"unknown"] containsObject:task[@"state"]];
                _task[@"state"]=sent?@"unknown":@"cancelled";
                _task[@"reason"]=sent?@"上次接口请求结果待核对，不自动重试":@"App 已重启，旧任务已取消";
            }
        }
        WDGAdsInstall();
        NSNotificationCenter *nc=NSNotificationCenter.defaultCenter;
        [nc addObserver:self selector:@selector(willResign:) name:UIApplicationWillResignActiveNotification object:nil];
        [nc addObserver:self selector:@selector(clockChanged:) name:UIApplicationSignificantTimeChangeNotification object:nil];
        [self recordEvent:@"startup" details:@{@"version":WDGVersion,@"build":WDGBuildID}];
    }
    return self;
}
- (NSDictionary *)status {
    if (![NSThread isMainThread]) {
        __block NSDictionary *copy=nil;
        dispatch_sync(dispatch_get_main_queue(), ^{copy=[self status];});
        return copy;
    }
    return @{@"version":WDGVersion,@"build":WDGBuildID,@"captureEnabled":@(self.captureEnabled),
             @"snapshot":self.snapshot?:@{},@"task":[self.task copy],@"events":[self.recent copy],
             @"firedCount":@(self.firedCount),@"ioError":self.ioError?:@"",@"storagePath":self.storagePath,@"receipt":self.lastReceipt?:@{},@"transport":[WDGOrderService diagnostics],@"cart":WDGCartDiagnostics(),@"clock":WDGCachedClockStatus(self.serverClock),@"ads":WDGAdsDiagnostics(),@"retryEnabled":@(self.cartRetryEnabled)};
}
- (void)setAdsEnabled:(BOOL)enabled {
    if(![NSThread isMainThread]){dispatch_async(dispatch_get_main_queue(), ^{[self setAdsEnabled:enabled];});return;}
    WDGAdsSetEnabled(enabled);
    [self persist];
    [self recordEvent:@"ads_toggle" details:@{@"result":enabled?@"on":@"off"}];
    [NSNotificationCenter.defaultCenter postNotificationName:WDGStateDidChange object:self];
}
- (void)refreshServerClock {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(), ^{[self refreshServerClock];});return;}
    self.serverClock=[WDGReadServerClock() copy];
    // A passive display refresh never reconfigures a task or its service.
    [NSNotificationCenter.defaultCenter postNotificationName:WDGStateDidChange object:self];
}
- (void)persist {
    // Call only on the main queue. All persisted fields are our own metadata or
    // the adapter's product whitelist, never an NSURLRequest or raw model.
    NSDictionary *payload=@{@"version":WDGVersion,@"build":WDGBuildID,@"captureEnabled":@(self.captureEnabled),@"adsEnabled":@(WDGAdsEnabled()),@"snapshot":self.snapshot?:@{},@"task":[self.task copy]};
    NSError *error=nil;
    NSData *json=[NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:&error];
    if (json && [json writeToFile:[self.storagePath stringByAppendingPathComponent:@"state.json"] options:NSDataWritingAtomic error:&error]) {
        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:[self.storagePath stringByAppendingPathComponent:@"state.json"] error:NULL];
    } else if (error) {
        self.ioError=[NSString stringWithFormat:@"state write error %ld",(long)error.code];
        NSLog(@"[WeidianGrab %@] state write error %ld",WDGVersion,(long)error.code);
    }
}
- (void)recordEvent:(NSString *)event details:(NSDictionary *)details {
    if (![NSThread isMainThread]) {
        NSDictionary *copy=[details copy];
        dispatch_async(dispatch_get_main_queue(), ^{[self recordEvent:event details:copy];});return;
    }
    // This explicit key allowlist is also applied to diagnostics from hooks.
    NSSet *allowed=[NSSet setWithArray:@[@"version",@"build",@"stage",@"pageKind",@"source",@"class",@"selector",@"itemCount",@"reason",@"action",@"taskId",@"state",@"latenessMs",@"captureEnabled",@"errorCode",@"result"]];
    NSMutableDictionary *safe=[NSMutableDictionary dictionary];
    [details enumerateKeysAndObjectsUsingBlock:^(id key,id value,BOOL *stop){
        if ([allowed containsObject:key] && ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class])) safe[key]=value;
    }];
    NSDictionary *row=@{@"at":@([NSDate date].timeIntervalSince1970),@"event":event?:@"unknown",@"details":safe};
    [self.recent addObject:row];if(self.recent.count>80)[self.recent removeObjectAtIndex:0];
    NSData *json=[NSJSONSerialization dataWithJSONObject:row options:0 error:NULL];
    NSString *path=[self.storagePath stringByAppendingPathComponent:@"events.jsonl"];
    NSNumber *size=[[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] objectForKey:NSFileSize];
    if(size.unsignedLongLongValue>1024*1024) {
        NSString *old=[path stringByAppendingString:@".1"];
        [[NSFileManager defaultManager] removeItemAtPath:old error:NULL];
        [[NSFileManager defaultManager] moveItemAtPath:path toPath:old error:NULL];
    }
    int fd=open(path.fileSystemRepresentation,O_WRONLY|O_APPEND|O_CREAT,0600);
    if(fd>=0) {
        if(json) {const uint8_t *p=json.bytes;size_t left=json.length;while(left){ssize_t n=write(fd,p,left);if(n<0&&errno==EINTR)continue;if(n<=0)break;p+=n;left-=(size_t)n;} (void)write(fd,"\n",1);}
        close(fd);
    } else self.ioError=[NSString stringWithFormat:@"event log errno %d",errno];
    [self persist];
    [[NSNotificationCenter defaultCenter] postNotificationName:WDGStateDidChange object:self];
}
- (void)setCaptureEnabled:(BOOL)enabled {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(), ^{[self setCaptureEnabled:enabled];});return;}
    _captureEnabled=enabled;
    [self recordEvent:@"capture_toggle" details:@{@"captureEnabled":@(enabled)}];
    if(enabled) WDGRefreshTradeSnapshot();
}
- (void)acceptSnapshot:(NSDictionary *)snapshot {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(), ^{[self acceptSnapshot:snapshot];});return;}
    if(!self.captureEnabled)return;
    NSError *err=nil;
    NSData *data=[NSJSONSerialization dataWithJSONObject:snapshot options:0 error:&err];
    NSDictionary *frozen=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
    if(![frozen isKindOfClass:NSDictionary.class]){[self recordEvent:@"snapshot_error" details:@{@"errorCode":@(err.code)}];return;}
    if([self.task[@"action"] isEqual:@"serviceOnce"] && [self.task[@"state"] isEqual:@"armed"] && ![self.task[@"sampleKey"] isEqual:frozen[@"sampleKey"]]) [self cancelTask:@"采集内容或页面已变化"];
    self.snapshot=frozen;
    [self recordEvent:@"snapshot" details:@{@"stage":frozen[@"stage"]?:@"",@"pageKind":frozen[@"pageKind"]?:@"",@"itemCount":@([frozen[@"items"] count])}];
}
- (void)clearSnapshot {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(), ^{[self clearSnapshot];});return;}
    [self cancelTask:@"采集样本已清空"];self.snapshot=@{};WDGCartClear();
    [self recordEvent:@"snapshot_cleared" details:@{}];
}
- (BOOL)armCartAt:(NSDate *)date maximumTotal:(NSDecimalNumber *)maximumTotal error:(NSError **)error {
    return [self armCartAt:date maximumTotal:maximumTotal concurrentLanes:1 error:error];
}
- (BOOL)armCartAt:(NSDate *)date maximumTotal:(NSDecimalNumber *)maximumTotal concurrentLanes:(NSUInteger)lanes error:(NSError **)error {
    if(!NSThread.isMainThread){if(error)*error=WGDError(1,@"请在主线程设置任务");return NO;}
    return [self armCartAt:date maximumTotal:maximumTotal concurrentLanes:lanes clockSnapshot:WDGReadServerClock() error:error];
}
- (BOOL)armCartAt:(NSDate *)date maximumTotal:(NSDecimalNumber *)maximumTotal concurrentLanes:(NSUInteger)lanes clockSnapshot:(NSDictionary *)clockSnapshot error:(NSError **)error {
    if(!NSThread.isMainThread){if(error)*error=WGDError(1,@"请在主线程设置任务");return NO;}
    if(lanes!=1&&lanes!=2&&lanes!=4){if(error)*error=WGDError(30,@"并发只支持 1/2/4 路");return NO;}
    NSDictionary *review=[clockSnapshot copy],*fresh=[WDGReadServerClock() copy];
    self.serverClock=fresh;
    NSDate *localDue=date;NSDictionary *chosen=review;
    if(WDGNativeClockMode(review)){
        NSString *reason=nil;
        // Do not convert the Review observation: it may be >5s old by now.
        // Same raw offset + a valid fresh observation preserves exactly what
        // was displayed, without ever silently falling back to local time.
        if(!WDGClockOffsetsMatch(review,fresh)||!(localDue=WDGLocalDeadlineFromClock(date,fresh,&reason))){
            if(error)*error=WGDError(31,[NSString stringWithFormat:@"%@；请重新打开确认页核对",reason?:@"微店时钟样本或时差已变化"]);return NO;
        }
        chosen=fresh;
    } else {
        // A Review that explicitly displayed local fallback stays local even
        // if the App has acquired a valid native observation in the meantime.
        NSMutableDictionary *local=[(review?:WDGCachedClockStatus(nil)) mutableCopy];
        local[@"valid"]=@NO;local[@"offsetMs"]=NSNull.null;chosen=[local copy];
    }
    self.cartClockSnapshot=chosen;self.cartLocalDue=localDue;
    self.cartMaximum=maximumTotal;self.cartLanes=lanes;
    BOOL armed=[self armAt:date action:@"preheatOnce" payType:nil error:error];
    self.cartMaximum=nil;self.cartLanes=1;self.cartLocalDue=nil;self.cartClockSnapshot=nil;return armed;
}
- (void)setRetryEnabled:(BOOL)enabled attempts:(NSUInteger)attempts {
    if(![NSThread isMainThread]){dispatch_async(dispatch_get_main_queue(), ^{[self setRetryEnabled:enabled attempts:attempts];});return;}
    self.cartRetryEnabled=enabled;self.cartRetryAttempts=attempts;
}
- (BOOL)armAt:(NSDate *)date action:(NSString *)action payType:(NSNumber *)payType error:(NSError **)error {
    if(!NSThread.isMainThread){if(error)*error=WGDError(1,@"请在主线程设置任务");return NO;}
    NSTimeInterval validationNow=NSDate.date.timeIntervalSince1970;
    NSTimeInterval delta=date.timeIntervalSince1970-validationNow;
    if(self.cancellingTask||[@[@"sending",@"unknown"] containsObject:self.task[@"state"]]){if(error)*error=WGDError(3,@"上一笔接口请求仍需核对结果，请勿覆盖");return NO;}
    BOOL cartTask=[action isEqual:@"preheatOnce"];
    BOOL detailTask=[action isEqual:@"detailOnce"];
    id detailTarget=nil;NSString *detailItemID=nil;
    NSDate *localDue=cartTask?(self.cartLocalDue?:date):date;
    NSTimeInterval localDelta=localDue.timeIntervalSince1970-validationNow;
    NSDecimalNumber *maximum=self.cartMaximum;
    NSString *sampleKey=[(cartTask?WDGCartSnapshotKey():self.snapshot[@"sampleKey"]) copy];
    NSString *reason=nil;
    if(![@[@"reminder",@"dryRun",@"serviceOnce",@"preheatOnce",@"detailOnce"] containsObject:action])reason=@"未知任务类型";
    else if(!isfinite(delta)||delta<2||delta>86400)reason=@"任务时间请设在 2 秒至 24 小时以内";
    else if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)reason=@"请保持微店在前台；后台或锁屏期间不保证执行";
    else if(detailTask){
        // Same gates as the fire path: visible detail page, readable itemId and
        // an exact void(id,SEL) purchase method. Nothing is stored on disk.
        NSString *detailReason=nil;
        detailTarget=WDGDetailTarget(&detailItemID,&detailReason);
        if(!detailTarget)reason=detailReason?:@"请先打开商品详情页";
    }
    else if([action isEqual:@"serviceOnce"]){
        NSArray *items=self.snapshot[@"items"];
        NSString *price=self.snapshot[@"totalPrice"];
        if(items.count==0||price.length==0)reason=@"请先进入订单确认页采集商品、规格及金额";
        else if(!payType)reason=@"请选择从当前确认页读取的提交按钮";
        else {
            NSString *bindingReason=nil;
            if(!WDGInterfaceTargetReady(sampleKey,payType,&bindingReason)) reason=bindingReason?:@"当前页面尚未完成验证";
        }
    }
    else if(cartTask){
        if(!sampleKey.length||WDGCartSelectedLines().count==0)reason=@"请先在购物车页明确选择目标商品";
        else if(![maximum isKindOfClass:NSDecimalNumber.class]||[maximum isEqual:NSDecimalNumber.notANumber]||[maximum compare:NSDecimalNumber.zero]!=NSOrderedDescending)reason=@"请确认大于零的最高实付金额";
        else {
            NSString *preheatReason=nil;
            if(![WDGOrderService preheatReady:&preheatReason])reason=preheatReason?:@"预热接口未就绪";
        }
    }
    if(detailTask && delta>590)reason=@"详情页直提只支持十分钟以内，请把任务设在十分钟以内";
    if([action isEqual:@"serviceOnce"] && delta>590)reason=@"接口参数本轮只验证十分钟有效期，请把任务设在十分钟以内";
    if(cartTask&&(!isfinite(delta)||delta<2||delta>43200||!isfinite(localDelta)||localDelta<2||localDelta>43200))
        reason=@"公告时刻与本地执行时刻都须在未来 2 秒至 12 小时内，请重新确认时差和时间";
    if(reason){if(error)*error=WGDError(2,reason);return NO;}
    WDGOrderService *prepared=nil;
    if([action isEqual:@"serviceOnce"]){
        prepared=WDGPrepareObservedInterface(sampleKey,payType,error);
        if(!prepared)return NO;
    } else if(cartTask){
        prepared=[self preparePreheatWithPayType:nil error:error];
        if(!prepared||![prepared.sampleKey isEqual:sampleKey]||
           ![prepared configureConcurrentLanes:self.cartLanes error:error]||
           ![prepared configureRetryEnabled:self.cartRetryEnabled attempts:(self.cartRetryAttempts?:1) error:error]||
           ![prepared configureCartDueAt:localDue maximumTotal:maximum error:error]){
            if(prepared&&![prepared.sampleKey isEqual:sampleKey]&&error)*error=WGDError(21,@"准备期间购物车目标已变化，请重新确认");
            return NO;
        }
    }
    [self cancelTask:@"新任务替代旧任务"];
    if([@[@"sending",@"unknown"] containsObject:self.task[@"state"]]){if(error)*error=WGDError(3,@"旧任务的创建请求已经发出，请先核对结果");return NO;}
    if((cartTask&&![sampleKey isEqual:WDGCartSnapshotKey()])||([action isEqual:@"serviceOnce"]&&![sampleKey isEqual:self.snapshot[@"sampleKey"]])){if(error)*error=WGDError(21,@"准备期间目标已变化，请重新确认");return NO;}
    if(detailTask){
        NSString *nowItemID=nil,*nowReason=nil;
        id nowTarget=WDGDetailTarget(&nowItemID,&nowReason);
        if(!nowTarget||![nowItemID isEqualToString:detailItemID]){if(error)*error=WGDError(21,nowReason?:@"详情页商品已变化，请重新确认");return NO;}
        detailTarget=nowTarget;detailItemID=nowItemID;
    }
    NSTimeInterval armedAt=NSDate.date.timeIntervalSince1970,armedUptime=NSProcessInfo.processInfo.systemUptime;
    NSTimeInterval dueTS=localDue.timeIntervalSince1970;
    if(cartTask&&(date.timeIntervalSince1970-armedAt<2||date.timeIntervalSince1970-armedAt>43200||dueTS-armedAt<2||dueTS-armedAt>43200)){
        if(error)*error=WGDError(2,@"准备后公告时刻或本地执行时刻已超出未来 2 秒至 12 小时，请重新确认");return NO;
    }
    self.preparedService=prepared;self.lastReceipt=nil;
    NSTimeInterval fireAt=cartTask?dueTS-5:dueTS;
    self.task=[@{@"id":NSUUID.UUID.UUIDString,@"state":@"armed",@"action":action,@"sampleKey":sampleKey?:@"",@"payType":cartTask?NSNull.null:(payType?:NSNull.null),@"announcedDueAt":@(date.timeIntervalSince1970),@"dueAt":@(dueTS),@"fireAt":@(fireAt),@"armedAt":@(armedAt),@"armedUptime":@(armedUptime)} mutableCopy];
    // The controller stays memory-only (weak) and the item id is the only
    // detail-page fact written to task metadata.
    self.detailController=detailTask?detailTarget:nil;
    self.detailPollAttempts=0;self.detailFiredAt=0;
    if(detailTask)self.task[@"detailItemId"]=detailItemID?:@"";
    if(cartTask){
        NSDictionary *clock=self.cartClockSnapshot?:WDGCachedClockStatus(nil);BOOL native=WDGNativeClockMode(clock);
        self.task[@"warmupAt"]=@(fireAt);
        self.task[@"maximumTotal"]=maximum.stringValue;self.task[@"concurrentLanes"]=@(self.cartLanes);
        self.task[@"retryEnabled"]=@(self.cartRetryEnabled);self.task[@"retryAttempts"]=@(self.cartRetryAttempts?:1);
        self.task[@"clockMode"]=native?@"native_recent":@"local";
        self.task[@"clockOffsetMs"]=native?clock[@"offsetMs"]:@0;
        self.task[@"clockSource"]=clock[@"source"]?:@"none";
        self.task[@"clockRawMarker"]=clock[@"updatedAtServerMs"]?:NSNull.null;
        self.task[@"clockRawOffsetMs"]=clock[@"rawOffsetMs"]?:NSNull.null;
        self.task[@"clockSampledAt"]=clock[@"sampledAt"]?:@0;
        self.task[@"clockSampledUptime"]=clock[@"sampledUptime"]?:@0;
        self.task[@"clockGeneration"]=clock[@"clockGeneration"]?:@0;
        self.task[@"clockSample"]=clock;self.task[@"clockReason"]=clock[@"reason"]?:@"";
        self.task[@"serverOffsetMs"]=self.task[@"clockOffsetMs"];self.task[@"serverClockOk"]=@(native);
        if(!native)self.task[@"reason"]=@"已确认回退：按本地时间运行，不自动应用后续校准样本";
    }
    // Inside the last five seconds, start the same one warmup immediately.
    // Persist the exact T-5 instant; do not add an early Create or a retry.
    WDGTaskGateArm(&_taskGate,cartTask?MAX(armedAt,fireAt):fireAt);
    self.timer=[NSTimer timerWithTimeInterval:0.1 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self recordEvent:@"task_armed" details:@{@"taskId":self.task[@"id"],@"action":action}];
    return YES;
}
// This only freezes a local request; submitTask owns Confirm/Create dispatch.
- (WDGOrderService *)preparePreheatWithPayType:(NSNumber *)payType error:(NSError **)error {
    NSString *key=[WDGCartSnapshotKey() copy];
    if(!key.length){if(error)*error=WGDError(20,@"请在购物车或助手中明确选择目标商品");return nil;}
    id request=WDGCartBuildRequest(error);
    if(!request)return nil;
    if(![key isEqual:WDGCartSnapshotKey()]){if(error)*error=WGDError(21,@"构建期间购物车目标已变化，请重新确认");return nil;}
    WDGOrderService *service=[WDGOrderService preparePreheatRequest:request sampleKey:key payType:payType error:error];
    if(service&&![key isEqual:WDGCartSnapshotKey()]){if(error)*error=WGDError(21,@"准备期间购物车目标已变化，请重新确认");return nil;}
    return service;
}
- (void)tick:(NSTimer *)timer {
    if(timer!=self.timer){[timer invalidate];return;}
    if(![self.task[@"state"] isEqual:@"armed"]){[timer invalidate];self.timer=nil;return;}
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    BOOL cartTask=[self.task[@"action"] isEqual:@"preheatOnce"];
    if(cartTask){
        NSTimeInterval wallElapsed=now-[self.task[@"armedAt"] doubleValue];
        NSTimeInterval uptimeElapsed=NSProcessInfo.processInfo.systemUptime-[self.task[@"armedUptime"] doubleValue];
        // Cheap local checks also catch backward jumps before the wall clock
        // reaches T-5. Native state is read only when the gate actually fires.
        if(!isfinite(wallElapsed)||!isfinite(uptimeElapsed)||uptimeElapsed<0||fabs(wallElapsed-uptimeElapsed)>0.250){
            WDGInvalidateServerClock();[self cancelTask:@"系统时间与计时基准偏差超过 250 ms，任务已取消，请重新确认"];return;
        }
    }
    WDGTickDecision decision=WDGTaskGateTick(&_taskGate,now,UIApplication.sharedApplication.applicationState==UIApplicationStateActive);
    if(decision==WDGTickWait)return;
    if(decision==WDGTickInactive){[self cancelTask:@"微店离开前台，任务已取消"];return;}
    if(decision==WDGTickExpired){[self cancelTask:@"错过执行时刻超过 2 秒或时间无效，请重新设置"];return;}
    if(decision==WDGTickIdle){[timer invalidate];self.timer=nil;return;}
    if(cartTask&&[self.task[@"clockMode"] isEqual:@"native_recent"]){
        NSDictionary *fresh=[WDGReadServerClock() copy];self.serverClock=fresh;
        NSDate *announced=[NSDate dateWithTimeIntervalSince1970:[self.task[@"announcedDueAt"] doubleValue]];
        if(!WDGClockOffsetsMatch(self.task[@"clockSample"],fresh)||!WDGLocalDeadlineFromClock(announced,fresh,NULL)){
            [self cancelTask:@"微店时差已变化或有效样本已失效，任务已停止，请重新确认"];return;
        }
    }
    if([self.task[@"action"] isEqual:@"preheatOnce"] && ![self.task[@"sampleKey"] isEqual:WDGCartSnapshotKey()]){[self cancelTask:@"购物车目标、规格或数量已变化"];return;}
    NSTimeInterval late=now-[self.task[@"fireAt"] doubleValue];
    [self.timer invalidate];self.timer=nil;
    NSString *action=self.task[@"action"],*firedTaskID=[self.task[@"id"] copy];
    self.task[@"state"]=@"firing";
    [self recordEvent:@"timer_fired" details:@{@"action":action,@"taskId":firedTaskID,@"latenessMs":@(late*1000)}];
    if(![self.task[@"id"] isEqual:firedTaskID]||![self.task[@"state"] isEqual:@"firing"])return;
    if([action isEqual:@"detailOnce"]){[self fireDetailPurchase];return;}
    if(WDGActionIsInterface(action.UTF8String)){
        NSError *error=nil;NSString *taskID=[self.task[@"id"] copy];
        self.task[@"state"]=[action isEqual:@"preheatOnce"]?@"preheating":@"sending";
        self.task[@"reason"]=[action isEqual:@"preheatOnce"]?@"读取确认订单数据，尚未创建订单":@"直接提交创建订单接口，等待响应";
        [self recordEvent:@"interface_send" details:@{@"taskId":taskID}];
        __weak WDGCore *weakSelf=self;
        if(![self.task[@"id"] isEqual:taskID]||![@[@"preheating",@"sending"] containsObject:self.task[@"state"]]||!self.preparedService)return;
        BOOL sent=[self.preparedService submitTask:taskID completion:^(NSDictionary *receipt){[weakSelf completeReply:receipt taskID:taskID];} error:&error];
        if(![self.task[@"id"] isEqual:taskID])return;
        if(!sent&&[@[@"preheating",@"waitingSale",@"sending"] containsObject:self.task[@"state"]]){self.task[@"state"]=@"failed";self.task[@"reason"]=error.localizedDescription?:@"参数验证未通过，未发出请求";self.preparedService=nil;[self recordEvent:@"interface_not_sent" details:@{@"taskId":taskID,@"reason":self.task[@"reason"]}];}
        else if(sent&&[@[@"preheating",@"waitingSale",@"sending"] containsObject:self.task[@"state"]]){
            self.replyTimeout=[NSTimer timerWithTimeInterval:MAX(35,[self.task[@"dueAt"] doubleValue]-now+35) target:self selector:@selector(replyTimedOut:) userInfo:taskID repeats:NO];
            [NSRunLoop.mainRunLoop addTimer:self.replyTimeout forMode:NSRunLoopCommonModes];
        }
    } else {
        self.firedCount++;
        self.task[@"state"]=@"fired";
        self.task[@"reason"]=[action isEqual:@"dryRun"]?@"本地定时演练完成，未发网络请求":@"已到设定时间";
        [self recordEvent:@"local_task_complete" details:@{@"action":action,@"taskId":self.task[@"id"]}];
        [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
        WDGShowOverlay();
    }
}
// detailOnce fire path. The page's own 立即购买 is the only action taken here;
// the resulting confirmation page is the only thing ever submitted, and only
// after the adapter publishes a sample newer than this trigger.
- (void)fireDetailPurchase {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(), ^{[self fireDetailPurchase];});return;}
    if(![self.task[@"action"] isEqual:@"detailOnce"]||![self.task[@"state"] isEqual:@"firing"])return;
    NSString *taskID=[self.task[@"id"] copy];
    NSString *expected=[self.task[@"detailItemId"] isKindOfClass:NSString.class]?self.task[@"detailItemId"]:@"";
    id controller=self.detailController;
    NSString *reason=nil;
    if(!controller)reason=@"详情页实例已释放，未提交";
    else if(!WDGDetailIsPage(controller))reason=@"详情页对象已失效，未提交";
    else {
        SEL selector=NSSelectorFromString(@"itemId");
        Method method=WDGDetailInstanceMethod(controller,selector,2);
        if(!method||!WDGDetailMethodReturns(method,'@')||!WDGDetailMethodArgument(method,1,':'))reason=@"详情页 itemId 读取 ABI 不匹配，未提交";
        else {
            id value=nil;
            @try{value=((id(*)(id,SEL))objc_msgSend)(controller,selector);}
            @catch(__unused NSException *exception){reason=@"详情页 itemId 读取异常，未提交";}
            if(!reason){
                if(![value isKindOfClass:NSString.class]||![(NSString *)value length])reason=@"详情页 itemId 为空，未提交";
                else if(expected.length&&![(NSString *)value isEqualToString:expected])reason=@"详情页商品已变化，未提交";
            }
        }
    }
    if(!reason&&!WDGDetailPurchaseReady(controller))reason=@"立即购买方法 ABI 不是 void(id,SEL)，未提交";
    if(reason){
        self.task[@"state"]=@"failed";
        self.task[@"reason"]=reason;
        self.preparedService=nil;self.detailController=nil;
        [self recordEvent:@"detail_not_fired" details:@{@"taskId":taskID?:@"",@"reason":reason}];
        return;
    }
    self.task[@"state"]=@"preheating";
    self.task[@"reason"]=@"已触发立即购买，等待确认订单数据";
    self.detailPollAttempts=0;self.detailFiredAt=NSDate.date.timeIntervalSince1970;
    [self recordEvent:@"detail_purchase" details:@{@"taskId":taskID?:@""}];
    @try{((void(*)(id,SEL))objc_msgSend)(controller,NSSelectorFromString(@"handlePurchaseOperation"));}
    @catch(__unused NSException *exception){
        self.task[@"state"]=@"failed";
        self.task[@"reason"]=@"立即购买调用异常，未提交";
        [self recordEvent:@"detail_not_fired" details:@{@"taskId":taskID?:@"",@"reason":self.task[@"reason"]}];
        return;
    }
    if(![self.task[@"id"] isEqual:taskID]||![self.task[@"state"] isEqual:@"preheating"])return;
    self.detailPoll=[NSTimer timerWithTimeInterval:0.05 target:self selector:@selector(detailPollTick:) userInfo:taskID repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.detailPoll forMode:NSRunLoopCommonModes];
}
// 40 probes at 0.05s (about two seconds). A sample is usable only when it is a
// new confirmation page published after the purchase trigger and carries
// exactly one payment option; anything else ends the task without submitting.
- (void)detailPollTick:(NSTimer *)timer {
    if(timer!=self.detailPoll){[timer invalidate];return;}
    if(![self.task[@"action"] isEqual:@"detailOnce"]||![self.task[@"state"] isEqual:@"preheating"]){[timer invalidate];self.detailPoll=nil;return;}
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){[timer invalidate];self.detailPoll=nil;[self cancelTask:@"微店离开前台，任务已取消"];return;}
    NSDictionary *snapshot=self.snapshot?:@{};
    NSString *sampleKey=[snapshot[@"sampleKey"] isKindOfClass:NSString.class]?snapshot[@"sampleKey"]:nil;
    NSString *baseline=[self.task[@"sampleKey"] isKindOfClass:NSString.class]?self.task[@"sampleKey"]:@"";
    NSNumber *capturedAt=[snapshot[@"capturedAt"] isKindOfClass:NSNumber.class]?snapshot[@"capturedAt"]:nil;
    // No publish timestamp means the sample cannot be proven newer than the
    // purchase trigger, so it is never submitted.
    BOOL fresh=capturedAt&&[capturedAt doubleValue]>=self.detailFiredAt;
    if(sampleKey.length&&![sampleKey isEqualToString:baseline]&&[snapshot[@"stage"] isEqual:@"confirmed"]&&fresh){
        NSArray *options=[snapshot[@"payOptions"] isKindOfClass:NSArray.class]?snapshot[@"payOptions"]:@[];
        NSNumber *payType=options.count==1&&[options.firstObject isKindOfClass:NSDictionary.class]?((NSDictionary *)options.firstObject)[@"type"]:nil;
        [timer invalidate];self.detailPoll=nil;
        if(options.count>1){[self failDetailTask:[NSString stringWithFormat:@"未拿到确认页数据，未提交：确认页有 %lu 个可用支付按钮，无法唯一确定",(unsigned long)options.count]];return;}
        if(![payType isKindOfClass:NSNumber.class]){[self failDetailTask:@"未拿到确认页数据，未提交：确认页未给出唯一支付参数"];return;}
        [self submitDetailSample:sampleKey payType:payType];
        return;
    }
    if(++self.detailPollAttempts>=40){[timer invalidate];self.detailPoll=nil;[self failDetailTask:@"未拿到确认页数据，未提交"];}
}
- (void)failDetailTask:(NSString *)reason {
    if(![self.task[@"action"] isEqual:@"detailOnce"])return;
    if(![@[@"firing",@"preheating"] containsObject:self.task[@"state"]])return;
    self.task[@"state"]=@"failed";
    self.task[@"reason"]=reason?:@"未拿到确认页数据，未提交";
    self.preparedService=nil;self.detailController=nil;
    [self recordEvent:@"detail_failed" details:@{@"taskId":[self.task[@"id"] copy],@"reason":self.task[@"reason"]}];
}
// The fresh sample is bound exactly like serviceOnce: prepare observed
// interface, then submitTask. A rejected arm or a rejected submit ends the task.
- (void)submitDetailSample:(NSString *)sampleKey payType:(NSNumber *)payType {
    NSString *taskID=[self.task[@"id"] copy];
    if(![self.task[@"action"] isEqual:@"detailOnce"]||![self.task[@"state"] isEqual:@"preheating"])return;
    NSError *error=nil;
    WDGOrderService *service=WDGPrepareObservedInterface(sampleKey,payType,&error);
    if(!service){[self failDetailTask:error.localizedDescription?:@"确认页参数未就绪，未提交"];return;}
    self.preparedService=service;self.lastReceipt=nil;
    self.task[@"state"]=@"sending";
    self.task[@"reason"]=@"已触发立即购买，正在提交创建订单";
    [self recordEvent:@"detail_submit" details:@{@"taskId":taskID?:@""}];
    __weak WDGCore *weakSelf=self;
    BOOL sent=[service submitTask:taskID completion:^(NSDictionary *receipt){[weakSelf completeReply:receipt taskID:taskID];} error:&error];
    if(![self.task[@"id"] isEqual:taskID])return;
    if(!sent&&[@[@"preheating",@"waitingSale",@"sending"] containsObject:self.task[@"state"]]){
        self.task[@"state"]=@"failed";
        self.task[@"reason"]=error.localizedDescription?:@"参数验证未通过，未发出请求";
        self.preparedService=nil;
        [self recordEvent:@"detail_not_sent" details:@{@"taskId":taskID?:@"",@"reason":self.task[@"reason"]}];
    } else if(sent&&[@[@"preheating",@"waitingSale",@"sending"] containsObject:self.task[@"state"]]){
        self.replyTimeout=[NSTimer timerWithTimeInterval:35 target:self selector:@selector(replyTimedOut:) userInfo:taskID repeats:NO];
        [NSRunLoop.mainRunLoop addTimer:self.replyTimeout forMode:NSRunLoopCommonModes];
    }
}
- (void)cancelTask:(NSString *)reason {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(), ^{[self cancelTask:reason];});return;}
    if(self.cancellingTask)return;
    self.cancellingTask=YES;
    WDGTaskGateCancel(&_taskGate);
    [self.timer invalidate];self.timer=nil;
    [self.detailPoll invalidate];self.detailPoll=nil;
    NSString *taskID=[self.task[@"id"] copy];
    WDGOrderService *service=self.preparedService;
    BOOL stopped=service?[service cancelBeforeCreate]:![@[@"sending",@"unknown"] containsObject:self.task[@"state"]];
    if(!stopped){
        if([self.task[@"id"] isEqual:taskID]&&[@[@"preheating",@"waitingSale",@"sending",@"unknown"] containsObject:self.task[@"state"]]){
            if(![self.task[@"state"] isEqual:@"unknown"])self.task[@"state"]=@"sending";
            self.task[@"reason"]=@"创建请求已经发出，继续核对结果；本地取消不代表撤单";
            [self recordEvent:@"cancel_after_send" details:@{@"taskId":taskID?:@""}];
        }
        self.cancellingTask=NO;return;
    }
    [self.replyTimeout invalidate];self.replyTimeout=nil;
    if(self.preparedService==service)self.preparedService=nil;
    if([self.task[@"id"] isEqual:taskID]&&[@[@"armed",@"firing",@"preheating",@"waitingSale"] containsObject:self.task[@"state"]]){
        self.task[@"state"]=@"cancelled";self.task[@"reason"]=reason?:@"用户取消";
        [self recordEvent:@"task_cancelled" details:@{@"reason":self.task[@"reason"],@"taskId":taskID?:@""}];
    }
    self.cancellingTask=NO;
}
- (void)completeReply:(NSDictionary *)receipt taskID:(NSString *)taskID {
    if(!NSThread.isMainThread){NSDictionary *copy=[receipt copy];dispatch_async(dispatch_get_main_queue(), ^{[self completeReply:copy taskID:taskID];});return;}
    if(![self.task[@"id"] isEqual:taskID]||![@[@"preheating",@"waitingSale",@"sending",@"unknown"] containsObject:self.task[@"state"]])return;
    NSString *state=receipt[@"state"];
    if(![receipt[@"terminal"] boolValue]){
        NSArray *stages=@[@"preheating",@"waitingSale",@"sending"];
        NSUInteger current=[stages indexOfObject:self.task[@"state"]],next=[stages indexOfObject:state?:@""];
        if(current==NSNotFound||next==NSNotFound||next<current)return;
        self.task[@"state"]=state;
        self.task[@"reason"]=receipt[@"message"]?:@"等待确认数据";
        [self recordEvent:@"interface_stage" details:@{@"taskId":taskID,@"state":state,@"reason":self.task[@"reason"]}];return;
    }
    if(![@[@"apiSucceeded",@"failed",@"cancelled",@"unknown"] containsObject:state?:@""])state=@"unknown";
    [self.replyTimeout invalidate];self.replyTimeout=nil;
    self.lastReceipt=[receipt copy];
    // Unknown is provisional: keep the service and accept its late final reply.
    if(![state isEqual:@"unknown"])self.preparedService=nil;
    self.task[@"state"]=state;
    self.task[@"reason"]=receipt[@"message"]?:@"接口结果待核对";
    self.task[@"apiSucceeded"]=receipt[@"apiSucceeded"]?:@NO;
    self.task[@"orderCount"]=receipt[@"orderCount"]?:@0;
    [self recordEvent:@"interface_result" details:@{@"taskId":taskID,@"state":state,@"reason":self.task[@"reason"]}];
}
- (void)replyTimedOut:(NSTimer *)timer {
    if(timer!=self.replyTimeout)return;
    self.replyTimeout=nil;
    NSString *taskID=timer.userInfo;
    if(![self.task[@"id"] isEqual:taskID]||![@[@"preheating",@"waitingSale",@"sending"] containsObject:self.task[@"state"]])return;
    [self.preparedService expireUnresolvedTask:taskID];
    if([@[@"preheating",@"waitingSale"] containsObject:self.task[@"state"]]){[self cancelTask:@"确认数据等待超时，创建请求未发出"];return;}
    if(![self.task[@"state"] isEqual:@"sending"])return;
    self.task[@"state"]=@"unknown";self.task[@"reason"]=@"创建接口暂未返回，订单结果待核对；未自动重试";
    [self recordEvent:@"interface_timeout" details:@{@"taskId":taskID}];
}
- (void)willResign:(NSNotification *)n {[self cancelTask:@"微店已切到后台或锁屏，请重新设置任务"] ;}
- (void)clockChanged:(NSNotification *)n {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(), ^{[self clockChanged:n];});return;}
    WDGInvalidateServerClock();
    [self cancelTask:@"系统时间已变化，旧校准样本已失效，请重新确认任务"];
}
- (NSString *)exportReport:(NSError **)error {
    NSMutableDictionary *data=[self.status mutableCopy];
    [data removeObjectForKey:@"receipt"]; // Any order numbers stay in UI memory.
    data[@"hooks"]=WDGObserverDiagnostics();
    NSData *json=[NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:error];
    NSString *path=[self.storagePath stringByAppendingPathComponent:@"report.json"];
    if(json&&[json writeToFile:path options:NSDataWritingAtomic error:error]){
        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:NULL];return path;
    }
    return nil;
}
@end
