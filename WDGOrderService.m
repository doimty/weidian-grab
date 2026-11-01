#import "WDGOrderService.h"
#import "WDGServiceState.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>
#import <math.h>

// Microstore buyer 7.9.62: Confirm and Create both use the verified native
// callback void (^)(BOOL, id payload, WDNErrorDO *). No Controller or payment
// URL is invoked here. The real transport/signature remains the App's Service.
static NSUInteger gCreateCalls, gConfirmCalls, gReplies;
static uint64_t gGeneration;
static BOOL (^gExecutionAllowed)(void);
static NSString * const gCreateSelector = @"createOrderRequestDO:confirmOrderDO:result:";
static NSString * const gConfirmSelector = @"confirmOrderWithRequestDO:result:";

static NSError *WGSError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"WeidianGrab.OrderService" code:code
                          userInfo:@{NSLocalizedDescriptionKey:message}];
}
static const char *WGSType(const char *s) {
    if (!s) return "";
    while (*s && strchr("rnNoORV", *s)) ++s;
    return s;
}
static BOOL WGSObject(const char *s) {
    s=WGSType(s);return s[0]=='@' && (!s[1] || s[1]=='"');
}
static BOOL WGSTyped(Method m, unsigned count, char expected) {
    if (!m || method_getNumberOfArguments(m)!=count) return NO;
    char buf[256]={0};method_getReturnType(m,buf,sizeof(buf));
    const char *s=WGSType(buf);
    return expected=='@'?WGSObject(s):(s[0]==expected && !s[1]);
}
static BOOL WGSArg(Method m,unsigned index,char expected) {
    if (!m || index>=method_getNumberOfArguments(m)) return NO;
    char buf[256]={0};method_getArgumentType(m,index,buf,sizeof(buf));
    const char *s=WGSType(buf);
    return expected=='@'?WGSObject(s):(s[0]==expected && !s[1]);
}
static id WGSGet(id object,NSString *name) {
    if (!object) return nil;
    SEL sel=NSSelectorFromString(name);
    if (!WGSTyped(class_getInstanceMethod(object_getClass(object),sel),2,'@')) return nil;
    @try { return ((id(*)(id,SEL))objc_msgSend)(object,sel); }
    @catch (__unused NSException *e) { return nil; }
}
static NSString *WGSString(id object,NSString *name) {
    id value=WGSGet(object,name);
    return [value isKindOfClass:NSString.class] && [value length]<=4096?value:nil;
}
static NSNumber *WGSBool(id object,NSString *name) {
    if (!object) return nil;
    SEL sel=NSSelectorFromString(name);Method m=class_getInstanceMethod(object_getClass(object),sel);
    if (!WGSTyped(m,2,'B') && !WGSTyped(m,2,'c')) return nil;
    @try { return @(((BOOL(*)(id,SEL))objc_msgSend)(object,sel)); }
    @catch (__unused NSException *e) { return nil; }
}
static NSNumber *WGSUnsigned(id object,NSString *name) {
    if (!object) return nil;
    SEL sel=NSSelectorFromString(name);
    if (!WGSTyped(class_getInstanceMethod(object_getClass(object),sel),2,'Q')) return nil;
    @try { return @(((NSUInteger(*)(id,SEL))objc_msgSend)(object,sel)); }
    @catch (__unused NSException *e) { return nil; }
}
static NSArray *WGSArray(id object,NSString *name) {
    id value=WGSGet(object,name);
    return [value isKindOfClass:NSArray.class] && [value count]<=200?value:nil;
}
static BOOL WGSAllowed(void) { return !gExecutionAllowed || gExecutionAllowed(); }
static NSData *WGSMemorySnapshot(id model) {
    // This complete parameter fingerprint stays in memory. It is never a log,
    // an export or a reconstructed raw HTTP request.
    id json=WGSGet(model,@"yy_modelToJSONObject");
    if (![json isKindOfClass:NSDictionary.class]) return nil;
    NSData *data=[NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingSortedKeys error:NULL];
    return data.length && data.length<=2*1024*1024?data:nil;
}
static NSDecimalNumber *WGSAmount(NSString *text) {
    if (!text.length || text.length>20) return nil;
    NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:@"^[0-9]+(?:\\.[0-9]{1,2})?$" options:0 error:NULL];
    if ([pattern numberOfMatchesInString:text options:0 range:NSMakeRange(0,text.length)]!=1) return nil;
    NSDecimalNumber *n=[NSDecimalNumber decimalNumberWithString:text locale:@{NSLocaleDecimalSeparator:@"."}];
    return [n isEqualToNumber:NSDecimalNumber.notANumber]?nil:n;
}
static BOOL WGSQuantity(NSString *s) {
    NSCharacterSet *digits=[NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
    return s.length && s.length<=6 && [s rangeOfCharacterFromSet:digits.invertedSet].location==NSNotFound && s.longLongValue>0 && s.longLongValue<=99999;
}
static NSString *WGSTuple(id item) {
    NSString *iid=WGSString(item,@"item_id"),*sku=WGSString(item,@"item_sku_id")?:@"",*qty=WGSString(item,@"quantity");
    if (!iid.length || !WGSQuantity(qty)) return nil;
    NSData *data=[NSJSONSerialization dataWithJSONObject:@[iid,sku,@(qty.longLongValue)] options:0 error:NULL];
    return data?[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]:nil;
}
static NSArray *WGSRequestTuples(id request) {
    NSArray *items=WGSArray(request,@"items");if (!items.count) return nil;
    Class type=NSClassFromString(@"VDTradeConfOrderRequestItemDO");
    NSMutableArray *tuples=[NSMutableArray array];
    for (id item in items) {
        if (!type || ![item isKindOfClass:type]) return nil;
        NSString *t=WGSTuple(item);if (!t) return nil;[tuples addObject:t];
    }
    return [tuples sortedArrayUsingSelector:@selector(compare:)];
}
static NSArray *WGSConfirmationTuples(id model) {
    NSArray *shops=WGSArray(model,@"shop_list");if (!shops.count) return nil;
    Class type=NSClassFromString(@"VDTradeConfirmOrderShopItemDO");
    NSMutableArray *tuples=[NSMutableArray array];
    for (id shop in shops) {
        NSArray *items=WGSArray(shop,@"item_list");if (!items) return nil;
        for (id item in items) {
            if (!type || ![item isKindOfClass:type]) return nil;
            NSString *t=WGSTuple(item);if (!t) return nil;[tuples addObject:t];
        }
    }
    return [tuples sortedArrayUsingSelector:@selector(compare:)];
}
static BOOL WGSServiceABI(NSString *name,unsigned count,NSString **reason) {
    Class cls=NSClassFromString(@"VDTradeConfOrderService");
    Method m=cls?class_getClassMethod(cls,NSSelectorFromString(name)):NULL;
    BOOL ok=WGSTyped(m,count,'v') && WGSArg(m,2,'@');
    if (count==5) ok=ok && WGSArg(m,3,'@');
    char buf[256]={0};if (m) method_getArgumentType(m,count-1,buf,sizeof(buf));
    ok=ok && strcmp(WGSType(buf),"@?")==0;
    if (reason) *reason=ok?nil:@"原生订单 Service 模型与回调 ABI 不匹配";
    return ok;
}
static id WGSConvertConfirmation(NSDictionary *json) {
    Class cls=NSClassFromString(@"VDTradeConfirmOrderDO");
    for (NSString *name in @[@"yy_modelWithDictionary:",@"yy_modelWithJSON:"]) {
        SEL sel=NSSelectorFromString(name);Method m=cls?class_getClassMethod(cls,sel):NULL;
        if (!WGSTyped(m,3,'@') || !WGSArg(m,2,'@')) continue;
        @try { id model=((id(*)(id,SEL,id))objc_msgSend)(cls,sel,json);if ([model isKindOfClass:cls]) return model; }
        @catch (__unused NSException *e) { }
    }
    return nil;
}
static BOOL WGSSetObject(id object,NSString *name,id value) {
    SEL sel=NSSelectorFromString(name);Method m=class_getInstanceMethod(object_getClass(object),sel);
    char a[256]={0};if (m) method_getArgumentType(m,2,a,sizeof(a));
    if (!WGSTyped(m,3,'v') || !WGSObject(a)) return NO;
    ((void(*)(id,SEL,id))objc_msgSend)(object,sel,value);return YES;
}
static BOOL WGSSetUnsigned(id object,NSString *name,NSUInteger value) {
    SEL sel=NSSelectorFromString(name);Method m=class_getInstanceMethod(object_getClass(object),sel);
    if (!WGSTyped(m,3,'v') || !WGSArg(m,2,'Q')) return NO;
    ((void(*)(id,SEL,NSUInteger))objc_msgSend)(object,sel,value);return YES;
}
static BOOL WGSSetBool(id object,NSString *name,BOOL value) {
    SEL sel=NSSelectorFromString(name);Method m=class_getInstanceMethod(object_getClass(object),sel);
    if (!WGSTyped(m,3,'v') || (!WGSArg(m,2,'B') && !WGSArg(m,2,'c'))) return NO;
    ((void(*)(id,SEL,BOOL))objc_msgSend)(object,sel,value);return YES;
}
// Each racing lane gets its own typed request model. Never share one mutable
// request across two in-flight native calls: the Service binds payButtonType on
// it and the Thor payload is serialized later.
static id WGSCloneRequest(id request) {
    Class rc=NSClassFromString(@"VDTradeConfirmOrderRequestDO");
    Class ic=NSClassFromString(@"VDTradeConfOrderRequestItemDO");
    if (!rc || !ic || ![request isKindOfClass:rc]) return nil;
    id copy=nil;
    id json=WGSGet(request,@"yy_modelToJSONObject");
    if ([json isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *scalar=[json mutableCopy];[scalar removeObjectForKey:@"items"];
        for (NSString *name in @[@"yy_modelWithDictionary:",@"yy_modelWithJSON:"]) {
            SEL sel=NSSelectorFromString(name);Method m=class_getClassMethod(rc,sel);
            if (!WGSTyped(m,3,'@') || !WGSArg(m,2,'@')) continue;
            @try { id o=((id(*)(id,SEL,id))objc_msgSend)(rc,sel,scalar);if ([o isKindOfClass:rc]) {copy=o;break;} }
            @catch (__unused NSException *e) { }
        }
    }
    if (!copy) copy=[[rc alloc] init];
    NSArray *source=WGSArray(request,@"items");
    NSMutableArray *typed=[NSMutableArray array];
    NSDictionary *setters=@{@"price_type":@"setPrice_type:",@"extend":@"setExtend:",
                            @"installment_id":@"setInstallment_id:",@"activity_id":@"setActivity_id:",
                            @"biz_key":@"setBiz_key:",@"item_type":@"setItem_type:"};
    for (id src in source) {
        NSString *iid=WGSString(src,@"item_id"),*qty=WGSString(src,@"quantity");
        if (!iid.length || !WGSQuantity(qty)) return nil;
        id item=[[ic alloc] init];
        if (!WGSSetObject(item,@"setItem_id:",iid)) return nil;
        if (!WGSSetObject(item,@"setItem_sku_id:",WGSString(src,@"item_sku_id")?:@"")) return nil;
        if (!WGSSetObject(item,@"setQuantity:",qty)) return nil;
        for (NSString *field in setters) {
            NSString *value=WGSString(src,field);
            if (value.length && !WGSSetObject(item,setters[field],value)) return nil;
        }
        NSNumber *instalment=WGSBool(src,@"use_installment");
        if (instalment && !WGSSetBool(item,@"setUse_installment:",instalment.boolValue)) return nil;
        [typed addObject:item];
    }
    if (!typed.count || !WGSSetObject(copy,@"setItems:",typed)) return nil;
    return copy;
}
static id WGSCloneConfirmation(id model) {
    id json=WGSGet(model,@"yy_modelToJSONObject");
    return [json isKindOfClass:NSDictionary.class]?WGSConvertConfirmation(json):nil;
}
@interface WDGServiceLane : NSObject
@property(nonatomic,strong) id request;
@property(nonatomic,strong) id confirmation;
@property(nonatomic) BOOL settled;
@property(nonatomic) BOOL success;
@property(nonatomic,copy) NSString *outcome;
@end
@implementation WDGServiceLane
@end
@interface WDGOrderService ()
@property(nonatomic,strong) id requestModel;
@property(nonatomic,strong) id confirmationModel;
@property(nonatomic,strong) NSData *requestBaseline;
@property(nonatomic,strong) NSData *confirmationBaseline;
@property(nonatomic,copy) NSString *sampleKey;
@property(nonatomic,strong,nullable) NSNumber *payType;
@property(nonatomic,copy) NSString *taskID;
@property(nonatomic) NSTimeInterval preparedUptime;
@property(nonatomic) BOOL preheatMode;
@property(nonatomic,strong) NSDate *dueAt;
@property(nonatomic,strong) NSDecimalNumber *maximumTotal;
@property(nonatomic,strong) NSTimer *dueTimer;
@property(nonatomic,strong) NSTimer *timeoutTimer;
@property(nonatomic,copy) WDGOrderReply reply;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL finished;
@property(nonatomic) BOOL createStarted;
@property(nonatomic) BOOL waitingForOpening;
@property(nonatomic) BOOL confirming;
@property(nonatomic) NSUInteger confirmAttempts;
@property(nonatomic) NSUInteger savedPayType;
@property(nonatomic) BOOL payTypeBound;
@property(nonatomic) NSUInteger concurrentLanes;
@property(nonatomic,strong) NSMutableArray<WDGServiceLane *> *lanes;
@property(nonatomic) BOOL aggregateTimedOut;
- (void)beginConfirm;
- (void)beginCreate;
- (void)scheduleDue;
- (NSString *)validateConfirmedModel:(id)model;
@end
@implementation WDGOrderService {
    WDGServiceState _state;
    uint64_t _generation;
}
- (instancetype)init {
    if ((self=[super init])) _concurrentLanes=1;
    return self;
}
- (BOOL)configureConcurrentLanes:(NSUInteger)lanes error:(NSError **)error {
    if (self.active || self.finished || self.taskID.length) {if(error)*error=WGSError(12,@"任务已开始，不能再改并发路数");return NO;}
    if (lanes!=1 && lanes!=2) {if(error)*error=WGSError(13,@"并发只支持单路或双路竞速");return NO;}
    self.concurrentLanes=lanes;return YES;
}
+ (void)setExecutionAllowedCheck:(BOOL (^)(void))check { gExecutionAllowed=[check copy]; }
+ (BOOL)runtimeReady:(NSString **)reason { return WGSServiceABI(gCreateSelector,5,reason); }
+ (BOOL)preheatReady:(NSString **)reason { return WGSServiceABI(gConfirmSelector,4,reason); }
+ (instancetype)preparePreheatRequest:(id)request sampleKey:(NSString *)key payType:(NSNumber *)type error:(NSError **)error {
    NSString *reason=nil;Class cls=NSClassFromString(@"VDTradeConfirmOrderRequestDO");
    if (!NSThread.isMainThread || ![self preheatReady:&reason] || ![self runtimeReady:&reason] || !cls || ![request isKindOfClass:cls] || !key.length) {
        if (error) *error=WGSError(1,reason?:@"预热请求模型不完整");return nil;
    }
    if (!WGSRequestTuples(request)) {if(error)*error=WGSError(2,@"请求 items 必须是完整原生商品模型");return nil;}
    Method setter=class_getInstanceMethod(object_getClass(request),@selector(setPayButtonType:));
    if (!WGSTyped(setter,3,'v') || !WGSArg(setter,2,'Q') || !WGSUnsigned(request,@"payButtonType")) {
        if(error)*error=WGSError(3,@"支付字段 NSUInteger ABI 不匹配");return nil;
    }
    if (type) {
        const char *t=WGSType(type.objCType);
        if (![type isKindOfClass:NSNumber.class] || !t[0] || t[1] || !strchr("cCsSiIlLqQ",t[0]) || [type compare:@0]==NSOrderedAscending) {
            if(error)*error=WGSError(4,@"支付参数格式错误");return nil;
        }
    }
    NSData *baseline=WGSMemorySnapshot(request);
    if (!baseline) {if(error)*error=WGSError(5,@"请求参数内存快照失败");return nil;}
    WDGOrderService *s=[self new];s.requestModel=request;s.requestBaseline=baseline;
    s.sampleKey=key;s.payType=type;s.preheatMode=YES;s.preparedUptime=NSProcessInfo.processInfo.systemUptime;
    s->_generation=++gGeneration;WDGServicePrepare(&s->_state,s->_generation);return s;
}
+ (instancetype)prepareRequest:(id)request confirmation:(id)confirmation sampleKey:(NSString *)key payType:(NSNumber *)type error:(NSError **)error {
    WDGOrderService *s=[self preparePreheatRequest:request sampleKey:key payType:type error:error];
    if (!s) return nil;
    Class cls=NSClassFromString(@"VDTradeConfirmOrderDO");
    if (!cls || ![confirmation isKindOfClass:cls] || !type) {if(error)*error=WGSError(6,@"确认模型或支付参数不完整");return nil;}
    NSData *baseline=WGSMemorySnapshot(confirmation);
    if (!baseline) {if(error)*error=WGSError(7,@"确认模型内存快照失败");return nil;}
    s.preheatMode=NO;s.confirmationModel=confirmation;s.confirmationBaseline=baseline;return s;
}
- (BOOL)configureCartDueAt:(NSDate *)due maximumTotal:(NSDecimalNumber *)maximum error:(NSError **)error {
    NSTimeInterval delay=[due isKindOfClass:NSDate.class]?due.timeIntervalSinceNow:-1;
    if (!self.preheatMode || self.active || self.finished || !isfinite(delay) || delay<=0 || delay>43200 || ![maximum isKindOfClass:NSDecimalNumber.class] || [maximum isEqualToNumber:NSDecimalNumber.notANumber] || [maximum compare:NSDecimalNumber.zero]!=NSOrderedDescending) {
        if(error)*error=WGSError(8,@"请设置未来十二小时内的时间与明确最高实付金额");return NO;
    }
    self.dueAt=due;self.maximumTotal=maximum;return YES;
}
- (void)fillAggregateCounters:(NSMutableDictionary *)receipt {
    NSUInteger pending=0,successes=0,unknowns=0,total=self.lanes.count;
    for (WDGServiceLane *lane in self.lanes) {
        if(!lane.settled){++pending;continue;}
        if(lane.success)++successes;
        else if([lane.outcome isEqual:@"unknown"])++unknowns;
    }
    if (!receipt[@"apiSucceeded"]) receipt[@"apiSucceeded"]=@NO;
    if (!receipt[@"paymentInvoked"]) receipt[@"paymentInvoked"]=@NO;
    receipt[@"concurrentLanes"]=@(total?total:self.concurrentLanes);
    receipt[@"successCallbacks"]=@(successes);
    receipt[@"completedRequests"]=@(total-pending);
    receipt[@"pendingRequests"]=@(pending);
    receipt[@"unknownRequests"]=@(unknowns);
}
- (void)progress:(NSString *)state message:(NSString *)message {
    if (!self.reply) return;
    NSMutableDictionary *r=[@{@"terminal":@NO,@"state":state,@"message":message} mutableCopy];
    [self fillAggregateCounters:r];self.reply([r copy]);
}
- (void)restorePayment {
    if (self.payTypeBound && self.requestModel) {
        ((void(*)(id,SEL,NSUInteger))objc_msgSend)(self.requestModel,@selector(setPayButtonType:),self.savedPayType);
        self.payTypeBound=NO;
    }
}
- (void)releaseModels {
    [self restorePayment];self.requestModel=nil;self.confirmationModel=nil;
    self.requestBaseline=nil;self.confirmationBaseline=nil;
}
- (void)finish:(NSDictionary *)receipt {
    if (self.finished) return;
    self.finished=YES;self.active=NO;self.confirming=NO;
    [self.dueTimer invalidate];self.dueTimer=nil;[self.timeoutTimer invalidate];self.timeoutTimer=nil;
    [self releaseModels];WDGOrderReply callback=self.reply;self.reply=nil;if(callback)callback(receipt);
}
- (void)stop:(NSString *)message state:(NSString *)state {
    NSMutableDictionary *r=[@{@"terminal":@YES,@"state":state,@"apiSucceeded":@NO,@"paymentInvoked":@NO,@"message":message} mutableCopy];
    [self fillAggregateCounters:r];
    [self finish:[r copy]];
}
- (BOOL)submitTask:(NSString *)taskID completion:(WDGOrderReply)completion error:(NSError **)error {
    NSString *reason=nil;
    if (!NSThread.isMainThread || !taskID.length || !completion || self.taskID.length || self.finished || !WGSAllowed() || ![self.class runtimeReady:&reason]) {
        if(error)*error=WGSError(9,reason?:@"任务已使用或当前执行状态不可用");return NO;
    }
    if (self.preheatMode && (!self.dueAt || !self.maximumTotal)) {if(error)*error=WGSError(10,@"购物车任务尚未确认时间与最高金额");return NO;}
    NSTimeInterval age=NSProcessInfo.processInfo.systemUptime-self.preparedUptime;
    if (age<0 || age>(self.preheatMode?43200:600) || ![WGSMemorySnapshot(self.requestModel) isEqual:self.requestBaseline]) {
        if(error)*error=WGSError(11,@"订单参数已变化或样本过期");return NO;
    }
    self.taskID=taskID;self.reply=[completion copy];self.active=YES;
    if (self.preheatMode) [self beginConfirm];else [self beginCreate];return YES;
}
- (void)scheduleDue {
    if (self.finished || !self.active) return;
    [self.dueTimer invalidate];self.dueTimer=nil;
    [self progress:@"waitingSale" message:self.waitingForOpening?@"当前未开放，到设定时刻再确认一次":@"确认数据已就绪，等待设定时刻直接创建订单"];
    NSTimeInterval delay=self.dueAt.timeIntervalSinceNow;
    if (delay<=0) {[self dueReached:nil];return;}
    self.dueTimer=[NSTimer timerWithTimeInterval:delay target:self selector:@selector(dueReached:) userInfo:nil repeats:NO];
    [NSRunLoop.mainRunLoop addTimer:self.dueTimer forMode:NSRunLoopCommonModes];
}
- (void)dueReached:(NSTimer *)timer {
    [self.dueTimer invalidate];self.dueTimer=nil;
    if (!self.active || self.finished) return;
    if (!WGSAllowed()) {[self stop:@"微店已离开前台，任务取消" state:@"cancelled"];return;}
    if (self.dueAt.timeIntervalSinceNow < -2) {[self stop:@"错过提交时刻超过两秒，未创建订单" state:@"failed"];return;}
    if (self.waitingForOpening) {
        if (self.confirmAttempts<2) [self beginConfirm];else [self stop:@"当前仍未开放，未创建订单" state:@"failed"];
    } else [self beginCreate];
}
- (void)beginConfirm {
    if (!self.active || self.finished || self.confirming) return;
    if (!WGSAllowed()) {[self stop:@"微店已离开前台，未创建订单" state:@"cancelled"];return;}
    if (self.confirmAttempts>=2) {[self stop:@"确认次数上限已到，未创建订单" state:@"failed"];return;}
    if (![WGSMemorySnapshot(self.requestModel) isEqual:self.requestBaseline]) {[self stop:@"采集后参数已变化，未创建订单" state:@"failed"];return;}
    self.confirming=YES;NSUInteger attempt=++self.confirmAttempts;++gConfirmCalls;
    [self progress:@"preheating" message:@"只请求确认数据，尚未创建订单"];
    self.timeoutTimer=[NSTimer timerWithTimeInterval:30 target:self selector:@selector(confirmTimedOut:) userInfo:nil repeats:NO];
    [NSRunLoop.mainRunLoop addTimer:self.timeoutTimer forMode:NSRunLoopCommonModes];
    void (^callback)(BOOL,id,id)=^(BOOL success,id payload,id nativeError) {
        dispatch_async(dispatch_get_main_queue(),^{
            if (!self.active || self.finished || !self.confirming || self.confirmAttempts!=attempt) return;
            self.confirming=NO;[self.timeoutTimer invalidate];self.timeoutTimer=nil;
            if (!success || nativeError) {[self stop:@"确认接口返回错误，未创建订单；本次不自动重试" state:@"failed"];return;}
            if (![payload isKindOfClass:NSDictionary.class]) {[self stop:@"确认响应结构未知，未创建订单" state:@"failed"];return;}
            id model=WGSConvertConfirmation(payload);
            if (!model) {[self stop:@"确认模型转换失败，未创建订单" state:@"failed"];return;}
            NSNumber *blocked=WGSBool(model,@"cannot_submit");
            if (!blocked) {[self stop:@"确认数据缺少已验证的提交状态" state:@"failed"];return;}
            if (blocked.boolValue) {
                self.waitingForOpening=YES;self.confirmationModel=nil;
                if (self.dueAt.timeIntervalSinceNow<=0) {[self stop:@"商品仍未开放或禁止提交，未创建订单" state:@"failed"];return;}
                [self scheduleDue];return;
            }
            NSArray *requested=WGSRequestTuples(self.requestModel),*confirmed=WGSConfirmationTuples(model);
            if (!requested.count || ![requested isEqual:confirmed]) {[self stop:@"确认的商品、规格或数量与选择不一致，未创建订单" state:@"failed"];return;}
            NSString *validation=[self validateConfirmedModel:model];
            if (validation) {[self stop:validation state:@"failed"];return;}
            self.waitingForOpening=NO;self.confirmationModel=model;self.confirmationBaseline=WGSMemorySnapshot(model);
            if (!self.confirmationBaseline) {[self stop:@"确认参数快照失败，未创建订单" state:@"failed"];return;}
            [self scheduleDue];
        });
    };
    @try {
        ((void(*)(id,SEL,id,id))objc_msgSend)(NSClassFromString(@"VDTradeConfOrderService"),NSSelectorFromString(gConfirmSelector),self.requestModel,[callback copy]);
    } @catch (__unused NSException *e) { [self stop:@"确认接口调用异常，未创建订单" state:@"failed"]; }
}
- (NSString *)validateConfirmedModel:(id)model {
    NSNumber *blocked=WGSBool(model,@"cannot_submit");if(!blocked || blocked.boolValue)return @"当前确认数据禁止提交";
    if ([WGSBool(model,@"need_add_address") boolValue]) return @"微店要求补充收件信息，本次停止";
    if (WGSGet(model,@"confSlideDO") && ![WGSBool(model,@"slideChecked") boolValue]) return @"微店要求完成页面验证，本次停止";
    // Native createOrderHelp: gates on getRealAgreementInfos, not the raw
    // agreement_info_list. Display-only entries may be filtered out. Never
    // set isAgreementChecked here: the native confirmation belongs to the user.
    NSArray *agreements=WGSArray(model,@"getRealAgreementInfos");
    if (!agreements) return @"交易协议状态尚未识别，请在微店确认页核对";
    if (agreements.count && ![WGSBool(model,@"isAgreementChecked") boolValue]) return @"此订单有交易协议待确认，请在微店确认页查看";
    NSDecimalNumber *price=WGSAmount(WGSString(model,@"total_pay_price"));
    if (!price) return @"确认金额格式未知，未创建订单";
    if (self.preheatMode && [price compare:self.maximumTotal]==NSOrderedDescending) return @"确认金额超过设置的最高实付金额，未创建订单";
    NSMutableArray *buttons=[NSMutableArray array];
    for (id option in WGSArray(model,@"pay_options")) {
        NSNumber *selected=WGSBool(option,@"selected"),*available=WGSBool(option,@"available");
        if (!selected || !available) return @"支付状态 getter ABI 未验证";
        if (!selected.boolValue || !available.boolValue) continue;
        for (id button in WGSArray(option,@"buttons")) {
            NSNumber *type=WGSUnsigned(button,@"type");NSString *title=WGSString(button,@"name");
            if (!type || !title.length) return @"支付按钮格式未知";
            if (!self.payType || [self.payType isEqualToNumber:type]) [buttons addObject:type];
        }
    }
    if (buttons.count!=1) return @"服务端未提供唯一匹配的可用支付按钮，本次停止";
    self.payType=buttons.firstObject;return nil;
}
- (void)emitAggregateTerminal:(BOOL)terminal {
    NSUInteger pending=0,successes=0,unknowns=0;
    for (WDGServiceLane *lane in self.lanes) {
        if(!lane.settled){++pending;continue;}
        if(lane.success)++successes;
        else if([lane.outcome isEqual:@"unknown"])++unknowns;
    }
    NSMutableDictionary *r=[@{@"paymentInvoked":@NO,
        @"concurrentLanes":@(self.lanes.count),
        @"successCallbacks":@(successes),
        @"completedRequests":@(self.lanes.count-pending),
        @"pendingRequests":@(pending),
        @"unknownRequests":@(unknowns)} mutableCopy];
    r[@"terminal"]=@(terminal);
    if(!terminal) {
        r[@"state"]=@"sending";r[@"apiSucceeded"]=@NO;
        r[@"message"]=[NSString stringWithFormat:@"已发出 %lu 路请求，%lu 路已有结果",(unsigned long)self.lanes.count,(unsigned long)(self.lanes.count-pending)];
    } else if(pending) {
        r[@"state"]=@"unknown";r[@"apiSucceeded"]=@NO;
        r[@"message"]=[NSString stringWithFormat:@"仍有 %lu 路未返回，订单结果待核对；未重试",(unsigned long)pending];
    } else if(unknowns) {
        r[@"state"]=@"unknown";r[@"apiSucceeded"]=@NO;
        r[@"message"]=[NSString stringWithFormat:@"有 %lu 路结果未知；请核对微店订单，未重试",(unsigned long)unknowns];
    } else if(successes) {
        r[@"state"]=@"apiSucceeded";r[@"apiSucceeded"]=@YES;
        r[@"message"]=[NSString stringWithFormat:@"%lu 路创建接口返回成功；若服务端不去重可能生成多笔订单，请以微店订单列表为准",(unsigned long)successes];
    } else {
        r[@"state"]=@"failed";r[@"apiSucceeded"]=@NO;r[@"message"]=@"创建接口均未成功；未自动重试";
    }
    if(self.reply) self.reply([r copy]);
}
- (void)beginCreate {
    if (!self.active || self.finished || self.createStarted) return;
    if (!WGSAllowed()) {[self stop:@"微店已离开前台，未创建订单" state:@"cancelled"];return;}
    if (self.preheatMode) {
        if (self.dueAt.timeIntervalSinceNow>0) {[self scheduleDue];return;}
        if (self.dueAt.timeIntervalSinceNow < -2) {[self stop:@"已错过提交时刻，未创建订单" state:@"failed"];return;}
    }
    if (![WGSMemorySnapshot(self.requestModel) isEqual:self.requestBaseline] || ![WGSMemorySnapshot(self.confirmationModel) isEqual:self.confirmationBaseline]) {
        [self stop:@"确认后参数已变化，未创建订单" state:@"failed"];return;
    }
    NSString *validation=[self validateConfirmedModel:self.confirmationModel];
    if (validation) {[self stop:validation state:@"failed"];return;}
    if (!WDGServiceDispatch(&_state,_generation)) {[self stop:@"任务已消费，不重复创建订单" state:@"failed"];return;}
    NSUInteger laneCount=MIN(MAX(self.concurrentLanes,1),2);
    NSMutableArray *lanes=[NSMutableArray array];
    for (NSUInteger i=0;i<laneCount;++i) {
        // Every lane owns typed copies. The native Service binds payButtonType
        // and serializes the Thor payload later, so sharing one model is unsafe.
        id request=WGSCloneRequest(self.requestModel);
        id confirmation=WGSCloneConfirmation(self.confirmationModel);
        if (!request || !confirmation || !WGSSetUnsigned(request,@"setPayButtonType:",self.payType.unsignedIntegerValue)) {
            [self stop:@"竞速参数复制失败，未创建订单" state:@"failed"];return;
        }
        WDGServiceLane *lane=[WDGServiceLane new];lane.request=request;lane.confirmation=confirmation;
        [lanes addObject:lane];
    }
    self.lanes=lanes;self.createStarted=YES;self.aggregateTimedOut=NO;
    gCreateCalls+=lanes.count;
    self.savedPayType=WGSUnsigned(self.requestModel,@"payButtonType").unsignedIntegerValue;
    [self progress:@"sending" message:lanes.count>1?@"双路竞速已发出，可能生成重复订单":@"已发出创建请求，等待真实响应"];
    self.timeoutTimer=[NSTimer timerWithTimeInterval:30 target:self selector:@selector(createTimedOut:) userInfo:nil repeats:NO];
    [NSRunLoop.mainRunLoop addTimer:self.timeoutTimer forMode:NSRunLoopCommonModes];
    for (WDGServiceLane *lane in lanes) {
        void (^callback)(BOOL,id,id)=^(BOOL success,id response,id nativeError) {
            dispatch_async(dispatch_get_main_queue(),^{
                if (lane.settled) return;
                lane.settled=YES;lane.success=success&&!nativeError;
                lane.outcome=lane.success?@"success":([WGSGet(nativeError,@"originError") isKindOfClass:NSError.class]?@"unknown":@"failed");
                ++gReplies;
                BOOL pending=NO;
                for (WDGServiceLane *other in self.lanes) if(!other.settled) pending=YES;
                [self emitAggregateTerminal:!pending];
                if (!pending && !self.finished) {
                    self.finished=YES;self.active=NO;
                    [self.timeoutTimer invalidate];self.timeoutTimer=nil;[self releaseModels];
                }
            });
        };
        @try {
            ((void(*)(id,SEL,id,id,id))objc_msgSend)(NSClassFromString(@"VDTradeConfOrderService"),NSSelectorFromString(gCreateSelector),lane.request,lane.confirmation,[callback copy]);
        } @catch (__unused NSException *e) {
            WDGServiceTimeout(&_state,_generation);
            for (WDGServiceLane *other in self.lanes) other.settled=YES;
            [self emitAggregateTerminal:YES];
            self.finished=YES;self.active=NO;[self releaseModels];return;
        }
    }
}
- (void)confirmTimedOut:(NSTimer *)timer {
    if (!self.createStarted && !self.finished) { self.confirming=NO;[self stop:@"确认接口超时，未创建订单；迟到确认不会继续提交" state:@"failed"]; }
}
- (void)createTimedOut:(NSTimer *)timer {
    if (!self.createStarted || self.finished || self.aggregateTimedOut) return;
    BOOL pending=NO;
    for (WDGServiceLane *lane in self.lanes) if(!lane.settled) pending=YES;
    if(!pending) return;
    self.aggregateTimedOut=YES;WDGServiceTimeout(&_state,_generation);
    [self.timeoutTimer invalidate];self.timeoutTimer=nil;
    [self releaseModels];
    [self emitAggregateTerminal:YES];
    // In-flight native callbacks stay registered; a late real result may update
    // the aggregate, but this task can never send another Create.
}
- (BOOL)cancelBeforeCreate {
    if (self.createStarted) return NO;
    WDGServiceCancelBeforeDispatch(&_state);[self stop:@"用户或系统取消，未创建订单" state:@"cancelled"];return YES;
}
- (void)expireUnresolvedTask:(NSString *)taskID {
    if (![self.taskID isEqual:taskID]) return;
    if (self.createStarted) [self createTimedOut:nil];else [self confirmTimedOut:nil];
}
+ (NSDictionary *)diagnostics {
    return @{@"transport":@"native Service / Thor POST",@"route":@"vbuy/CreateOrder/1.0",@"serviceCalls":@(gCreateCalls),@"confirmCalls":@(gConfirmCalls),@"serviceReplies":@(gReplies),@"uiActionCalls":@0,@"pluginRetryCount":@0};
}
@end
