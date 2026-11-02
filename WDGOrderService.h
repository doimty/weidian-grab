#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

// The captured models remain in memory only. No UIWindow, UIViewController or
// gesture is part of the submission path.
typedef void (^WDGOrderReply)(NSDictionary *receipt);

@interface WDGOrderService : NSObject
@property (nonatomic, readonly) NSString *sampleKey;
@property (nonatomic, readonly, nullable) NSNumber *payType;
+ (BOOL)runtimeReady:(NSString * _Nullable * _Nullable)reason;
+ (BOOL)runtimeReady:(NSString * _Nullable * _Nullable)reason;
+ (BOOL)preheatReady:(NSString * _Nullable * _Nullable)reason;
+ (instancetype _Nullable)prepareRequest:(id)request
                           confirmation:(id)confirmation
                              sampleKey:(NSString *)sampleKey
                                payType:(NSNumber *)payType
                                  error:(NSError * _Nullable * _Nullable)error;
// Preheat mode keeps only the App's own requestDO. At fire time it first asks
// the App to confirm, converts the returned dictionary into the confirmation
// model, then submits. Used when the cart is captured well before the sale.
+ (instancetype _Nullable)preparePreheatRequest:(id)request
                                      sampleKey:(NSString *)sampleKey
                                        payType:(NSNumber * _Nullable)payType
                                          error:(NSError * _Nullable * _Nullable)error;
// Configured while the user confirms the cart task. A fresh confirmation is
// required near dueAt; unknown/blocked responses never trigger CreateOrder.
- (BOOL)configureCartDueAt:(NSDate *)dueAt maximumTotal:(NSDecimalNumber *)maximumTotal error:(NSError * _Nullable * _Nullable)error;
// Lane racing is opt-in. 1 is the default and preserves the tested single
// submission. 2 sends two independent CreateOrder requests for the same cart
// template; the server may or may not de-duplicate them.
- (BOOL)configureConcurrentLanes:(NSUInteger)lanes error:(NSError * _Nullable * _Nullable)error;
// Opt-in bounded resend. Only a definite business rejection (proven no order)
// triggers the next wave; success or any unknown/timeout result stops it.
- (BOOL)configureRetryEnabled:(BOOL)enabled attempts:(NSUInteger)attempts error:(NSError * _Nullable * _Nullable)error;
@property (nonatomic, readonly) NSUInteger concurrentLanes;
- (BOOL)submitTask:(NSString *)taskID completion:(WDGOrderReply)completion error:(NSError * _Nullable * _Nullable)error;
- (BOOL)cancelBeforeCreate;
- (void)expireUnresolvedTask:(NSString *)taskID;
+ (void)setExecutionAllowedCheck:(BOOL (^)(void))check;
+ (NSDictionary *)diagnostics;
@end
NS_ASSUME_NONNULL_END
