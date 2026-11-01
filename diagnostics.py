"""Read-only runtime metadata probe. Never invokes order/purchase methods or reads headers/bodies."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import sys
import threading
import frida

JS = r'''
const api = n => Module.findExportByName(null, n);
const cgi = new NativeFunction(api('class_getInstanceMethod'), 'pointer', ['pointer','pointer']);
const cgc = new NativeFunction(api('class_getClassMethod'), 'pointer', ['pointer','pointer']);
const mgt = new NativeFunction(api('method_getTypeEncoding'), 'pointer', ['pointer']);
const mgi = new NativeFunction(api('method_getImplementation'), 'pointer', ['pointer']);
const sel = new NativeFunction(api('sel_registerName'), 'pointer', ['pointer']);
const targets = {
 'VDTradeConfOrderService':['+ confirmOrderWithRequestDO:result:','+ reconfirmOrderRequestDO:confirmOrderDO:result:','+ createOrderRequestDO:confirmOrderDO:result:'],
 'VDTradeConfOrderViewModel':['- initWithRequest:','- requestConfirmOrder:','- createOrder:result:','- setRequestDO:','- setConfirmOrderDO:'],
 'VDTradeConfOrderViewController':['- viewDidAppear:','- createOrder:','- createRealOrder:','- createOrderFinish:isSuccess:error:payButtonType:'],
 'VDTradeQuickOrderView':['- show','- createOrder:','- createRealOrder:','- viewModel'],
 'VDConfQuickOrderViewModel':['- requestConfirmOrder:','- createOrder:result:','- requestDO','- setRequestDO:'],
 'NSURLSession':['- dataTaskWithRequest:','- dataTaskWithRequest:completionHandler:']
};
const result = {pid:Process.id, classes:{}, tweakModules:[]};
for (const cname in targets) {
 const k=ObjC.classes[cname];
 if (!k) {result.classes[cname]={present:false}; continue;}
 const detail={present:true,methods:[]};
 for (const s of targets[cname]) {
  const sp=sel(Memory.allocUtf8String(s.substring(2)));
  const mp=(s[0]==='+'?cgc:cgi)(k.handle,sp);
  if(mp.isNull()) {detail.methods.push({selector:s,present:false});continue;}
  const imp=mgi(mp), mod=Process.findModuleByAddress(imp);
  detail.methods.push({selector:s,present:true,types:mgt(mp).readUtf8String(),image:mod?mod.name:null});
 }
 result.classes[cname]=detail;
}
result.tweakModules=Process.enumerateModules().filter(m=>/WeidianGrab|AutoPatches|libjoker/i.test(m.name)).map(m=>({name:m.name,path:m.path}));
const hd=api('NSHomeDirectory');
try {if(hd)result.home=new ObjC.Object(new NativeFunction(hd,'pointer',[])()).toString();}catch(e){result.homeError=String(e);}
const obs=Module.findExportByName(null,'WDGObserverDiagnostics');
if(obs){
 try{
  const value=new ObjC.Object(new NativeFunction(obs,'pointer',[])());
  const data=ObjC.classes.NSJSONSerialization.dataWithJSONObject_options_error_(value,0,ptr(0));
  const text=ObjC.classes.NSString.alloc().initWithData_encoding_(data,4).toString();
  result.observer=JSON.parse(text);
 }catch(e){result.observerError=String(e);}
}
send({kind:'metadata',data:result});
'''

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--host',default='127.0.0.1:27043')
    parser.add_argument('--out',default=str(Path(__file__).parent/'research'/'runtime-metadata.json'))
    parser.add_argument('--timeout',type=int,default=25)
    args=parser.parse_args()
    cancellable=frida.Cancellable()
    def deadline():
        print('Runtime probe deadline: cancelling current operation',file=sys.stderr,flush=True)
        cancellable.cancel()
    timer=threading.Timer(args.timeout,deadline);timer.daemon=True;timer.start()
    session=None
    try:
        with cancellable:
            print('Connecting to Frida tunnel',flush=True)
            dev=frida.get_device_manager().add_remote_device(args.host)
            print('Enumerating target process',flush=True)
            procs=[p for p in dev.enumerate_processes() if p.name=='WDBuyerUniv']
            if not procs:
                print('Weidian is not running',flush=True)
                return 2
            print('Attaching to pid',procs[0].pid,flush=True)
            session=dev.attach(procs[0].pid)
        script=session.create_script(JS)
        event=threading.Event();box={}
        def message(m,data):
            if m.get('type')=='send' and m.get('payload',{}).get('kind')=='metadata':
                box.update(m['payload']['data']);event.set()
            elif m.get('type')=='error':
                box['error']=m.get('description');event.set()
        script.on('message',message);script.load()
        if not event.wait(10):raise TimeoutError('No introspection reply')
        if 'error' in box:raise RuntimeError(box['error'])
        out=Path(args.out);out.parent.mkdir(parents=True,exist_ok=True)
        out.write_text(json.dumps(box,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps(box,ensure_ascii=False,indent=2),flush=True)
        return 0
    finally:
        if session:
            try:session.detach()
            except Exception:pass
        timer.cancel()

if __name__=='__main__':raise SystemExit(main())
