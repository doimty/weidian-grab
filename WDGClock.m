#import "WDGClock.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>
#import <string.h>

// Buyer 7.9.62 offline evidence:
// currentServerTime 0x10587bdd8 = local wall ms + timeOffsetMS.
// updateServerTime: 0x10587bf04 enqueues serverTimeMS=received value and
// timeOffsetMS=receivedServerMs-currentLocalMs. init restores ONLY offset from
// defaults, not serverTimeMS, so an offset (even zero) is not proof of freshness.
static const double WGCMaxOffsetMs = 60000.0;
static const double WGCMaxNativeAgeMs = 600000.0;
static const double WGCMaxReadMs = 50.0;
static const double WGCMaxSnapshotAge = 5.0;
static const double WGCJumpToleranceMs = 250.0;

@interface WDGClockState : NSObject @end
@implementation WDGClockState @end
static BOOL gHavePreviousRead;
static double gPreviousWallMs, gPreviousUptime;
static long long gLastMarker, gInvalidMarker;
static BOOL gRequireNewMarker;
static NSUInteger gClockGeneration;

static double WGCWallMs(void) { return NSDate.date.timeIntervalSince1970 * 1000.0; }
static double WGCUptime(void) { return NSProcessInfo.processInfo.systemUptime; }
static const char *WGCUnqualified(const char *type) {
    if (!type) return "";
    while (*type && strchr("rnNoORV", *type)) ++type;
    return type;
}
static BOOL WGCObjectType(const char *type) {
    type = WGCUnqualified(type);
    return type[0] == '@' && (type[1] == '\0' || type[1] == '"');
}
static BOOL WGCReturns(Method m, unsigned int count, char expected) {
    if (!m || method_getNumberOfArguments(m) != count) return NO;
    char encoding[256] = {0};
    method_getReturnType(m, encoding, sizeof(encoding));
    const char *type = WGCUnqualified(encoding);
    return expected == '@' ? WGCObjectType(type) : (type[0] == expected && type[1] == '\0');
}
static NSDictionary *WGCInvalid(NSMutableDictionary *sample, NSString *status, NSString *reason) {
    sample[@"valid"] = @NO;
    sample[@"offsetMs"] = NSNull.null;
    sample[@"status"] = status;
    sample[@"reason"] = reason;
    return [sample copy];
}
static BOOL WGCRealisticEpoch(double ms) {
    // Reject seconds mistaken for milliseconds, zero initialization and overflow.
    return isfinite(ms) && ms >= 946684800000.0 && ms <= 4102444800000.0;
}
static NSDictionary *WGCReadLocked(void) {
    NSMutableDictionary *sample = [@{
        @"valid":@NO, @"status":@"unavailable", @"offsetMs":NSNull.null,
        @"source":@"WDTNServerClockProofreader",
        @"sampledAt":@(NSDate.date.timeIntervalSince1970),
        @"sampledUptime":@(WGCUptime()), @"ageMs":NSNull.null,
        @"readDurationMs":@0, @"clockGeneration":@(gClockGeneration),
        @"accuracy":@"network latency and clock accuracy not measured"
    } mutableCopy];
    Class cls = NSClassFromString(@"WDTNServerClockProofreader");
    SEL sharedSel = NSSelectorFromString(@"sharedInstance");
    Method shared = cls ? class_getClassMethod(cls, sharedSel) : NULL;
    if (!WGCReturns(shared, 2, '@')) return WGCInvalid(sample,@"unavailable",@"微店时钟读取器尚未就绪，使用手机时间");

    id clock = nil;
    @try { clock = ((id (*)(id,SEL))objc_msgSend)((id)cls, sharedSel); }
    @catch (__unused NSException *e) { return WGCInvalid(sample,@"unavailable",@"微店时钟读取异常，使用手机时间"); }
    if (!clock || ![clock isKindOfClass:cls]) return WGCInvalid(sample,@"unavailable",@"微店时钟实例缺失，使用手机时间");
    SEL offsetSel = NSSelectorFromString(@"timeOffsetMS");
    SEL serverSel = NSSelectorFromString(@"currentServerTime");
    SEL markerSel = NSSelectorFromString(@"serverTimeMS");
    Class runtimeClass = object_getClass(clock);
    if (!WGCReturns(class_getInstanceMethod(runtimeClass,offsetSel),2,'q') ||
        !WGCReturns(class_getInstanceMethod(runtimeClass,serverSel),2,'q') ||
        !WGCReturns(class_getInstanceMethod(runtimeClass,markerSel),2,'q')) {
        return WGCInvalid(sample,@"unavailable",@"微店时钟方法类型未匹配，使用手机时间");
    }

    long long offBefore=0, offAfter=0, markerBefore=0, markerAfter=0, serverNow=0;
    double wall0=WGCWallMs(), uptime0=WGCUptime();
    @try {
        offBefore=((long long (*)(id,SEL))objc_msgSend)(clock,offsetSel);
        markerBefore=((long long (*)(id,SEL))objc_msgSend)(clock,markerSel);
        // Native code synchronizes this read on its own small serial queue.
        // This accessor never makes a network request.
        serverNow=((long long (*)(id,SEL))objc_msgSend)(clock,serverSel);
        offAfter=((long long (*)(id,SEL))objc_msgSend)(clock,offsetSel);
        markerAfter=((long long (*)(id,SEL))objc_msgSend)(clock,markerSel);
    } @catch (__unused NSException *e) { return WGCInvalid(sample,@"unavailable",@"微店时钟取值异常，使用手机时间"); }
    double uptime1=WGCUptime(), wall1=WGCWallMs();
    double elapsedMs=(uptime1-uptime0)*1000.0;
    sample[@"sampledAt"]=@(wall1/1000.0);
    sample[@"sampledUptime"]=@(uptime1);
    sample[@"readDurationMs"]=@(elapsedMs);
    sample[@"rawOffsetMs"]=@(offAfter);
    sample[@"updatedAtServerMs"]=@(markerAfter);

    BOOL wallChanged = !isfinite(wall0) || !isfinite(wall1) || !isfinite(uptime1) ||
        fabs((wall1-wall0)-elapsedMs)>WGCJumpToleranceMs;
    if (gHavePreviousRead) {
        wallChanged = wallChanged || uptime1<gPreviousUptime ||
            fabs((wall1-gPreviousWallMs)-(uptime1-gPreviousUptime)*1000.0)>WGCJumpToleranceMs;
    }
    gHavePreviousRead=YES;gPreviousWallMs=wall1;gPreviousUptime=uptime1;gLastMarker=markerAfter;
    if (wallChanged) {
        ++gClockGeneration;gRequireNewMarker=YES;gInvalidMarker=markerAfter;
        sample[@"clockGeneration"]=@(gClockGeneration);
        return WGCInvalid(sample,@"clock_changed",@"系统时间已变化，等待微店获得新校准样本");
    }
    if (gRequireNewMarker) {
        if (!gInvalidMarker) gInvalidMarker=markerAfter;
        if (markerAfter<=0 || markerAfter==gInvalidMarker) {
            return WGCInvalid(sample,@"clock_changed",@"旧时钟样本已失效，等待微店更新");
        }
        gRequireNewMarker=NO;
    }
    if (elapsedMs<0 || elapsedMs>WGCMaxReadMs || offBefore!=offAfter || markerBefore!=markerAfter) {
        return WGCInvalid(sample,@"unstable",@"读取期间时钟正在更新，请稍后再读");
    }
    if (!WGCRealisticEpoch((double)serverNow) || fabs((double)offAfter)>WGCMaxOffsetMs) {
        return WGCInvalid(sample,@"out_of_range",@"时钟单位或偏差异常，使用手机时间");
    }
    // Native offset can be restored from an earlier launch. Without this
    // process's serverTimeMS marker the original reader is just a cached clock.
    if (markerAfter<=0) return WGCInvalid(sample,@"cache_only",@"只有微店历史缓存，尚无本次有效校准样本");
    if (!WGCRealisticEpoch((double)markerAfter)) return WGCInvalid(sample,@"out_of_range",@"原生校准时间格式异常，使用手机时间");
    double localFromServer=(double)serverNow-(double)offAfter;
    if (localFromServer < wall0-2.0 || localFromServer > wall1+2.0) {
        return WGCInvalid(sample,@"unstable",@"服务器时钟读数与缓存偏差不一致，使用手机时间");
    }
    double nativeAgeMs=(double)serverNow-(double)markerAfter;
    sample[@"ageMs"]=@(MAX(0.0,nativeAgeMs));
    if (nativeAgeMs < -2000.0) return WGCInvalid(sample,@"future",@"原生校准样本来自未来时刻，使用手机时间");
    if (nativeAgeMs > WGCMaxNativeAgeMs) return WGCInvalid(sample,@"stale",@"微店校准样本超过十分钟，使用手机时间");

    sample[@"offsetMs"]=@(offAfter); // Never use a noisy post-call subtraction.
    sample[@"observedOffsetMs"]=@((double)serverNow-(wall0+wall1)/2.0);
    sample[@"valid"]=@YES;sample[@"status"]=@"native_recent";
    sample[@"reason"]=@"读取微店最近校准缓存；未测量网络延迟或绝对精度";
    return [sample copy];
}
NSDictionary *WDGReadServerClock(void) {
    @synchronized (WDGClockState.class) { return WGCReadLocked(); }
}
long long WDGServerClockOffsetMs(BOOL *valid) {
    NSDictionary *sample=WDGReadServerClock();
    BOOL ok=[sample[@"valid"] boolValue];
    if(valid)*valid=ok;return ok?[sample[@"offsetMs"] longLongValue]:0;
}
void WDGInvalidateServerClock(void) {
    @synchronized (WDGClockState.class) {
        ++gClockGeneration;gRequireNewMarker=YES;gInvalidMarker=gLastMarker;
        gHavePreviousRead=NO;
    }
}
NSDate *WDGLocalDeadlineFromClock(NSDate *serverDate, NSDictionary *sample, NSString **reason) {
#define WGC_INVALID(message) do { if(reason)*reason=(message); return nil; } while(0)
    if (![serverDate isKindOfClass:NSDate.class] || !isfinite(serverDate.timeIntervalSince1970)) WGC_INVALID(@"任务时间格式无效");
    if (![sample isKindOfClass:NSDictionary.class] || ![sample[@"valid"] isKindOfClass:NSNumber.class] || ![sample[@"valid"] boolValue]) WGC_INVALID(@"尚无有效校准样本");
    NSNumber *offset=sample[@"offsetMs"],*wall=sample[@"sampledAt"],*uptime=sample[@"sampledUptime"];
    if (![offset isKindOfClass:NSNumber.class] || ![wall isKindOfClass:NSNumber.class] || ![uptime isKindOfClass:NSNumber.class]) WGC_INVALID(@"校准样本字段不完整");
    double delta=offset.doubleValue, t0=wall.doubleValue, u0=uptime.doubleValue;
    if (!isfinite(delta) || fabs(delta)>WGCMaxOffsetMs || trunc(delta)!=delta ||
        CFGetTypeID((__bridge CFTypeRef)offset)==CFBooleanGetTypeID() || !isfinite(t0) || !isfinite(u0)) WGC_INVALID(@"校准偏差格式无效");
    @synchronized (WDGClockState.class) {
        NSNumber *epoch=sample[@"clockGeneration"];
        if (gRequireNewMarker || (epoch && epoch.unsignedIntegerValue!=gClockGeneration)) WGC_INVALID(@"系统时间改变后，旧校准样本已失效");
    }
    double age=WGCUptime()-u0, wallAge=NSDate.date.timeIntervalSince1970-t0;
    if (age < -0.01 || age > WGCMaxSnapshotAge) WGC_INVALID(@"读取样本已过期，请重新读取微店时钟");
    if (fabs(wallAge-age)>WGCJumpToleranceMs/1000.0) WGC_INVALID(@"读取后系统时间已变化，请重新确认");
    NSTimeInterval local=serverDate.timeIntervalSince1970-delta/1000.0;
    if (!isfinite(local)) WGC_INVALID(@"校正后的时间无效");
    if(reason)*reason=nil;
    return [NSDate dateWithTimeIntervalSince1970:local];
#undef WGC_INVALID
}
