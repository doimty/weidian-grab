#ifndef WDG_SERVICE_STATE_H
#define WDG_SERVICE_STATE_H
#include <stdint.h>

typedef enum {
    WDGServiceIdle, WDGServicePrepared, WDGServiceSending,
    WDGServiceAPIResult, WDGServiceFailed, WDGServiceUnknown
} WDGServicePhase;

typedef struct {
    WDGServicePhase phase;
    uint64_t generation;
    unsigned int dispatches;
    unsigned int acceptedResults;
} WDGServiceState;

static inline int WDGServicePrepare(WDGServiceState *s, uint64_t generation) {
    if (s->phase == WDGServiceSending) return 0;
    s->phase=WDGServicePrepared; s->generation=generation;
    s->dispatches=0; s->acceptedResults=0;
    return 1;
}
static inline int WDGServiceDispatch(WDGServiceState *s, uint64_t generation) {
    if (s->phase!=WDGServicePrepared || s->generation!=generation || s->dispatches) return 0;
    s->phase=WDGServiceSending; ++s->dispatches;
    return 1;
}
static inline int WDGServiceResolve(WDGServiceState *s, uint64_t generation, int success) {
    if ((s->phase!=WDGServiceSending && s->phase!=WDGServiceUnknown) || s->generation!=generation || s->acceptedResults) return 0;
    ++s->acceptedResults;
    s->phase=success?WDGServiceAPIResult:WDGServiceFailed;
    return 1;
}
static inline int WDGServiceTimeout(WDGServiceState *s, uint64_t generation) {
    if (s->phase!=WDGServiceSending || s->generation!=generation) return 0;
    s->phase=WDGServiceUnknown;
    return 1;
}
static inline int WDGServiceCancelBeforeDispatch(WDGServiceState *s) {
    if (s->phase==WDGServiceSending) return 0;
    s->phase=WDGServiceIdle;
    return 1;
}
#endif
