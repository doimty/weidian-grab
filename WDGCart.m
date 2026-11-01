#import "WDGCart.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonDigest.h>
#import <string.h>

@protocol WGCNativeViewModelInitializer
- (instancetype)initWithRequest:(id)request;
@end

static NSArray<NSDictionary *> *gCandidates;
static NSDictionary<NSString *,NSDictionary *> *gRaw;
static NSString *gChosenLine;
static NSString *gReason;
static NSData *gSalt;
static NSUInteger gCaptures;
static BOOL gInstalled;
static void (*gOriginalFetch)(id,SEL,BOOL,id);
static NSDictionary *gRouteContext;
static __weak id gLiveList;
static __weak id gLiveController;
static BOOL gAwaitingNativeCallback;
static BOOL gSyncing;
static NSString *gLiveSource;
static NSUInteger gLiveReads;
static NSUInteger gRowBuilds;
static NSUInteger gSnapshotHashes;
static NSUInteger gClearEpoch;
static NSArray *gKeyIdentity;
static NSString *gSnapshot;
static void (*gOriginalWillAppear)(id,SEL,BOOL);

@interface WGCLineState : NSObject
@property(nonatomic,weak) id nativeItem;
@property(nonatomic,copy) NSArray *values;
@property(nonatomic,copy) NSDictionary *row;
@property(nonatomic,copy) NSDictionary *raw;
@end
@implementation WGCLineState
@end
static NSDictionary<NSArray *,WGCLineState *> *gLineStates;

