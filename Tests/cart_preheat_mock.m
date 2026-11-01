// macOS, from tools/weidian-grab (links the real production implementations):
// clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter \
//   -framework Foundation Tests/cart_preheat_mock.m WDGCart.m \
//   WDGOrderService.m -o /tmp/cart_preheat_mock && /tmp/cart_preheat_mock
// No UIKit, devices, URL requests, networking libraries, or production stubs.
// BOOL callback ABI is native BOOL; model flags use bool for the verified B ABI,
// including on Intel macOS where BOOL itself has the c encoding.
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#import <stdbool.h>
#import <stdio.h>
#import "../WDGCart.h"
#import "../WDGOrderService.h"

static void FixtureRequire(BOOL condition, NSString *message, const char *function, int line) {
    if (!condition) [NSException raise:@"FixtureAssertion"
        format:@"%s:%d: %@", function, line, message];
}
// Variadic forwarding also permits commas inside Objective-C array literals.
#define REQUIRE(...) FixtureRequire(__VA_ARGS__, __func__, __LINE__)

static NSUInteger OriginalCallbacks;
static BOOL OriginalLastOK;
static id OriginalLastList;
static NSUInteger UnknownReads;
static NSUInteger WrongGetterCalls;
static NSUInteger ModelConversions;
static NSUInteger NativeVMInitializations;
static NSString *LastItemsToken;
static NSUInteger ConfirmCalls;
static NSUInteger CreateCalls;
static NSUInteger FixtureGeneration;
static NSString *NativeViolation;
static NSDate *ExpectedDueAt;
static NSMutableArray<NSDate *> *ConfirmDates;
static NSMutableArray<NSDate *> *CreateDates;
static NSMutableArray<NSDictionary *> *ConfirmRequests;
static NSMutableArray<NSDictionary *> *CreateRequests;
static NSMutableArray<id> *ConfirmCallbacks;
static NSMutableArray<id> *CreateCallbacks;
static Class ConfirmationSubclass;

typedef void (^NativeReply)(BOOL, id, id);

@interface WDURLRouterRequest : NSObject
@property(nonatomic, copy) NSDictionary *queryParams;
@property(nonatomic, copy) NSDictionary *nativeParams;
@end
@implementation WDURLRouterRequest
@end

@interface VDTradeMyCartViewController : NSObject
@property(nonatomic, strong) WDURLRouterRequest *request;
- (void)fetchDataSucceed:(BOOL)ok cartListDO:(id)list;
@end
@implementation VDTradeMyCartViewController
- (void)fetchDataSucceed:(BOOL)ok cartListDO:(id)list {
    ++OriginalCallbacks;
    OriginalLastOK = ok;
    OriginalLastList = list;
}
@end

@interface VDTradeCartListDO : NSObject
@property(nonatomic, copy) NSArray *shops;
@end
@implementation VDTradeCartListDO
@end

@interface VDTradeCartItemDO : NSObject
@property(nonatomic, copy) NSArray *partitions;
@property(nonatomic, copy) NSString *shopId;
@end
@implementation VDTradeCartItemDO
@end

@interface VDTradeCartPartitionDO : NSObject
@property(nonatomic, copy) NSArray *itemList;
@end
@implementation VDTradeCartPartitionDO
@end

@interface VDTradeGoodsItemDO : NSObject
@property(nonatomic, copy) NSString *id;
@property(nonatomic, copy) NSString *itemId;
@property(nonatomic, copy) NSString *skuId;
@property(nonatomic, copy) NSString *shopId;
@property(nonatomic, copy) NSString *count;
@property(nonatomic, copy) NSString *itemName;
@property(nonatomic, copy) NSString *skuName;
@property(nonatomic, copy) NSString *price;
@property(nonatomic) long long priceType;
@property(nonatomic) long long payType;
@property(nonatomic) bool isSelected;
@property(nonatomic) bool canOrder;
@property(nonatomic) bool hasSku;
@property(nonatomic, copy) NSString *available_date;
@end
@implementation VDTradeGoodsItemDO
@end

@interface VDTradeConfOrderRequestItemDO : NSObject
@property(nonatomic, copy) NSString *item_id;
@property(nonatomic, copy) NSString *item_sku_id;
@property(nonatomic, copy) NSString *quantity;
@property(nonatomic, copy) NSString *price_type;
@property(nonatomic) bool use_installment;
- (NSDictionary *)yy_modelToJSONObject;
@end
@implementation VDTradeConfOrderRequestItemDO
- (NSDictionary *)yy_modelToJSONObject {
    return @{@"item_id": self.item_id ?: @"",
             @"item_sku_id": self.item_sku_id ?: @"",
             @"quantity": self.quantity ?: @"",
             @"price_type": self.price_type ?: @""};
}
@end

@interface VDTradeConfirmOrderRequestDO : NSObject
@property(nonatomic, strong) NSMutableArray<VDTradeConfOrderRequestItemDO *> *items;
@property(nonatomic, copy) NSString *source_id;
@property(nonatomic, copy) NSString *channel;
@property(nonatomic, copy) NSString *address_id;
@property(nonatomic, copy) NSString *wfr;
@property(nonatomic) NSUInteger payButtonType;
- (NSDictionary *)yy_modelToJSONObject;
@end
@implementation VDTradeConfirmOrderRequestDO
- (instancetype)init {
    self = [super init];
    if (self) {
        _items = [NSMutableArray array];
        _source_id = @"";
        _channel = @"";
        _address_id = @"";
        _wfr = @"";
    }
    return self;
}
- (NSDictionary *)yy_modelToJSONObject {
    NSMutableArray *items = [NSMutableArray array];
    for (id item in self.items) {
        if (![item isKindOfClass:VDTradeConfOrderRequestItemDO.class]) {
            [NSException raise:@"FixtureTypedItems"
                        format:@"request.items contains %@, not a native item DO", [item class]];
        }
        [items addObject:[item yy_modelToJSONObject]];
    }
    return @{@"items": items, @"source_id": self.source_id ?: @"",
             @"channel": self.channel ?: @"", @"address_id": self.address_id ?: @"",
             @"wfr": self.wfr ?: @"", @"payButtonType": @(self.payButtonType)};
}
@end

// Mirrors only the observed pure token parser, not an App controller or API.
@interface VDTradeConfOrderViewModel : NSObject
@property(nonatomic, strong) VDTradeConfirmOrderRequestDO *requestDO;
- (instancetype)initWithRequest:(WDURLRouterRequest *)router;
@end
@implementation VDTradeConfOrderViewModel
- (instancetype)initWithRequest:(WDURLRouterRequest *)router {
    self = [super init];
    if (!self) return nil;
    ++NativeVMInitializations;
    _requestDO = [VDTradeConfirmOrderRequestDO new];
    NSDictionary *params = router.queryParams;
    id token = router.nativeParams[@"items"] ?: params[@"items"];
    LastItemsToken = [token isKindOfClass:NSString.class] ? [token copy] : nil;
    if ([token isKindOfClass:NSArray.class]) {
        // Native array branch only copies: dictionaries must not be converted.
        _requestDO.items = [token mutableCopy];
    } else if ([token isKindOfClass:NSString.class]) {
        for (NSString *line in [token componentsSeparatedByString:@","]) {
            NSArray<NSString *> *parts = [line componentsSeparatedByString:@"_"];
            if (parts.count < 2 || !parts[0].length) continue;
            VDTradeConfOrderRequestItemDO *item = [VDTradeConfOrderRequestItemDO new];
            item.item_id = parts[0];
            item.quantity = parts[1];
            item.item_sku_id = parts.count > 2 ? parts[2] : @"";
            item.price_type = parts.count > 3 && parts[3].length ? parts[3] : @"1";
            item.use_installment = YES;
            [_requestDO.items addObject:item];
        }
    }
    // Observed initWithRequest does not assign address_id.
    for (NSString *key in @[@"source_id", @"channel", @"wfr"]) {
        id value = params[key];
        if ([value isKindOfClass:NSString.class]) [_requestDO setValue:value forKey:key];
    }
    return self;
}
@end

@interface VDTradeConfirmOrderPayButtonDO : NSObject
@property(nonatomic) NSUInteger type;
@property(nonatomic, copy) NSString *name;
- (NSDictionary *)yy_modelToJSONObject;
@end
@implementation VDTradeConfirmOrderPayButtonDO
- (NSDictionary *)yy_modelToJSONObject {
    return @{@"type": @(self.type), @"name": self.name ?: @""};
}
@end

@interface VDTradeConfirmOrderPayOptionDO : NSObject
@property(nonatomic) bool available;
@property(nonatomic) bool selected;
@property(nonatomic) NSUInteger pay_type;
@property(nonatomic, copy) NSArray<VDTradeConfirmOrderPayButtonDO *> *buttons;
- (NSDictionary *)yy_modelToJSONObject;
@end
@implementation VDTradeConfirmOrderPayOptionDO
- (NSDictionary *)yy_modelToJSONObject {
    NSMutableArray *buttons = [NSMutableArray array];
    for (VDTradeConfirmOrderPayButtonDO *button in self.buttons) {
        [buttons addObject:button.yy_modelToJSONObject];
    }
    return @{@"available": @(self.available), @"selected": @(self.selected),
             @"pay_type": @(self.pay_type), @"buttons": buttons};
}
@end

