// Run from tools/weidian-grab on macOS:
// clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter \
//   -framework Foundation Tests/ads_mock.m WDGAds.m -o /tmp/ads_mock && /tmp/ads_mock
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "../WDGAds.h"

static NSUInteger gAssertions, gCasesPassed, gCasesFailed;
static NSUInteger gOriginalSplashCalls, gOriginalHotCalls, gOriginalSDKCalls;
static NSUInteger gOriginalMaterialCalls, gOriginalNormalCalls, gOriginalRequestCalls;
static NSUInteger gOriginalRegisterCalls;

@interface WDBSplashManager : NSObject
+ (BOOL)showSplashIfNeeded;
+ (BOOL)showSplashIfNeededWithHotLaunch:(BOOL)hot;
+ (BOOL)_showSDKAd:(long long)kind isHotLaunch:(BOOL)hot;
+ (BOOL)_showAvailableMaterialWithHotLaunch:(BOOL)hot;
+ (BOOL)_showNormalSplash:(id)splash index:(long long)index;
+ (void)requestSplashData;
@end
@implementation WDBSplashManager
+ (BOOL)showSplashIfNeeded { ++gOriginalSplashCalls; return YES; }
+ (BOOL)showSplashIfNeededWithHotLaunch:(BOOL)hot { ++gOriginalHotCalls; return hot; }
+ (BOOL)_showSDKAd:(long long)kind isHotLaunch:(BOOL)hot { ++gOriginalSDKCalls; return kind>=0||hot; }
+ (BOOL)_showAvailableMaterialWithHotLaunch:(BOOL)hot { ++gOriginalMaterialCalls; return hot; }
+ (BOOL)_showNormalSplash:(id)splash index:(long long)index { ++gOriginalNormalCalls; return splash!=nil||index>=0; }
+ (void)requestSplashData { ++gOriginalRequestCalls; }
@end

@interface WDBBaseCardManager : NSObject
@property(nonatomic,strong) NSMutableDictionary *registered;
- (void)registerCard:(Class)card withCardType:(long long)type;
- (Class)cardWithType:(long long)type;
@end
@implementation WDBBaseCardManager
- (instancetype)init { if((self=[super init])) _registered=[NSMutableDictionary dictionary]; return self; }
- (void)registerCard:(Class)card withCardType:(long long)type {
    ++gOriginalRegisterCalls;
    if (card) self.registered[@(type)] = card;
}
- (Class)cardWithType:(long long)type { return self.registered[@(type)]; }
@end

@interface WDBHomeHalfCpcCard : NSObject @end
@implementation WDBHomeHalfCpcCard @end
@interface WDBHomeActivityCard : NSObject @end
@implementation WDBHomeActivityCard @end

static void Require(BOOL condition, NSString *message, const char *function, int line) {
    ++gAssertions;
    if (condition) return;
    @throw [NSException exceptionWithName:@"AdsAssertion"
                                   reason:[NSString stringWithFormat:@"%s:%d: %@", function, line, message]
                                 userInfo:nil];
}
#define REQUIRE(...) Require(__VA_ARGS__, __func__, __LINE__)

static void Case(NSString *name, void (^body)(void)) {
    @try { body(); ++gCasesPassed; fprintf(stdout, "PASS %s\n", name.UTF8String); }
    @catch (NSException *exception) {
        ++gCasesFailed;
        fprintf(stdout, "FAIL %s: %s\n", name.UTF8String, exception.reason.UTF8String ?: "unknown");
    }
}

static void ClassNameFilter(void) {
    REQUIRE(WDGAdsShouldBlockCardClass(@"WDBHomeHalfCpcCard"), @"real CPC slot class was not blocked");
    REQUIRE(!WDGAdsShouldBlockCardClass(@"WDBHomeActivityCard"), @"normal activity card was blocked");
    REQUIRE(!WDGAdsShouldBlockCardClass(@"WDBHomeCollectGoodsBannerCard"), @"banner card was blocked");
    REQUIRE(!WDGAdsShouldBlockCardClass(@"WDBItemUpdateAddressDO"), @"address model was blocked");
    REQUIRE(!WDGAdsShouldBlockCardClass(@""), @"empty name was blocked");
    REQUIRE(!WDGAdsShouldBlockCardClass(nil), @"nil name was blocked");
    REQUIRE(!WDGAdsShouldBlockCardClass((id)@42), @"non-string input was blocked");
    REQUIRE(WDGAdsShouldBlockCardClass(@"WDBFooGoldenADCard"), @"golden ad card was not blocked");
}

