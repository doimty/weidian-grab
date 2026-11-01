#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Only observes decoded cart data. No cart mutation or networking.
FOUNDATION_EXPORT void WDGCartInstallObservers(void);
FOUNDATION_EXPORT NSDictionary *WDGCartDiagnostics(void);
// Reads synchronize the still-live native model (main-thread getters only).
// Stable lines and snapshot HMACs are cached; no cart mutation/networking.
FOUNDATION_EXPORT NSArray<NSDictionary *> *WDGCartCandidates(void);
// Follow checked native rows by default; ChooseLine(non-nil) overrides locally.
// A vanished manual line stays empty until explicitly chosen/followed again.
FOUNDATION_EXPORT NSArray<NSDictionary *> *WDGCartSelectedLines(void);
FOUNDATION_EXPORT NSString * _Nullable WDGCartSnapshotKey(void);
FOUNDATION_EXPORT BOOL WDGCartChooseLine(NSString * _Nullable lineKey);
// Clears cached selection and latches live reads until the NEXT valid native
// fetch callback. Getter/lifecycle polling alone never repopulates after Clear.
FOUNDATION_EXPORT void WDGCartClear(void);
// Keys include cart-line ID, shop, item and SKU. Raw values stay in memory.
FOUNDATION_EXPORT NSDictionary * _Nullable WDGCartRawLine(NSString * _Nullable lineKey);
FOUNDATION_EXPORT NSArray<NSDictionary *> *WDGCartCopyRawSelection(void);
// Pure local builder: creates typed request items; never calls Confirm/Create.
FOUNDATION_EXPORT id _Nullable WDGCartBuildRequest(NSError * _Nullable * _Nullable error);
NS_ASSUME_NONNULL_END
