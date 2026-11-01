#import "WDGCore.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <string.h>
#import <stdlib.h>

// This adapter owns no transport or persistence. All mutable state is main-queue
// confined; hooks observe the application's original method before sampling.
static const NSTimeInterval WDGMaximumSampleAge = 10.0 * 60.0;
static const NSUInteger WDGMaximumItems = 200;
static const NSUInteger WDGMaximumShops = 40;

@interface WDGObserverCandidate : NSObject
@property (nonatomic, weak) id viewModel;
@property (nonatomic, weak) id pendingRequest;
@property (nonatomic, weak) id pendingConfirmation;
@property (nonatomic, weak) id publishedRequest;
@property (nonatomic, weak) id publishedConfirmation;
@property (nonatomic, weak) id boundPage;
@property (nonatomic, copy) NSString *pageKind;
@property (nonatomic, copy) NSString *sampleKey;
@property (nonatomic, copy) NSString *fingerprint;
@property (nonatomic, copy) NSDictionary *snapshot;
@property (nonatomic, copy) NSString *readinessReason;
@property (nonatomic) NSTimeInterval capturedAt;
@property (nonatomic) NSTimeInterval capturedUptime;
@end
@implementation WDGObserverCandidate
@end

@interface WDGObserverBuild : NSObject
@property (nonatomic, copy) NSDictionary *payload;
@property (nonatomic, copy) NSString *fingerprint;
@property (nonatomic, copy) NSString *readinessReason;
@property (nonatomic, copy) NSSet<NSNumber *> *allowedPayTypes;
@property (nonatomic, weak) id requestModel;
@property (nonatomic, weak) id confirmationModel;
@end
@implementation WDGObserverBuild
@end

static NSMapTable<id, WDGObserverCandidate *> *WDGCandidates;
static NSMutableArray<NSDictionary *> *WDGHookResults;
static NSData *WDGSessionSalt;
static NSString *WDGSessionIdentifier;
static __weak UIViewController *WDGOrdinaryController;
static __weak UIView *WDGQuickView;
static __weak UIViewController *WDGQuickHostController;
static __weak WDGObserverCandidate *WDGPublishedCandidate;
static NSString *WDGLastConsumedTaskID;
static NSString *WDGLastObservation;
static NSUInteger WDGObservationCount;
static NSUInteger WDGDispatchCount;
static BOOL WDGInstalled;

static void WDGOnMainSync(dispatch_block_t block) {
    if ([NSThread isMainThread]) block();
    else dispatch_sync(dispatch_get_main_queue(), block);
}

static void WDGEnsureState(void) {
    if (WDGCandidates) return;
    WDGCandidates = [[NSMapTable alloc]
        initWithKeyOptions:(NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality)
        valueOptions:NSPointerFunctionsStrongMemory capacity:8];
    WDGHookResults = [NSMutableArray array];
    WDGSessionIdentifier = [NSUUID UUID].UUIDString;
    WDGSessionSalt = [[NSUUID UUID].UUIDString dataUsingEncoding:NSUTF8StringEncoding];
    WDGLastObservation = @"none";
}

static const char *WDGUnqualifiedType(const char *type) {
    if (!type) return "";
    while (*type && strchr("rnNoORVA", *type)) ++type;
    return type;
}

static BOOL WDGExactType(const char *encoded, char expected) {
    const char *type = WDGUnqualifiedType(encoded);
    return type[0] == expected && type[1] == '\0';
}

static BOOL WDGObjectType(const char *encoded) {
    const char *type = WDGUnqualifiedType(encoded);
    // Blocks (@?) and Class (#) have different contracts and are not read here.
    return type[0] == '@' && (type[1] == '\0' || type[1] == '"');
}

static Method WDGInstanceMethod(id receiver, SEL selector, unsigned int count) {
    if (!receiver || object_isClass(receiver)) return NULL;
    Method method = class_getInstanceMethod(object_getClass(receiver), selector);
    if (!method || method_getNumberOfArguments(method) != count) return NULL;
    return method;
}

static BOOL WDGMethodReturns(Method method, char type) {
    if (!method) return NO;
    char result[256] = {0};
    method_getReturnType(method, result, sizeof(result));
    return WDGExactType(result, type);
}

static BOOL WDGMethodArgument(Method method, unsigned int index, char type) {
    if (!method || index >= method_getNumberOfArguments(method)) return NO;
    char argument[256] = {0};
    method_getArgumentType(method, index, argument, sizeof(argument));
    return type == '@' ? WDGObjectType(argument) : WDGExactType(argument, type);
}

static BOOL WDGIsModel(id value, NSString *className) {
    Class cls = NSClassFromString(className);
    if (!value || !cls || object_isClass(value)) return NO;
    @try { return [value isKindOfClass:cls]; }
    @catch (__unused NSException *exception) { return NO; }
}

