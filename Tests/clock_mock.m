// Run from tools/weidian-grab on macOS:
// clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter \
//   -framework Foundation Tests/clock_mock.m WDGClock.m -o /tmp/clock_mock && /tmp/clock_mock
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <float.h>
#import <math.h>
#import <stdio.h>
#import "../WDGClock.h"

typedef NS_ENUM(NSUInteger, WDGFixtureMode) {
    WDGFixtureModeNormal = 0,
    WDGFixtureModeWrongUnits,
    WDGFixtureModeOffsetChanges,
    WDGFixtureModeMarkerChanges,
    WDGFixtureModeClockSkew,
    WDGFixtureModeThrows
};

static long long FixtureWallMS(void) {
    return (long long)floor(NSDate.date.timeIntervalSince1970 * 1000.0);
}

@interface WDTNServerClockProofreader : NSObject
+ (id)sharedInstance;
- (long long)serverTimeMS;
- (long long)timeOffsetMS;
- (long long)currentServerTime;
@property(nonatomic) long long fixtureOffset;
@property(nonatomic) long long fixtureMarker;
@property(nonatomic) long long fixtureCurrentSkew;
@property(nonatomic) WDGFixtureMode fixtureMode;
@end

static WDTNServerClockProofreader *gNativeClock;
static NSUInteger gOffsetGetterCalls;
static NSUInteger gMarkerGetterCalls;
static NSUInteger gWrongGetterCalls;
static NSUInteger gDynamicClassSequence;

@implementation WDTNServerClockProofreader
+ (id)sharedInstance {
    return gNativeClock;
}

- (long long)serverTimeMS {
    ++gMarkerGetterCalls;
    if (self.fixtureMode == WDGFixtureModeThrows) {
        @throw [NSException exceptionWithName:@"FixtureNativeRead"
                                       reason:@"fixture serverTimeMS exception"
                                     userInfo:nil];
    }
    if (self.fixtureMode == WDGFixtureModeMarkerChanges && gMarkerGetterCalls > 1) {
        return self.fixtureMarker + 1;
    }
    return self.fixtureMarker;
}

- (long long)timeOffsetMS {
    ++gOffsetGetterCalls;
    if (self.fixtureMode == WDGFixtureModeThrows) {
        @throw [NSException exceptionWithName:@"FixtureNativeRead"
                                       reason:@"fixture timeOffsetMS exception"
                                     userInfo:nil];
    }
    if (self.fixtureMode == WDGFixtureModeOffsetChanges && gOffsetGetterCalls > 1) {
        return self.fixtureOffset + 1;
    }
    return self.fixtureOffset;
}

- (long long)currentServerTime {
    if (self.fixtureMode == WDGFixtureModeThrows) {
        @throw [NSException exceptionWithName:@"FixtureNativeRead"
                                       reason:@"fixture currentServerTime exception"
                                     userInfo:nil];
    }
    long long now = FixtureWallMS();
    if (self.fixtureMode == WDGFixtureModeWrongUnits) {
        return now / 1000 + self.fixtureOffset;
    }
    if (self.fixtureMode == WDGFixtureModeClockSkew) {
        return now + self.fixtureOffset + self.fixtureCurrentSkew;
    }
    return now + self.fixtureOffset;
}
@end

static NSUInteger gAssertions;
static NSUInteger gCasesPassed;
static NSUInteger gCasesFailed;

static void FixtureRequire(BOOL condition, NSString *message, const char *function, int line) {
    ++gAssertions;
    if (!condition) {
        NSString *reason = [NSString stringWithFormat:@"%s:%d: %@", function, line,
                                                      message ?: @"assertion failed"];
        @throw [NSException exceptionWithName:@"FixtureAssertion" reason:reason userInfo:nil];
    }
}

#define REQUIRE(...) FixtureRequire(__VA_ARGS__, __func__, __LINE__)

static void FixtureResetNative(void) {
    if (!gNativeClock) gNativeClock = [WDTNServerClockProofreader new];
    object_setClass(gNativeClock, WDTNServerClockProofreader.class);
    gNativeClock.fixtureOffset = 0;
    gNativeClock.fixtureMarker = 0;
    gNativeClock.fixtureCurrentSkew = 0;
    gNativeClock.fixtureMode = WDGFixtureModeNormal;
    gOffsetGetterCalls = 0;
    gMarkerGetterCalls = 0;
    gWrongGetterCalls = 0;
}