@interface VDTradeConfirmOrderShopItemDO : NSObject
@property(nonatomic, copy) NSString *item_id;
@property(nonatomic, copy) NSString *item_sku_id;
@property(nonatomic, copy) NSString *quantity;
- (NSDictionary *)yy_modelToJSONObject;
@end
@implementation VDTradeConfirmOrderShopItemDO
- (NSDictionary *)yy_modelToJSONObject {
    return @{@"item_id": self.item_id ?: @"", @"item_sku_id": self.item_sku_id ?: @"",
             @"quantity": self.quantity ?: @""};
}
@end

@interface VDTradeConfirmOrderShopDO : NSObject
@property(nonatomic, strong) NSMutableArray<VDTradeConfirmOrderShopItemDO *> *item_list;
- (NSDictionary *)yy_modelToJSONObject;
@end
@implementation VDTradeConfirmOrderShopDO
- (NSDictionary *)yy_modelToJSONObject {
    NSMutableArray *items = [NSMutableArray array];
    for (VDTradeConfirmOrderShopItemDO *item in self.item_list) {
        [items addObject:item.yy_modelToJSONObject];
    }
    return @{@"item_list": items};
}
@end

@interface VDTradeConfirmOrderDO : NSObject
@property(nonatomic) bool cannot_submit;
@property(nonatomic) bool need_add_address;
@property(nonatomic, copy) NSString *total_pay_price;
@property(nonatomic, copy) NSArray<VDTradeConfirmOrderShopDO *> *shop_list;
@property(nonatomic, copy) NSArray<VDTradeConfirmOrderPayOptionDO *> *pay_options;
@property(nonatomic, copy) NSArray *agreement_info_list;
@property(nonatomic, copy) NSArray *fixture_real_agreements;
@property(nonatomic) bool fixture_checkbox;
@property(nonatomic) bool isAgreementChecked;
- (NSArray *)getRealAgreementInfos;
- (bool)shouldShowAgreementInCheckbox;
+ (instancetype)yy_modelWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)yy_modelToJSONObject;
@end
@implementation VDTradeConfirmOrderDO
- (NSArray *)getRealAgreementInfos {return self.fixture_real_agreements ?: @[];}
- (bool)shouldShowAgreementInCheckbox {return self.fixture_checkbox;}
+ (instancetype)yy_modelWithDictionary:(NSDictionary *)dictionary {
    ++ModelConversions;
    if (![dictionary isKindOfClass:NSDictionary.class]) return nil;
    VDTradeConfirmOrderDO *model = [(ConfirmationSubclass ?: self) new];
    model.cannot_submit = [dictionary[@"cannot_submit"] boolValue];
    model.need_add_address = [dictionary[@"need_add_address"] boolValue];
    model.total_pay_price = dictionary[@"total_pay_price"];
    model.agreement_info_list = dictionary[@"agreement_info_list"] ?: @[];
    model.fixture_real_agreements = dictionary[@"fixture_real_agreements"] ?: model.agreement_info_list;
    model.fixture_checkbox = [dictionary[@"fixture_checkbox"] boolValue];
    model.isAgreementChecked = [dictionary[@"isAgreementChecked"] boolValue];
    NSMutableArray *shops = [NSMutableArray array];
    for (NSDictionary *shopJSON in dictionary[@"shop_list"] ?: @[]) {
        VDTradeConfirmOrderShopDO *shop = [VDTradeConfirmOrderShopDO new];
        shop.item_list = [NSMutableArray array];
        for (NSDictionary *itemJSON in shopJSON[@"item_list"] ?: @[]) {
            VDTradeConfirmOrderShopItemDO *item = [VDTradeConfirmOrderShopItemDO new];
            item.item_id = itemJSON[@"item_id"];
            item.item_sku_id = itemJSON[@"item_sku_id"];
            item.quantity = itemJSON[@"quantity"];
            [shop.item_list addObject:item];
        }
        [shops addObject:shop];
    }
    model.shop_list = shops;
    NSMutableArray *options = [NSMutableArray array];
    for (NSDictionary *optionJSON in dictionary[@"pay_options"] ?: @[]) {
        VDTradeConfirmOrderPayOptionDO *option = [VDTradeConfirmOrderPayOptionDO new];
        option.available = [optionJSON[@"available"] boolValue];
        option.selected = [optionJSON[@"selected"] boolValue];
        option.pay_type = [optionJSON[@"pay_type"] unsignedIntegerValue];
        NSMutableArray *buttons = [NSMutableArray array];
        for (NSDictionary *buttonJSON in optionJSON[@"buttons"] ?: @[]) {
            VDTradeConfirmOrderPayButtonDO *button = [VDTradeConfirmOrderPayButtonDO new];
            button.type = [buttonJSON[@"type"] unsignedIntegerValue];
            button.name = buttonJSON[@"name"];
            [buttons addObject:button];
        }
        option.buttons = buttons;
        [options addObject:option];
    }
    model.pay_options = options;
    return model;
}
- (NSDictionary *)yy_modelToJSONObject {
    NSMutableArray *shops = [NSMutableArray array];
    NSMutableArray *options = [NSMutableArray array];
    for (VDTradeConfirmOrderShopDO *shop in self.shop_list) {
        [shops addObject:shop.yy_modelToJSONObject];
    }
    for (VDTradeConfirmOrderPayOptionDO *option in self.pay_options) {
        [options addObject:option.yy_modelToJSONObject];
    }
    return @{@"cannot_submit": @(self.cannot_submit),
             @"need_add_address": @(self.need_add_address),
             @"total_pay_price": self.total_pay_price ?: @"",
             @"shop_list": shops, @"pay_options": options,
             @"agreement_info_list": self.agreement_info_list ?: @[],
             @"fixture_real_agreements": self.fixture_real_agreements ?: @[],
             @"fixture_checkbox": @(self.fixture_checkbox),
             @"isAgreementChecked": @(self.isAgreementChecked)};
}
@end

@interface WDGFixturePoisonList : NSObject
- (NSArray *)shops;
@end
@implementation WDGFixturePoisonList
- (NSArray *)shops {
    ++UnknownReads;
    [NSException raise:@"FixturePoisonRead" format:@"FALSE callback read the unknown model"];
    return nil;
}
@end

@interface WDGFixtureStep : NSObject
@property(nonatomic) BOOL ok;
@property(nonatomic, strong) id response;
@property(nonatomic, strong) id error;
@property(nonatomic) NSTimeInterval delay;
@property(nonatomic) NSUInteger copies;
@property(nonatomic) BOOL hanging;
+ (instancetype)success:(id)response;
@end
@implementation WDGFixtureStep
+ (instancetype)success:(id)response {
    WDGFixtureStep *step = [self new];
    step.ok = YES;
    step.response = response;
    step.copies = 1;
    return step;
}
@end
static NSMutableArray<WDGFixtureStep *> *ConfirmSteps;
static WDGFixtureStep *CreateStep;

static void FixtureDeliver(WDGFixtureStep *step, NativeReply result) {
    if (step.hanging) return;
    NSUInteger generation = FixtureGeneration;
    dispatch_block_t deliver = ^{
        if (generation != FixtureGeneration) return;
        for (NSUInteger i = 0; i < step.copies; ++i) {
            result(step.ok, step.response, step.error);
        }
    };
    if (step.delay > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                       (int64_t)(step.delay * (double)NSEC_PER_SEC)),
                       dispatch_get_main_queue(), deliver);
    } else {
        deliver(); // Deliberately synchronous, before the native method returns.
    }
}

static void FixtureCheckNativeRequest(id request) {
    if (![request isKindOfClass:VDTradeConfirmOrderRequestDO.class]) {
        NativeViolation = @"native Service received an untyped request";
        return;
    }
    VDTradeConfirmOrderRequestDO *typed = request;
    if (![typed.items isKindOfClass:NSArray.class] || !typed.items.count) {
        NativeViolation = @"native Service received empty or unknown items";
    }
    for (id item in typed.items) {
        if (![item isKindOfClass:VDTradeConfOrderRequestItemDO.class] ||
            [item isKindOfClass:NSDictionary.class]) {
            NativeViolation = @"native Service received dictionaries in request.items";
        }
    }
    for (id value in @[typed.source_id ?: NSNull.null, typed.channel ?: NSNull.null,
                       typed.address_id ?: NSNull.null, typed.wfr ?: NSNull.null]) {
        if (![value isKindOfClass:NSString.class]) {
            NativeViolation = @"native request source/channel/address/wfr must remain strings";
        }
    }
}

@interface VDTradeConfOrderService : NSObject
+ (void)confirmOrderWithRequestDO:(VDTradeConfirmOrderRequestDO *)request
                         result:(void (^)(BOOL, id, id))result;
+ (void)createOrderRequestDO:(VDTradeConfirmOrderRequestDO *)request
             confirmOrderDO:(VDTradeConfirmOrderDO *)confirmation
                     result:(void (^)(BOOL, id, id))result;