static id WDGReadObject(id receiver, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    Method method = WDGInstanceMethod(receiver, selector, 2);
    if (!method) return nil;
    char result[256] = {0};
    method_getReturnType(method, result, sizeof(result));
    if (!WDGObjectType(result)) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(receiver, selector); }
    @catch (__unused NSException *exception) { return nil; }
}

static NSString *WDGReadString(id receiver, NSString *name) {
    id value = WDGReadObject(receiver, name);
    if (![value isKindOfClass:[NSString class]] || [value length] > 4096) return nil;
    return [value copy];
}

static NSArray *WDGReadArray(id receiver, NSString *name, NSUInteger maximum) {
    id value = WDGReadObject(receiver, name);
    if (![value isKindOfClass:[NSArray class]] || [value count] > maximum) return nil;
    return [value copy];
}

static NSNumber *WDGReadBool(id receiver, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    Method method = WDGInstanceMethod(receiver, selector, 2);
    if (!WDGMethodReturns(method, 'B')) return nil;
    @try { return @(((BOOL (*)(id, SEL))objc_msgSend)(receiver, selector)); }
    @catch (__unused NSException *exception) { return nil; }
}

static NSNumber *WDGReadUnsigned(id receiver, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    Method method = WDGInstanceMethod(receiver, selector, 2);
    if (sizeof(NSUInteger) != 8 || !WDGMethodReturns(method, 'Q')) return nil;
    @try { return @(((NSUInteger (*)(id, SEL))objc_msgSend)(receiver, selector)); }
    @catch (__unused NSException *exception) { return nil; }
}

static NSString *WDGDisplayText(NSString *value) {
    if (!value.length) return nil;
    NSString *clean = [[value componentsSeparatedByCharactersInSet:
                       [NSCharacterSet controlCharacterSet]] componentsJoinedByString:@" "];
    clean = [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (clean.length > 160) {
        NSRange range = [clean rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, 160)];
        clean = [clean substringWithRange:range];
    }
    return clean.length ? clean : nil;
}

static NSString *WDGQuantity(NSString *value) {
    if (!value) return nil;
    NSString *text = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length || text.length > 20) return nil;
    BOOL nonzero = NO;
    for (NSUInteger i = 0; i < text.length; ++i) {
        unichar c = [text characterAtIndex:i];
        if (c < '0' || c > '9') return nil;
        if (c != '0') nonzero = YES;
    }
    if (!nonzero) return nil;
    NSUInteger start = 0;
    while (start + 1 < text.length && [text characterAtIndex:start] == '0') ++start;
    return [text substringFromIndex:start];
}

static NSString *WDGHashData(NSData *data) {
    if (!data) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CCHmac(kCCHmacAlgSHA256, WDGSessionSalt.bytes, WDGSessionSalt.length,
           data.bytes, data.length, digest);
    static const char hex[] = "0123456789abcdef";
    char output[CC_SHA256_DIGEST_LENGTH * 2 + 1] = {0};
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; ++i) {
        output[i * 2] = hex[digest[i] >> 4];
        output[i * 2 + 1] = hex[digest[i] & 15];
    }
    return [[NSString alloc] initWithBytes:output length:sizeof(output) - 1 encoding:NSASCIIStringEncoding];
}

static NSString *WDGHashJSON(id json) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingSortedKeys error:&error];
    return data && !error ? WDGHashData(data) : nil;
}

static NSDictionary *WDGRow(id model, BOOL confirmation, BOOL *complete) {
    NSString *expected = confirmation ? @"VDTradeConfirmOrderShopItemDO" : @"VDTradeConfOrderRequestItemDO";
    if (!WDGIsModel(model, expected)) { *complete = NO; return nil; }
    NSString *item = WDGReadString(model, @"item_id");
    NSString *sku = WDGReadString(model, @"item_sku_id");
    NSString *quantity = WDGQuantity(WDGReadString(model, @"quantity"));
    // An explicitly empty SKU string remains distinct from an absent getter/value.
    if (!item.length || item.length > 256 || !sku || sku.length > 256 || !quantity) {
        *complete = NO;
        return nil;
    }
    NSString *itemRef = WDGHashJSON(@[@"item", item]);
    NSString *skuRef = WDGHashJSON(@[@"sku", item, sku]);
    if (!itemRef || !skuRef) { *complete = NO; return nil; }
    NSMutableDictionary *row = [@{@"itemRef": itemRef, @"skuRef": skuRef,
                                  @"quantity": quantity} mutableCopy];
    if (confirmation) {
        NSString *title = WDGDisplayText(WDGReadString(model, @"item_name"));
        NSString *skuTitle = WDGDisplayText(WDGReadString(model, @"item_sku_title"));
        NSString *price = WDGDisplayText(WDGReadString(model, @"price"));
        NSNumber *valid = WDGReadBool(model, @"is_valid");
        NSNumber *selected = WDGReadBool(model, @"is_select");
        if (title) row[@"title"] = title;
        if (skuTitle) row[@"skuTitle"] = skuTitle;
        if (price) row[@"price"] = price;
        if (valid) row[@"valid"] = valid;
        if (selected) row[@"selected"] = selected;
    }
    return [row copy];
}

