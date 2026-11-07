import assert from 'node:assert/strict';
import {scanDirectory,deleteConfirmed} from './dist/file-access.mjs';
import {isVideo} from './dist/core.mjs';
let removes=[];
function fixture({permission='granted',same=true,size=20,modified=100,fail=false}={}){
 const handle={kind:'file',name:'clip.mp4',async getFile(){return {name:this.name,size,lastModified:modified};},async isSameEntry(){return same;}};
 const root={name:'videos',async queryPermission(){return permission;}};
 const parent={async getFileHandle(){return handle;},async removeEntry(name,options){assert.equal(options.recursive,false);if(fail)throw Error('disk error');removes.push(name);}};
 return {id:'0',name:'clip.mp4',size:20,modified:100,handle,parent,root};
}
let n=0;
async function test(name,fn){removes=[];await fn();console.log('PASS',name);n++;}
await test('confirmation required',async()=>{await assert.rejects(()=>deleteConfirmed([fixture()]));assert.equal(removes.length,0);});
await test('kept file protected',async()=>{const r=await deleteConfirmed([fixture()],{confirmed:true,isKept:()=>true});assert.ok(r[0].error);assert.equal(removes.length,0);});
await test('read-only record rejected',async()=>{const r=await deleteConfirmed([{name:'x.mp4'}],{confirmed:true});assert.ok(r[0].error);assert.equal(removes.length,0);});
await test('permission denied',async()=>{const r=await deleteConfirmed([fixture({permission:'denied'})],{confirmed:true});assert.ok(r[0].error);assert.equal(removes.length,0);});
await test('replaced handle rejected',async()=>{const r=await deleteConfirmed([fixture({same:false})],{confirmed:true});assert.ok(r[0].error);assert.equal(removes.length,0);});
await test('changed size rejected',async()=>{const r=await deleteConfirmed([fixture({size:21})],{confirmed:true});assert.ok(r[0].error);assert.equal(removes.length,0);});
await test('changed date rejected',async()=>{const r=await deleteConfirmed([fixture({modified:101})],{confirmed:true});assert.ok(r[0].error);assert.equal(removes.length,0);});
await test('success removes exact file',async()=>{const r=await deleteConfirmed([fixture()],{confirmed:true});assert.equal(r[0].error,null);assert.deepEqual(removes,['clip.mp4']);});
await test('partial failure preserved',async()=>{const r=await deleteConfirmed([fixture({fail:true}),fixture()],{confirmed:true});assert.ok(r[0].error);assert.equal(r[1].error,null);assert.equal(removes.length,1);});
await test('cancel before start',async()=>{const a=new AbortController();a.abort();assert.equal((await deleteConfirmed([fixture()],{confirmed:true,signal:a.signal})).length,0);assert.equal(removes.length,0);});
await test('cancel remaining files',async()=>{const a=new AbortController();const r=await deleteConfirmed([fixture(),fixture()],{confirmed:true,signal:a.signal,onProgress:()=>a.abort()});assert.equal(r.length,1);assert.equal(removes.length,1);});
await test('missing file reported',async()=>{const f=fixture();f.parent.getFileHandle=async()=>{throw Error('not found');};const r=await deleteConfirmed([f],{confirmed:true});assert.ok(r[0].error);assert.equal(removes.length,0);});
await test('nested scan only videos',async()=>{const h=fixture().handle;const sub={name:'sub',kind:'directory',async *values(){yield h;}};const root={name:'root',async *values(){yield {kind:'file',name:'readme.txt'};yield sub;}};const r=await scanDirectory(root,isVideo);assert.equal(r.records.length,1);assert.equal(r.records[0].path,'root/sub/clip.mp4');assert.equal(r.records[0].parent,sub);assert.equal(r.records[0].root,root);});
await test('scan 1700 mocked files',async()=>{const root={name:'root',async *values(){for(let i=0;i<1700;i++)yield {...fixture().handle,name:i+'.mp4'};}};const r=await scanDirectory(root,isVideo);assert.equal(r.records.length,1700);assert.equal(new Set(r.records.map(x=>x.id)).size,1700);});
await test('scan cancellation',async()=>{const a=new AbortController();a.abort();await assert.rejects(()=>scanDirectory({name:'root'},isVideo,{signal:a.signal}),{name:'AbortError'});});
console.log(`${n} file-access scenarios passed (mocks, no real files deleted)`);