static void InstallAndSplash(void) {
    WDGAdsInstall();
    NSDictionary *diagnostics = WDGAdsDiagnostics();
    REQUIRE([diagnostics[@"installed"] boolValue], @"hooks were not installed");
    REQUIRE([diagnostics[@"enabled"] boolValue], @"ads were disabled by default");
    REQUIRE([diagnostics[@"installFailures"] unsignedIntegerValue] == 0,
            @"a real-looking hook failed ABI validation");

    REQUIRE([WDBSplashManager showSplashIfNeeded] == NO, @"cold splash was allowed");
    REQUIRE([WDBSplashManager showSplashIfNeededWithHotLaunch:YES] == NO, @"hot splash was allowed");
    REQUIRE([WDBSplashManager _showSDKAd:3 isHotLaunch:YES] == NO, @"SDK splash was allowed");
    REQUIRE([WDBSplashManager _showAvailableMaterialWithHotLaunch:YES] == NO, @"splash material was allowed");
    REQUIRE([WDBSplashManager _showNormalSplash:@"x" index:1] == NO, @"normal splash was allowed");
    [WDBSplashManager requestSplashData];
    REQUIRE(gOriginalSplashCalls + gOriginalHotCalls + gOriginalSDKCalls +
            gOriginalMaterialCalls + gOriginalNormalCalls + gOriginalRequestCalls == 0,
            @"an original splash implementation still ran");
    REQUIRE([WDGAdsDiagnostics()[@"splashBlocked"] unsignedIntegerValue] >= 6,
            @"splash blocks were not counted");
}

static void CardRegistration(void) {
    WDBBaseCardManager *manager = [WDBBaseCardManager new];
    [manager registerCard:WDBHomeHalfCpcCard.class withCardType:7];
    REQUIRE(gOriginalRegisterCalls == 0, @"blocked card reached the original registration");
    REQUIRE([manager cardWithType:7] == Nil, @"blocked card type still resolves to a class");
    REQUIRE([WDGAdsDiagnostics()[@"cardsBlocked"] unsignedIntegerValue] == 1, @"card block was not counted");
    REQUIRE([WDGAdsDiagnostics()[@"blockedClasses"] containsObject:@"WDBHomeHalfCpcCard"],
            @"blocked class name was not recorded");

    [manager registerCard:WDBHomeActivityCard.class withCardType:9];
    REQUIRE(gOriginalRegisterCalls == 1, @"normal card was not registered");
    REQUIRE([manager cardWithType:9] == WDBHomeActivityCard.class, @"normal card type lost its class");
}

static void DisabledPassThrough(void) {
    WDGAdsSetEnabled(NO);
    REQUIRE([WDBSplashManager showSplashIfNeeded] == YES, @"disabled switch still blocked the splash");
    REQUIRE(gOriginalSplashCalls == 1, @"original splash did not run when disabled");
    WDBBaseCardManager *manager = [WDBBaseCardManager new];
    [manager registerCard:WDBHomeHalfCpcCard.class withCardType:7];
    REQUIRE(gOriginalRegisterCalls == 2, @"disabled switch still skipped registration");
    REQUIRE([manager cardWithType:7] == WDBHomeHalfCpcCard.class, @"disabled switch dropped a real card");
    WDGAdsSetEnabled(YES);
}

static void IdempotentInstall(void) {
    NSDictionary *before = WDGAdsDiagnostics();
    WDGAdsInstall();
    WDGAdsInstall();
    NSDictionary *after = WDGAdsDiagnostics();
    REQUIRE([before[@"installFailures"] isEqual:after[@"installFailures"]],
            @"repeat install changed the failure count");
    REQUIRE([WDBSplashManager showSplashIfNeeded] == NO, @"repeat install broke the hook");
}

int main(void) {
    @autoreleasepool {
        Case(@"card class name filter", ^{ ClassNameFilter(); });
        Case(@"splash suppression", ^{ InstallAndSplash(); });
        Case(@"card registration block", ^{ CardRegistration(); });
        Case(@"disabled switch passes through", ^{ DisabledPassThrough(); });
        Case(@"install is idempotent", ^{ IdempotentInstall(); });
        fprintf(stdout, "ads_mock assertions: %lu\n", (unsigned long)gAssertions);
        fprintf(stdout, "ads_mock: %lu passed, %lu failed\n",
                (unsigned long)gCasesPassed, (unsigned long)gCasesFailed);
        return gCasesFailed ? 1 : 0;
    }
}
