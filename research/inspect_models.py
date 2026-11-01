"""Read only, bounded inspection of the currently visible order-confirmation models.
Prints class names/counts/ABI and in-memory equality booleans, never IDs, buyers,
addresses, tokens, headers or full object descriptions.
"""
import sys,json,threading
import frida
JS=r'''
ObjC.schedule(ObjC.mainQueue,function(){
 function get(o,s){try{if(!o||o.handle.isNull())return null;return o['- '+s]();}catch(e){return null;}}
 function name(o){return o&&o.$className?o.$className:null;}
 function arr(o){const r=[];try{for(let i=0;i<Math.min(Number(o.count()),80);i++)r.push(o.objectAtIndex_(i));}catch(e){}return r;}
 function text(o,s){const v=get(o,s);return v===null?'':String(v);}
 const queue=[];
 const app=ObjC.classes.UIApplication.sharedApplication();
 try{for(const scene of arr(app.connectedScenes().allObjects()))for(const w of arr(scene.windows())){const root=get(w,'rootViewController');if(root)queue.push(root);}}catch(e){}
 if(!queue.length){const root=get(get(app,'keyWindow'),'rootViewController');if(root)queue.push(root);}
 const seen=new Set();let target=null,steps=0;
 while(queue.length&&steps++<100){const vc=queue.shift(),key=String(vc.handle);if(seen.has(key))continue;seen.add(key);if(name(vc)==='VDTradeConfOrderViewController'){target=vc;break;}const presented=get(vc,'presentedViewController');if(presented)queue.unshift(presented);for(const child of arr(get(vc,'childViewControllers')))queue.push(child);}
 if(!target){send({error:'No ordinary confirmation controller found'});return;}
 const vm=get(target,'viewModel'),request=get(vm,'requestDO'),confirm=get(vm,'confirmOrderDO');
 const requests=arr(get(request,'items')),shops=arr(get(confirm,'shop_list')),items=[];
 shops.forEach(s=>arr(get(s,'item_list')).forEach(i=>items.push(i)));
 function triple(o){return [text(o,'item_id'),text(o,'item_sku_id'),text(o,'quantity')].join('|');}
 const left=requests.map(triple).sort(),right=items.map(triple).sort();
 const result={controller:name(target),vm:name(vm),request:name(request),confirmation:name(confirm),requestItemCount:requests.length,requestItemClasses:[...new Set(requests.map(name))],shopCount:shops.length,shopClasses:[...new Set(shops.map(name))],confirmedItemCount:items.length,confirmedItemClasses:[...new Set(items.map(name))],sameTupleList:JSON.stringify(left)===JSON.stringify(right),hasTotalPrice:!!get(confirm,'total_pay_price'),payOptionCount:arr(get(confirm,'pay_options')).length};
 function modelSummary(o){const ss=arr(get(o,'shop_list'));return {class:name(o),shopCount:ss.length,itemCount:ss.reduce((n,s)=>n+arr(get(s,'item_list')).length,0),hasTotalPrice:!!get(o,'total_pay_price'),payOptionCount:arr(get(o,'pay_options')).length};}
 result.modelSources={vmConfirm:modelSummary(confirm),vmPreConfirm:modelSummary(get(vm,'preConfirmOrderDO')),viewConfirm:modelSummary(get(get(target,'orderView'),'confirmOrderDO')),viewModelFromView:name(get(get(target,'orderView'),'viewModel'))};
 send(result);
});
'''
def main():
    cancel=frida.Cancellable();timer=threading.Timer(25,cancel.cancel);timer.daemon=True;timer.start();session=None
    try:
        with cancel:
            d=frida.get_device_manager().add_remote_device('127.0.0.1:27043')
            p=next(p for p in d.enumerate_processes() if p.name=='WDBuyerUniv');session=d.attach(p.pid)
            sc=session.create_script(JS);event=threading.Event();out={}
            def msg(m,data):
                if m.get('type')=='send':out.update(m['payload']);event.set()
                elif m.get('type')=='error':out['error']=m.get('description');event.set()
            sc.on('message',msg);sc.load();event.wait(12);print(json.dumps(out,ensure_ascii=False,indent=2))
    finally:
        if session:session.detach()
        timer.cancel()
if __name__=='__main__':main()
