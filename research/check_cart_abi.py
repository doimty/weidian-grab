"""Read-only: print the real type encoding of the cart callback selector.
No method is invoked; only runtime metadata is read.
"""
import json, threading
import frida

JS = r'''
ObjC.schedule(ObjC.mainQueue, function () {
  try {
    var out = {classes: {}};
    var names = ['VDTradeMyCartViewController', 'VDTradeCartListDO', 'VDTradeCartItemDO',
                 'VDTradeCartPartitionDO', 'VDTradeGoodsItemDO'];
    for (var i = 0; i < names.length; i++) {
      var n = names[i];
      var k = ObjC.classes[n];
      if (!k) { out.classes[n] = {present: false}; continue; }
      var info = {present: true, methods: {}};
      if (n === 'VDTradeMyCartViewController') {
        var sel = '- fetchDataSucceed:cartListDO:';
        try {
          var m = k[sel];
          info.methods[sel] = m ? m.implementation : null;
          info.hasSelector = !!m;
        } catch (e) { info.error = String(e); }
      }
      out.classes[n] = info;
    }
    send(out);
  } catch (e) { send({error: String(e)}); }
});
'''

def main():
    cancel = frida.Cancellable()
    timer = threading.Timer(25, cancel.cancel); timer.daemon = True; timer.start()
    s = None
    try:
        with cancel:
            d = frida.get_device_manager().add_remote_device('127.0.0.1:27043')
            p = next(x for x in d.enumerate_processes() if x.name == 'WDBuyerUniv')
            s = d.attach(p.pid)
            sc = s.create_script(JS)
            ev = threading.Event(); box = {}
            def on(m, data):
                if m.get('type') == 'send':
                    box.update(m['payload']); ev.set()
                elif m.get('type') == 'error':
                    box['error'] = m.get('description'); ev.set()
            sc.on('message', on); sc.load(); ev.wait(12)
            print(json.dumps(box, ensure_ascii=False, indent=2))
    finally:
        if s: s.detach()
        timer.cancel()

if __name__ == '__main__':
    main()