static void FixtureFresh(long long offset, long long markerAgeMs) {
    gNativeClock.fixtureOffset = offset;
    gNativeClock.fixtureMarker = FixtureWallMS() + offset - markerAgeMs;
    gNativeClock.fixtureCurrentSkew = 0;
    gNativeClock.fixtureMode = WDGFixtureModeNormal;
    gOffsetGetterCalls = 0;
    gMarkerGetterCalls = 0;
}

static void FixtureValidateShape(NSDictionary *sample) {
    REQUIRE([sample isKindOfClass:NSDictionary.class], @"clock result is not a dictionary");
    REQUIRE([sample[@"valid"] isKindOfClass:NSNumber.class], @"valid is not NSNumber");
    REQUIRE([sample[@"status"] isKindOfClass:NSString.class], @"status is not NSString");
    NSSet *statuses = [NSSet setWithArray:@[
        @"native_recent", @"cache_only", @"stale", @"future", @"unstable",
        @"out_of_range", @"unavailable", @"clock_changed"
    ]];
    REQUIRE([statuses containsObject:sample[@"status"]], @"unknown clock status");
    id offset = sample[@"offsetMs"];
    REQUIRE(offset == NSNull.null || [offset isKindOfClass:NSNumber.class],
            @"offsetMs is neither NSNumber nor NSNull");
    id rawOffset = sample[@"rawOffsetMs"];
    REQUIRE(!rawOffset || [rawOffset isKindOfClass:NSNumber.class],
            @"rawOffsetMs is not NSNumber when present");
    id marker = sample[@"updatedAtServerMs"];
    REQUIRE(!marker || marker == NSNull.null || [marker isKindOfClass:NSNumber.class],
            @"updatedAtServerMs is neither NSNumber nor NSNull when present");
    id age = sample[@"ageMs"];
    REQUIRE(age != nil && (age == NSNull.null || [age isKindOfClass:NSNumber.class]),
            @"ageMs is missing or neither NSNumber nor NSNull");
    for (NSString *key in @[@"sampledAt", @"sampledUptime", @"readDurationMs"]) {
        NSNumber *value = sample[key];
        REQUIRE([value isKindOfClass:NSNumber.class] && isfinite(value.doubleValue),
                [NSString stringWithFormat:@"%@ is not finite NSNumber", key]);
    }
    REQUIRE([sample[@"readDurationMs"] doubleValue] >= 0.0, @"readDurationMs is negative");
    REQUIRE([sample[@"reason"] isKindOfClass:NSString.class] && [sample[@"reason"] length] > 0,
            @"reason is missing");
    REQUIRE([sample[@"source"] isEqual:@"WDTNServerClockProofreader"], @"source is wrong");
    REQUIRE([sample[@"clockGeneration"] isKindOfClass:NSNumber.class],
            @"clockGeneration is missing");
}

static void FixtureRequireStatus(NSDictionary *sample, NSString *status, BOOL valid) {
    FixtureValidateShape(sample);
    REQUIRE([sample[@"status"] isEqual:status],
            [NSString stringWithFormat:@"expected status %@, got %@", status, sample[@"status"]]);
    REQUIRE([sample[@"valid"] boolValue] == valid, @"valid does not match status expectation");
    if (valid) {
        REQUIRE([sample[@"offsetMs"] isKindOfClass:NSNumber.class],
                @"valid sample has no numeric offsetMs");
    } else {
        REQUIRE(sample[@"offsetMs"] == NSNull.null, @"invalid sample retained an offsetMs");
    }
}

static void FixtureRequireRecent(NSDictionary *sample, long long offset, long long marker) {
    FixtureRequireStatus(sample, @"native_recent", YES);
    REQUIRE([sample[@"offsetMs"] longLongValue] == offset, @"native offset differs from raw offset");
    REQUIRE([sample[@"rawOffsetMs"] longLongValue] == offset, @"raw offset differs from fixture");
    REQUIRE([sample[@"updatedAtServerMs"] longLongValue] == marker, @"marker was not reported");
    REQUIRE([sample[@"ageMs"] isKindOfClass:NSNumber.class] &&
            [sample[@"ageMs"] doubleValue] >= 0.0 && [sample[@"ageMs"] doubleValue] < 600000.0,
            @"recent sample age is invalid");
}

