#import "WDGCart.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <string.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonDigest.h>

// Cart path evidence (7.9.62 header export, tools/weidian-grab/weidian-objc.txt):
//   371428 -[VDTradeMyCartViewController fetchDataSucceed:cartListDO:]
//   361127 VDTradeCartListDO.shops / .selectedItems
//   361020 VDTradeCartItemDO.partitions / .shopId
//   361189 VDTradeCartPartitionDO.itemList
//   369282 VDTradeGoodsItemDO: itemId/skuId/count/shopId/canOrder/isSelected
//   369385 VDTradeGoodsItemDO.available_date
// Observation only: the App's original method runs first and untouched, we
// never mutate the cart or issue a request.
static NSArray<NSDictionary *> *WDGCartLines;
static NSString *WDGCartKey;
static NSDictionary *WDGCartMeta;
static NSUInteger WDGCartCaptures;
static NSString *WDGCartLastReason;
static BOOL WDGCartInstalled;
static NSData *WDGCartSalt;
static IMP WDGCartOriginalFetch;
static NSMutableDictionary<NSString *, NSDictionary *> *WDGCartRawMap;

static const char *WDGCartUnqualified(const char *type) {
    if (!type) return "";
    while (*type && strchr("rnNoORV", *type)) ++type;
    return type;
}

static NSString *WDGCartText(id object, NSString *selectorName) {
    if (!object) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    Method m = class_getInstanceMethod(object_getClass(object), sel);
    if (!m || method_getNumberOfArguments(m) != 2) return nil;
    char ret[256] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    const char *t = WDGCartUnqualified(ret);
    if (t[0] != '@' || (t[1] && t[1] != '"')) return nil;
    @try {
        id v = ((id (*)(id, SEL))objc_msgSend)(object, sel);
        return [v isKindOfClass:NSString.class] ? [v copy] : nil;
    } @catch (__unused NSException *e) { return nil; }
}

static NSNumber *WDGCartBool(id object, NSString *selectorName) {
    if (!object) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    Method m = class_getInstanceMethod(object_getClass(object), sel);
    if (!m || method_getNumberOfArguments(m) != 2) return nil;
    char ret[256] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    const char *t = WDGCartUnqualified(ret);
    if (t[0] != 'B' || t[1]) return nil;
    @try { return @(((BOOL (*)(id, SEL))objc_msgSend)(object, sel)); }
    @catch (__unused NSException *e) { return nil; }
}

static NSNumber *WDGCartInt(id object, NSString *selectorName) {
    if (!object) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    Method m = class_getInstanceMethod(object_getClass(object), sel);
    if (!m || method_getNumberOfArguments(m) != 2) return nil;
    char ret[256] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    const char *t = WDGCartUnqualified(ret);
    if (!t[0] || t[1] || !strchr("cCsSiIlLqQ", t[0])) return nil;
    @try { return @(((long long (*)(id, SEL))objc_msgSend)(object, sel)); }
    @catch (__unused NSException *e) { return nil; }
}

static NSArray *WDGCartArray(id object, NSString *selectorName) {    if (!object) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    Method m = class_getInstanceMethod(object_getClass(object), sel);
    if (!m || method_getNumberOfArguments(m) != 2) return nil;
    @try {
        id v = ((id (*)(id, SEL))objc_msgSend)(object, sel);
        return [v isKindOfClass:NSArray.class] ? v : nil;
    } @catch (__unused NSException *e) { return nil; }
}

// Session-salted reference so raw item/shop ids never leave memory as text.
static NSString *WDGCartRef(NSString *value) {
    if (!value.length || value.length > 128) return nil;
    if (!WDGCartSalt) WDGCartSalt = [NSUUID.UUID.UUIDString dataUsingEncoding:NSUTF8StringEncoding];
    NSData *in = [value dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char out[CC_SHA256_DIGEST_LENGTH] = {0};
    CCHmac(kCCHmacAlgSHA256, WDGCartSalt.bytes, WDGCartSalt.length, in.bytes, in.length, out);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; ++i) [hex appendFormat:@"%02x", out[i]];
    return [hex substringToIndex:32];
}

static void WDGCartAppendLines(NSArray *shops, NSMutableArray *out) {
    for (id shop in shops) {
        if (out.count >= 100) return;
        NSString *shopId = WDGCartText(shop, @"shopId");
        NSArray *partitions = WDGCartArray(shop, @"partitions");
        for (id partition in partitions ?: @[]) {
            if (out.count >= 100) return;
            NSArray *items = WDGCartArray(partition, @"itemList") ?: WDGCartArray(partition, @"items");
            for (id item in items ?: @[]) {
                if (out.count >= 100) return;
                NSString *itemId = WDGCartText(item, @"itemId");
                if (!itemId.length) continue;
                NSString *name = WDGCartText(item, @"itemName");
                if (name.length > 120) {
                    NSRange r = [name rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, 120)];
                    name = [name substringWithRange:r];
                }
                NSMutableDictionary *line = [@{
                    @"itemRef": WDGCartRef(itemId) ?: @"",
                    @"skuRef": WDGCartRef(WDGCartText(item, @"skuId")) ?: @"",
                    @"shopRef": WDGCartRef(shopId) ?: @"",
                    @"quantity": WDGCartText(item, @"count") ?: @"",
                    @"title": name ?: @"",
                    @"skuTitle": WDGCartText(item, @"skuName") ?: @"",
                } mutableCopy];
                // Keep the raw ids only in this process's memory so the request
                // model can be built at fire time without touching disk.
                if (!WDGCartRawMap) WDGCartRawMap = [NSMutableDictionary dictionary];
                NSMutableDictionary *raw = [NSMutableDictionary dictionary];
                if (itemId) raw[@"itemId"] = itemId;
                NSString *skuId = WDGCartText(item, @"skuId");
                if (skuId) raw[@"skuId"] = skuId;
                NSString *count = WDGCartText(item, @"count");
                if (count) raw[@"count"] = count;
                NSNumber *payType = WDGCartInt(item, @"payType");
                if (payType) raw[@"priceType"] = payType;
                NSString *itemRef = line[@"itemRef"];
                if (itemRef.length) WDGCartRawMap[itemRef] = [raw copy];
                NSNumber *selected = WDGCartBool(item, @"isSelected");
                NSNumber *orderable = WDGCartBool(item, @"canOrder");
                if (selected) line[@"selected"] = selected;
                if (orderable) line[@"canOrder"] = orderable;
                NSString *available = WDGCartText(item, @"available_date");
                if (available.length) line[@"availableDate"] = available;
                NSString *invalid = WDGCartText(item, @"promotionInvalidTimeText");
                if (invalid.length) line[@"promotionInvalidTime"] = invalid;
                [out addObject:line];
            }
        }
    }
}

