#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString * const WDGStateDidChange;
FOUNDATION_EXPORT NSString * const WDGVersion;
FOUNDATION_EXPORT NSString * const WDGBuildID;

@interface WDGCore : NSObject
+ (instancetype)shared;
// All public mutators below marshal to the main queue. Status returns a copy.
@property (nonatomic, readonly) NSDictionary *status;
@property (nonatomic, readonly) NSString *storagePath;
- (void)setCaptureEnabled:(BOOL)enabled;
// Display-level ad suppression. Persisted; takes effect immediately because the
// hooks check the flag at call time.
- (void)setAdsEnabled:(BOOL)enabled;
// Explicit passive read for the panel/new tasks; never sends a request or
// changes an already armed deadline. Status itself does not read native state.
- (void)refreshServerClock;
- (void)recordEvent:(NSString *)event details:(NSDictionary *)details;
- (void)acceptSnapshot:(NSDictionary *)snapshot;
- (void)clearSnapshot;
- (BOOL)armAt:(NSDate *)date action:(NSString *)action payType:(NSNumber * _Nullable)payType error:(NSError **)error;
- (BOOL)armCartAt:(NSDate *)date maximumTotal:(NSDecimalNumber *)maximumTotal error:(NSError **)error;
// lanes: 1 keeps the tested single submission; 2 races two independent
// CreateOrder requests for the same cart template. The server may create more
// than one order. Validated before any request is sent.
- (BOOL)armCartAt:(NSDate *)date maximumTotal:(NSDecimalNumber *)maximumTotal concurrentLanes:(NSUInteger)lanes error:(NSError **)error;
// Freeze Review's mode/offset. Confirmation re-reads native state; a changed
// native offset requires a new Review, while displayed local mode stays local.
- (BOOL)armCartAt:(NSDate *)date maximumTotal:(NSDecimalNumber *)maximumTotal concurrentLanes:(NSUInteger)lanes clockSnapshot:(NSDictionary *)clockSnapshot error:(NSError **)error;
- (void)cancelTask:(NSString *)reason;
// Bounded resend: applies to cart tasks only. The service stops on success or
// on any unknown/timeout result; only definite business rejections resend.
- (void)setRetryEnabled:(BOOL)enabled attempts:(NSUInteger)attempts;
- (NSString * _Nullable)exportReport:(NSError **)error;
@end

// Native adapter: introspection/observation only at startup. Actions only when
// explicitly armed by the user in the panel; no arbitrary HTTP replay.
FOUNDATION_EXPORT void WDGInstallTradeObservers(void);
FOUNDATION_EXPORT void WDGRefreshTradeSnapshot(void);
FOUNDATION_EXPORT NSDictionary *WDGObserverDiagnostics(void);
@class WDGOrderService;
FOUNDATION_EXPORT BOOL WDGInterfaceTargetReady(NSString * _Nullable sampleKey, NSNumber * _Nullable payType, NSString * _Nullable * _Nullable reason);
FOUNDATION_EXPORT WDGOrderService * _Nullable WDGPrepareObservedInterface(NSString *sampleKey, NSNumber *payType, NSError * _Nullable * _Nullable error);
FOUNDATION_EXPORT void WDGShowOverlay(void);
NS_ASSUME_NONNULL_END
