#import "WDGCore.h"
#import "WDGBuild.h"
#import "WDGTaskGate.h"
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>

NSString * const WDGStateDidChange = @"WDGStateDidChange";
NSString * const WDGVersion = @"0.5.2";
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
            if ([task isKindOfClass:NSDictionary.class] && [@[@"armed",@"firing"] containsObject:task[@"state"]]) {
                _task=[task mutableCopy];_task[@"state"]=@"cancelled";_task[@"reason"]=@"App 已重启，请重新设置任务";
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
             @"firedCount":@(self.firedCount),@"ioError":self.ioError?:@"",@"storagePath":self.storagePath};
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
    NSString *reason=nil;
    if(![@[@"reminder",@"dryRun",@"nativeOnce"] containsObject:action])reason=@"未知任务类型";
    else if(delta<2||delta>86400)reason=@"任务时间请设在 2 秒至 24 小时以内";
    else if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)reason=@"请保持微店在前台";
    else if([action isEqual:@"nativeOnce"]){
        NSArray *items=self.snapshot[@"items"];
        NSString *price=self.snapshot[@"totalPrice"];
        if(items.count==0||price.length==0)reason=@"请先进入订单确认页采集商品、规格及金额";
        else if(!payType)reason=@"请选择从当前确认页读取的提交按钮";
        else {
            NSString *bindingReason=nil;
            if(!WDGNativeTargetReady(self.snapshot[@"sampleKey"],payType,&bindingReason)) reason=bindingReason?:@"当前页面尚未完成验证";
        }
    }
    if(reason){if(error)*error=WGDError(2,reason);return NO;}
    [self cancelTask:@"新任务替代旧任务"];
    self.task=[@{@"id":NSUUID.UUID.UUIDString,@"state":@"armed",@"action":action,@"sampleKey":self.snapshot[@"sampleKey"]?:@"",@"payType":payType?:NSNull.null,@"dueAt":@(date.timeIntervalSince1970),@"armedAt":@(NSDate.date.timeIntervalSince1970)} mutableCopy];
    WDGTaskGateArm(&_taskGate,date.timeIntervalSince1970);
    self.timer=[NSTimer timerWithTimeInterval:0.1 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self recordEvent:@"task_armed" details:@{@"taskId":self.task[@"id"],@"action":action}];
    return YES;
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
    if([action isEqual:@"nativeOnce"]){
        NSError *error=nil;
        BOOL sent=WDGExecuteNativeOnce(self.task[@"sampleKey"],self.task[@"payType"],&error);
        self.task[@"state"]=sent?@"dispatched":@"failed";
        self.task[@"reason"]=sent?@"已交给微店处理，请查看 App 的订单结果":(error.localizedDescription?:@"页面状态未通过验证");
        [self recordEvent:sent?@"native_dispatched":@"native_cancelled" details:@{@"taskId":self.task[@"id"],@"reason":self.task[@"reason"]}];
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
    WDGTaskGateCancel(&_taskGate);
    [self.timer invalidate];self.timer=nil;
    if([@[@"armed",@"firing"] containsObject:self.task[@"state"]]){
        self.task[@"state"]=@"cancelled";self.task[@"reason"]=reason?:@"用户取消";
        [self recordEvent:@"task_cancelled" details:@{@"reason":self.task[@"reason"],@"taskId":self.task[@"id"]?:@""}];
    }
}
- (void)willResign:(NSNotification *)n {[self cancelTask:@"微店已切到后台或锁屏，请重新设置任务"] ;}
- (void)clockChanged:(NSNotification *)n {[self cancelTask:@"系统时间已变化，请重新设置任务"] ;}
- (NSString *)exportReport:(NSError **)error {
    NSMutableDictionary *data=[self.status mutableCopy];
    data[@"hooks"]=WDGObserverDiagnostics();
    NSData *json=[NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:error];
    NSString *path=[self.storagePath stringByAppendingPathComponent:@"report.json"];
    if(json&&[json writeToFile:path options:NSDataWritingAtomic error:error]){
        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:NULL];return path;
    }
    return nil;
}
@end
