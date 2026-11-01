"""Inspect only the installed clock reader and compare local deadline math.
Never arms a task or calls ConfirmOrder/CreateOrder; no OS clock changes.
"""
import argparse,json,threading
from pathlib import Path
import frida
JS=r'''
ObjC.schedule(ObjC.mainQueue,function(){
 try{
  function js(o){const data=ObjC.classes.NSJSONSerialization.dataWithJSONObject_options_error_(o,0,ptr(0));return JSON.parse(ObjC.classes.NSString.alloc().initWithData_encoding_(data,4).toString());}
  const out={};
  const clockPtr=Module.findExportByName(null,'WDGReadServerClock');
  if(!clockPtr){send({error:'Installed clock module not found'});return;}
  const svc=ObjC.classes.WDGOrderService;
  const before=svc?js(svc.diagnostics()):{};
  const sampleObj=new ObjC.Object(new NativeFunction(clockPtr,'pointer',[])());
  out.clock=js(sampleObj);
  const c=ObjC.classes.WDGCore;
  if(c){const status=js(c.shared().status());out.version=status.version;out.build=status.build;out.taskState=status.task.state;}
  if(out.clock.valid){
   const date=ObjC.classes.NSDate.dateWithTimeIntervalSinceNow_(300);
   const error=Memory.alloc(Process.pointerSize);error.writePointer(ptr(0));
   const mapper=Module.findExportByName(null,'WDGLocalDeadlineFromClock');
   const converted=new NativeFunction(mapper,'pointer',['pointer','pointer','pointer'])(date.handle,sampleObj.handle,error);
   if(converted.isNull())out.mappingError=error.readPointer().isNull()?'Mapping returned nil':new ObjC.Object(error.readPointer()).toString();
   else{const local=new ObjC.Object(converted);out.actualAdjustmentMs=(Number(local.timeIntervalSince1970())-Number(date.timeIntervalSince1970()))*1000;out.expectedAdjustmentMs=-out.clock.offsetMs;}
  }
  const after=svc?js(svc.diagnostics()):{};
  out.confirmCallsDelta=(after.confirmCalls||0)-(before.confirmCalls||0);
  out.createCallsDelta=(after.serviceCalls||0)-(before.serviceCalls||0);
  send(out);
 }catch(e){send({error:String(e)});}
});
'''
def main():
 p=argparse.ArgumentParser();p.add_argument('--host',default='127.0.0.1:27043');p.add_argument('--out');p.add_argument('--pid',type=int);a=p.parse_args()
 c=frida.Cancellable();timer=threading.Timer(20,c.cancel);timer.daemon=True;timer.start();s=None
 try:
  with c:
   d=frida.get_device_manager().add_remote_device(a.host)
   pid=a.pid or next(x.pid for x in d.enumerate_processes() if x.name=='WDBuyerUniv')
   s=d.attach(pid);script=s.create_script(JS);ev=threading.Event();out={}
   def msg(m,data):
    if m.get('type')=='send':out.update(m['payload']);ev.set()
    elif m.get('type')=='error':out['error']=m.get('description');ev.set()
   script.on('message',msg);script.load()
   if not ev.wait(8):raise TimeoutError('No read-only clock reply')
   text=json.dumps(out,ensure_ascii=False,indent=2);print(text,flush=True)
   if a.out:
    path=Path(a.out)
    if path.exists():raise RuntimeError('Output exists')
    path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text+'\n',encoding='utf-8')
   return 1 if out.get('error') else 0
 finally:
  if s:
   try:s.detach()
   except Exception:pass
  timer.cancel()
if __name__=='__main__':raise SystemExit(main())
