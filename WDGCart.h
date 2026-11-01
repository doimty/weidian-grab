#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

// Cart-resident capture. Only observes the App's own cart response; it never
// adds, removes or modifies a cart line and never sends a request itself.
FOUNDATION_EXPORT void WDGCartInstallObservers(void);
FOUNDATION_EXPORT NSDictionary *WDGCartDiagnostics(void);

// Returns the currently captured, user-selected cart lines. Values are the
// App's own NSString fields; they stay in memory and are never persisted.
FOUNDATION_EXPORT NSArray<NSDictionary *> * _Nullable WDGCartSelectedLines(void);
FOUNDATION_EXPORT NSString * _Nullable WDGCartSnapshotKey(void);
// Resolve a session-salted itemRef back to the raw ids. The map lives only in
// process memory and is never persisted.
FOUNDATION_EXPORT NSDictionary * _Nullable WDGCartRawLine(NSString * _Nullable itemRef);
NS_ASSUME_NONNULL_END