static Class FixtureBadInstanceClass(SEL selector, IMP implementation, const char *types) {
    NSString *name = [NSString stringWithFormat:@"WDGClockFixtureBadInstance_%lu",
                       (unsigned long)++gDynamicClassSequence];
    Class subclass = objc_allocateClassPair(WDTNServerClockProofreader.class,
                                             name.UTF8String, 0);
    REQUIRE(subclass != Nil, @"could not allocate bad native subclass");
    REQUIRE(class_addMethod(subclass, selector, implementation, types),
            @"could not install bad native method");
    objc_registerClassPair(subclass);
    return subclass;
}

static double FixtureWrongDoubleGetter(id receiver, SEL selector) {
    ++gWrongGetterCalls;
    return 1.0;
}

static void *FixtureWrongSharedGetter(id receiver, SEL selector) {
    ++gWrongGetterCalls;
    return NULL;
}

static void FixtureWithBadSharedABI(void (^body)(void)) {
    NSString *name = [NSString stringWithFormat:@"WDGClockFixtureBadShared_%lu",
                       (unsigned long)++gDynamicClassSequence];
    Class badClass = objc_allocateClassPair(NSObject.class, name.UTF8String, 0);
    REQUIRE(badClass != Nil, @"could not allocate bad shared class");
    Class badMeta = object_getClass(badClass);
    REQUIRE(class_addMethod(badMeta, @selector(sharedInstance),
                            (IMP)FixtureWrongSharedGetter, "@?@:"),
            @"could not install block-returning sharedInstance");
    objc_registerClassPair(badClass);
    Class nativeClass = WDTNServerClockProofreader.class;
    Class savedMeta = object_setClass((id)nativeClass, badMeta);
    @try {
        body();
    } @finally {
        object_setClass((id)nativeClass, savedMeta);
    }
}

static NSDictionary *FixtureMathSample(double offset, NSTimeInterval age,
                                       NSTimeInterval wallSkew) {
    NSTimeInterval wall = NSDate.date.timeIntervalSince1970;
    NSTimeInterval uptime = NSProcessInfo.processInfo.systemUptime;
    return @{
        @"valid": @YES,
        @"offsetMs": @(offset),
        @"sampledAt": @(wall - age + wallSkew),
        @"sampledUptime": @(uptime - age)
    };
}

static void FixtureCase(NSString *name, void (^body)(void)) {
    @autoreleasepool {
        FixtureResetNative();
        @try {
            body();
            ++gCasesPassed;
        } @catch (NSException *exception) {
            ++gCasesFailed;
            fprintf(stderr, "FAIL %s: %s\n", name.UTF8String,
                    exception.reason.UTF8String ?: "unknown failure");
        }
    }
}

static void FixtureNativeRecentCases(void) {
    for (NSNumber *number in @[@250, @-350, @0]) {
        long long offset = number.longLongValue;
        FixtureFresh(offset, 1000);
        long long marker = gNativeClock.fixtureMarker;
        NSDictionary *sample = WDGReadServerClock();
        FixtureRequireRecent(sample, offset, marker);
        BOOL valid = NO;
        long long observed = WDGServerClockOffsetMs(&valid);
        REQUIRE(valid && observed == offset, @"offset helper rejected a recent native sample");
    }
}

static void FixtureCacheOnlyCases(void) {
    for (NSNumber *number in @[@250, @-350, @0]) {
        FixtureFresh(number.longLongValue, 1000);
        gNativeClock.fixtureMarker = 0;
        NSDictionary *sample = WDGReadServerClock();
        FixtureRequireStatus(sample, @"cache_only", NO);
        REQUIRE([sample[@"rawOffsetMs"] longLongValue] == number.longLongValue,
                @"cache-only raw offset was lost");
        REQUIRE([sample[@"updatedAtServerMs"] longLongValue] == 0,
                @"cache-only marker was not reported");
        BOOL valid = YES;
        REQUIRE(WDGServerClockOffsetMs(&valid) == 0 && !valid,
                @"cache-only offset helper claimed validity");
    }
}

static void FixtureBoundaryCases(void) {
    FixtureFresh(250, 600001);
    FixtureRequireStatus(WDGReadServerClock(), @"stale", NO);

    FixtureFresh(-350, -2501);
    FixtureRequireStatus(WDGReadServerClock(), @"future", NO);

    for (NSNumber *offset in @[@60001, @-60001]) {
        FixtureFresh(offset.longLongValue, 1000);
        FixtureRequireStatus(WDGReadServerClock(), @"out_of_range", NO);
    }

    for (NSNumber *offset in @[@60000, @-60000]) {
        FixtureFresh(offset.longLongValue, 1000);
        FixtureRequireRecent(WDGReadServerClock(), offset.longLongValue,
                             gNativeClock.fixtureMarker);
    }
}

