#include "../WDGServiceState.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    WDGServiceState s = {0};
    // Cannot dispatch without preparing.
    assert(WDGServiceDispatch(&s, 1) == 0);
    // Prepare then dispatch exactly once per generation.
    assert(WDGServicePrepare(&s, 1) == 1);
    assert(s.phase == WDGServicePrepared);
    assert(WDGServiceDispatch(&s, 2) == 0);            // stale generation
    assert(WDGServiceDispatch(&s, 1) == 1);
    assert(s.phase == WDGServiceSending && s.dispatches == 1);
    assert(WDGServiceDispatch(&s, 1) == 0);            // no double send
    assert(s.dispatches == 1);
    // Cannot prepare over an in-flight send.
    assert(WDGServicePrepare(&s, 9) == 0);
    assert(s.phase == WDGServiceSending);
    // Cancel after send is refused (the request is already out).
    assert(WDGServiceCancelBeforeDispatch(&s) == 0);
    assert(s.phase == WDGServiceSending);
    // Exactly one accepted result.
    assert(WDGServiceResolve(&s, 1, 1) == 1);
    assert(s.phase == WDGServiceAPIResult && s.acceptedResults == 1);
    assert(WDGServiceResolve(&s, 1, 1) == 0);          // duplicate callback
    assert(WDGServiceResolve(&s, 1, 0) == 0);
    assert(s.acceptedResults == 1);

    // Timeout first, then a late real result still counts once.
    WDGServiceState t = {0};
    assert(WDGServicePrepare(&t, 5) == 1);
    assert(WDGServiceDispatch(&t, 5) == 1);
    assert(WDGServiceTimeout(&t, 4) == 0);             // wrong generation
    assert(WDGServiceTimeout(&t, 5) == 1);
    assert(t.phase == WDGServiceUnknown);
    assert(WDGServiceResolve(&t, 5, 1) == 1);
    assert(t.phase == WDGServiceAPIResult && t.acceptedResults == 1);
    assert(WDGServiceResolve(&t, 5, 1) == 0);

    // Cancel before dispatch is allowed and returns to idle.
    WDGServiceState u = {0};
    assert(WDGServicePrepare(&u, 7) == 1);
    assert(WDGServiceCancelBeforeDispatch(&u) == 1);
    assert(u.phase == WDGServiceIdle);
    assert(WDGServiceDispatch(&u, 7) == 0);            // cancelled task never sends

    // A failure result is distinct from API success.
    WDGServiceState v = {0};
    assert(WDGServicePrepare(&v, 11) == 1);
    assert(WDGServiceDispatch(&v, 11) == 1);
    assert(WDGServiceResolve(&v, 11, 0) == 1);
    assert(v.phase == WDGServiceFailed);

    // A new generation after completion can be prepared again.
    assert(WDGServicePrepare(&v, 12) == 1);
    assert(WDGServiceDispatch(&v, 12) == 1);

    puts("PASS: 24 interface-state assertions (single send, no retry, late reply)");
    return 0;
}
