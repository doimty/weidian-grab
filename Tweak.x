// RootHide tweak bootstrap. Constructors work normally under libhooker;
// delay UIKit work until the application's main runloop is ready.
#import "WDGCore.h"

__attribute__((constructor))
static void WDGInitialize(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.koudai.weidian.buyer"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            static dispatch_once_t once;
            dispatch_once(&once, ^{
                WDGCore *core=[WDGCore shared];
                [core recordEvent:@"bootstrap" details:@{@"version":WDGVersion,@"build":WDGBuildID}];
                WDGInstallTradeObservers();
                WDGShowOverlay();
            });
        });
    }
}