static void FixtureUnstableCases(void) {
    FixtureFresh(250, 1000);
    gNativeClock.fixtureMode = WDGFixtureModeOffsetChanges;
    FixtureRequireStatus(WDGReadServerClock(), @"unstable", NO);
    REQUIRE(gOffsetGetterCalls >= 2, @"offset-change fixture did not expose both reads");

    FixtureFresh(250, 1000);
    gNativeClock.fixtureMode = WDGFixtureModeMarkerChanges;
    FixtureRequireStatus(WDGReadServerClock(), @"unstable", NO);
    REQUIRE(gMarkerGetterCalls >= 2, @"marker-change fixture did not expose both reads");

    FixtureFresh(250, 1000);
    gNativeClock.fixtureMode = WDGFixtureModeClockSkew;
    gNativeClock.fixtureCurrentSkew = 150;
    FixtureRequireStatus(WDGReadServerClock(), @"unstable", NO);
}

static void FixtureMalformedNativeCases(void) {
    FixtureFresh(250, 1000);
    gNativeClock.fixtureMode = WDGFixtureModeWrongUnits;
    FixtureRequireStatus(WDGReadServerClock(), @"out_of_range", NO);

    FixtureFresh(250, 1000);
    gNativeClock.fixtureMode = WDGFixtureModeThrows;
    FixtureRequireStatus(WDGReadServerClock(), @"unavailable", NO);
}

static void FixtureABICases(void) {
    FixtureFresh(250, 1000);
    NSArray<NSString *> *selectors = @[@"serverTimeMS", @"timeOffsetMS", @"currentServerTime"];
    for (NSString *name in selectors) {
        gWrongGetterCalls = 0;
        SEL selector = NSSelectorFromString(name);
        Class bad = FixtureBadInstanceClass(selector, (IMP)FixtureWrongDoubleGetter, "d@:");
        Class saved = object_setClass(gNativeClock, bad);
        @try {
            NSDictionary *sample = WDGReadServerClock();
            FixtureRequireStatus(sample, @"unavailable", NO);
            REQUIRE(gWrongGetterCalls == 0,
                    [NSString stringWithFormat:@"wrong ABI getter %@ was invoked", name]);
        } @finally {
            object_setClass(gNativeClock, saved);
        }
    }

    gWrongGetterCalls = 0;
    FixtureWithBadSharedABI(^{
        NSDictionary *sample = WDGReadServerClock();
        FixtureRequireStatus(sample, @"unavailable", NO);
        REQUIRE(gWrongGetterCalls == 0, @"block-returning sharedInstance was invoked");
    });
}

static void FixturePureConversionCases(void) {
    NSDate *serverDate = [NSDate dateWithTimeIntervalSince1970:2000000000.123];
    NSTimeInterval original = serverDate.timeIntervalSince1970;
    for (NSNumber *number in @[@250, @-350, @0]) {
        double offset = number.doubleValue;
        NSDictionary *sample = FixtureMathSample(offset, 0.0, 0.0);
        NSString *reason = @"sentinel";
        NSDate *first = WDGLocalDeadlineFromClock(serverDate, sample, &reason);
        REQUIRE(first != nil && reason == nil, @"fresh math sample did not convert");
        double expected = original - offset / 1000.0;
        REQUIRE(fabs(first.timeIntervalSince1970 - expected) < 0.000001,
                @"deadline conversion has the wrong offset sign");

        reason = @"sentinel";
        NSDate *second = WDGLocalDeadlineFromClock(serverDate, sample, &reason);
        REQUIRE(second != nil && reason == nil, @"second conversion did not succeed");
        REQUIRE(fabs(second.timeIntervalSince1970 - first.timeIntervalSince1970) < 0.000001,
                @"repeated conversion applied the offset twice");
        REQUIRE(fabs(serverDate.timeIntervalSince1970 - original) < 0.000001,
                @"server date was modified");
    }
}

