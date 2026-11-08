import {getDecision} from './decisions.mjs';
const CHUNK=1024*1024,EDGE=64*1024;
function check(signal){if(signal?.aborted)throw new DOMException('中止しました','AbortError');}
async function fingerprint(file,signal){
 check(signal);const first=new Uint8Array(await file.slice(0,EDGE).arrayBuffer());const last=new Uint8Array(await file.slice(Math.max(0,file.size-EDGE)).arrayBuffer());
 const bytes=new Uint8Array(first.length+last.length);bytes.set(first);bytes.set(last,first.length);
 return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),v=>v.toString(16).padStart(2,'0')).join('');
}
export async function sameFileBytes(a,b,signal){
 if(a.size!==b.size)return false;
 for(let offset=0;offset<a.size;offset+=CHUNK){
  check(signal);const [ab,bb]=await Promise.all([a.slice(offset,offset+CHUNK).arrayBuffer(),b.slice(offset,offset+CHUNK).arrayBuffer()]);const x=new Uint8Array(ab),y=new Uint8Array(bb);if(x.length!==y.length)return false;
  for(let i=0;i<x.length;i++)if(x[i]!==y[i])return false;
  await new Promise(resolve=>setTimeout(resolve,0));
 }
 check(signal);return true;
}
export async function findDuplicates(records,{signal,onProgress=()=>{}}={}){
 const groups=[],sizes=new Map();let skipped=0,processed=0;
 for(const r of records){if(!r.file||!r.size){skipped++;continue;}const bucket=sizes.get(r.size)||[];bucket.push(r);sizes.set(r.size,bucket);}
 const work=[...sizes.values()].filter(list=>list.length>1);const total=work.reduce((n,list)=>n+list.length,0);
 for(const list of work){
  const buckets=new Map();
  for(const r of list){check(signal);try{const key=await fingerprint(r.file,signal),bucket=buckets.get(key)||[];bucket.push(r);buckets.set(key,bucket);}catch(e){if(e.name==='AbortError')throw e;skipped++;}processed++;onProgress(processed,total);}
  for(const candidates of buckets.values()){
   const exact=[];
   for(const r of candidates){
    check(signal);let placed=false;
    for(const group of exact){try{if(await sameFileBytes(r.file,group[0].file,signal)){group.push(r);placed=true;break;}}catch(e){if(e.name==='AbortError')throw e;skipped++;placed=true;break;}}
    if(!placed)exact.push([r]);
   }
   groups.push(...exact.filter(g=>g.length>1));
  }
 }
 return {groups,skipped,processed};
}
export function duplicateCopies(groups,decisions={}){
 return groups.flatMap(group=>{const keeper=group.find(r=>getDecision(r,decisions)==='keep')||group[0];return group.filter(r=>r!==keeper&&getDecision(r,decisions)!=='keep');});
}