static NSString *WDGSelectionKey(NSDictionary *row) {
    return WDGHashJSON(@[row[@"itemRef"], row[@"skuRef"], row[@"quantity"]]);
}

static NSArray<NSString *> *WDGSelectionKeys(NSArray<NSDictionary *> *rows) {
    NSMutableArray *keys = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSNumber *selected = row[@"selected"];
        if (selected && !selected.boolValue) continue;
        NSString *key = WDGSelectionKey(row);
        if (key) [keys addObject:key];
    }
    return keys;
}

static NSArray<NSDictionary *> *WDGRequestRows(id request, BOOL *complete) {
    if (!WDGIsModel(request, @"VDTradeConfirmOrderRequestDO")) {
        *complete = NO; return @[];
    }
    NSArray *items = WDGReadArray(request, @"items", WDGMaximumItems);
    if (!items.count) { *complete = NO; return @[]; }
    NSMutableArray *rows = [NSMutableArray array];
    for (id item in items) {
        NSDictionary *row = WDGRow(item, NO, complete);
        if (row) [rows addObject:row];
    }
    return [rows copy];
}

static NSArray<NSDictionary *> *WDGConfirmationRows(id confirmation, BOOL *complete) {
    NSArray *shops = WDGReadArray(confirmation, @"shop_list", WDGMaximumShops);
    if (!shops.count) { *complete = NO; return @[]; }
    NSMutableArray *rows = [NSMutableArray array];
    for (id shop in shops) {
        if (!WDGIsModel(shop, @"VDTradeConfirmOrderShopDO")) { *complete = NO; continue; }
        NSArray *items = WDGReadArray(shop, @"item_list", WDGMaximumItems);
        if (!items) { *complete = NO; continue; }
        for (id item in items) {
            if (rows.count >= WDGMaximumItems) { *complete = NO; return [rows copy]; }
            NSDictionary *row = WDGRow(item, YES, complete);
            if (row) [rows addObject:row];
        }
    }
    if (!rows.count) *complete = NO;
    return [rows copy];
}

static NSArray<NSDictionary *> *WDGPayOptions(id confirmation, BOOL *complete, NSString **reason) {
    NSArray *options = WDGReadArray(confirmation, @"pay_options", 32);
    if (!options.count) { *complete = NO; return @[]; }
    NSMutableArray *result = [NSMutableArray array];
    NSMutableDictionary<NSNumber *, NSString *> *seen = [NSMutableDictionary dictionary];
    for (id option in options) {
        if (!WDGIsModel(option, @"VDTradeConfirmOrderPayOptionDO")) { *complete = NO; continue; }
        NSNumber *available = WDGReadBool(option, @"available");
        NSNumber *selected = WDGReadBool(option, @"selected");
        if (!available || !selected) {
            *complete = NO;
            if (reason && !*reason) *reason = !available ?
                @"付款选项 available getter 缺失、异常或非 BOOL(B) ABI" :
                @"付款选项 selected getter 缺失、异常或非 BOOL(B) ABI";
            continue;
        }
        if (!available.boolValue || !selected.boolValue) continue;
        NSArray *buttons = WDGReadArray(option, @"buttons", 16);
        if (!buttons.count) { *complete = NO; continue; }
        for (id button in buttons) {
            if (!WDGIsModel(button, @"VDTradeConfirmOrderPayButtonDO")) { *complete = NO; continue; }
            NSNumber *type = WDGReadUnsigned(button, @"type");
            NSString *title = WDGDisplayText(WDGReadString(button, @"name"));
            if (!type || !title) { *complete = NO; continue; }
            if (seen[type]) {
                if (![seen[type] isEqualToString:title]) *complete = NO;
                continue;
            }
            seen[type] = title;
            [result addObject:@{@"type": type, @"title": title}];
        }
    }
    if (!result.count) *complete = NO;
    return [result copy];
}

static BOOL WDGQuickSelectionMatches(UIView *page, NSArray<NSString *> *requestKeys) {
    id info = WDGReadObject(page, @"infoDO");
    if (!WDGIsModel(info, @"VDTradeItemInfoDO")) return NO;
    id skuInfo = WDGReadObject(info, @"selectedSkuInfo");
    if (!WDGIsModel(skuInfo, @"VDTradeItemSkuInfo")) return NO;
    NSString *item = WDGReadString(info, @"itemId");
    NSString *sku = WDGReadString(skuInfo, @"id");
    NSString *quantity = WDGQuantity(WDGReadString(info, @"count"));
    if (!item.length || item.length > 256 || !sku || sku.length > 256 || !quantity) return NO;
    NSString *itemRef = WDGHashJSON(@[@"item", item]);
    NSString *skuRef = WDGHashJSON(@[@"sku", item, sku]);
    if (!itemRef || !skuRef) return NO;
    NSString *key = WDGSelectionKey(@{@"itemRef": itemRef, @"skuRef": skuRef, @"quantity": quantity});
    return requestKeys.count == 1 && [requestKeys.firstObject isEqualToString:key];
}