@end
@implementation VDTradeConfOrderService
+ (void)confirmOrderWithRequestDO:(VDTradeConfirmOrderRequestDO *)request
                         result:(void (^)(BOOL, id, id))result {
    ++ConfirmCalls;
    [ConfirmDates addObject:NSDate.date];
    [ConfirmCallbacks addObject:[result copy]];
    FixtureCheckNativeRequest(request);
    [ConfirmRequests addObject:request.yy_modelToJSONObject];
    if (ConfirmCalls > ConfirmSteps.count) {
        NativeViolation = @"unexpected Confirm invocation (script exhausted)";
        return;
    }
    FixtureDeliver(ConfirmSteps[ConfirmCalls - 1], result);
}
+ (void)createOrderRequestDO:(VDTradeConfirmOrderRequestDO *)request
             confirmOrderDO:(VDTradeConfirmOrderDO *)confirmation
                     result:(void (^)(BOOL, id, id))result {
    ++CreateCalls;
    [CreateDates addObject:NSDate.date];
    [CreateCallbacks addObject:[result copy]];
    FixtureCheckNativeRequest(request);
    [CreateRequests addObject:request.yy_modelToJSONObject];
    if (![confirmation isKindOfClass:VDTradeConfirmOrderDO.class]) {
        NativeViolation = @"Create received JSON instead of the confirmation DO";
    }
    if (ExpectedDueAt && [NSDate.date compare:ExpectedDueAt] == NSOrderedAscending) {
        NativeViolation = @"Create was sent before dueAt";
    }
    if (CreateCalls > 1) NativeViolation = @"Create retried or duplicate-dispatched";
    FixtureDeliver(CreateStep, result);
}
@end

@interface WDGFixtureRun : NSObject
@property(nonatomic, strong) WDGOrderService *service;
@property(nonatomic, strong) VDTradeConfirmOrderRequestDO *request;
@property(nonatomic, copy) NSString *taskID;
@property(nonatomic, strong) NSDate *dueAt;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *receipts;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *terminals;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *progress;
@property(nonatomic) NSUInteger savedPayButtonType;
@end
@implementation WDGFixtureRun
@end
static NSMutableArray<WDGFixtureRun *> *Runs;

// A timer is a real run-loop input source; an idle loop therefore does not turn
// into a CPU-burning poll. NSRunLoop also services the asynchronous main queue.
static BOOL FixturePump(NSTimeInterval limit, BOOL (^condition)(void)) {
    REQUIRE(limit >= 0 && limit <= 0.80, @"every bounded wait must be <= 0.8 second");
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:limit];
    NSTimer *pulse = [NSTimer timerWithTimeInterval:0.004 repeats:YES
                      block:^(NSTimer *timer) { (void)timer; }];
    [NSRunLoop.currentRunLoop addTimer:pulse forMode:NSDefaultRunLoopMode];
    while ([deadline timeIntervalSinceNow] > 0 && (!condition || !condition())) {
        NSDate *slice = [NSDate dateWithTimeIntervalSinceNow:0.008];
        if ([slice compare:deadline] == NSOrderedDescending) slice = deadline;
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:slice];
    }
    [pulse invalidate];
    return !condition || condition();
}

static long long FixtureWrongIntegerGetter(id receiver, SEL selector) {
    ++WrongGetterCalls;
    return 1; // Calling this as an object getter would hand ARC address 0x1.
}
static double FixtureWrongDoubleGetter(id receiver, SEL selector) {
    ++WrongGetterCalls;
    return 1.0;
}
static void FixtureWrongIntegerSetter(id receiver, SEL selector, long long value) {
    ++WrongGetterCalls;
}
static long long FixtureWrongCreate(id receiver, SEL selector, id request, id model, id reply) {
    ++WrongGetterCalls;
    return 1;
}
static long long FixtureWrongConfirm(id receiver, SEL selector, id request, id reply) {
    ++WrongGetterCalls;
    return 1;
}
static Class FixtureSubclass(Class base, NSString *tag, SEL selector, IMP implementation,
                             const char *types) {
    static NSUInteger sequence;
    NSString *name = [NSString stringWithFormat:@"WDGFixture_%@_%lu", tag,
                                               (unsigned long)++sequence];
    Class subclass = objc_allocateClassPair(base, name.UTF8String, 0);
    REQUIRE(subclass != Nil, @"runtime subclass allocation failed");
    REQUIRE(class_addMethod(subclass, selector, implementation, types),
            @"installing deliberately incompatible getter failed");
    objc_registerClassPair(subclass);
    return subclass;
}

static VDTradeGoodsItemDO *FixtureGoods(NSString *cartID, NSString *sku, NSString *count,
                                      BOOL selected) {
    VDTradeGoodsItemDO *goods = [VDTradeGoodsItemDO new];
    goods.id = cartID;
    goods.itemId = @"item-1";
    goods.skuId = sku;
    goods.shopId = @"shop-1";
    goods.count = count;
    goods.itemName = @"Fixture goods";
    goods.skuName = sku;
    goods.price = @"12.50";
    goods.priceType = 7;
    goods.payType = 31;
    goods.isSelected = selected;
    goods.canOrder = YES;
    goods.hasSku = YES;
    goods.available_date = @"2099-01-01 00:00:00";
    return goods;
}
static VDTradeCartListDO *FixtureCart(NSArray *items) {
    VDTradeCartPartitionDO *partition = [VDTradeCartPartitionDO new];
    partition.itemList = items;
    VDTradeCartItemDO *shop = [VDTradeCartItemDO new];
    shop.shopId = @"shop-1";
    shop.partitions = @[partition];
    VDTradeCartListDO *list = [VDTradeCartListDO new];
    list.shops = @[shop];
    return list;
}
static VDTradeMyCartViewController *FixtureController(void) {
    WDURLRouterRequest *router = [WDURLRouterRequest new];
    router.queryParams = @{@"source_id": @"5774937da7853cd3860c022c7fb13f84",
                          @"channel": @"fixture-channel", @"address_id": @"fixture-address",
                          @"wfr": @"fixture-wfr"};
    router.nativeParams = @{};
    VDTradeMyCartViewController *controller = [VDTradeMyCartViewController new];
    controller.request = router;
    return controller;
}
static void FixtureCapture(NSArray *items) {
    [FixtureController() fetchDataSucceed:YES cartListDO:FixtureCart(items)];
}
static NSString *FixtureLineKey(NSDictionary *line) {
    id key = line[@"lineKey"];
    REQUIRE([key isKindOfClass:NSString.class] && [key length],
            @"each cart detail must expose a nonempty lineKey");
    return key;
}
static VDTradeConfirmOrderRequestDO *FixtureRequest(void) {
    VDTradeConfOrderRequestItemDO *item = [VDTradeConfOrderRequestItemDO new];
    item.item_id = @"item-1";
    item.item_sku_id = @"sku-1";
    item.quantity = @"1";
    // Observed native itemIdCountSku token[3] maps payType to price_type.
    item.price_type = @"31";
    VDTradeConfirmOrderRequestDO *request = [VDTradeConfirmOrderRequestDO new];
    request.items = [NSMutableArray arrayWithObject:item];
    request.source_id = @"cart";
    request.channel = @"fixture-channel";
    request.address_id = @"fixture-address";
    request.wfr = @"fixture-wfr";
    request.payButtonType = 99;
    return request;
}
static NSDictionary *FixtureConfirmation(VDTradeConfirmOrderRequestDO *request) {
    NSMutableArray *items = [NSMutableArray array];
    for (VDTradeConfOrderRequestItemDO *item in request.items) {
        [items addObject:@{@"item_id": item.item_id ?: @"",
                          @"item_sku_id": item.item_sku_id ?: @"",
                          @"quantity": item.quantity ?: @""}];
    }
    return @{@"cannot_submit": @NO, @"need_add_address": @NO,
             @"total_pay_price": @"25.00", @"shop_list": @[@{@"item_list": items}],
             @"pay_options": @[@{@"available": @YES, @"selected": @YES,
                                    @"pay_type": @9003,
                                    @"buttons": @[@{@"type": @3, @"name": @"Fixture button"}]}]};
}
static void FixtureScript(NSArray<WDGFixtureStep *> *steps) {
    ConfirmSteps = [steps mutableCopy];
}
static void FixtureDefaultScript(VDTradeConfirmOrderRequestDO *request) {
    FixtureScript(@[[WDGFixtureStep success:FixtureConfirmation(request)]]);
}
static WDGFixtureRun *FixturePrepare(VDTradeConfirmOrderRequestDO *request,
                                    NSNumber *payType, NSTimeInterval dueDelay) {
    NSError *error = nil;
    WDGOrderService *service = [WDGOrderService preparePreheatRequest:request
        sampleKey:@"fixture-cart-snapshot" payType:payType error:&error];
    REQUIRE(service && !error, [NSString stringWithFormat:@"prepare failed: %@", error]);
    WDGFixtureRun *run = [WDGFixtureRun new];
    run.service = service;
    run.request = request;
    run.savedPayButtonType = request.payButtonType;
    run.taskID = [NSUUID UUID].UUIDString;
    run.dueAt = [NSDate dateWithTimeIntervalSinceNow:dueDelay];
    run.receipts = [NSMutableArray array];
    run.terminals = [NSMutableArray array];
    run.progress = [NSMutableArray array];
    error = nil;
    REQUIRE([service configureCartDueAt:run.dueAt
        maximumTotal:[NSDecimalNumber decimalNumberWithString:@"100.00"] error:&error] && !error,
        [NSString stringWithFormat:@"future subsecond dueAt must be usable in fixture: %@", error]);
    ExpectedDueAt = run.dueAt;
    [Runs addObject:run];
    return run;
}
static BOOL FixtureSubmit(WDGFixtureRun *run, NSError **error) {
    return [run.service submitTask:run.taskID completion:^(NSDictionary *receipt) {
        // A progress receipt MUST NOT finish the fixture or mark API success.
        [run.receipts addObject:receipt];
        if ([receipt[@"terminal"] boolValue]) [run.terminals addObject:receipt];
        else [run.progress addObject:receipt];
    } error:error];
}
static void FixtureStart(WDGFixtureRun *run) {
    NSError *error = nil;
    REQUIRE(FixtureSubmit(run, &error) && !error,
            [NSString stringWithFormat:@"submit failed: %@", error]);
}
static void FixtureValidateReceipts(WDGFixtureRun *run) {
    NSSet *states = [NSSet setWithArray:@[@"apiSucceeded", @"failed", @"cancelled", @"unknown"]];
    for (NSDictionary *receipt in run.receipts) {
        REQUIRE([receipt[@"terminal"] isKindOfClass:NSNumber.class],
                @"every stage receipt must explicitly contain terminal BOOL");
        REQUIRE(![receipt[@"paymentInvoked"] boolValue], @"fixture must never invoke payment");
        if ([receipt[@"terminal"] boolValue]) {
            REQUIRE([states containsObject:receipt[@"state"]], @"unrecognized terminal state");
        } else {
            REQUIRE(![receipt[@"apiSucceeded"] boolValue], @"progress claims API success");
        }
    }
    REQUIRE(!NativeViolation, NativeViolation ?: @"native fixture contract violation");
}
static NSDictionary *FixtureFinish(WDGFixtureRun *run) {
    REQUIRE(FixturePump(0.55, ^BOOL { return run.terminals.count > 0; }),
        [NSString stringWithFormat:@"terminal=YES never arrived; receipts=%@", run.receipts]);
    FixtureValidateReceipts(run);
    return run.terminals.lastObject;
}
static void FixtureRequireState(WDGFixtureRun *run, NSString *state) {
    NSDictionary *terminal = FixtureFinish(run);
    REQUIRE([terminal[@"state"] isEqual:state],
            [NSString stringWithFormat:@"wanted %@, got %@", state, terminal]);
    REQUIRE([terminal[@"apiSucceeded"] boolValue] == [state isEqual:@"apiSucceeded"],
            @"apiSucceeded flag disagrees with the terminal state");
}
static void FixtureNoEarlyCreate(WDGFixtureRun *run) {
    FixturePump(0.025, nil);
    REQUIRE([run.dueAt timeIntervalSinceNow] > 0, @"fixture pre-due observation missed its window");
    REQUIRE(CreateCalls == 0, @"warmup dispatched Create before dueAt");
    REQUIRE(run.terminals.count == 0, @"warmup progress was incorrectly terminal");
}
static void FixtureNoResubmit(WDGFixtureRun *run) {
    NSError *error = nil;
    NSUInteger confirms = ConfirmCalls;
    NSUInteger creates = CreateCalls;
    REQUIRE(!FixtureSubmit(run, &error) && error, @"the same service/task was submitted twice");
    REQUIRE(ConfirmCalls == confirms && CreateCalls == creates, @"rejected resubmit touched native Service");
}
static void FixtureReset(void) {
    ++FixtureGeneration;
    OriginalCallbacks = 0;
    OriginalLastOK = NO;
    OriginalLastList = nil;
    UnknownReads = 0;
    WrongGetterCalls = 0;
    ModelConversions = 0;
    NativeVMInitializations = 0;
    LastItemsToken = nil;
    ConfirmCalls = 0;
    CreateCalls = 0;
    NativeViolation = nil;
    ExpectedDueAt = nil;
    ConfirmationSubclass = Nil;
    ConfirmDates = [NSMutableArray array];
    CreateDates = [NSMutableArray array];
    ConfirmRequests = [NSMutableArray array];
    CreateRequests = [NSMutableArray array];
    ConfirmCallbacks = [NSMutableArray array];
    CreateCallbacks = [NSMutableArray array];
    ConfirmSteps = [NSMutableArray array];
    CreateStep = [WDGFixtureStep success:@{@"order_id": @"fixture-order-1"}];
    Runs = [NSMutableArray array];
    WDGCartClear();
}

