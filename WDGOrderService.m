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
static NSNumber *WGSSigned(id object,NSString *name) {
    if (!object) return nil;
    SEL sel=NSSelectorFromString(name);
    if (!WGSTyped(class_getInstanceMethod(object_getClass(object),sel),2,'q')) return nil;
    @try { return @(((long long(*)(id,SEL))objc_msgSend)(object,sel)); }
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
static NSDictionary *WGSReceipt(BOOL success,id response,id error) {
    NSMutableDictionary *r=[@{@"terminal":@YES,@"apiSucceeded":@(success && !error),@"paymentInvoked":@NO} mutableCopy];
    if (!success || error) {
        BOOL network=[WGSGet(error,@"originError") isKindOfClass:NSError.class];
        r[@"state"]=network?@"unknown":@"failed";
        r[@"message"]=network?@"网络返回错误，订单结果待核对；未自动重试":@"创建接口返回错误；未自动重试";
        NSNumber *code=WGSSigned(error,@"code"),*server=WGSSigned(error,@"serverCode");
        if (code) r[@"errorCode"]=code;if (server) r[@"serverCode"]=server;
        return r;
    }
    if (![response isKindOfClass:NSDictionary.class]) {
        r[@"state"]=@"unknown";r[@"message"]=@"接口回调成功，但响应结构未知；请核对订单，不重试";return r;
    }
    NSMutableArray *keys=[NSMutableArray array];
    for (NSString *key in @[@"url",@"friends_pay_url",@"success_url"]) {
        id value=response[key];if ([value isKindOfClass:NSString.class] && [value length]) [keys addObject:key];
    }
    r[@"recognizedFields"]=keys;r[@"state"]=@"apiSucceeded";
    r[@"message"]=@"创建接口返回成功；未打开支付链接，订单状态请以微店为准";
    return r;
}

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
- (void)beginConfirm;
- (void)beginCreate;
- (void)scheduleDue;
- (NSString *)validateConfirmedModel:(id)model;
@end
@implementation WDGOrderService {
    WDGServiceState _state;
    uint64_t _generation;
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
- (void)progress:(NSString *)state message:(NSString *)message {
    if (self.reply) self.reply(@{@"terminal":@NO,@"state":state,@"message":message,@"paymentInvoked":@NO});
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
    [self finish:@{@"terminal":@YES,@"state":state,@"apiSucceeded":@NO,@"paymentInvoked":@NO,@"message":message}];
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
    if (WGSArray(model,@"agreement_info_list").count && ![WGSBool(model,@"isAgreementChecked") boolValue]) return @"新增协议尚未确认，本次停止";
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
    self.createStarted=YES;++gCreateCalls;
    self.savedPayType=WGSUnsigned(self.requestModel,@"payButtonType").unsignedIntegerValue;
    ((void(*)(id,SEL,NSUInteger))objc_msgSend)(self.requestModel,@selector(setPayButtonType:),self.payType.unsignedIntegerValue);
    self.payTypeBound=YES;[self progress:@"sending" message:@"直接创建订单一次，等待真实响应"];
    self.timeoutTimer=[NSTimer timerWithTimeInterval:30 target:self selector:@selector(createTimedOut:) userInfo:nil repeats:NO];
    [NSRunLoop.mainRunLoop addTimer:self.timeoutTimer forMode:NSRunLoopCommonModes];
    void (^callback)(BOOL,id,id)=^(BOOL success,id response,id nativeError) {
        dispatch_async(dispatch_get_main_queue(),^{
            if (self.finished || !self.createStarted || !WDGServiceResolve(&self->_state,self->_generation,success)) return;
            ++gReplies;[self finish:WGSReceipt(success,response,nativeError)];
        });
    };
    @try {
        ((void(*)(id,SEL,id,id,id))objc_msgSend)(NSClassFromString(@"VDTradeConfOrderService"),NSSelectorFromString(gCreateSelector),self.requestModel,self.confirmationModel,[callback copy]);
    } @catch (__unused NSException *e) { [self createTimedOut:nil]; }
}
- (void)confirmTimedOut:(NSTimer *)timer {
    if (!self.createStarted && !self.finished) { self.confirming=NO;[self stop:@"确认接口超时，未创建订单；迟到确认不会继续提交" state:@"failed"]; }
}
- (void)createTimedOut:(NSTimer *)timer {
    if (!self.createStarted || self.finished || _state.phase!=WDGServiceSending) return;
    WDGServiceTimeout(&_state,_generation);[self.timeoutTimer invalidate];self.timeoutTimer=nil;
    [self releaseModels];
    if (self.reply) self.reply(@{@"terminal":@YES,@"state":@"unknown",@"apiSucceeded":@NO,@"message":@"创建接口暂未返回，结果待核对；未重试",@"paymentInvoked":@NO});
    // Retain callback identity for at most the native request's lifetime. A late
    // Create result may settle unknown; it cannot initiate another request.
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
