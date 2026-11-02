#import "WDGAds.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>

// Buyer 7.9.62 evidence (decrypted dump, same 148,799,904-byte image):
// +[WDBSplashManager showSplashIfNeeded]                  -> BOOL, 0x10041f238
// +[WDBSplashManager showSplashIfNeededWithHotLaunch:]    -> BOOL
// +[WDBSplashManager _showSDKAd:isHotLaunch:]             -> BOOL
// -[WDBBaseCardManager registerCard:withCardType:]        -> void (Class, long long)
// Home CPC ad slot registers WDBHomeHalfCpcCard.
static BOOL gAdsEnabled = YES;
static BOOL gAdsInstalled;
static NSUInteger gSplashBlocked, gCardsBlocked, gInstallFailures;
static NSMutableArray<NSString *> *gBlockedClasses;

static const char *WDGAdsType(const char *type) {
    if (!type) return "";
    while (*type && strchr("rnNoORV", *type)) ++type;
    return type;
}
// method_getReturnType cannot take a compound literal portably here.
static BOOL WDGAdsBoolReturn(Method method, unsigned int count) {
    if (!method || method_getNumberOfArguments(method) != count) return NO;
    char buffer[256] = {0};
    method_getReturnType(method, buffer, sizeof(buffer));
    const char *type = WDGAdsType(buffer);
    return type[0] == 'B' && type[1] == '\0';
}
static BOOL WDGAdsArgumentIs(Method method, unsigned int index, char expected) {
    if (!method) return NO;
    char buffer[256] = {0};
    method_getArgumentType(method, index, buffer, sizeof(buffer));
    const char *type = WDGAdsType(buffer);
    return type[0] == expected && type[1] == '\0';
}

BOOL WDGAdsShouldBlockControllerClass(NSString *className) {
    if (![className isKindOfClass:NSString.class] || className.length == 0) return NO;
    // Only full-screen paid formats. Deliberately excludes ordinary pages whose
    // names merely contain "Ad" such as address books or admin tools.
    if ([className containsString:@"SplashAd"]) return YES;
    if ([className containsString:@"Interstitial"]) return YES;
    if ([className containsString:@"RewardedVideo"] || [className containsString:@"RewardVideo"]) return YES;
    if ([className containsString:@"WindMillSplash"] || [className containsString:@"WindmillSplash"]) return YES;
    return NO;
}
BOOL WDGAdsShouldBlockCardClass(NSString *className) {
    if (![className isKindOfClass:NSString.class] || className.length == 0) return NO;
    // Deliberately narrow: only classes the dump proves are paid slots. A broad
    // "contains Ad" rule would remove unrelated cards such as address or admin.
    if ([className hasSuffix:@"CpcCard"] || [className hasSuffix:@"CPCCard"]) return YES;
    if ([className hasSuffix:@"GoldenADCard"] || [className hasSuffix:@"GoldenAdCard"]) return YES;
    if ([className hasSuffix:@"SplashAdCard"] || [className hasSuffix:@"SplashADCard"]) return YES;
    return NO;
}
BOOL WDGAdsEnabled(void) { return gAdsEnabled; }
void WDGAdsSetEnabled(BOOL enabled) { gAdsEnabled = enabled; }
static void WDGAdsNote(NSString *className) {
    if (!className.length) return;
    if (!gBlockedClasses) gBlockedClasses = [NSMutableArray array];
    if (gBlockedClasses.count < 8 && ![gBlockedClasses containsObject:className]) [gBlockedClasses addObject:className];
}
NSDictionary *WDGAdsDiagnostics(void) {
    return @{@"installed":@(gAdsInstalled), @"enabled":@(gAdsEnabled),
             @"splashBlocked":@(gSplashBlocked), @"cardsBlocked":@(gCardsBlocked),
             @"installFailures":@(gInstallFailures),
             @"blockedClasses":[gBlockedClasses copy] ?: @[]};
}

// --- splash ---------------------------------------------------------------
static BOOL (*gOriginalShowSplash)(id,SEL);
static BOOL (*gOriginalShowHot)(id,SEL,BOOL);
static BOOL (*gOriginalShowSDKAd)(id,SEL,long long,BOOL);
static BOOL (*gOriginalShowMaterial)(id,SEL,BOOL);
static BOOL (*gOriginalShowNormal)(id,SEL,id,long long);
static void (*gOriginalRequestSplash)(id,SEL);
static void (*gOriginalShowWindmillSplash)(id,SEL,BOOL);

static void WDGAdsShowWindmillSplash(id self, SEL command, BOOL hot) {
    // Evidence: the launch screenshot shows a WindMill template interstitial with
    // the "广告" badge that never passes through WDBSplashManager.
    if (gAdsEnabled) { ++gSplashBlocked; return; }
    if (gOriginalShowWindmillSplash) gOriginalShowWindmillSplash(self, command, hot);
}