static const char *WGCType(const char *t) { if(!t)return "";while(*t&&strchr("rnNoORV",*t))++t;return t; }
static BOOL WGCObject(const char *t) { t=WGCType(t);return t[0]=='@'&&(t[1]=='\0'||t[1]=='"'); }
static BOOL WGCTyped(Method m,unsigned n,char kind) {
    if(!m||method_getNumberOfArguments(m)!=n)return NO;
    char r[256]={0};method_getReturnType(m,r,sizeof(r));const char *t=WGCType(r);
    return kind=='@'?WGCObject(t):(t[0]==kind&&t[1]=='\0');
}
static id WGCGet(id o,NSString *name) {
    if(!o)return nil;SEL s=NSSelectorFromString(name);
    if(!WGCTyped(class_getInstanceMethod(object_getClass(o),s),2,'@'))return nil;
    @try { return ((id(*)(id,SEL))objc_msgSend)(o,s); } @catch(__unused NSException *e){return nil;}
}
static NSString *WGCString(id o,NSString *key) {id v=WGCGet(o,key);return [v isKindOfClass:NSString.class]&&[v length]<=4096?[v copy]:nil;}
static NSNumber *WGCBool(id o,NSString *key) {
    SEL s=NSSelectorFromString(key);if(!o||!WGCTyped(class_getInstanceMethod(object_getClass(o),s),2,'B'))return nil;
    @try{return @(((BOOL(*)(id,SEL))objc_msgSend)(o,s));}@catch(__unused NSException *e){return nil;}
}
static NSNumber *WGCInt(id o,NSString *key) {
    SEL s=NSSelectorFromString(key);if(!o||!WGCTyped(class_getInstanceMethod(object_getClass(o),s),2,'q'))return nil;
    @try{return @(((long long(*)(id,SEL))objc_msgSend)(o,s));}@catch(__unused NSException *e){return nil;}
}
static NSArray *WGCArray(id o,NSString *key,NSUInteger cap) {id a=WGCGet(o,key);return [a isKindOfClass:NSArray.class]&&[a count]<=cap?[a copy]:nil;}
static NSString *WGCRef(id value) {
    if(!gSalt)gSalt=[NSUUID.UUID.UUIDString dataUsingEncoding:NSUTF8StringEncoding];
    NSData *bytes=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:NULL];
    if(!bytes||bytes.length>1024*1024)return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256,gSalt.bytes,gSalt.length,bytes.bytes,bytes.length,digest);
    NSMutableString *s=[NSMutableString string];for(NSUInteger i=0;i<sizeof(digest);i++)[s appendFormat:@"%02x",digest[i]];
    return s;
}
static NSString *WGCTitle(NSString *s) {
    if(!s)return @"";if(s.length<=160)return s;
    return [s substringWithRange:[s rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,160)]];
}
static BOOL WGCQuantity(NSString *s) {
    if(!s.length||s.length>6)return NO;
    return [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location==NSNotFound&&s.longLongValue>0&&s.longLongValue<=99999;
}
static BOOL WGCSet(id o,NSString *name,id value) {
    SEL sel=NSSelectorFromString(name);Method m=class_getInstanceMethod(object_getClass(o),sel);
    char a[256]={0};if(m)method_getArgumentType(m,2,a,sizeof(a));
    if(!WGCTyped(m,3,'v')||!WGCObject(a))return NO;
    ((void(*)(id,SEL,id))objc_msgSend)(o,sel,value);return YES;
}
static void WGCEmptySnapshot(void) {
    gCandidates=@[];gRaw=@{};gLineStates=@{};gRouteContext=@{};
    gKeyIdentity=nil;gSnapshot=nil;
}
static BOOL WGCCollect(id list,id controller) {
    Class lc=NSClassFromString(@"VDTradeCartListDO");
    if(!lc||![list isKindOfClass:lc]){WGCEmptySnapshot();gReason=@"购物车响应模型类型未验证";return NO;}
    NSArray *shops=WGCArray(list,@"shops",40);
    if(!shops){WGCEmptySnapshot();gReason=@"购物车 shops 缺失或超过采集上限";return NO;}
    NSMutableArray *rows=[NSMutableArray array];NSMutableDictionary *raws=[NSMutableDictionary dictionary];
    NSMutableDictionary *states=[NSMutableDictionary dictionary];
    BOOL invalid=NO;
    for(id shop in shops) {
        NSString *shopID=WGCString(shop,@"shopId")?:@"";
        NSArray *parts=WGCArray(shop,@"partitions",100);
        if(!parts){invalid=YES;continue;}
        for(id partition in parts) {
            NSArray *items=WGCArray(partition,@"itemList",200);
            if(!items){invalid=YES;continue;}
            for(id item in items) {
                if(rows.count>=200){invalid=YES;break;}
                NSString *itemID=WGCString(item,@"itemId"),*skuID=WGCString(item,@"skuId")?:@"";
                NSString *qty=WGCString(item,@"count"),*cartID=WGCString(item,@"id")?:@"";
                NSString *actualShop=WGCString(item,@"shopId");if(!actualShop.length)actualShop=shopID;
                if(!itemID.length||!WGCQuantity(qty)){invalid=YES;continue;}
                NSArray *identity=@[cartID,actualShop?:@"",itemID,skuID];
                if(states[identity]){invalid=YES;continue;}
                NSNumber *selected=WGCBool(item,@"isSelected"),*canOrder=WGCBool(item,@"canOrder"),*hasSku=WGCBool(item,@"hasSku");
                NSNumber *priceType=WGCInt(item,@"priceType"),*payType=WGCInt(item,@"payType");
                NSString *price=WGCString(item,@"price"),*available=WGCString(item,@"available_date");
                NSString *title=WGCTitle(WGCString(item,@"itemName")),*skuTitle=WGCTitle(WGCString(item,@"skuName"));
                // Compare cheap native values first. Stable polls reuse immutable
                // rows/raw data and never serialize or HMAC the complete cart.
                NSArray *values=@[qty,selected?:NSNull.null,canOrder?:NSNull.null,hasSku?:NSNull.null,priceType?:NSNull.null,payType?:NSNull.null,price?:NSNull.null,available?:NSNull.null,title,skuTitle];
                WGCLineState *state=gLineStates[identity];
                if(!state||![state.values isEqual:values]) {
                    NSString *key=state.row[@"lineKey"]?:WGCRef(identity);
                    if(!key){invalid=YES;continue;}
                    NSMutableDictionary *raw=[@{@"itemId":itemID,@"skuId":skuID,@"shopId":actualShop?:@"",@"count":qty,@"cartId":cartID} mutableCopy];
                    if(priceType)raw[@"priceType"]=priceType;if(payType)raw[@"payType"]=payType;
                    NSMutableDictionary *row=state? [state.row mutableCopy]:[@{@"lineKey":key,@"itemRef":WGCRef(@[itemID])?:@"",@"skuRef":WGCRef(@[skuID])?:@"",@"shopRef":WGCRef(@[actualShop?:@""])?:@""} mutableCopy];
                    row[@"quantity"]=qty;row[@"title"]=title;row[@"skuTitle"]=skuTitle;
                    NSArray *flags=@[@"isSelected",@"canOrder",@"hasSku"];
                    NSArray *flagValues=@[selected?:NSNull.null,canOrder?:NSNull.null,hasSku?:NSNull.null];
                    for(NSUInteger i=0;i<flags.count;i++) {
                        NSString *flag=flags[i],*rowFlag=i==0?@"selected":flag;id value=flagValues[i];
                        if(value!=NSNull.null){row[rowFlag]=value;raw[flag]=value;}else [row removeObjectForKey:rowFlag];
                    }
                    if(price){row[@"price"]=price;raw[@"price"]=price;}else [row removeObjectForKey:@"price"];
                    if(available)row[@"availableDate"]=WGCTitle(available);else [row removeObjectForKey:@"availableDate"];
                    state=[WGCLineState new];state.values=values;state.row=row;state.raw=raw;gRowBuilds++;
                }
                state.nativeItem=item;states[identity]=state;
                raws[state.row[@"lineKey"]]=state.raw;[rows addObject:state.row];
            }
        }
    }
    if(![gCandidates isEqual:rows])gCandidates=[rows copy];
    if(![gRaw isEqual:raws])gRaw=[raws copy];
    gLineStates=[states copy];
    // A vanished manual target stays manual/empty instead of silently following
    // a different checked row. Explicit ChooseLine(nil) restores follow mode.
    gReason=invalid?@"存在未完整解析的购物车行，本轮暂停自动设置":nil;
    id request=WGCGet(controller,@"request");id params=WGCGet(request,@"queryParams");
    NSMutableDictionary *context=[NSMutableDictionary dictionary];
    if([params isKindOfClass:NSDictionary.class])for(NSString *k in @[@"address_id",@"source_id",@"wfr",@"channel",@"express_type"]) {
        id value=params[k];if([value isKindOfClass:NSString.class]&&[value length]<=512)context[k]=[value copy];
    }
    if(![gRouteContext isEqual:context])gRouteContext=[context copy];
    return YES;
}
static id WGCControllerList(id controller,BOOL *hasGetter) {
    Class lc=NSClassFromString(@"VDTradeCartListDO");
    id vm=WGCGet(controller,@"viewModel");
    NSArray *owners=controller?(vm?@[controller,vm]:@[controller]):@[];
    for(id owner in owners)for(NSString *name in @[@"currentcartListDO",@"cartListDO",@"listDO"]) {
        SEL sel=NSSelectorFromString(name);
        if(!WGCTyped(class_getInstanceMethod(object_getClass(owner),sel),2,'@'))continue;
        *hasGetter=YES;id list=WGCGet(owner,name);
        if(lc&&[list isKindOfClass:lc]){gLiveSource=[NSString stringWithFormat:@"%@.%@",owner==controller?@"controller":@"viewModel",name];return list;}
    }
    return nil;
}
static void WGCSyncLive(void) {
    if(gAwaitingNativeCallback||gSyncing)return;
    if(!NSThread.isMainThread){dispatch_sync(dispatch_get_main_queue(),^{WGCSyncLive();});return;}
    gSyncing=YES;
    @try {
        id controller=gLiveController;BOOL hasGetter=NO;
        id list=WGCControllerList(controller,&hasGetter);
        if(!list&&!hasGetter){list=gLiveList;if(list)gLiveSource=@"callback_weak_model";}
        if(list){gLiveList=list;gLiveReads++;WGCCollect(list,controller);}
        else if(gCandidates.count){WGCEmptySnapshot();gReason=@"原生购物车模型已释放或当前 getter 为空，等待有效模型";}
    } @finally {gSyncing=NO;}
}
static void WGCObserveFetch(id receiver,SEL command,BOOL success,id cartList) {
    if(gOriginalFetch)gOriginalFetch(receiver,command,success,cartList);
    if(!success||!cartList)return;
    NSUInteger epoch=gClearEpoch;
    void (^capture)(void)=^{
        if(epoch!=gClearEpoch)return;
        Class lc=NSClassFromString(@"VDTradeCartListDO");
        if(!lc||![cartList isKindOfClass:lc])return;
        gLiveController=receiver;gLiveList=cartList;
        // Clear remains latched until a subsequent valid native callback.
        // A malformed payload must not unlock it.
        if(!WGCArray(cartList,@"shops",40)) {
            if(!gAwaitingNativeCallback)WGCCollect(cartList,receiver);
            return;
        }
        gAwaitingNativeCallback=NO;gCaptures++;gLiveSource=@"native_fetch_callback";
        WGCCollect(cartList,receiver);
    };
    if(NSThread.isMainThread)capture();else dispatch_async(dispatch_get_main_queue(),capture);
}
static void WGCObserveWillAppear(id receiver,SEL command,BOOL animated) {
    if(gOriginalWillAppear)gOriginalWillAppear(receiver,command,animated);
    gLiveController=receiver;WGCSyncLive();
}
static BOOL WGCBoolArgument(Method m,unsigned index) {
    char a[256]={0};if(m)method_getArgumentType(m,index,a,sizeof(a));const char *t=WGCType(a);
    return (t[0]=='B'||t[0]=='c')&&!t[1];
}
void WDGCartInstallObservers(void) {
    if(gInstalled)return;
    Class cls=NSClassFromString(@"VDTradeMyCartViewController");SEL s=NSSelectorFromString(@"fetchDataSucceed:cartListDO:");
    Method m=cls?class_getInstanceMethod(cls,s):NULL;
    char b[256]={0};if(m)method_getArgumentType(m,3,b,sizeof(b));
    if(!WGCTyped(m,4,'v')||!WGCBoolArgument(m,2)||!WGCObject(b)){gReason=@"购物车回调 BOOL/object ABI 未匹配";return;}
    gOriginalFetch=(void(*)(id,SEL,BOOL,id))method_getImplementation(m);
    method_setImplementation(m,(IMP)WGCObserveFetch);gInstalled=YES;
    SEL appear=NSSelectorFromString(@"viewWillAppear:");Method am=class_getInstanceMethod(cls,appear);
    if(WGCTyped(am,3,'v')&&WGCBoolArgument(am,2)) {
        gOriginalWillAppear=(void(*)(id,SEL,BOOL))method_getImplementation(am);
        // Add an override if inherited: never replace the base Controller's IMP.
        if(!class_addMethod(cls,appear,(IMP)WGCObserveWillAppear,method_getTypeEncoding(am)))method_setImplementation(am,(IMP)WGCObserveWillAppear);
    }
}
NSArray<NSDictionary *> *WDGCartCandidates(void){WGCSyncLive();return gCandidates?:@[];}
NSArray<NSDictionary *> *WDGCartSelectedLines(void) {
    WGCSyncLive();NSMutableArray *picked=[NSMutableArray array];
    for(NSDictionary *r in gCandidates?:@[])if(gChosenLine?[r[@"lineKey"] isEqual:gChosenLine]:[r[@"selected"] boolValue])[picked addObject:r];
    return [picked copy];
}
NSString *WDGCartSnapshotKey(void) {
    NSArray *picked=WDGCartSelectedLines();
    if(!picked.count){gKeyIdentity=nil;gSnapshot=nil;return nil;}
    picked=[picked sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"lineKey"] compare:b[@"lineKey"]];}];
    NSMutableArray *identity=[NSMutableArray array];
    for(NSDictionary *line in picked){NSDictionary *raw=gRaw[line[@"lineKey"]];if(!raw)return nil;[identity addObject:raw];}
    if(![gKeyIdentity isEqual:identity]){gKeyIdentity=[identity copy];gSnapshot=WGCRef(identity);gSnapshotHashes++;}
    return gSnapshot;
}
BOOL WDGCartChooseLine(NSString *lineKey) {
    WGCSyncLive();if(lineKey&&!gRaw[lineKey])return NO;gChosenLine=[lineKey copy];return YES;
}
void WDGCartClear(void){gClearEpoch++;WGCEmptySnapshot();gLiveList=nil;gAwaitingNativeCallback=YES;gChosenLine=nil;gReason=nil;gLiveSource=@"cleared_waiting_native_callback";}
NSDictionary *WDGCartRawLine(NSString *lineKey){WGCSyncLive();return lineKey?gRaw[lineKey]:nil;}
NSArray<NSDictionary *> *WDGCartCopyRawSelection(void) {
    NSMutableArray *a=[NSMutableArray array];for(NSDictionary *r in WDGCartSelectedLines()){NSDictionary *raw=gRaw[r[@"lineKey"]];if(!raw)return @[];[a addObject:[raw copy]];}return [a copy];
}
id WDGCartBuildRequest(NSError **error) {
#define WGC_FAIL(c,msg) do{if(error)*error=[NSError errorWithDomain:@"WeidianGrab.Cart" code:c userInfo:@{NSLocalizedDescriptionKey:msg}];return nil;}while(0)
    WGCSyncLive();
    if(gReason.length)WGC_FAIL(1,gReason);
    NSArray *selected=WDGCartCopyRawSelection();if(!selected.count)WGC_FAIL(2,@"请选择具体购物车商品，助手不会自动全选");
    Class rc=NSClassFromString(@"VDTradeConfirmOrderRequestDO"),ic=NSClassFromString(@"VDTradeConfOrderRequestItemDO");
    if(!rc||!ic)WGC_FAIL(3,@"原生请求模型缺失");
    // Follow the App's pure token-parser initializer when it is present. It
    // supplies native defaults (including price_type/use_installment) without
    // pushing a Controller or calling a network method.
    Class routerClass=NSClassFromString(@"WDURLRouterRequest"),vmClass=NSClassFromString(@"VDTradeConfOrderViewModel");
    if(!routerClass||!vmClass)WGC_FAIL(3,@"原生纯解析模型缺失");
    NSMutableArray *tokens=[NSMutableArray array];
    for(NSDictionary *raw in selected) {
        NSString *iid=raw[@"itemId"],*sku=raw[@"skuId"]?:@"",*qty=raw[@"count"];
        if(!raw[@"hasSku"]||!iid.length||!WGCQuantity(qty)||([raw[@"hasSku"] boolValue]&&!sku.length))WGC_FAIL(4,@"商品、规格状态或数量不完整");
        if(![raw[@"hasSku"] boolValue])sku=@"";
        if([iid containsString:@"_"]||[iid containsString:@","]||[sku containsString:@"_"]||[sku containsString:@","])WGC_FAIL(9,@"商品标识不符合已验证的购物车 token 格式");
        // Native itemIdCountSku token[3] is payType.stringValue, not priceType.
        NSString *priceType=raw[@"payType"]?[raw[@"payType"] stringValue]:@"1";
        [tokens addObject:[NSString stringWithFormat:@"%@_%@_%@_%@",iid,qty,sku,priceType]];
    }
    NSMutableDictionary *params=[gRouteContext mutableCopy]?:[NSMutableDictionary dictionary];
    params[@"items"]=[tokens componentsJoinedByString:@","];
    params[@"source_id"]=@"5774937da7853cd3860c022c7fb13f84";
    @try {
        id router=[[routerClass alloc] init];
        if(!WGCSet(router,@"setQueryParams:",params))WGC_FAIL(10,@"原生路由参数 ABI 未匹配");
        SEL init=NSSelectorFromString(@"initWithRequest:");Method m=class_getInstanceMethod(vmClass,init);char a[256]={0};if(m)method_getArgumentType(m,2,a,sizeof(a));
        if(!WGCTyped(m,3,'@')||!WGCObject(a))WGC_FAIL(11,@"原生订单 ViewModel 初始化 ABI 未匹配");
        id vm=[(id<WGCNativeViewModelInitializer>)[vmClass alloc] initWithRequest:router];
        id nativeRequest=WGCGet(vm,@"requestDO");NSArray *nativeItems=WGCArray(nativeRequest,@"items",200);
        if(![nativeRequest isKindOfClass:rc]||nativeItems.count!=selected.count)WGC_FAIL(12,@"原生解析未生成完整购物车请求");
        for(NSUInteger i=0;i<nativeItems.count;i++) {
            id item=nativeItems[i];NSDictionary *raw=selected[i];
            NSString *sku=[raw[@"hasSku"] boolValue]?raw[@"skuId"]:@"";
            NSString *price=raw[@"payType"]?[raw[@"payType"] stringValue]:@"1";
            if(![item isKindOfClass:ic]||![WGCString(item,@"item_id") isEqual:raw[@"itemId"]]||![WGCString(item,@"item_sku_id") isEqual:sku]||![WGCString(item,@"quantity") isEqual:raw[@"count"]]||![WGCString(item,@"price_type") isEqual:price])WGC_FAIL(13,@"原生解析的请求条目与所选商品不一致");
        }
        return nativeRequest;
    } @catch(__unused NSException *exception) { WGC_FAIL(14,@"原生纯解析请求异常"); }
#undef WGC_FAIL
}
NSDictionary *WDGCartDiagnostics(void) {
    NSArray *selected=WDGCartSelectedLines();NSString *key=WDGCartSnapshotKey();
    BOOL manualMissing=gChosenLine&&!gRaw[gChosenLine];
    NSString *selectionReason=gAwaitingNativeCallback?@"采集已清空，等待下一次有效原生回调":manualMissing?@"手动指定行已消失，请重新指定或恢复跟随购物车":gChosenLine?@"助手手动指定，覆盖原生勾选":selected.count?@"实时跟随原生购物车勾选":@"原生购物车当前未勾选商品";
    return @{@"installed":@(gInstalled),@"captures":@(gCaptures),@"candidateCount":@(gCandidates.count),@"lineCount":@(selected.count),@"key":key?:@"",@"reason":gReason?:@"",@"selectionSource":gChosenLine?@"assistant_explicit":@"app_checked",@"selectionReason":selectionReason,@"manualLineAvailable":@(!gChosenLine||!manualMissing),@"awaitingNativeCallback":@(gAwaitingNativeCallback),@"liveControllerAlive":@(gLiveController!=nil),@"liveModelAlive":@(gLiveList!=nil),@"liveSource":gLiveSource?:@"none",@"liveReads":@(gLiveReads),@"rowBuilds":@(gRowBuilds),@"snapshotHashes":@(gSnapshotHashes)};
}
