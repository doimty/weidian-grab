"""Device smoke tests for local tasks only. Never selects/calls nativeOnce.
--mode cancel: arm +60s, cancel, read state.
--mode background-arm: arm +60s; external Home/app switch must cancel it.
Refuses to replace an already-armed real native task.
"""
import argparse,json,threading
import frida
JS=r'''
ObjC.schedule(ObjC.mainQueue,function(){
 try {
  function ns(s){return ObjC.classes.NSString.stringWithUTF8String_(Memory.allocUtf8String(s));}
  function obj(d){const data=ObjC.classes.NSJSONSerialization.dataWithJSONObject_options_error_(d,0,ptr(0));return JSON.parse(ObjC.classes.NSString.alloc().initWithData_encoding_(data,4).toString());}
  const c=ObjC.classes.WDGCore.shared(),before=obj(c.status());
  if(before.task.state==='armed'&&before.task.action==='nativeOnce'){send({error:'A user native task is armed; test skipped'});return;}
  const error=Memory.alloc(Process.pointerSize);error.writePointer(ptr(0));
  const date=ObjC.classes.NSDate.dateWithTimeIntervalSinceNow_(60);
  const ok=c['- armAt:action:payType:error:'](date,ns('dryRun'),ptr(0),error);
  if(!ok){send({error:'Local dryRun arm failed'});return;}
  const armed=obj(c.status());
  if(MODE==='cancel')c['- cancelTask:'](ns('device cancel smoke test'));
  const state=obj(c.status());
  const diag=Module.findExportByName(null,'WDGObserverDiagnostics');
  const observer=diag?obj(new ObjC.Object(new NativeFunction(diag,'pointer',[])())):{};
  send({mode:MODE,armedState:armed.task.state,resultState:state.task.state,action:state.task.action,reason:state.task.reason||null,taskId:state.task.id,nativeDispatchCount:observer.nativeDispatchCount});
 }catch(e){send({error:String(e)});}
});
'''
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--mode',choices=['cancel','background-arm'],default='cancel');a=ap.parse_args()
    cancel=frida.Cancellable();timer=threading.Timer(25,cancel.cancel);timer.daemon=True;timer.start();s=None
    try:
        with cancel:
            d=frida.get_device_manager().add_remote_device('127.0.0.1:27043');p=next(p for p in d.enumerate_processes() if p.name=='WDBuyerUniv');s=d.attach(p.pid)
            script=s.create_script('const MODE='+json.dumps(a.mode)+';\n'+JS);event=threading.Event();out={}
            def message(m,data):
                if m.get('type')=='send':out.update(m['payload']);event.set()
                elif m.get('type')=='error':out['error']=m.get('description');event.set()
            script.on('message',message);script.load();event.wait(12);print(json.dumps(out,ensure_ascii=False,indent=2))
            if out.get('error'):return 1
            return 0
    finally:
        if s:s.detach()
        timer.cancel()
if __name__=='__main__':raise SystemExit(main())
