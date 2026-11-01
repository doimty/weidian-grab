#import "WDGOrderService.h"
#import "WDGServiceState.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>

// Offline evidence for buyer 7.9.62:
// Service IMP 0x104ccbbb8 -> vbuy/CreateOrder/1.0 -> native Thor POST/signing.
// Caller descriptor 0x107819be0 has v28@?0B8@12@"WDNErrorDO"20.
// The order callback is (BOOL, id, WDNErrorDO *), NOT (id, BOOL, NSError *).
// Do not forward it to a controller: that controller can route into payment.
static unsigned int WDGServiceCalls;
static unsigned int WDGServiceReplies;
static uint64_t WDGNextGeneration;
static NSString * const WDGCreateSelector=@"createOrderRequestDO:confirmOrderDO:result:";

static NSError *WDGServiceError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"WeidianGrab.OrderService" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}
static const char *WDGSType(const char *t) {while(t&&*t&&strchr("rnNoORV",*t))t++;return t?:"";}
static BOOL WDGSTypeIs(const char *t,char want) {t=WDGSType(t);return t[0]==want&&t[1]=='\0';}
static BOOL WDGSObject(const char *t) {t=WDGSType(t);return t[0]=='@'&&(t[1]=='\0'||t[1]=='"');}
static BOOL WDGSTyped(Method m,unsigned int n,char result) {
    if(!m||method_getNumberOfArguments(m)!=n)return NO;
    char b[256]={0};method_getReturnType(m,b,sizeof(b));
    return result=='@'?WDGSObject(b):WDGSTypeIs(b,result);
}
static BOOL WDGSArgument(Method m,unsigned int i,char kind) {
    char b[256]={0};method_getArgumentType(m,i,b,sizeof(b));
    return kind=='@'?WDGSObject(b):WDGSTypeIs(b,kind);
}
static id WDGSGet(id o,NSString *name) {
    if(!o)return nil;
    SEL s=NSSelectorFromString(name);
    Method m=class_getInstanceMethod(object_getClass(o),s);
    if(!WDGSTyped(m,2,'@'))return nil;
    @try{return ((id(*)(id,SEL))objc_msgSend)(o,s);}@catch(__unused NSException *e){return nil;}
}
static NSNumber *WDGSSigned(id o,NSString *name) {
    if(!o)return nil;
    SEL s=NSSelectorFromString(name);Method m=class_getInstanceMethod(object_getClass(o),s);
    if(!WDGSTyped(m,2,'q'))return nil;
    @try{return @(((long long(*)(id,SEL))objc_msgSend)(o,s));}@catch(__unused NSException *e){return nil;}
}
static NSData *WDGSMemorySnapshot(id model) {
    // Use the App's installed model category. Serialized personal fields never
    // leave memory or enter a log. Pin the original typed model, rather than
    // cloning it into untyped dictionaries (request.items has no generic map).
    id json=WDGSGet(model,@"yy_modelToJSONObject");
    if(![json isKindOfClass:NSDictionary.class])return nil;
    NSData *data=[NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingSortedKeys error:NULL];
    return data.length&&data.length<=2*1024*1024?data:nil;
}
static NSDictionary *WDGSReceipt(BOOL success,id response,id error) {
    NSMutableDictionary *r=[@{@"apiSucceeded":@(success&&error==nil),@"paymentInvoked":@NO} mutableCopy];
    if(!success||error){
        BOOL transportError=[WDGSGet(error,@"originError") isKindOfClass:NSError.class];
        r[@"state"]=transportError?@"unknown":@"failed";
        r[@"message"]=transportError?@"网络返回错误，订单结果待核对；未自动重试":@"创建订单接口返回错误，未自动重试";
        NSNumber *code=WDGSSigned(error,@"code"),*serverCode=WDGSSigned(error,@"serverCode");
        if(code)r[@"errorCode"]=code;if(serverCode)r[@"serverCode"]=serverCode;
        return r;
    }
    if(![response isKindOfClass:NSDictionary.class]){
        r[@"state"]=@"unknown";r[@"message"]=@"接口回调成功但响应结构未知，请核对订单；未自动重试";return r;
    }
    NSDictionary *d=response;
    // These three URL fields are used by the original Controller. Only record
    // presence; never open them or retain their authentication-bearing query.
    NSMutableArray *fields=[NSMutableArray array];
    for(NSString *key in @[@"url",@"friends_pay_url",@"success_url"]){if([d[key] isKindOfClass:NSString.class]&&[d[key] length])[fields addObject:key];}
    r[@"recognizedFields"]=fields;
    // order_id/order_ids are optional recognizers, not a claimed universal
    // schema. With no verified ID, report API success, not payment success.
    NSMutableArray *ids=[NSMutableArray array];
    id one=d[@"order_id"]; id many=d[@"order_ids"];
    if([one isKindOfClass:NSString.class]&&[one length]&&[one length]<=80)[ids addObject:one];
    if([many isKindOfClass:NSArray.class])for(id v in many){if(ids.count>=40)break;if([v isKindOfClass:NSString.class]&&[v length]&&[v length]<=80)[ids addObject:v];}
    r[@"orderCount"]=@(ids.count);
    if(ids.count)r[@"orderIds"]=ids; // UI memory only; Core never persists these.
    r[@"state"]=@"apiSucceeded";
    r[@"message"]=ids.count?@"创建接口返回成功，已收到订单号；未调用支付管理器":@"创建接口返回成功；当前响应未提供可识别订单号，未调用支付管理器";
    return r;
}