static WDGObserverBuild *WDGBuild(id viewModel, id page, NSString *kind) {
    WDGObserverBuild *build = [WDGObserverBuild new];
    build.allowedPayTypes = [NSSet set];
    id request = WDGReadObject(viewModel, @"requestDO");
    id confirmation = WDGReadObject(viewModel, @"confirmOrderDO");
    build.requestModel = request;
    build.confirmationModel = confirmation;
    BOOL requestComplete = YES, confirmationComplete = YES;
    NSArray *requestRows = WDGRequestRows(request, &requestComplete);
    NSArray *confirmationRows = @[];
    BOOL knownConfirmation = WDGIsModel(confirmation, @"VDTradeConfirmOrderDO");
    if (knownConfirmation) confirmationRows = WDGConfirmationRows(confirmation, &confirmationComplete);
    NSArray *requestKeys = WDGSelectionKeys(requestRows);
    NSArray *confirmationKeys = WDGSelectionKeys(confirmationRows);
    BOOL correlated = requestComplete && confirmationComplete && knownConfirmation && requestKeys.count &&
        [[requestKeys sortedArrayUsingSelector:@selector(compare:)]
         isEqualToArray:[confirmationKeys sortedArrayUsingSelector:@selector(compare:)]];
    NSMutableDictionary *payload = [@{@"pageKind": kind, @"stage": correlated ? @"confirmed" : @"request",
                                      @"items": correlated ? confirmationRows : requestRows,
                                      @"payOptions": @[]} mutableCopy];
    NSString *reason = @"";
    if (!requestComplete) reason = @"请求商品模型或字段尚未完整";
    else if (!knownConfirmation) reason = @"等待同一 ViewModel 的确认模型";
    else if (!correlated) reason = @"同一 ViewModel 的请求与确认商品尚未匹配";
    if (correlated) {
        NSNumber *blocked = WDGReadBool(confirmation, @"cannot_submit");
        NSString *total = WDGDisplayText(WDGReadString(confirmation, @"total_pay_price"));
        BOOL optionsComplete = YES;
        NSString *optionsReason = nil;
        NSArray *options = WDGPayOptions(confirmation, &optionsComplete, &optionsReason);
        payload[@"payOptions"] = options;
        if (blocked) payload[@"cannotSubmit"] = blocked;
        if (total) payload[@"totalPrice"] = total;
        NSMutableSet *types = [NSMutableSet set];
        for (NSDictionary *option in options) [types addObject:option[@"type"]];
        build.allowedPayTypes = [types copy];
        if (!blocked) reason = @"提交状态 getter 未通过 BOOL ABI 校验";
        else if (blocked.boolValue) reason = @"页面当前禁止提交";
        else if (!total.length) reason = @"确认总价尚未完整";
        else if (!optionsComplete) reason = optionsReason ?: @"当前付款按钮模型或 ABI 尚未完整";
        for (NSDictionary *row in confirmationRows) {
            NSNumber *valid = row[@"valid"], *selected = row[@"selected"];
            if ((!selected || selected.boolValue) && valid && !valid.boolValue) {
                reason = @"所选商品存在失效状态";
                break;
            }
        }
        if ([kind isEqualToString:@"quick"] && !WDGQuickSelectionMatches(page, requestKeys))
            reason = @"快捷页当前 SKU 与 ViewModel 请求尚未匹配";
    }
    build.payload = [payload copy];
    build.fingerprint = WDGHashJSON(payload);
    build.readinessReason = build.fingerprint ? reason : @"摘要编码失败";
    return build;
}

static BOOL WDGViewVisible(UIView *view) {
    UIWindow *window = view.window;
    if (!view || !window || window.hidden || window.alpha <= 0.01) return NO;
    if (window.windowScene && window.windowScene.activationState != UISceneActivationStateForegroundActive) return NO;
    UIView *cursor = view;
    NSUInteger depth = 0;
    while (cursor && depth++ < 64) {
        if (cursor.hidden || cursor.alpha <= 0.01) return NO;
        cursor = cursor.superview;
    }
    if (cursor) return NO;
    CGRect rect = [view convertRect:view.bounds toView:window];
    return !CGRectIsEmpty(CGRectIntersection(rect, window.bounds));
}

static UIViewController *WDGTopController(UIWindow *window) {
    UIViewController *controller = window.rootViewController;
    for (NSUInteger depth = 0; controller && depth < 32; ++depth) {
        UIViewController *next = nil;
        if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed)
            next = controller.presentedViewController;
        else if ([controller isKindOfClass:[UINavigationController class]])
            next = ((UINavigationController *)controller).visibleViewController;
        else if ([controller isKindOfClass:[UITabBarController class]])
            next = ((UITabBarController *)controller).selectedViewController;
        else if ([controller isKindOfClass:[UISplitViewController class]])
            next = ((UISplitViewController *)controller).viewControllers.lastObject;
        if (!next || next == controller) return controller;
        controller = next;
    }
    return nil;
}

