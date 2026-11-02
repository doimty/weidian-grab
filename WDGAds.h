#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

// Ad suppression is a display-level filter. It never deletes App data, never
// changes the account, and never blocks the app's own business requests.
// Cards whose class is registration-denied simply do not render.
FOUNDATION_EXPORT BOOL WDGAdsShouldBlockCardClass(NSString * _Nullable className);
FOUNDATION_EXPORT BOOL WDGAdsShouldBlockControllerClass(NSString * _Nullable className);
FOUNDATION_EXPORT BOOL WDGAdsEnabled(void);
FOUNDATION_EXPORT void WDGAdsSetEnabled(BOOL enabled);
FOUNDATION_EXPORT NSDictionary *WDGAdsDiagnostics(void);
// Idempotent; every hook is ABI-verified and skipped when the class or selector
// is absent, so a different App build degrades to "no ads blocked".
FOUNDATION_EXPORT void WDGAdsInstall(void);
NS_ASSUME_NONNULL_END