@interface WDGOrderService ()
@property(nonatomic,strong) id requestModel;
@property(nonatomic,strong) id confirmationModel;
@property(nonatomic,strong) NSData *requestBaseline;
@property(nonatomic,strong) NSData *confirmationBaseline;
@property(nonatomic,copy) NSString *sampleKey;
@property(nonatomic,strong) NSNumber *payType;
@property(nonatomic,copy) NSString *taskID;
@property(nonatomic) NSTimeInterval preparedUptime;
@end
@implementation WDGOrderService {
    WDGServiceState _state;
    uint64_t _generation;
}
+ (BOOL)runtimeReady:(NSString **)reason {
    Class cls=NSClassFromString(@"VDTradeConfOrderService");
    Method m=cls?class_getClassMethod(cls,NSSelectorFromString(WDGCreateSelector)):NULL;
    BOOL ok=WDGSTyped(m,5,'v')&&WDGSArgument(m,2,'@')&&WDGSArgument(m,3,'@');
    char block[256]={0};if(m)method_getArgumentType(m,4,block,sizeof(block));
    ok=ok&&strcmp(WDGSType(block),"@?")==0;
    if(reason)*reason=ok?nil:@"创建订单 Service 不存在或 ABI 与已验证版本不一致";
    return ok;
}
+ (instancetype)prepareRequest:(id)request confirmation:(id)confirmation sampleKey:(NSString *)sampleKey payType:(NSNumber *)payType error:(NSError **)error {
    NSString *reason=nil;
    if(!NSThread.isMainThread||![self runtimeReady:&reason]){if(error)*error=WDGServiceError(1,reason?:@"请在主线程准备任务");return nil;}
    Class rc=NSClassFromString(@"VDTradeConfirmOrderRequestDO"),cc=NSClassFromString(@"VDTradeConfirmOrderDO");
    if(!rc||!cc||![request isKindOfClass:rc]||![confirmation isKindOfClass:cc]||!sampleKey.length||![payType isKindOfClass:NSNumber.class]){if(error)*error=WDGServiceError(2,@"请求与确认模型类型不完整");return nil;}
    Method setter=class_getInstanceMethod(object_getClass(request),@selector(setPayButtonType:));
    Method getter=class_getInstanceMethod(object_getClass(request),@selector(payButtonType));
    if(!WDGSTyped(setter,3,'v')||!WDGSArgument(setter,2,'Q')||!WDGSTyped(getter,2,'Q')){if(error)*error=WDGServiceError(3,@"payButtonType 未通过 NSUInteger ABI 校验");return nil;}
    NSData *a=WDGSMemorySnapshot(request),*b=WDGSMemorySnapshot(confirmation);
    if(!a||!b){if(error)*error=WDGServiceError(4,@"模型序列化尚未验证，未创建接口任务");return nil;}
    WDGOrderService *s=[self new];s.requestModel=request;s.confirmationModel=confirmation;s.requestBaseline=a;s.confirmationBaseline=b;s.sampleKey=sampleKey;s.payType=payType;s.preparedUptime=NSProcessInfo.processInfo.systemUptime;
    s->_generation=++WDGNextGeneration;WDGServicePrepare(&s->_state,s->_generation);
    return s;
}
- (BOOL)submitTask:(NSString *)taskID completion:(WDGOrderReply)completion error:(NSError **)error {
    NSString *reason=nil;
    if(!NSThread.isMainThread||![self.class runtimeReady:&reason]||!taskID.length||!completion){if(error)*error=WDGServiceError(5,reason?:@"任务调用条件不完整");return NO;}
    NSTimeInterval age=NSProcessInfo.processInfo.systemUptime-self.preparedUptime;
    if(age<0||age>600){if(error)*error=WDGServiceError(6,@"接口参数样本超过十分钟，请重新采集");return NO;}
    if(![WDGSMemorySnapshot(self.requestModel) isEqual:self.requestBaseline]||![WDGSMemorySnapshot(self.confirmationModel) isEqual:self.confirmationBaseline]){if(error)*error=WDGServiceError(7,@"采集后订单参数已变化，请重新确认任务");return NO;}
    if(!WDGServiceDispatch(&_state,_generation)){if(error)*error=WDGServiceError(8,@"当前接口任务已消费，不重复提交");return NO;}
    self.taskID=taskID;
    id request=self.requestModel,confirmation=self.confirmationModel;
    SEL setter=@selector(setPayButtonType:),getter=@selector(payButtonType);
    NSUInteger saved=((NSUInteger(*)(id,SEL))objc_msgSend)(request,getter);
    // Native service builds its WDNetworkContext synchronously before returning.
    // Only the selected pay type is temporarily bound. Never rewrite login,
    // server-time signatures, risk fields, captcha or agreement values.
    ((void(*)(id,SEL,NSUInteger))objc_msgSend)(request,setter,self.payType.unsignedIntegerValue);
    void (^reply)(BOOL,id,id)=^(BOOL success,id result,id nativeError){
        dispatch_async(dispatch_get_main_queue(),^{
            // Thor payload is serialized later than the Service call, so the
            // temporary payButtonType must survive until this reply arrives.
            ((void(*)(id,SEL,NSUInteger))objc_msgSend)(request,setter,saved);
            if(!WDGServiceResolve(&self->_state,self->_generation,success))return;
            ++WDGServiceReplies;
            NSDictionary *receipt=WDGSReceipt(success,result,nativeError);
            self.requestModel=nil;self.confirmationModel=nil;self.requestBaseline=nil;self.confirmationBaseline=nil;
            completion(receipt);
        });
    };
    @try {
        ++WDGServiceCalls;
        ((void(*)(id,SEL,id,id,id))objc_msgSend)(NSClassFromString(@"VDTradeConfOrderService"),NSSelectorFromString(WDGCreateSelector),request,confirmation,[reply copy]);
    } @catch(__unused NSException *exception) {
        ((void(*)(id,SEL,NSUInteger))objc_msgSend)(request,setter,saved);
        WDGServiceTimeout(&_state,_generation);
        completion(@{@"state":@"unknown",@"apiSucceeded":@NO,@"message":@"Service 调用异常，结果待核对；未自动重试",@"paymentInvoked":@NO});
    }
    return YES; // Invocation only: Core waits for our own network result block.
}
- (void)expireUnresolvedTask:(NSString *)taskID {
    if([self.taskID isEqualToString:taskID]){
        WDGServiceTimeout(&_state,_generation);
        self.requestModel=nil;self.confirmationModel=nil;self.requestBaseline=nil;self.confirmationBaseline=nil;
    }
}
+ (NSDictionary *)diagnostics {return @{@"transport":@"native Service / Thor POST",@"route":@"vbuy/CreateOrder/1.0",@"serviceCalls":@(WDGServiceCalls),@"serviceReplies":@(WDGServiceReplies),@"uiActionCalls":@0,@"pluginRetryCount":@0};}
@end