static BOOL WDGWindowAllowsTarget(UIWindow *target, BOOL executing) {
    if (!target || target.hidden || target.alpha <= 0.01) return NO;
    NSArray<UIWindow *> *windows = target.windowScene ? target.windowScene.windows : @[target];
    UIWindow *key = nil;
    Class helperClass = NSClassFromString(@"WDGPassWindow");
    for (UIWindow *window in windows) {
        if (executing && helperClass && object_getClass(window) == helperClass &&
            window.windowScene == target.windowScene && !window.hidden && window.alpha > 0.01) {
            UIViewController *modal = window.rootViewController.presentedViewController;
            if (modal && !modal.isBeingDismissed) return NO;
        }
        if (!window.isKeyWindow) continue;
        if (key && key != window) return NO;
        key = window;
    }
    if (key == target) return YES;
    if (!key || !helperClass || object_getClass(key) != helperClass ||
        key.windowScene != target.windowScene || key.hidden || key.alpha <= 0.01) return NO;
    // Readiness is also checked inside the panel's own confirmation alert.
    // That trusted helper window may own key focus; it never authorizes an
    // unrelated app window, nor an outstanding helper modal at dispatch time.
    return YES;
}

static BOOL WDGPageVisible(id page, NSString *kind) {
    if ([kind isEqualToString:@"confirm"]) {
        if (!WDGIsModel(page, @"VDTradeConfOrderViewController")) return NO;
        UIViewController *controller = page;
        UIView *view = controller.viewIfLoaded;
        return view && WDGViewVisible(view) && WDGWindowAllowsTarget(view.window, NO) && !controller.isBeingDismissed &&
            !controller.isMovingFromParentViewController && WDGTopController(view.window) == controller;
    }
    if (![kind isEqualToString:@"quick"] || !WDGIsModel(page, @"VDTradeQuickOrderView")) return NO;
    UIView *view = page;
    if (view != WDGQuickView || !WDGViewVisible(view) || !WDGWindowAllowsTarget(view.window, NO)) return NO;
    UIViewController *top = WDGTopController(view.window);
    if (!top || [top isKindOfClass:[UIAlertController class]]) return NO;
    // A popup may be attached to a controller's view or directly to its window.
    UIResponder *responder = view.nextResponder;
    for (NSUInteger depth = 0; responder && depth < 64; ++depth) {
        if ([responder isKindOfClass:[UIViewController class]]) return responder == top;
        if (responder == view.window) return top == WDGQuickHostController;
        responder = responder.nextResponder;
    }
    return NO;
}

static BOOL WDGMatchesPage(id page, id viewModel, NSString *kind) {
    NSString *vmClass = [kind isEqualToString:@"quick"] ? @"VDConfQuickOrderViewModel" : @"VDTradeConfOrderViewModel";
    return WDGIsModel(viewModel, vmClass) && WDGReadObject(page, @"viewModel") == viewModel;
}

static WDGObserverCandidate *WDGCandidate(id viewModel, NSString *kind) {
    WDGObserverCandidate *candidate = [WDGCandidates objectForKey:viewModel];
    if (!candidate) {
        candidate = [WDGObserverCandidate new];
        candidate.viewModel = viewModel;
        candidate.pageKind = kind;
        [WDGCandidates setObject:candidate forKey:viewModel];
    }
    return candidate;
}

static void WDGPublish(WDGObserverCandidate *candidate, id page) {
    id viewModel = candidate.viewModel;
    if (!viewModel || !WDGPageVisible(page, candidate.pageKind) ||
        !WDGMatchesPage(page, viewModel, candidate.pageKind)) return;
    WDGObserverBuild *build = WDGBuild(viewModel, page, candidate.pageKind);
    if (!build.fingerprint) return;
    BOOL changed = ![candidate.fingerprint isEqualToString:build.fingerprint] || candidate.boundPage != page ||
        candidate.publishedRequest != build.requestModel || candidate.publishedConfirmation != build.confirmationModel;
    if (changed || !candidate.sampleKey.length) {
        candidate.sampleKey = [NSUUID UUID].UUIDString;
        candidate.capturedAt = [NSDate date].timeIntervalSince1970;
        candidate.capturedUptime = [NSProcessInfo processInfo].systemUptime;
    }
    candidate.boundPage = page;
    candidate.pendingRequest = build.requestModel;
    candidate.pendingConfirmation = build.confirmationModel;
    candidate.publishedRequest = build.requestModel;
    candidate.publishedConfirmation = build.confirmationModel;
    candidate.fingerprint = build.fingerprint;
    candidate.readinessReason = build.readinessReason;
    NSMutableDictionary *snapshot = [build.payload mutableCopy];
    snapshot[@"sampleKey"] = candidate.sampleKey;
    snapshot[@"capturedAt"] = @(candidate.capturedAt);
    candidate.snapshot = [snapshot copy];
    WDGPublishedCandidate = candidate;
    [[WDGCore shared] acceptSnapshot:candidate.snapshot];
}