static NSUInteger CasesPassed;
static NSUInteger CasesFailed;
static void FixtureCase(NSString *name, void (^body)(void)) {
    @autoreleasepool {
        FixtureReset();
        NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
        @try {
            body();
            REQUIRE(!NativeViolation, NativeViolation ?: @"native contract violation");
            REQUIRE(NSProcessInfo.processInfo.systemUptime - started <= 1.0,
                    @"a case took more than one second");
            ++CasesPassed;
            fprintf(stdout, "PASS %s\n", name.UTF8String);
        } @catch (NSException *exception) {
            ++CasesFailed;
            fprintf(stderr, "FAIL %s: %s\n", name.UTF8String, exception.reason.UTF8String);
        } @finally {
            for (WDGFixtureRun *run in Runs) {
                [run.service cancelBeforeCreate];
                [run.service expireUnresolvedTask:run.taskID];
            }
            // Let queued teardown deliveries drain before this case's models go.
            FixturePump(0.008, nil);
            [Runs removeAllObjects];
        }
    }
}

static void FixtureCartCases(void) {
    FixtureCase(@"cart installs actual observer IMP, original exactly once", ^{
        Method method = class_getInstanceMethod(VDTradeMyCartViewController.class,
                         @selector(fetchDataSucceed:cartListDO:));
        IMP original = method_getImplementation(method);
        WDGCartInstallObservers();
        IMP observed = method_getImplementation(method);
        REQUIRE(observed != original, @"observer did not replace the native IMP");
        WDGCartInstallObservers();
        REQUIRE(method_getImplementation(method) == observed, @"observer was installed twice");
        VDTradeCartListDO *list = FixtureCart(@[FixtureGoods(@"cart-1", @"sku-1", @"1", YES)]);
        [[VDTradeMyCartViewController new] fetchDataSucceed:YES cartListDO:list];
        REQUIRE(OriginalCallbacks == 1 && OriginalLastOK && OriginalLastList == list,
                @"the original BOOL,id callback was not preserved exactly once");
        REQUIRE(WDGCartCandidates().count == 1, @"observed cart list was not captured");
    });
    FixtureCase(@"cart same item different SKUs, raw identity and typed native items", ^{
        VDTradeGoodsItemDO *a = FixtureGoods(@"cart-1", @"sku-1", @"1", YES);
        VDTradeGoodsItemDO *b = FixtureGoods(@"cart-2", @"sku-2", @"2", YES);
        b.priceType = 8;
        b.payType = 32;
        FixtureCapture(@[a, b]);
        NSArray *lines = WDGCartCandidates();
        REQUIRE(lines.count == 2 && WDGCartSelectedLines().count == 2, @"same-item SKUs collapsed");
        NSString *keyA = FixtureLineKey(lines[0]);
        NSString *keyB = FixtureLineKey(lines[1]);
        REQUIRE(![keyA isEqual:keyB], @"distinct cart lines share lineKey");
        REQUIRE([lines[0][@"itemRef"] isEqual:lines[1][@"itemRef"]], @"fixture should have one item identity");
        NSDictionary *rawA = WDGCartRawLine(keyA);
        NSDictionary *rawB = WDGCartRawLine(keyB);
        REQUIRE([rawA[@"skuId"] isEqual:@"sku-1"] && [rawB[@"skuId"] isEqual:@"sku-2"],
                @"raw map keyed by itemRef overwrote a SKU");
        REQUIRE([rawA[@"count"] isEqual:@"1"] && [rawB[@"count"] isEqual:@"2"] &&
                [rawA[@"price"] isEqual:@"12.50"] && [rawB[@"price"] isEqual:@"12.50"],
                @"raw counts/display prices were lost or normalized");
        REQUIRE([rawA[@"priceType"] isEqual:@7] && [rawA[@"payType"] isEqual:@31] &&
                [rawB[@"priceType"] isEqual:@8] && [rawB[@"payType"] isEqual:@32],
                @"raw priceType and payType were mixed");
        REQUIRE(WDGCartCopyRawSelection().count == 2, @"raw selection lost a SKU");
        REQUIRE(!WDGCartRawLine(lines[0][@"itemRef"]), @"raw lookup still accepts itemRef instead of lineKey");
        NSError *error = nil;
        id built = WDGCartBuildRequest(&error);
        REQUIRE([built isKindOfClass:VDTradeConfirmOrderRequestDO.class] && !error, @"builder lost typed request");
        VDTradeConfirmOrderRequestDO *request = built;
        REQUIRE(NativeVMInitializations == 1, @"production builder did not use the available pure native VM");
        NSSet *tokens = [NSSet setWithArray:[LastItemsToken componentsSeparatedByString:@","]];
        REQUIRE([tokens isEqual:[NSSet setWithArray:@[@"item-1_1_sku-1_31", @"item-1_2_sku-2_32"]]],
                @"native cart token lost SKU/count/payType identity");
        REQUIRE(request.items.count == 2, @"request omitted a selected SKU");
        NSMutableDictionary *bySKU = [NSMutableDictionary dictionary];
        for (id object in request.items) {
            REQUIRE([object isKindOfClass:VDTradeConfOrderRequestItemDO.class] &&
                    ![object isKindOfClass:NSDictionary.class], @"request.items must contain native DOs");
            VDTradeConfOrderRequestItemDO *item = object;
            bySKU[item.item_sku_id] = item;
            REQUIRE([item.price_type isKindOfClass:NSString.class], @"price_type must have object/string ABI");
        }
        VDTradeConfOrderRequestItemDO *itemA = bySKU[@"sku-1"];
        VDTradeConfOrderRequestItemDO *itemB = bySKU[@"sku-2"];
        REQUIRE([itemA.quantity isEqual:@"1"] && [itemB.quantity isEqual:@"2"], @"SKU counts overwritten");
        REQUIRE([itemA.price_type isEqual:@"31"] && [itemB.price_type isEqual:@"32"],
                @"native token[3] mapping must use payType.stringValue, retaining raw priceType separately");
    });
    FixtureCase(@"cart explicit line choice and nil returns to App checked rows", ^{
        VDTradeGoodsItemDO *a = FixtureGoods(@"cart-1", @"sku-1", @"1", YES);
        VDTradeGoodsItemDO *b = FixtureGoods(@"cart-2", @"sku-2", @"1", NO);
        FixtureCapture(@[a, b]);
        NSArray *lines = WDGCartCandidates();
        NSString *appKey = FixtureLineKey(lines[0]);
        NSString *manualKey = FixtureLineKey(lines[1]);
        REQUIRE(WDGCartChooseLine(manualKey), @"explicit valid line choice failed");
        REQUIRE(WDGCartSelectedLines().count == 1 &&
                [FixtureLineKey(WDGCartSelectedLines()[0]) isEqual:manualKey], @"manual choice picked the wrong line");
        REQUIRE(a.isSelected && !b.isSelected, @"local choice changed App selection flags");
        REQUIRE(!WDGCartChooseLine(@"not-a-line"), @"unknown lineKey was accepted");
        REQUIRE([FixtureLineKey(WDGCartSelectedLines()[0]) isEqual:manualKey], @"failed choice altered selection");
        REQUIRE(WDGCartChooseLine(nil), @"nil should restore App selection mode");
        REQUIRE(WDGCartSelectedLines().count == 1 &&
                [FixtureLineKey(WDGCartSelectedLines()[0]) isEqual:appKey], @"nil did not use App checked rows");
    });
    FixtureCase(@"cart unchecked rows are candidates, never implicit select-all", ^{
        VDTradeGoodsItemDO *a = FixtureGoods(@"cart-1", @"sku-1", @"1", NO);
        a.canOrder = NO;
        FixtureCapture(@[a, FixtureGoods(@"cart-2", @"sku-2", @"1", NO)]);
        REQUIRE(WDGCartCandidates().count == 2, @"pre-sale unorderable candidate was hidden");
        REQUIRE(WDGCartSelectedLines().count == 0 && WDGCartCopyRawSelection().count == 0,
                @"empty App selection silently became select-all");
        NSError *error = nil;
        REQUIRE(!WDGCartBuildRequest(&error) && error, @"empty selection produced a request");
        REQUIRE(WDGCartChooseLine(FixtureLineKey(WDGCartCandidates()[0])), @"cannot choose pre-sale candidate");
        REQUIRE(WDGCartSelectedLines().count == 1, @"explicit choice did not select just one row");
        REQUIRE(WDGCartChooseLine(nil) && WDGCartSelectedLines().count == 0,
                @"restoring unchecked App rows silently selected all");
    });
    FixtureCase(@"cart successful empty list clears candidates, selection, raw map and key", ^{
        FixtureCapture(@[FixtureGoods(@"cart-1", @"sku-1", @"1", YES)]);
        NSString *oldKey = FixtureLineKey(WDGCartCandidates()[0]);
        REQUIRE(WDGCartSnapshotKey().length, @"nonempty selection lacks a snapshot key");
        VDTradeCartListDO *empty = [VDTradeCartListDO new];
        empty.shops = @[];
        [[VDTradeMyCartViewController new] fetchDataSucceed:YES cartListDO:empty];
        REQUIRE(WDGCartCandidates().count == 0 && WDGCartSelectedLines().count == 0 &&
                WDGCartCopyRawSelection().count == 0 && !WDGCartRawLine(oldKey) &&
                !WDGCartSnapshotKey().length, @"empty cart retained old submit-capable state");
        NSError *error = nil;
        REQUIRE(!WDGCartBuildRequest(&error) && error, @"empty refreshed cart used stale request data");
    });
    FixtureCase(@"cart FALSE callback preserves original and never reads unknown model", ^{
        FixtureCapture(@[FixtureGoods(@"cart-1", @"sku-1", @"1", YES)]);
        NSArray *before = [WDGCartCandidates() copy];
        NSString *key = [WDGCartSnapshotKey() copy];
        WDGFixturePoisonList *poison = [WDGFixturePoisonList new];
        [[VDTradeMyCartViewController new] fetchDataSucceed:NO cartListDO:poison];
        REQUIRE(OriginalCallbacks == 2 && !OriginalLastOK && OriginalLastList == poison,
                @"FALSE original callback arguments changed");
        REQUIRE(UnknownReads == 0, @"FALSE callback queried shops on unknown object");
        REQUIRE([before isEqual:WDGCartCandidates()] && [key isEqual:WDGCartSnapshotKey()],
                @"failed fetch changed the previous decoded snapshot");
    });
    FixtureCase(@"cart rejects wrong object getter ABI at every container level", ^{
        Class listClass = FixtureSubclass(VDTradeCartListDO.class, @"BadShops", @selector(shops),
                                         (IMP)FixtureWrongIntegerGetter, "q@:");
        [[VDTradeMyCartViewController new] fetchDataSucceed:YES cartListDO:[listClass new]];
        Class shopClass = FixtureSubclass(VDTradeCartItemDO.class, @"BadPartitions", @selector(partitions),
                                         (IMP)FixtureWrongIntegerGetter, "q@:");
        VDTradeCartListDO *list = [VDTradeCartListDO new];
        list.shops = @[[shopClass new]];
        [[VDTradeMyCartViewController new] fetchDataSucceed:YES cartListDO:list];
        Class partitionClass = FixtureSubclass(VDTradeCartPartitionDO.class, @"BadItems", @selector(itemList),
                                              (IMP)FixtureWrongIntegerGetter, "q@:");
        VDTradeCartItemDO *shop = [VDTradeCartItemDO new];
        shop.shopId = @"shop-1";
        shop.partitions = @[[partitionClass new]];
        list.shops = @[shop];
        [[VDTradeMyCartViewController new] fetchDataSucceed:YES cartListDO:list];
        REQUIRE(WrongGetterCalls == 0, @"unverified scalar getter was invoked as id");
        REQUIRE(WDGCartCandidates().count == 0, @"wrong ABI yielded fabricated candidates");
    });
    FixtureCase(@"cart rejects wrong identity and bool getter ABI without executing it", ^{
        Class identityClass = FixtureSubclass(VDTradeGoodsItemDO.class, @"BadItemID", @selector(itemId),
                                             (IMP)FixtureWrongIntegerGetter, "q@:");
        FixtureCapture(@[[identityClass new]]);
        REQUIRE(WDGCartCandidates().count == 0 && WrongGetterCalls == 0, @"bad itemId getter executed");
        Class boolClass = FixtureSubclass(VDTradeGoodsItemDO.class, @"BadSelected", @selector(isSelected),
                                         (IMP)FixtureWrongDoubleGetter, "d@:");
        VDTradeGoodsItemDO *bad = FixtureGoods(@"cart-1", @"sku-1", @"1", YES);
        object_setClass(bad, boolClass);
        FixtureCapture(@[bad]);
        REQUIRE(WrongGetterCalls == 0 && WDGCartSelectedLines().count == 0,
                @"wrong-ABI selection getter was called or treated as checked");
    });
    FixtureCase(@"cart wrong priceType ABI is skipped, independent native payType retained", ^{
        Class badClass = FixtureSubclass(VDTradeGoodsItemDO.class, @"BadPriceType", @selector(priceType),
                                        (IMP)FixtureWrongDoubleGetter, "d@:");
        VDTradeGoodsItemDO *goods = FixtureGoods(@"cart-1", @"sku-1", @"1", YES);
        object_setClass(goods, badClass);
        FixtureCapture(@[goods]);
        NSDictionary *raw = WDGCartRawLine(FixtureLineKey(WDGCartCandidates()[0]));
        REQUIRE(!raw[@"priceType"] && [raw[@"payType"] isEqual:@31] && WrongGetterCalls == 0,
                @"wrong priceType getter executed or contaminated payType");
        NSError *error = nil;
        VDTradeConfirmOrderRequestDO *request = WDGCartBuildRequest(&error);
        REQUIRE(request && !error && [request.items[0].price_type isEqual:@"31"],
                @"verified payType token mapping depends on unrelated priceType getter");
    });
    FixtureCase(@"cart wrong payType ABI uses observed native default, never calls it", ^{
        Class badClass = FixtureSubclass(VDTradeGoodsItemDO.class, @"BadPayType", @selector(payType),
                                        (IMP)FixtureWrongDoubleGetter, "d@:");
        VDTradeGoodsItemDO *goods = FixtureGoods(@"cart-1", @"sku-1", @"1", YES);
        object_setClass(goods, badClass);
        FixtureCapture(@[goods]);
        NSDictionary *raw = WDGCartRawLine(FixtureLineKey(WDGCartCandidates()[0]));
        REQUIRE([raw[@"priceType"] isEqual:@7] && !raw[@"payType"] && WrongGetterCalls == 0,
                @"wrong payType getter executed or priceType was substituted");
        NSError *error = nil;
        VDTradeConfirmOrderRequestDO *request = WDGCartBuildRequest(&error);
        REQUIRE(request && !error && [request.items[0].price_type isEqual:@"1"],
                @"missing verified payType did not retain the observed native default");
    });
    FixtureCase(@"cart item without SKU uses empty native token SKU only when hasSku is false", ^{
        VDTradeGoodsItemDO *goods = FixtureGoods(@"cart-1", nil, @"1", YES);
        goods.hasSku = NO;
        FixtureCapture(@[goods]);
        NSError *error = nil;
        VDTradeConfirmOrderRequestDO *request = WDGCartBuildRequest(&error);
        REQUIRE(request && !error && [request.items[0].item_sku_id isEqual:@""],
                @"a verified SKU-less item was rejected or assigned a made-up SKU");
    });
    FixtureCase(@"cart identical item/SKU retain separate cart and shop identity", ^{
        VDTradeGoodsItemDO *a = FixtureGoods(@"cart-1", @"sku-1", @"1", YES);
        VDTradeGoodsItemDO *b = FixtureGoods(@"cart-2", @"sku-1", @"2", YES);
        VDTradeGoodsItemDO *c = FixtureGoods(@"cart-1", @"sku-1", @"3", YES);
        c.shopId = @"shop-2";
        FixtureCapture(@[a, b, c]);
        REQUIRE(WDGCartCandidates().count == 3, @"cart/shop identity collapsed same-SKU rows");
        NSMutableSet *keys = [NSMutableSet set];
        for (NSDictionary *line in WDGCartCandidates()) [keys addObject:FixtureLineKey(line)];
        REQUIRE(keys.count == 3 && WDGCartCopyRawSelection().count == 3,
                @"raw key omitted cartId or shopId");
    });
    for (id sku in @[@"sku-1", NSNull.null]) {
        FixtureCase([NSString stringWithFormat:@"cart unknown hasSku remains unready with %@", sku], ^{
            Class badClass = FixtureSubclass(VDTradeGoodsItemDO.class, @"BadHasSku", @selector(hasSku),
                                            (IMP)FixtureWrongDoubleGetter, "d@:");
            VDTradeGoodsItemDO *goods = FixtureGoods(@"cart-1", [sku isKindOfClass:NSString.class] ? sku : nil, @"1", YES);
            object_setClass(goods, badClass);
            FixtureCapture(@[goods]);
            REQUIRE(WDGCartCandidates().count == 1 && WDGCartSelectedLines().count == 1,
                    @"unknown SKU state should remain visible for diagnosis");
            NSError *error = nil;
            REQUIRE(!WDGCartBuildRequest(&error) && error && WrongGetterCalls == 0,
                    @"unknown hasSku was executed or guessed from skuId");
            REQUIRE(NativeVMInitializations == 0 && ConfirmCalls == 0 && CreateCalls == 0,
                    @"unknown SKU state reached native request generation");
        });
    }
    FixtureCase(@"cart invalid refreshed shops clears old raw/manual selection", ^{
        FixtureCapture(@[FixtureGoods(@"cart-1", @"sku-1", @"1", YES)]);
        NSString *key = FixtureLineKey(WDGCartCandidates()[0]);
        REQUIRE(WDGCartChooseLine(key), @"could not select captured line");
        VDTradeCartListDO *invalid = [VDTradeCartListDO new];
        [FixtureController() fetchDataSucceed:YES cartListDO:invalid];
        REQUIRE(!WDGCartRawLine(key) && !WDGCartSnapshotKey() &&
                WDGCartCandidates().count == 0 && WDGCartSelectedLines().count == 0,
                @"invalid refresh retained stale submit data");
        NSError *error = nil;
        REQUIRE(!WDGCartBuildRequest(&error) && error, @"invalid shops generated a request");
    });
    FixtureCase(@"cart native source/defaults preserved and builder stays pure", ^{
        VDTradeMyCartViewController *controller = FixtureController();
        controller.request.queryParams = @{@"source_id": @"unverified-route-source", @"address_id": @"route-address"};
        [controller fetchDataSucceed:YES cartListDO:FixtureCart(@[FixtureGoods(@"cart-1", @"sku-1", @"01", YES)])];
        NSError *error = nil;
        VDTradeConfirmOrderRequestDO *request = WDGCartBuildRequest(&error);
        REQUIRE(request && !error && [request.source_id isEqual:@"5774937da7853cd3860c022c7fb13f84"],
                @"native cart source constant replaced by unrelated route value");
        REQUIRE([request.items[0].quantity isEqual:@"01"] && request.items[0].use_installment,
                @"native parser quantity/default installment was overwritten");
        REQUIRE(request.address_id.length == 0 && ConfirmCalls == 0 && CreateCalls == 0,
                @"pure builder invented init address or dispatched network service");
    });
    for (NSString *field in @[@"itemId", @"skuId"]) {
        FixtureCase([@"cart builder rejects missing " stringByAppendingString:field], ^{
            VDTradeGoodsItemDO *goods = FixtureGoods(@"cart-1", @"sku-1", @"1", YES);
            [goods setValue:nil forKey:field];
            VDTradeCartListDO *list = FixtureCart(@[goods]);
            [[VDTradeMyCartViewController new] fetchDataSucceed:YES cartListDO:list];
            NSError *error = nil;
            REQUIRE(!WDGCartBuildRequest(&error) && error, @"incomplete identity built a request");
        });
    }
    for (id count in @[NSNull.null, @"", @"0", @"-1", @"1.5", @"2x", @"999999999999999999999999999"]) {
        FixtureCase([NSString stringWithFormat:@"cart builder rejects quantity %@", count], ^{
            NSString *text = [count isKindOfClass:NSString.class] ? count : nil;
            FixtureCapture(@[FixtureGoods(@"cart-1", @"sku-1", text, YES)]);
            NSError *error = nil;
            REQUIRE(!WDGCartBuildRequest(&error) && error, @"missing/non-positive/non-integral quantity accepted");
        });
    }
}

