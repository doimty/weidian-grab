#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

// Passive sampling of the App's native clock. It never fetches a URL, changes
// phone time or alters native clock properties. Milliseconds use server-local.
FOUNDATION_EXPORT NSDictionary *WDGReadServerClock(void);
FOUNDATION_EXPORT long long WDGServerClockOffsetMs(BOOL * _Nullable valid);

// Pure conversion using a recent valid observation: localDue=serverDue-offset.
// A nil result means the caller must explicitly choose/display local-time mode.
FOUNDATION_EXPORT NSDate * _Nullable WDGLocalDeadlineFromClock(
    NSDate *serverDate, NSDictionary *sample, NSString * _Nullable * _Nullable reason);

// Reject reuse after a wall-clock change until a new native server sample is
// observed; this does NOT set/refresh the App's own server-time cache.
FOUNDATION_EXPORT void WDGInvalidateServerClock(void);
NS_ASSUME_NONNULL_END