static BOOL WDGAdsShowSplash(id self, SEL command) {
    if (gAdsEnabled) { ++gSplashBlocked; return NO; }
    return gOriginalShowSplash ? gOriginalShowSplash(self, command) : NO;
}
static BOOL WDGAdsShowHot(id self, SEL command, BOOL hot) {
    if (gAdsEnabled) { ++gSplashBlocked; return NO; }
    return gOriginalShowHot ? gOriginalShowHot(self, command, hot) : NO;
}
static BOOL WDGAdsShowSDKAd(id self, SEL command, long long kind, BOOL hot) {
    if (gAdsEnabled) { ++gSplashBlocked; return NO; }
    return gOriginalShowSDKAd ? gOriginalShowSDKAd(self, command, kind, hot) : NO;
}
static BOOL WDGAdsShowMaterial(id self, SEL command, BOOL hot) {
    if (gAdsEnabled) { ++gSplashBlocked; return NO; }
    return gOriginalShowMaterial ? gOriginalShowMaterial(self, command, hot) : NO;
}
static BOOL WDGAdsShowNormal(id self, SEL command, id splash, long long index) {
    if (gAdsEnabled) { ++gSplashBlocked; return NO; }
    return gOriginalShowNormal ? gOriginalShowNormal(self, command, splash, index) : NO;
}
static void WDGAdsRequestSplash(id self, SEL command) {
    // Suppressing the prefetch is what keeps ad material off disk and off the
    // network; the splash itself is already blocked above.
    if (gAdsEnabled) { ++gSplashBlocked; return; }
    if (gOriginalRequestSplash) gOriginalRequestSplash(self, command);
}

static void WDGAdsHookClassMethod(Class cls, NSString *name, IMP replacement, IMP *original, unsigned int count, BOOL returnsBool) {
    Method method = cls ? class_getClassMethod(cls, NSSelectorFromString(name)) : NULL;
    if (!method || method_getNumberOfArguments(method) != count ||
        (returnsBool && !WDGAdsBoolReturn(method, count))) { ++gInstallFailures; return; }
    if (original) *original = method_setImplementation(method, replacement);
}

// --- cards ---------------------------------------------------------------
static void (*gOriginalRegisterCard)(id,SEL,Class,long long);
static void WDGAdsRegisterCard(id self, SEL command, Class card, long long type) {
    NSString *name = card ? NSStringFromClass(card) : nil;
    if (gAdsEnabled && WDGAdsShouldBlockCardClass(name)) {
        ++gCardsBlocked; WDGAdsNote(name);
        return; // Not registered: cardWithType: then yields nil and the slot is skipped.
    }
    if (gOriginalRegisterCard) gOriginalRegisterCard(self, command, card, type);
}

void WDGAdsInstall(void) {
    if (gAdsInstalled) return;
    Class splash = NSClassFromString(@"WDBSplashManager");
    if (splash) {
        WDGAdsHookClassMethod(splash, @"showSplashIfNeeded", (IMP)WDGAdsShowSplash, (IMP *)&gOriginalShowSplash, 2, YES);
        WDGAdsHookClassMethod(splash, @"showSplashIfNeededWithHotLaunch:", (IMP)WDGAdsShowHot, (IMP *)&gOriginalShowHot, 3, YES);
        WDGAdsHookClassMethod(splash, @"_showSDKAd:isHotLaunch:", (IMP)WDGAdsShowSDKAd, (IMP *)&gOriginalShowSDKAd, 4, YES);
        WDGAdsHookClassMethod(splash, @"_showAvailableMaterialWithHotLaunch:", (IMP)WDGAdsShowMaterial, (IMP *)&gOriginalShowMaterial, 3, YES);
        WDGAdsHookClassMethod(splash, @"_showNormalSplash:index:", (IMP)WDGAdsShowNormal, (IMP *)&gOriginalShowNormal, 4, YES);
        Method request = class_getClassMethod(splash, NSSelectorFromString(@"requestSplashData"));
        if (request && method_getNumberOfArguments(request) == 2) {
            char encoding[256] = {0};
            method_getReturnType(request, encoding, sizeof(encoding));
            if (WDGAdsType(encoding)[0] == 'v') gOriginalRequestSplash = (void (*)(id,SEL))method_setImplementation(request, (IMP)WDGAdsRequestSplash);
            else ++gInstallFailures;
        } else ++gInstallFailures;
    } else ++gInstallFailures;

    Class windmillSplash = NSClassFromString(@"WDWindmillSplashAdViewController");
    if (windmillSplash) {
        Method show = class_getClassMethod(windmillSplash, NSSelectorFromString(@"showWindmillSplashAdWithHotLaunch:"));
        if (show && method_getNumberOfArguments(show) == 3 && WDGAdsArgumentIs(show, 2, 'B')) {
            char encoding[256] = {0};
            method_getReturnType(show, encoding, sizeof(encoding));
            if (WDGAdsType(encoding)[0] == 'v') gOriginalShowWindmillSplash = (void (*)(id,SEL,BOOL))method_setImplementation(show, (IMP)WDGAdsShowWindmillSplash);
            else ++gInstallFailures;
        } else ++gInstallFailures;
    } else ++gInstallFailures;

    Class cards = NSClassFromString(@"WDBBaseCardManager");
    Method registerMethod = cards ? class_getInstanceMethod(cards, NSSelectorFromString(@"registerCard:withCardType:")) : NULL;
    if (registerMethod && method_getNumberOfArguments(registerMethod) == 4 &&
        WDGAdsArgumentIs(registerMethod, 2, '#') && WDGAdsArgumentIs(registerMethod, 3, 'q')) {
        char encoding[256] = {0};
        method_getReturnType(registerMethod, encoding, sizeof(encoding));
        if (WDGAdsType(encoding)[0] == 'v') gOriginalRegisterCard = (void (*)(id,SEL,Class,long long))method_setImplementation(registerMethod, (IMP)WDGAdsRegisterCard);
        else ++gInstallFailures;
    } else ++gInstallFailures;

    gAdsInstalled = YES;
}
// Runs when the dylib loads, before the App's own launch code can present an ad.
__attribute__((constructor)) static void WDGAdsBootstrap(void) {
    @autoreleasepool { WDGAdsInstall(); }
}