static void WDGCartHandleList(id cartList) {
    if (!cartList) { WDGCartLastReason = @"购物车回调没有模型"; return; }
    NSArray *shops = WDGCartArray(cartList, @"shops");
    if (!shops) { WDGCartLastReason = @"购物车模型没有 shops 字段"; return; }
    NSMutableArray *all = [NSMutableArray array];
    WDGCartAppendLines(shops, all);
    if (!all.count) { WDGCartLastReason = @"购物车没有商品行"; return; }
    // Prefer the user's checked lines; otherwise keep orderable ones so a
    // not-yet-checkable pre-sale line still shows up as a candidate.
    NSMutableArray *picked = [NSMutableArray array];
    for (NSDictionary *line in all) if ([line[@"selected"] boolValue]) [picked addObject:line];
    BOOL usedSelection = picked.count > 0;
    if (!usedSelection) {
        for (NSDictionary *line in all) {
            if (line[@"canOrder"] == nil || [line[@"canOrder"] boolValue]) [picked addObject:line];
        }
    }
    if (!picked.count) { WDGCartLastReason = @"购物车没有可提交商品"; return; }
    // Stable key: only the line identity set, not prices or timestamps, so a
    // background cart refresh does not invalidate an already armed task.
    NSMutableArray *identity = [NSMutableArray array];
    for (NSDictionary *line in picked) {
        [identity addObject:[NSString stringWithFormat:@"%@/%@/%@",
                             line[@"itemRef"], line[@"skuRef"], line[@"quantity"]]];
    }
    [identity sortUsingSelector:@selector(compare:)];
    NSString *newKey = WDGCartRef([identity componentsJoinedByString:@"|"]);
    if (newKey && ![newKey isEqualToString:WDGCartKey]) WDGCartKey = [newKey copy];
    WDGCartLines = [picked copy];
    WDGCartCaptures++;
    WDGCartMeta = @{@"lineCount": @(picked.count), @"totalLines": @(all.count),
                    @"usedSelection": @(usedSelection),
                    @"capturedAt": @(NSDate.date.timeIntervalSince1970)};
    WDGCartLastReason = nil;
}

static void WDGCartFetchData(id self, SEL _cmd, id first, id cartList) {
    // Original runs first; we only read the model it was handed.
    if (WDGCartOriginalFetch) ((void (*)(id, SEL, id, id))WDGCartOriginalFetch)(self, _cmd, first, cartList);
    id model = cartList;
    if (!model) model = first;
    dispatch_async(dispatch_get_main_queue(), ^{ WDGCartHandleList(model); });
}

void WDGCartInstallObservers(void) {
    if (WDGCartInstalled) return;
    WDGCartInstalled = YES;
    Class cls = NSClassFromString(@"VDTradeMyCartViewController");
    SEL sel = NSSelectorFromString(@"fetchDataSucceed:cartListDO:");
    Method m = cls ? class_getInstanceMethod(cls, sel) : NULL;
    char ret[256] = {0};
    if (m) method_getReturnType(m, ret, sizeof(ret));
    const char *t = WDGCartUnqualified(ret);
    if (!m || method_getNumberOfArguments(m) != 4 || t[0] != 'v' || t[1]) {
        WDGCartLastReason = @"购物车回调 ABI 不匹配";
        return;
    }
    WDGCartOriginalFetch = method_getImplementation(m);
    MSHookMessageEx(cls, sel, (IMP)WDGCartFetchData, &WDGCartOriginalFetch);
    WDGCartLastReason = nil;
}

NSArray<NSDictionary *> *WDGCartSelectedLines(void) { return WDGCartLines; }
NSString *WDGCartSnapshotKey(void) { return WDGCartKey; }
NSDictionary *WDGCartRawLine(NSString *itemRef) {
    if (!itemRef.length || !WDGCartRawMap) return nil;
    return WDGCartRawMap[itemRef];
}

NSDictionary *WDGCartDiagnostics(void) {
    return @{@"installed": @(WDGCartInstalled), @"captures": @(WDGCartCaptures),
             @"lineCount": @(WDGCartLines.count), @"key": WDGCartKey ?: @"",
             @"reason": WDGCartLastReason ?: @"", @"meta": WDGCartMeta ?: @{}};
}
