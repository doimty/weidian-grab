#ifndef WDG_TASK_GATE_H
#define WDG_TASK_GATE_H
#include <math.h>
#include <string.h>
static inline int WDGActionIsInterface(const char *action) {
    return action && (!strcmp(action,"serviceOnce") || !strcmp(action,"preheatOnce"));
}

typedef enum { WDGTickIdle, WDGTickWait, WDGTickFire, WDGTickInactive, WDGTickExpired } WDGTickDecision;
typedef struct { int armed; double dueAt; } WDGTaskGate;
static inline void WDGTaskGateArm(WDGTaskGate *gate, double dueAt) {gate->dueAt=dueAt;gate->armed=1;}
static inline void WDGTaskGateCancel(WDGTaskGate *gate) {gate->armed=0;}
// Main-queue owner only. A due task is consumed before the caller dispatches any
// action, so another tick can never execute the same task for a second time.
static inline WDGTickDecision WDGTaskGateTick(WDGTaskGate *gate, double now, int active) {
    if(!gate->armed)return WDGTickIdle;
    if(!active){gate->armed=0;return WDGTickInactive;}
    if(!isfinite(now)||!isfinite(gate->dueAt)){gate->armed=0;return WDGTickExpired;}
    if(now<gate->dueAt)return WDGTickWait;
    gate->armed=0;
    return now-gate->dueAt>2.0?WDGTickExpired:WDGTickFire;
}
#endif
