#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

// The captured models remain in memory only. No UIWindow, UIViewController or
// gesture is part of the submission path.
typedef void (^WDGOrderReply)(NSDictionary *receipt);

@interface WDGOrderService : NSObject
@property (nonatomic, readonly) NSString *sampleKey;
@property (nonatomic, readonly) NSNumber *payType;
+ (BOOL)runtimeReady:(NSString * _Nullable * _Nullable)reason;
+ (instancetype _Nullable)prepareRequest:(id)request
                           confirmation:(id)confirmation
                              sampleKey:(NSString *)sampleKey
                                payType:(NSNumber *)payType
                                  error:(NSError * _Nullable * _Nullable)error;
- (BOOL)submitTask:(NSString *)taskID completion:(WDGOrderReply)completion error:(NSError * _Nullable * _Nullable)error;
- (void)expireUnresolvedTask:(NSString *)taskID;
+ (NSDictionary *)diagnostics;
@end
NS_ASSUME_NONNULL_END
