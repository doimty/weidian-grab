"""Read-only ABI readiness check for the native CreateOrder service.
Calls only +[WDGOrderService runtimeReady:] and +[WDGOrderService diagnostics].
Never calls createOrderRequestDO:confirmOrderDO:result: or any network method.
"""
import json, threading
import frida

JS = r'''
ObjC.schedule(ObjC.mainQueue, function () {
  var out = {};
  try {
    var cls = ObjC.classes.WDGOrderService;
    if (!cls) { send({error: 'WDGOrderService missing'}); return; }
    var reasonPtr = Memory.alloc(Process.pointerSize);
    reasonPtr.writePointer(ptr(0));
    out.ready = cls['+ runtimeReady:'](reasonPtr);
    var r = reasonPtr.readPointer();
    out.reason = r.isNull() ? null : new ObjC.Object(r).toString();
    out.diagnostics = new ObjC.Object(cls['+ diagnostics']()).$className;
    var d = ObjC.classes.NSJSONSerialization.dataWithJSONObject_options_error_(cls['+ diagnostics'](), 0, ptr(0));
    out.diag = JSON.parse(ObjC.classes.NSString.alloc().initWithData_encoding_(d, 4).toString());
    var svc = ObjC.classes.VDTradeConfOrderService;
    var m = svc ? svc['+ createOrderRequestDO:confirmOrderDO:result:'] : null;
    out.servicePresent = !!svc;
    out.createSelectorPresent = !!m;
    send(out);
  } catch (e) { send({error: String(e)}); }
});
'''

def main():
    cancel = frida.Cancellable()
    timer = threading.Timer(25, cancel.cancel); timer.daemon = True; timer.start()
    session = None
    try:
        with cancel:
            dev = frida.get_device_manager().add_remote_device('127.0.0.1:27043')
            proc = next(p for p in dev.enumerate_processes() if p.name == 'WDBuyerUniv')
            session = dev.attach(proc.pid)
            script = session.create_script(JS)
            ev = threading.Event(); box = {}
            def on_msg(m, data):
                if m.get('type') == 'send':
                    box.update(m['payload']); ev.set()
                elif m.get('type') == 'error':
                    box['error'] = m.get('description'); ev.set()
            script.on('message', on_msg); script.load()
            ev.wait(12)
            print(json.dumps(box, ensure_ascii=False, indent=2))
    finally:
        if session:
            session.detach()
        timer.cancel()

if __name__ == '__main__':
    main()
