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
- (void)recordEvent:(NSString *)event details:(NSDictionary *)details;
- (void)acceptSnapshot:(NSDictionary *)snapshot;
- (void)clearSnapshot;
- (BOOL)armAt:(NSDate *)date action:(NSString *)action payType:(NSNumber * _Nullable)payType error:(NSError **)error;
- (void)cancelTask:(NSString *)reason;
- (NSString * _Nullable)exportReport:(NSError **)error;
@end

// Native adapter: introspection/observation only at startup. Actions only when
// explicitly armed by the user in the panel; no arbitrary HTTP replay.
FOUNDATION_EXPORT void WDGInstallTradeObservers(void);
FOUNDATION_EXPORT void WDGRefreshTradeSnapshot(void);
FOUNDATION_EXPORT NSDictionary *WDGObserverDiagnostics(void);
FOUNDATION_EXPORT BOOL WDGNativeTargetReady(NSString * _Nullable sampleKey, NSNumber * _Nullable payType, NSString * _Nullable * _Nullable reason);
FOUNDATION_EXPORT BOOL WDGExecuteNativeOnce(NSString * _Nullable sampleKey, NSNumber * _Nullable payType, NSError * _Nullable * _Nullable error);
FOUNDATION_EXPORT void WDGShowOverlay(void);
NS_ASSUME_NONNULL_END
