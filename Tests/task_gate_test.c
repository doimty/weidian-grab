#include "../WDGTaskGate.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    WDGTaskGate g={0};
    assert(WDGTaskGateTick(&g,100,1)==WDGTickIdle);
    WDGTaskGateArm(&g,100);
    assert(WDGTaskGateTick(&g,99.99,1)==WDGTickWait && g.armed);
    assert(WDGTaskGateTick(&g,100,1)==WDGTickFire && !g.armed);
    assert(WDGTaskGateTick(&g,100.1,1)==WDGTickIdle);
    WDGTaskGateArm(&g,200);
    assert(WDGTaskGateTick(&g,199,0)==WDGTickInactive && !g.armed);
    assert(WDGTaskGateTick(&g,200,1)==WDGTickIdle);
    WDGTaskGateArm(&g,300);WDGTaskGateCancel(&g);
    assert(WDGTaskGateTick(&g,300,1)==WDGTickIdle);
    WDGTaskGateArm(&g,400);
    assert(WDGTaskGateTick(&g,402.001,1)==WDGTickExpired && !g.armed);
    assert(WDGTaskGateTick(&g,403,1)==WDGTickIdle);
    WDGTaskGateArm(&g,500);
    assert(WDGTaskGateTick(&g,502,1)==WDGTickFire);
    WDGTaskGateArm(&g,NAN);
    assert(WDGTaskGateTick(&g,600,1)==WDGTickExpired);
    WDGTaskGateArm(&g,700);
    assert(WDGTaskGateTick(&g,INFINITY,1)==WDGTickExpired);
    // Replacement tasks only fire at the replacement date.
    WDGTaskGateArm(&g,800);WDGTaskGateCancel(&g);WDGTaskGateArm(&g,900);
    assert(WDGTaskGateTick(&g,800,1)==WDGTickWait);
    assert(WDGTaskGateTick(&g,900,1)==WDGTickFire);
    assert(WDGTaskGateTick(&g,900,1)==WDGTickIdle);
    puts("PASS: 15 production task-gate assertions (no network or purchase calls)");
    return 0;
}
