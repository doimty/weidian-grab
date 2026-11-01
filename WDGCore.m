#import "WDGCore.h"
#import "WDGBuild.h"
#import "WDGTaskGate.h"
#import "WDGOrderService.h"
#import "WDGCart.h"
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <objc/runtime.h>
#import <objc/message.h>

NSString * const WDGStateDidChange = @"WDGStateDidChange";
NSString * const WDGVersion = @"0.7.1";
#ifndef WDG_BUILD_ID
#define WDG_BUILD_ID "local-unbuilt"
#endif
NSString * const WDGBuildID = @WDG_BUILD_ID;

static NSError *WGDError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"WeidianGrab" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
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
            // Never resume a transaction after process restart: UI bindings are gone.
            NSDictionary *task=prior[@"task"];
            if ([task isKindOfClass:NSDictionary.class] && [@[@"armed",@"firing",@"sending",@"unknown"] containsObject:task[@"state"]]) {
                _task=[task mutableCopy];
                BOOL sent=[@[@"sending",@"unknown"] containsObject:task[@"state"]];
                _task[@"state"]=sent?@"unknown":@"cancelled";
                _task[@"reason"]=sent?@"上次接口请求结果待核对，不自动重试":@"App 已重启，旧任务已取消";
            }
        }
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
             @"firedCount":@(self.firedCount),@"ioError":self.ioError?:@"",@"storagePath":self.storagePath,@"receipt":self.lastReceipt?:@{},@"transport":[WDGOrderService diagnostics],@"cart":WDGCartDiagnostics()};
}
- (void)persist {
    // Call only on the main queue. All persisted fields are our own metadata or
    // the adapter's product whitelist, never an NSURLRequest or raw model.
    NSDictionary *payload=@{@"version":WDGVersion,@"build":WDGBuildID,@"captureEnabled":@(self.captureEnabled),@"snapshot":self.snapshot?:@{},@"task":[self.task copy]};
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
    if([self.task[@"state"] isEqual:@"armed"] && ![self.task[@"sampleKey"] isEqual:frozen[@"sampleKey"]]) [self cancelTask:@"采集内容或页面已变化"];
    self.snapshot=frozen;
    [self recordEvent:@"snapshot" details:@{@"stage":frozen[@"stage"]?:@"",@"pageKind":frozen[@"pageKind"]?:@"",@"itemCount":@([frozen[@"items"] count])}];
}
- (void)clearSnapshot {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(), ^{[self clearSnapshot];});return;}
    [self cancelTask:@"采集样本已清空"];self.snapshot=@{};
    [self recordEvent:@"snapshot_cleared" details:@{}];
}
- (BOOL)armAt:(NSDate *)date action:(NSString *)action payType:(NSNumber *)payType error:(NSError **)error {
    if(!NSThread.isMainThread){if(error)*error=WGDError(1,@"请在主线程设置任务");return NO;}
    NSTimeInterval delta=[date timeIntervalSinceNow];
    if([self.task[@"state"] isEqual:@"sending"]){if(error)*error=WGDError(3,@"上一笔接口请求正在等待结果，请勿覆盖");return NO;}
    NSString *reason=nil;
    if(![@[@"reminder",@"dryRun",@"serviceOnce",@"preheatOnce"] containsObject:action])reason=@"未知任务类型";
    else if(delta<2||delta>86400)reason=@"任务时间请设在 2 秒至 24 小时以内";
    else if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)reason=@"请保持微店在前台";
    else if([action isEqual:@"serviceOnce"]){
        NSArray *items=self.snapshot[@"items"];
        NSString *price=self.snapshot[@"totalPrice"];
        if(items.count==0||price.length==0)reason=@"请先进入订单确认页采集商品、规格及金额";
        else if(!payType)reason=@"请选择从当前确认页读取的提交按钮";
        else {
            NSString *bindingReason=nil;
            if(!WDGInterfaceTargetReady(self.snapshot[@"sampleKey"],payType,&bindingReason)) reason=bindingReason?:@"当前页面尚未完成验证";
        }
    }
    else if([action isEqual:@"preheatOnce"]){
        if(WDGCartSelectedLines().count==0)reason=@"请先在购物车页让插件采集到商品";
        else if(!payType)reason=@"请选择支付参数";
        else {
            NSString *preheatReason=nil;
            if(![WDGOrderService preheatReady:&preheatReason])reason=preheatReason?:@"预热接口未就绪";
        }
    }
    if([action isEqual:@"serviceOnce"] && delta>590)reason=@"接口参数本轮只验证十分钟有效期，请把任务设在十分钟以内";
    if([action isEqual:@"preheatOnce"] && delta>43200)reason=@"预热任务请设在 12 小时以内";
    if(reason){if(error)*error=WGDError(2,reason);return NO;}
    WDGOrderService *prepared=nil;
    if([action isEqual:@"serviceOnce"]){
        prepared=WDGPrepareObservedInterface(self.snapshot[@"sampleKey"],payType,error);
        if(!prepared)return NO;
    } else if([action isEqual:@"preheatOnce"]){
        prepared=[self preparePreheatWithPayType:payType error:error];
        if(!prepared)return NO;
    }
    [self cancelTask:@"新任务替代旧任务"];
    self.preparedService=prepared;self.lastReceipt=nil;
    self.task=[@{@"id":NSUUID.UUID.UUIDString,@"state":@"armed",@"action":action,@"sampleKey":self.snapshot[@"sampleKey"]?:@"",@"payType":payType?:NSNull.null,@"dueAt":@(date.timeIntervalSince1970),@"armedAt":@(NSDate.date.timeIntervalSince1970)} mutableCopy];
    WDGTaskGateArm(&_taskGate,date.timeIntervalSince1970);
    self.timer=[NSTimer timerWithTimeInterval:0.1 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self recordEvent:@"task_armed" details:@{@"taskId":self.task[@"id"],@"action":action}];
    return YES;
}
// Build a requestDO from the captured cart lines, so a pre-sale item can be
// submitted at the sale instant without visiting the confirmation page.
- (WDGOrderService *)preparePreheatWithPayType:(NSNumber *)payType error:(NSError **)error {
    NSArray<NSDictionary *> *lines=WDGCartSelectedLines();
    NSString *key=WDGCartSnapshotKey();
    if(!lines.count||!key.length){if(error)*error=WGDError(20,@"购物车采集为空，请先打开购物车页");return nil;}
    Class reqClass=NSClassFromString(@"VDTradeConfirmOrderRequestDO");
    Class itemClass=NSClassFromString(@"VDTradeConfOrderRequestItemDO");
    if(!reqClass||!itemClass){if(error)*error=WGDError(21,@"订单请求模型不可用");return nil;}
    SEL fromJSON=NSSelectorFromString(@"yy_modelWithJSON:");
    Method m=class_getClassMethod(reqClass,fromJSON);
    if(!m||method_getNumberOfArguments(m)!=3){if(error)*error=WGDError(22,@"请求模型构造入口不可用");return nil;}
    // Raw ids are recovered from the session-salted refs through the same map
    // the cart module kept in memory; nothing sensitive is written to disk.
    NSMutableArray *items=[NSMutableArray array];
    for(NSDictionary *line in lines){
        NSDictionary *raw=WDGCartRawLine(line[@"itemRef"]);
        if(!raw){continue;}
        NSMutableDictionary *json=[NSMutableDictionary dictionary];
        json[@"item_id"]=raw[@"itemId"]?:@"";
        json[@"item_sku_id"]=raw[@"skuId"]?:@"";
        json[@"quantity"]=raw[@"count"]?:@"1";
        if(raw[@"priceType"])json[@"price_type"]=raw[@"priceType"];
        id item=((id(*)(id,SEL,id))objc_msgSend)(itemClass,fromJSON,json);
        if(item)[items addObject:item];
    }
    if(!items.count){if(error)*error=WGDError(23,@"购物车商品未能转换为请求条目");return nil;}
    NSDictionary *requestJSON=@{@"items":items};
    id request=((id(*)(id,SEL,id))objc_msgSend)(reqClass,fromJSON,requestJSON);
    if(!request||![request isKindOfClass:reqClass]){if(error)*error=WGDError(24,@"请求模型构造失败");return nil;}
    return [WDGOrderService preparePreheatRequest:request sampleKey:key payType:payType error:error];
}
- (void)tick:(NSTimer *)timer {
    if(![self.task[@"state"] isEqual:@"armed"]){[timer invalidate];self.timer=nil;return;}
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    WDGTickDecision decision=WDGTaskGateTick(&_taskGate,now,UIApplication.sharedApplication.applicationState==UIApplicationStateActive);
    if(decision==WDGTickWait)return;
    if(decision==WDGTickInactive){[self cancelTask:@"微店离开前台，任务已取消"];return;}
    if(decision==WDGTickExpired){[self cancelTask:@"错过执行时刻超过 2 秒或时间无效，请重新设置"];return;}
    if(decision==WDGTickIdle){[timer invalidate];self.timer=nil;return;}
    NSTimeInterval late=now-[self.task[@"dueAt"] doubleValue];
    [self.timer invalidate];self.timer=nil;
    NSString *action=self.task[@"action"];
    self.task[@"state"]=@"firing";
    [self recordEvent:@"timer_fired" details:@{@"action":action,@"taskId":self.task[@"id"],@"latenessMs":@(late*1000)}];
    if([action isEqual:@"serviceOnce"]){
        NSError *error=nil;NSString *taskID=[self.task[@"id"] copy];
        self.task[@"state"]=@"sending";self.task[@"reason"]=@"直接提交 CreateOrder 接口，等待响应";
        [self recordEvent:@"interface_send" details:@{@"taskId":taskID}];
        __weak WDGCore *weakSelf=self;
        BOOL sent=[self.preparedService submitTask:taskID completion:^(NSDictionary *receipt){[weakSelf completeReply:receipt taskID:taskID];} error:&error];
        if(!sent){self.task[@"state"]=@"failed";self.task[@"reason"]=error.localizedDescription?:@"参数验证未通过，未发出请求";self.preparedService=nil;[self recordEvent:@"interface_not_sent" details:@{@"taskId":taskID,@"reason":self.task[@"reason"]}];}
        else if([self.task[@"state"] isEqual:@"sending"]){
            self.replyTimeout=[NSTimer timerWithTimeInterval:30 target:self selector:@selector(replyTimedOut:) userInfo:taskID repeats:NO];
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
- (void)cancelTask:(NSString *)reason {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(), ^{[self cancelTask:reason];});return;}
    if([self.task[@"state"] isEqual:@"sending"]){self.task[@"reason"]=@"请求已经发出，继续等待结果；本地取消不代表撤单";[self recordEvent:@"cancel_after_send" details:@{@"taskId":self.task[@"id"]}];return;}
    WDGTaskGateCancel(&_taskGate);
    [self.timer invalidate];self.timer=nil;
    self.preparedService=nil;
    if([@[@"armed",@"firing"] containsObject:self.task[@"state"]]){
        self.task[@"state"]=@"cancelled";self.task[@"reason"]=reason?:@"用户取消";
        [self recordEvent:@"task_cancelled" details:@{@"reason":self.task[@"reason"],@"taskId":self.task[@"id"]?:@""}];
    }
}
- (void)completeReply:(NSDictionary *)receipt taskID:(NSString *)taskID {
    if(![self.task[@"id"] isEqual:taskID]||![@[@"sending",@"unknown"] containsObject:self.task[@"state"]])return;
    [self.replyTimeout invalidate];self.replyTimeout=nil;
    self.lastReceipt=[receipt copy];self.preparedService=nil;
    self.task[@"state"]=receipt[@"state"]?:@"unknown";
    self.task[@"reason"]=receipt[@"message"]?:@"接口结果待核对";
    self.task[@"apiSucceeded"]=receipt[@"apiSucceeded"]?:@NO;
    self.task[@"orderCount"]=receipt[@"orderCount"]?:@0;
    [self recordEvent:@"interface_result" details:@{@"taskId":taskID,@"state":self.task[@"state"],@"reason":self.task[@"reason"]}];
}
- (void)replyTimedOut:(NSTimer *)timer {
    NSString *taskID=timer.userInfo;
    if(![self.task[@"id"] isEqual:taskID]||![self.task[@"state"] isEqual:@"sending"])return;
    [self.preparedService expireUnresolvedTask:taskID];
    self.task[@"state"]=@"unknown";self.task[@"reason"]=@"接口暂未返回，订单结果待核对；未自动重试";
    [self recordEvent:@"interface_timeout" details:@{@"taskId":taskID}];
}
- (void)willResign:(NSNotification *)n {[self cancelTask:@"微店已切到后台或锁屏，请重新设置任务"] ;}
- (void)clockChanged:(NSNotification *)n {[self cancelTask:@"系统时间已变化，请重新设置任务"] ;}
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