static void WDGObserveVM(id viewModel, id model, BOOL isConfirmation, NSString *kind) {
    WDGEnsureState();
    NSString *vmClass = [kind isEqualToString:@"quick"] ? @"VDConfQuickOrderViewModel" : @"VDTradeConfOrderViewModel";
    if (!WDGIsModel(viewModel, vmClass)) return;
    NSString *getter = isConfirmation ? @"confirmOrderDO" : @"requestDO";
    // A queued observation may have been superseded by another setter already.
    if (WDGReadObject(viewModel, getter) != model) return;
    WDGObserverCandidate *candidate = WDGCandidate(viewModel, kind);
    if (isConfirmation) candidate.pendingConfirmation = model;
    else candidate.pendingRequest = model;
    WDGObservationCount++;
    WDGLastObservation = [NSString stringWithFormat:@"%@.%@", kind,
                          isConfirmation ? @"confirmation" : @"request"];
    // Keep unbound models pending under their own weak-key VM, never globally.
    id quick = WDGQuickView;
    if (quick && WDGPageVisible(quick, @"quick")) {
        if ([kind isEqualToString:@"quick"] && WDGMatchesPage(quick, viewModel, kind)) WDGPublish(candidate, quick);
        return;
    }
    id ordinary = WDGOrdinaryController;
    if ([kind isEqualToString:@"confirm"] && ordinary && WDGMatchesPage(ordinary, viewModel, kind))
        WDGPublish(candidate, ordinary);
}

static void WDGObservePage(id page, NSString *kind) {
    WDGEnsureState();
    if ([kind isEqualToString:@"quick"]) {
        WDGQuickView = page;
        WDGQuickHostController = WDGTopController(((UIView *)page).window);
    } else WDGOrdinaryController = page;
    id viewModel = WDGReadObject(page, @"viewModel");
    if (!WDGMatchesPage(page, viewModel, kind)) return;
    WDGObservationCount++;
    WDGLastObservation = [kind stringByAppendingString:@".visible"];
    if ([kind isEqualToString:@"confirm"] && WDGPageVisible(WDGQuickView, @"quick")) return;
    WDGPublish(WDGCandidate(viewModel, kind), page);
}

static void WDGQueueVM(id self, id model, BOOL confirmation, NSString *kind) {
    __weak id weakVM = self;
    __weak id weakModel = model;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            id vm = weakVM, value = weakModel;
            if (vm) WDGObserveVM(vm, value, confirmation, kind);
        } @catch (__unused NSException *exception) {
            WDGLastObservation = @"observation.exception";
        }
    });
}

static void WDGQueuePage(id self, NSString *kind) {
    __weak id weakPage = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try { id page = weakPage; if (page) WDGObservePage(page, kind); }
        @catch (__unused NSException *exception) { WDGLastObservation = @"observation.exception"; }
    });
}

static void (*WDGOriginalOrdinaryRequest)(id, SEL, id);
static void (*WDGOriginalOrdinaryConfirmation)(id, SEL, id);
static void (*WDGOriginalQuickRequest)(id, SEL, id);
static void (*WDGOriginalQuickConfirmation)(id, SEL, id);
static void (*WDGOriginalAppear)(id, SEL, BOOL);
static void (*WDGOriginalShow)(id, SEL);

static void WDGHookOrdinaryRequest(id self, SEL cmd, id model) {
    WDGOriginalOrdinaryRequest(self, cmd, model); WDGQueueVM(self, model, NO, @"confirm");
}
static void WDGHookOrdinaryConfirmation(id self, SEL cmd, id model) {
    WDGOriginalOrdinaryConfirmation(self, cmd, model); WDGQueueVM(self, model, YES, @"confirm");
}
static void WDGHookQuickRequest(id self, SEL cmd, id model) {
    WDGOriginalQuickRequest(self, cmd, model); WDGQueueVM(self, model, NO, @"quick");
}
static void WDGHookQuickConfirmation(id self, SEL cmd, id model) {
    WDGOriginalQuickConfirmation(self, cmd, model); WDGQueueVM(self, model, YES, @"quick");
}
static void WDGHookAppear(id self, SEL cmd, BOOL animated) {
    WDGOriginalAppear(self, cmd, animated); WDGQueuePage(self, @"confirm");
}
static void WDGHookShow(id self, SEL cmd) {
    WDGOriginalShow(self, cmd); WDGQueuePage(self, @"quick");
}