static void FixtureConversionRejectionCases(void) {
    NSDictionary *good = FixtureMathSample(250, 0.0, 0.0);
    NSString *reason = nil;
    NSDate *nanDate = [NSDate dateWithTimeIntervalSince1970:NAN];
    REQUIRE(!WDGLocalDeadlineFromClock(nanDate, good, &reason) && reason.length > 0,
            @"nonfinite server date was accepted");

    NSMutableDictionary *invalid = [good mutableCopy];
    invalid[@"valid"] = @NO;
    reason = nil;
    REQUIRE(!WDGLocalDeadlineFromClock([NSDate date], invalid, &reason) && reason.length > 0,
            @"invalid sample was accepted");

    NSDictionary *stale = FixtureMathSample(250, 6.0, 0.0);
    reason = nil;
    REQUIRE(!WDGLocalDeadlineFromClock([NSDate date], stale, &reason) && reason.length > 0,
            @"sample older than five seconds was accepted");

    NSDictionary *wallJump = FixtureMathSample(250, 1.0, 0.5);
    reason = nil;
    REQUIRE(!WDGLocalDeadlineFromClock([NSDate date], wallJump, &reason) && reason.length > 0,
            @"wall and uptime sample disagreement was accepted");

    for (id offset in @[@(NAN), @(INFINITY), @250.5, @YES, @60001, @-60001, @(DBL_MAX)]) {
        NSMutableDictionary *malformed = [good mutableCopy];
        malformed[@"offsetMs"] = offset;
        reason = nil;
        REQUIRE(!WDGLocalDeadlineFromClock([NSDate date], malformed, &reason) && reason.length > 0,
                @"malformed or overflowing offset was accepted");
    }

    NSMutableDictionary *missing = [good mutableCopy];
    [missing removeObjectForKey:@"offsetMs"];
    reason = nil;
    REQUIRE(!WDGLocalDeadlineFromClock([NSDate date], missing, &reason) && reason.length > 0,
            @"sample with missing offset was accepted");

    NSMutableDictionary *nonfiniteWall = [good mutableCopy];
    nonfiniteWall[@"sampledAt"] = @(NAN);
    reason = nil;
    REQUIRE(!WDGLocalDeadlineFromClock([NSDate date], nonfiniteWall, &reason) && reason.length > 0,
            @"sample with nonfinite sampledAt was accepted");
}

static void FixtureInvalidationCases(void) {
    FixtureFresh(250, 1000);
    NSDictionary *before = WDGReadServerClock();
    FixtureRequireRecent(before, 250, gNativeClock.fixtureMarker);
    long long oldMarker = gNativeClock.fixtureMarker;
    NSDate *due = [NSDate dateWithTimeIntervalSinceNow:30.0];

    WDGInvalidateServerClock();
    NSString *reason = nil;
    REQUIRE(!WDGLocalDeadlineFromClock(due, before, &reason) && reason.length > 0,
            @"invalidated old sample remained usable for deadline conversion");
    NSDictionary *oldSample = WDGReadServerClock();
    FixtureRequireStatus(oldSample, @"clock_changed", NO);
    REQUIRE([oldSample[@"updatedAtServerMs"] longLongValue] == oldMarker,
            @"invalidated read did not retain the old marker for diagnosis");

    gNativeClock.fixtureMarker = oldMarker + 1;
    NSDictionary *recovered = WDGReadServerClock();
    FixtureRequireRecent(recovered, 250, oldMarker + 1);
    reason = nil;
    REQUIRE(!WDGLocalDeadlineFromClock(due, before, &reason) && reason.length > 0,
            @"old generation sample became usable after new marker recovery");
    reason = @"sentinel";
    REQUIRE(WDGLocalDeadlineFromClock(due, recovered, &reason) != nil && reason == nil,
            @"new marker sample did not restore deadline conversion");
}

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        gNativeClock = [WDTNServerClockProofreader new];
        FixtureCase(@"native recent offsets", ^{ FixtureNativeRecentCases(); });
        FixtureCase(@"cache-only marker", ^{ FixtureCacheOnlyCases(); });
        FixtureCase(@"freshness and offset boundaries", ^{ FixtureBoundaryCases(); });
        FixtureCase(@"unstable native snapshots", ^{ FixtureUnstableCases(); });
        FixtureCase(@"malformed native reads", ^{ FixtureMalformedNativeCases(); });
        FixtureCase(@"native ABI guards", ^{ FixtureABICases(); });
        FixtureCase(@"pure deadline conversion", ^{ FixturePureConversionCases(); });
        FixtureCase(@"deadline rejection and format guards", ^{ FixtureConversionRejectionCases(); });
        FixtureCase(@"invalidation requires a new marker", ^{ FixtureInvalidationCases(); });
        fprintf(stdout, "clock_mock assertions: %lu\n", (unsigned long)gAssertions);
        fprintf(stdout, "clock_mock: %lu passed, %lu failed\n",
                (unsigned long)gCasesPassed, (unsigned long)gCasesFailed);
        return gCasesFailed ? 1 : 0;
    }
}