static void FixtureServiceCases(void) {
    // This first service case intentionally does not install an execution check:
    // a Foundation fixture must execute with the production default YES.
    FixtureCase(@"service default YES, sync warmup, nil auto button, no early Create", ^{
        VDTradeConfirmOrderRequestDO *request = FixtureRequest();
        FixtureDefaultScript(request);
        WDGFixtureRun *run = FixturePrepare(request, nil, 0.10);
        FixtureStart(run);
        FixtureNoEarlyCreate(run);
        REQUIRE(ConfirmCalls == 1, @"submitTask did not start exactly one warmup Confirm");
        FixtureRequireState(run, @"apiSucceeded");
        REQUIRE(ConfirmCalls == 1 && CreateCalls == 1, @"available warmup should need one Confirm and one Create");
        REQUIRE([CreateRequests[0][@"payButtonType"] isEqual:@3],
                @"auto pay choice used option.pay_type or initial request value, not button.type");
        REQUIRE(request.payButtonType == 99, @"native payButtonType was not restored after completion");
        REQUIRE(run.terminals.count == 1, @"success emitted duplicate terminal receipts");
        FixtureNoResubmit(run);
    });
    FixtureCase(@"service real cart builder to Confirm model to Create integration", ^{
        FixtureCapture(@[FixtureGoods(@"cart-1", @"sku-1", @"1", YES),
                         FixtureGoods(@"cart-2", @"sku-2", @"2", YES)]);
        NSError *error = nil;
        VDTradeConfirmOrderRequestDO *request = WDGCartBuildRequest(&error);
        REQUIRE(request && !error, @"cart integration builder failed");
        NSUInteger saved = request.payButtonType;
        FixtureDefaultScript(request);
        WDGFixtureRun *run = FixturePrepare(request, @3, 0.08);
        FixtureStart(run);
        FixtureRequireState(run, @"apiSucceeded");
        REQUIRE(CreateCalls == 1 && ModelConversions >= 1, @"typed confirmation conversion was skipped");
        REQUIRE([(NSArray *)CreateRequests[0][@"items"] count] == 2, @"integration path lost a selected SKU");
        REQUIRE(request.payButtonType == saved, @"integration did not restore original payButtonType");
    });
    FixtureCase(@"service blocked warmup re-confirms only at due, maximum two Confirms", ^{
        VDTradeConfirmOrderRequestDO *request = FixtureRequest();
        NSMutableDictionary *blocked = [FixtureConfirmation(request) mutableCopy];
        blocked[@"cannot_submit"] = @YES;
        WDGFixtureStep *first = [WDGFixtureStep success:blocked];
        first.copies = 2;
        FixtureScript(@[first, [WDGFixtureStep success:FixtureConfirmation(request)]]);
        WDGFixtureRun *run = FixturePrepare(request, nil, 0.10);
        FixtureStart(run);
        FixtureNoEarlyCreate(run);
        REQUIRE(ConfirmCalls == 1, @"blocked warmup re-confirmed before due");
        FixtureRequireState(run, @"apiSucceeded");
        REQUIRE(ConfirmCalls == 2 && CreateCalls == 1, @"blocked warmup did not use exactly two Confirms");
        REQUIRE([ConfirmDates[1] compare:run.dueAt] != NSOrderedAscending, @"second Confirm was sent before due");
        NativeReply firstReply = ConfirmCallbacks[0];
        firstReply(YES, blocked, nil); // Old stage duplicate after success.
        FixturePump(0.025, nil);
        REQUIRE(ConfirmCalls == 2 && CreateCalls == 1 && run.terminals.count == 1,
                @"late first-stage duplicate restarted the driver");
    });
    FixtureCase(@"service still blocked at due fails, no third Confirm or Create", ^{
        VDTradeConfirmOrderRequestDO *request = FixtureRequest();
        NSMutableDictionary *blocked = [FixtureConfirmation(request) mutableCopy];
        blocked[@"cannot_submit"] = @YES;
        FixtureScript(@[[WDGFixtureStep success:blocked], [WDGFixtureStep success:blocked]]);
        WDGFixtureRun *run = FixturePrepare(request, nil, 0.08);
        FixtureStart(run);
        FixtureRequireState(run, @"failed");
        FixturePump(0.025, nil);
        REQUIRE(ConfirmCalls == 2 && CreateCalls == 0, @"persistent block caused Create or a third Confirm");
        FixtureNoResubmit(run);
    });
    FixtureCase(@"service delayed and duplicate native replies resolve once", ^{
        VDTradeConfirmOrderRequestDO *request = FixtureRequest();
        WDGFixtureStep *confirm = [WDGFixtureStep success:FixtureConfirmation(request)];
        confirm.delay = 0.018;
        confirm.copies = 2;
        CreateStep.delay = 0.018;
        CreateStep.copies = 2;
        FixtureScript(@[confirm]);
        WDGFixtureRun *run = FixturePrepare(request, @3, 0.10);
        FixtureStart(run);
        FixtureNoEarlyCreate(run);
        FixtureRequireState(run, @"apiSucceeded");
        FixturePump(0.025, nil);
        REQUIRE(ConfirmCalls == 1 && CreateCalls == 1 && run.terminals.count == 1,
                @"duplicate callback resolved twice or sent duplicate Create");
        REQUIRE(request.payButtonType == 99, @"delayed serializer binding was not restored");
    });
    FixtureCase(@"service cancel while warmup callback is delayed", ^{
        VDTradeConfirmOrderRequestDO *request = FixtureRequest();
        WDGFixtureStep *confirm = [WDGFixtureStep success:FixtureConfirmation(request)];
        confirm.delay = 0.045;
        FixtureScript(@[confirm]);
        WDGFixtureRun *run = FixturePrepare(request, nil, 0.10);
        FixtureStart(run);
        REQUIRE([run.service cancelBeforeCreate], @"pre-Create cancellation failed");
        FixtureRequireState(run, @"cancelled");
        FixturePump(0.13, nil);
        REQUIRE(ConfirmCalls == 1 && CreateCalls == 0 && run.terminals.count == 1,
                @"cancelled task's delayed Confirm created an order");
        FixtureNoResubmit(run);
    });
    FixtureCase(@"service cancel after warmup but before due", ^{
        VDTradeConfirmOrderRequestDO *request = FixtureRequest();
        FixtureDefaultScript(request);
        WDGFixtureRun *run = FixturePrepare(request, @3, 0.10);
        FixtureStart(run);
        FixtureNoEarlyCreate(run);
        REQUIRE([run.service cancelBeforeCreate], @"cannot cancel waiting-for-due task");
        FixtureRequireState(run, @"cancelled");
        FixturePump(0.11, nil);
        REQUIRE(CreateCalls == 0, @"cancelled due timer sent Create");
    });
    FixtureCase(@"service execution check turns NO before due", ^{
        __block BOOL foreground = YES;
        [WDGOrderService setExecutionAllowedCheck:^BOOL { return foreground; }];
        @try {
            VDTradeConfirmOrderRequestDO *request = FixtureRequest();
            FixtureDefaultScript(request);
            WDGFixtureRun *run = FixturePrepare(request, nil, 0.10);
            FixtureStart(run);
            FixtureNoEarlyCreate(run);
            foreground = NO;
            NSDictionary *receipt = FixtureFinish(run);
            REQUIRE([@[@"failed", @"cancelled"] containsObject:receipt[@"state"]],
                    @"background task did not fail/cancel before Create");
            REQUIRE(CreateCalls == 0, @"background check was ignored at Create dispatch");
        } @finally {
            [WDGOrderService setExecutionAllowedCheck:^BOOL { return YES; }];
        }
    });
    FixtureCase(@"service execution check NO at submit", ^{
        [WDGOrderService setExecutionAllowedCheck:^BOOL { return NO; }];
        @try {
            VDTradeConfirmOrderRequestDO *request = FixtureRequest();
            FixtureDefaultScript(request);
            WDGFixtureRun *run = FixturePrepare(request, nil, 0.08);
            NSError *error = nil;
            if (FixtureSubmit(run, &error)) {
                NSDictionary *receipt = FixtureFinish(run);
                REQUIRE(![receipt[@"apiSucceeded"] boolValue], @"NO execution check reported success");
            } else {
                REQUIRE(error != nil, @"blocked submit failed without an error");
            }
            REQUIRE(CreateCalls == 0, @"execution-denied task reached Create");
        } @finally {
            [WDGOrderService setExecutionAllowedCheck:^BOOL { return YES; }];
        }
    });
    FixtureCase(@"service hanging Confirm expires; late replies never Create", ^{
        VDTradeConfirmOrderRequestDO *request = FixtureRequest();
        WDGFixtureStep *confirm = [WDGFixtureStep success:FixtureConfirmation(request)];
        confirm.hanging = YES;
        FixtureScript(@[confirm]);
        WDGFixtureRun *run = FixturePrepare(request, nil, 0.10);
        FixtureStart(run);
        REQUIRE(FixturePump(0.08, ^BOOL { return ConfirmCallbacks.count == 1; }), @"warmup Confirm did not start");
        [run.service expireUnresolvedTask:run.taskID];
        NSDictionary *timeout = FixtureFinish(run);
        REQUIRE([@[@"failed", @"unknown"] containsObject:timeout[@"state"]], @"Confirm timeout not terminal");
        NativeReply reply = ConfirmCallbacks[0];
        reply(YES, FixtureConfirmation(request), nil);
        reply(YES, FixtureConfirmation(request), nil);
        FixturePump(0.13, nil);
        REQUIRE(CreateCalls == 0 && run.terminals.count == 1, @"expired Confirm late reply resumed submission");
        FixtureNoResubmit(run);
    });
    FixtureCase(@"service Create timeout unknown, one late final response, no retry", ^{
        VDTradeConfirmOrderRequestDO *request = FixtureRequest();
        FixtureDefaultScript(request);
        CreateStep.hanging = YES;
        WDGFixtureRun *run = FixturePrepare(request, @3, 0.08);
        FixtureStart(run);
        REQUIRE(FixturePump(0.30, ^BOOL { return CreateCalls == 1; }), @"Create did not begin at due");
        REQUIRE(![run.service cancelBeforeCreate], @"in-flight Create was misreported as cancellable");
        [run.service expireUnresolvedTask:@"another-task"];
        FixturePump(0.012, nil);
        REQUIRE(run.terminals.count == 0, @"wrong task ID expired the task");
        [run.service expireUnresolvedTask:run.taskID];
        FixtureRequireState(run, @"unknown");
        REQUIRE(run.terminals.count == 1 && CreateCalls == 1, @"Create timeout retried or duplicated terminal");
        NativeReply reply = CreateCallbacks[0];
        reply(YES, @{@"order_id": @"fixture-late-order"}, nil);
        reply(YES, @{@"order_id": @"fixture-late-order"}, nil);
        REQUIRE(FixturePump(0.25, ^BOOL { return run.terminals.count == 2; }),
                @"timed-out Create lost the one permitted late final response");
        FixtureValidateReceipts(run);
        REQUIRE([run.terminals[1][@"state"] isEqual:@"apiSucceeded"], @"late final response not recorded");
        reply(NO, nil, [NSError errorWithDomain:@"Fixture" code:8 userInfo:nil]);
        FixturePump(0.025, nil);
        REQUIRE(run.terminals.count == 2 && CreateCalls == 1, @"duplicate late responses re-resolved or retried");
        REQUIRE(request.payButtonType == 99, @"Create timeout/late result leaked temporary payment type");
        FixtureNoResubmit(run);
    });
    FixtureCase(@"service FALSE Confirm with error is terminal failed", ^{
        VDTradeConfirmOrderRequestDO *request = FixtureRequest();
        WDGFixtureStep *confirm = [WDGFixtureStep success:[WDGFixturePoisonList new]];
        confirm.ok = NO;
        confirm.error = [NSError errorWithDomain:@"Fixture" code:1 userInfo:nil];
        FixtureScript(@[confirm]);
        WDGFixtureRun *run = FixturePrepare(request, nil, 0.08);
        FixtureStart(run);
        FixtureRequireState(run, @"failed");
        REQUIRE(CreateCalls == 0 && ModelConversions == 0 && UnknownReads == 0,
                @"failed Confirm consumed unknown success payload");
    });
    FixtureCase(@"service malformed Confirm response never reaches Create", ^{
        VDTradeConfirmOrderRequestDO *request = FixtureRequest();
        FixtureScript(@[[WDGFixtureStep success:@"not-a-confirm-dictionary"]]);
        WDGFixtureRun *run = FixturePrepare(request, nil, 0.08);
        FixtureStart(run);
        NSDictionary *receipt = FixtureFinish(run);
        REQUIRE([@[@"failed", @"unknown"] containsObject:receipt[@"state"]] && CreateCalls == 0,
                @"unknown Confirm response generated Create");
    });
    FixtureCase(@"service Create failed BOOL,id,id callback resolves once", ^{
        VDTradeConfirmOrderRequestDO *request = FixtureRequest();
        FixtureDefaultScript(request);
        CreateStep.ok = NO;
        CreateStep.response = nil;
        CreateStep.error = [NSError errorWithDomain:@"Fixture" code:6 userInfo:nil];
        CreateStep.copies = 2;
        WDGFixtureRun *run = FixturePrepare(request, @3, 0.08);
        FixtureStart(run);
        FixtureRequireState(run, @"failed");
        FixturePump(0.025, nil);
        REQUIRE(CreateCalls == 1 && run.terminals.count == 1, @"failed native response retried or resolved twice");
    });
    for (NSString *mutation in @[@"over-cap", @"need-address", @"wrong-item", @"wrong-sku",
                                 @"wrong-quantity", @"extra-tuple", @"missing-shop-list",
                                 @"no-pay-options", @"unavailable-pay-option", @"no-selected-pay-option"]) {
        FixtureCase([@"service rejects confirmation " stringByAppendingString:mutation], ^{
            VDTradeConfirmOrderRequestDO *request = FixtureRequest();
            NSMutableDictionary *json = [FixtureConfirmation(request) mutableCopy];
            if ([mutation isEqual:@"over-cap"]) json[@"total_pay_price"] = @"100.01";
            else if ([mutation isEqual:@"need-address"]) json[@"need_add_address"] = @YES;
            else if ([mutation isEqual:@"missing-shop-list"]) json[@"shop_list"] = @[];
            else if ([mutation isEqual:@"no-pay-options"]) json[@"pay_options"] = @[];
            else if ([mutation isEqual:@"unavailable-pay-option"] || [mutation isEqual:@"no-selected-pay-option"]) {
                NSMutableDictionary *option = [json[@"pay_options"][0] mutableCopy];
                option[([mutation isEqual:@"unavailable-pay-option"] ? @"available" : @"selected")] = @NO;
                json[@"pay_options"] = @[option];
            } else {
                NSMutableDictionary *item = [json[@"shop_list"][0][@"item_list"][0] mutableCopy];
                if ([mutation isEqual:@"wrong-item"]) item[@"item_id"] = @"other-item";
                if ([mutation isEqual:@"wrong-sku"]) item[@"item_sku_id"] = @"other-sku";
                if ([mutation isEqual:@"wrong-quantity"]) item[@"quantity"] = @"2";
                NSArray *items = [mutation isEqual:@"extra-tuple"] ? @[item, item] : @[item];
                json[@"shop_list"] = @[@{@"item_list": items}];
            }
            FixtureScript(@[[WDGFixtureStep success:json]]);
            WDGFixtureRun *run = FixturePrepare(request, nil, 0.08);
            FixtureStart(run);
            FixtureRequireState(run, @"failed");
            REQUIRE(CreateCalls == 0, @"invalid confirmation created an order");
        });
    }
    for (NSString *scenario in @[@"display-only", @"required-unchecked", @"required-checked", @"checkbox-hidden-still-required", @"unknown-filter-abi"]) {
        FixtureCase([@"service native agreement gate " stringByAppendingString:scenario], ^{
            VDTradeConfirmOrderRequestDO *request = FixtureRequest();
            NSMutableDictionary *json = [FixtureConfirmation(request) mutableCopy];
            json[@"agreement_info_list"] = @[@{@"agreement_name": @"Fixture terms"}];
            json[@"fixture_real_agreements"] = [scenario isEqual:@"display-only"] ? @[] : json[@"agreement_info_list"];
            json[@"fixture_checkbox"] = @(![scenario isEqual:@"checkbox-hidden-still-required"]);
            json[@"isAgreementChecked"] = @([scenario isEqual:@"required-checked"]);
            if ([scenario isEqual:@"unknown-filter-abi"]) {
                ConfirmationSubclass = FixtureSubclass(VDTradeConfirmOrderDO.class, @"BadAgreementFilter",
                    @selector(getRealAgreementInfos), (IMP)FixtureWrongDoubleGetter, "d@:");
            }
            FixtureScript(@[[WDGFixtureStep success:json]]);
            WDGFixtureRun *run = FixturePrepare(request, nil, 0.08);
            FixtureStart(run);
            BOOL allowed = [scenario isEqual:@"display-only"] || [scenario isEqual:@"required-checked"];
            FixtureRequireState(run, allowed ? @"apiSucceeded" : @"failed");
            REQUIRE(CreateCalls == (allowed ? 1 : 0), @"native filtered agreement gate mismatch");
            REQUIRE(WrongGetterCalls == 0, @"unverified agreement filter ABI was called");
        });
    }
    FixtureCase(@"service explicit payment type unavailable in buttons is rejected", ^{
        VDTradeConfirmOrderRequestDO *request = FixtureRequest();
        FixtureDefaultScript(request);
        WDGFixtureRun *run = FixturePrepare(request, @88, 0.08);
        FixtureStart(run);
        FixtureRequireState(run, @"failed");
        REQUIRE(CreateCalls == 0, @"unavailable explicit button type reached Create");
    });
    FixtureCase(@"service exact decimal cap accepted", ^{
        VDTradeConfirmOrderRequestDO *request = FixtureRequest();
        NSMutableDictionary *json = [FixtureConfirmation(request) mutableCopy];
        json[@"total_pay_price"] = @"100.00";
        FixtureScript(@[[WDGFixtureStep success:json]]);
        WDGFixtureRun *run = FixturePrepare(request, @3, 0.08);
        FixtureStart(run);
        FixtureRequireState(run, @"apiSucceeded");
        REQUIRE(CreateCalls == 1, @"total equal to cap was incorrectly blocked");
    });
    FixtureCase(@"service request getter and setter ABI rejected without invoking them", ^{
        for (NSNumber *setter in @[@NO, @YES]) {
            VDTradeConfirmOrderRequestDO *request = FixtureRequest();
            Class bad = setter.boolValue
                ? FixtureSubclass(VDTradeConfirmOrderRequestDO.class, @"BadPaySetter", @selector(setPayButtonType:),
                                  (IMP)FixtureWrongIntegerSetter, "v@:q")
                : FixtureSubclass(VDTradeConfirmOrderRequestDO.class, @"BadPayGetter", @selector(payButtonType),
                                  (IMP)FixtureWrongDoubleGetter, "d@:");
            object_setClass(request, bad);
            NSError *error = nil;
            id service = [WDGOrderService preparePreheatRequest:request sampleKey:@"fixture"
                          payType:nil error:&error];
            REQUIRE(!service && error, @"wrong NSUInteger payment ABI was accepted");
        }
        REQUIRE(WrongGetterCalls == 0 && ConfirmCalls == 0 && CreateCalls == 0,
                @"unverified request method was executed");
    });
    FixtureCase(@"service confirmation flag ABI rejected without invoking it", ^{
        ConfirmationSubclass = FixtureSubclass(VDTradeConfirmOrderDO.class, @"BadCannotSubmit",
                               @selector(cannot_submit), (IMP)FixtureWrongDoubleGetter, "d@:");
        VDTradeConfirmOrderRequestDO *request = FixtureRequest();
        FixtureDefaultScript(request);
        WDGFixtureRun *run = FixturePrepare(request, nil, 0.08);
        FixtureStart(run);
        NSDictionary *receipt = FixtureFinish(run);
        REQUIRE([@[@"failed", @"unknown"] containsObject:receipt[@"state"]], @"unknown flag ABI was not terminal");
        REQUIRE(WrongGetterCalls == 0 && CreateCalls == 0, @"wrong ABI flag was invoked or permitted Create");
    });
    FixtureCase(@"service native selectors with unknown ABI fail readiness", ^{
        NSString *name = [@"WDGFixtureBadNative_" stringByAppendingString:NSUUID.UUID.UUIDString];
        Class bad = objc_allocateClassPair(NSObject.class, name.UTF8String, 0);
        REQUIRE(bad != Nil, @"bad native class allocation failed");
        Class meta = object_getClass(bad);
        REQUIRE(class_addMethod(meta, @selector(confirmOrderWithRequestDO:result:),
                (IMP)FixtureWrongConfirm, "q@:@@"), @"bad confirm method installation failed");
        REQUIRE(class_addMethod(meta, @selector(createOrderRequestDO:confirmOrderDO:result:),
                (IMP)FixtureWrongCreate, "q@:@@@"), @"bad create method installation failed");
        objc_registerClassPair(bad);
        Class native = NSClassFromString(@"VDTradeConfOrderService");
        Class savedMeta = object_getClass(native);
        object_setClass((id)native, meta);
        @try {
            NSString *reason = nil;
            REQUIRE(![WDGOrderService runtimeReady:&reason] && reason.length, @"unknown Create ABI passed readiness");
            reason = nil;
            REQUIRE(![WDGOrderService preheatReady:&reason] && reason.length, @"unknown Confirm ABI passed readiness");
            NSError *error = nil;
            REQUIRE(![WDGOrderService preparePreheatRequest:FixtureRequest() sampleKey:@"fixture"
                      payType:nil error:&error] && error, @"unknown native ABI prepared a task");
            REQUIRE(WrongGetterCalls == 0 && ConfirmCalls == 0 && CreateCalls == 0,
                    @"unknown ABI native methods were called");
        } @finally {
            object_setClass((id)native, savedMeta);
        }
    });
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        REQUIRE(NSThread.isMainThread, @"fixture main must run on the Foundation main thread");
        FixtureCartCases();
        FixtureServiceCases();
        fprintf(stdout, "cart_preheat_mock: %lu passed, %lu failed\n",
                (unsigned long)CasesPassed, (unsigned long)CasesFailed);
        return CasesFailed ? 1 : 0;
    }
}