static void WDGInstallHook(NSString *className, NSString *name, char argument, IMP replacement, IMP *original) {
    Class cls = NSClassFromString(className);
    SEL selector = NSSelectorFromString(name);
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    unsigned int count = argument ? 3 : 2;
    BOOL valid = method && method_getNumberOfArguments(method) == count && WDGMethodReturns(method, 'v') &&
        (!argument || WDGMethodArgument(method, 2, argument));
    if (valid) {
        *original = method_getImplementation(method);
        MSHookMessageEx(cls, selector, replacement, original);
    }
    [WDGHookResults addObject:@{@"class": className, @"selector": name, @"installed": @(valid),
                               @"reason": valid ? @"ok" : (method ? @"ABI mismatch" : @"missing")}];
}

void WDGInstallTradeObservers(void) {
    WDGOnMainSync(^{
        WDGEnsureState();
        if (WDGInstalled) return;
        WDGInstalled = YES;
        WDGInstallHook(@"VDTradeConfOrderViewModel", @"setRequestDO:", '@', (IMP)WDGHookOrdinaryRequest,
                       (IMP *)&WDGOriginalOrdinaryRequest);
        WDGInstallHook(@"VDTradeConfOrderViewModel", @"setConfirmOrderDO:", '@', (IMP)WDGHookOrdinaryConfirmation,
                       (IMP *)&WDGOriginalOrdinaryConfirmation);
        WDGInstallHook(@"VDConfQuickOrderViewModel", @"setRequestDO:", '@', (IMP)WDGHookQuickRequest,
                       (IMP *)&WDGOriginalQuickRequest);
        WDGInstallHook(@"VDConfQuickOrderViewModel", @"setConfirmOrderDO:", '@', (IMP)WDGHookQuickConfirmation,
                       (IMP *)&WDGOriginalQuickConfirmation);
        WDGInstallHook(@"VDTradeConfOrderViewController", @"viewDidAppear:", 'B', (IMP)WDGHookAppear,
                       (IMP *)&WDGOriginalAppear);
        WDGInstallHook(@"VDTradeQuickOrderView", @"show", '\0', (IMP)WDGHookShow, (IMP *)&WDGOriginalShow);
    });
}

NSDictionary *WDGObserverDiagnostics(void) {
    __block NSDictionary *result;
    WDGOnMainSync(^{
        WDGEnsureState();
        WDGObserverCandidate *candidate = WDGPublishedCandidate;
        // No core calls and no app-model getters: Core.status includes this map.
        result = @{@"installed": @(WDGInstalled), @"session": WDGSessionIdentifier,
                   @"hooks": [WDGHookResults copy], @"candidateCount": @(WDGCandidates.count),
                   @"observationCount": @(WDGObservationCount), @"lastObservation": WDGLastObservation ?: @"none",
                   @"pageKind": candidate.pageKind ?: @"none", @"sampleKey": candidate.sampleKey ?: @"",
                   @"stage": candidate.snapshot[@"stage"] ?: @"none",
                   @"candidateReason": candidate.readinessReason ?: @"尚未采到页面样本",
                   @"capturedAt": @(candidate.capturedAt), @"nativeDispatchCount": @(WDGDispatchCount),
                   @"lastConsumedTaskID": WDGLastConsumedTaskID ?: @""};
    });
    return result;
}

static NSNumber *WDGNormalizePayType(NSNumber *value) {
    if (![value isKindOfClass:[NSNumber class]] || sizeof(NSUInteger) != 8) return nil;
    if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return nil;
    const char *type = WDGUnqualifiedType(value.objCType);
    if (!type[0] || type[1] || !strchr("cCsSiIlLqQ", type[0]) || [value compare:@0] == NSOrderedAscending) return nil;
    return @((NSUInteger)value.unsignedLongLongValue);
}

static BOOL WDGActionABI(id page, NSString *kind, SEL *selectorOut) {
    SEL selector = NSSelectorFromString([kind isEqualToString:@"quick"] ? @"goToCreateOrder:" : @"createOrder:");
    Method method = WDGInstanceMethod(page, selector, 3);
    BOOL valid = sizeof(NSUInteger) == 8 && WDGMethodReturns(method, 'v') && WDGMethodArgument(method, 2, 'Q');
    if (valid && selectorOut) *selectorOut = selector;
    return valid;
}

static BOOL WDGReady(NSString *sampleKey, NSNumber *payType, NSString **reason,
                     id *pageOut, SEL *selectorOut, NSNumber **normalizedOut) {
#define WDG_NOT_READY(message) do { if (reason) *reason = (message); return NO; } while (0)
    WDGEnsureState();
    if (!WDGInstalled) WDG_NOT_READY(@"观察器尚未安装");
    if (![sampleKey isKindOfClass:[NSString class]] || !sampleKey.length) WDG_NOT_READY(@"缺少样本标识");
    WDGObserverCandidate *candidate = WDGPublishedCandidate;
    if (!candidate || ![candidate.sampleKey isEqualToString:sampleKey]) WDG_NOT_READY(@"样本已变化或失效");
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) WDG_NOT_READY(@"应用当前未在前台活动");
    id page = candidate.boundPage;
    id viewModel = candidate.viewModel;
    if (!page || !viewModel || !WDGPageVisible(page, candidate.pageKind) ||
        !WDGMatchesPage(page, viewModel, candidate.pageKind)) WDG_NOT_READY(@"目标页面已离开或 ViewModel 已替换");
    if ([candidate.pageKind isEqualToString:@"confirm"] && WDGPageVisible(WDGQuickView, @"quick"))
        WDG_NOT_READY(@"快捷页面覆盖了普通确认页");
    NSTimeInterval age = [NSDate date].timeIntervalSince1970 - candidate.capturedAt;
    NSTimeInterval uptimeAge = [NSProcessInfo processInfo].systemUptime - candidate.capturedUptime;
    if (age < 0 || age > WDGMaximumSampleAge || uptimeAge < 0 || uptimeAge > WDGMaximumSampleAge)
        WDG_NOT_READY(@"样本已超过十分钟或时钟发生变化");
    WDGObserverBuild *live = WDGBuild(viewModel, page, candidate.pageKind);
    if (live.requestModel != candidate.publishedRequest || live.confirmationModel != candidate.publishedConfirmation ||
        ![live.fingerprint isEqualToString:candidate.fingerprint]) WDG_NOT_READY(@"页面商品、价格或按钮已经变化");
    if (live.readinessReason.length) WDG_NOT_READY(live.readinessReason);
    NSNumber *normalized = WDGNormalizePayType(payType);
    if (!normalized || ![live.allowedPayTypes containsObject:normalized]) WDG_NOT_READY(@"请选择本样本当前可用的服务器按钮");
    SEL selector = NULL;
    if (!WDGActionABI(page, candidate.pageKind, &selector)) WDG_NOT_READY(@"UI 提交入口未通过 void/NSUInteger ABI 校验");
    if (reason) *reason = nil;
    if (pageOut) *pageOut = page;
    if (selectorOut) *selectorOut = selector;
    if (normalizedOut) *normalizedOut = normalized;
    return YES;
#undef WDG_NOT_READY
}

BOOL WDGNativeTargetReady(NSString *sampleKey, NSNumber *payType, NSString **reason) {
    __block BOOL ready = NO;
    __block NSString *message = @"页面状态检查失败";
    WDGOnMainSync(^{
        @try { ready = WDGReady(sampleKey, payType, &message, NULL, NULL, NULL); }
        @catch (__unused NSException *exception) { ready = NO; message = @"页面状态检查异常"; }
    });
    if (reason) *reason = message;
    return ready;
}

static NSError *WDGNativeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"WeidianGrab.NativeObserver" code:code
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}

BOOL WDGExecuteNativeOnce(NSString *sampleKey, NSNumber *payType, NSError **error) {
    __block BOOL dispatched = NO;
    __block NSError *failure = nil;
    WDGOnMainSync(^{
        @try {
            NSDictionary *status = [WDGCore shared].status;
            NSDictionary *task = [status[@"task"] isKindOfClass:[NSDictionary class]] ? status[@"task"] : nil;
            NSString *taskID = [task[@"id"] isKindOfClass:[NSString class]] ? task[@"id"] : nil;
            NSNumber *taskPayType = WDGNormalizePayType(task[@"payType"]);
            NSNumber *normalized = WDGNormalizePayType(payType);
            BOOL armed = [task[@"state"] isEqual:@"firing"] && [task[@"action"] isEqual:@"nativeOnce"] &&
                taskID.length && taskID.length <= 128 && [task[@"sampleKey"] isEqual:sampleKey] &&
                taskPayType && normalized && [taskPayType isEqualToNumber:normalized];
            if (!armed) { failure = WDGNativeError(1, @"缺少匹配的用户一次性任务"); return; }
            if ([WDGLastConsumedTaskID isEqualToString:taskID]) {
                failure = WDGNativeError(2, @"该任务已经消费"); return;
            }
            NSString *reason = nil;
            id page = nil;
            SEL selector = NULL;
            if (!WDGReady(sampleKey, normalized, &reason, &page, &selector, &normalized)) {
                failure = WDGNativeError(3, reason ?: @"页面当前未就绪"); return;
            }
            UIView *targetView = [page isKindOfClass:[UIViewController class]] ?
                ((UIViewController *)page).viewIfLoaded : (UIView *)page;
            if (!WDGWindowAllowsTarget(targetView.window, YES)) {
                failure = WDGNativeError(5, @"目标窗口被其他窗口或未关闭的助手弹窗覆盖"); return;
            }
            // Consume before invoking the UI entry. Even an exception never retries
            // this task; a later explicit arm has a new task UUID.
            WDGLastConsumedTaskID = [taskID copy];
            WDGDispatchCount++;
            ((void (*)(id, SEL, NSUInteger))objc_msgSend)(page, selector, normalized.unsignedIntegerValue);
            dispatched = YES; // Dispatch only, never a claim of order/payment success.
        } @catch (__unused NSException *exception) {
            failure = WDGNativeError(4, @"原生检查或 UI 入口异常；本次未重试");
        }
    });
    if (error) *error = failure;
    return dispatched;
}
