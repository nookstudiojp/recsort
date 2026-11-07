import {decisionKey,getDecision} from './decisions.mjs';
export function readReviewDates(raw){
 try{const data=JSON.parse(raw);if(!data||typeof data!=='object'||Array.isArray(data))return {};return Object.fromEntries(Object.entries(data).filter(([key,value])=>key.startsWith('[')&&Number.isFinite(value)&&value>=0));}catch{return {};}
}
export function reviewDue(record,decisions,dates,now=Date.now()) { return getDecision(record,decisions)==='later' && (!dates[decisionKey(record)] || dates[decisionKey(record)]<=now); }
export function nextFive(records,decisions,dates,isCandidate,now=Date.now()){
 return records.filter(r=>getDecision(r,decisions)!=='keep'&&(reviewDue(r,decisions,dates,now)||(getDecision(r,decisions)!=='later'&&isCandidate(r))))
 .sort((a,b)=>Number(reviewDue(b,decisions,dates,now))-Number(reviewDue(a,decisions,dates,now))||b.size-a.size||a.path.localeCompare(b.path)).slice(0,5);
}
export function makeSnapshot(records,label,now=Date.now()){
 return JSON.stringify({version:1,saved:now,label:String(label).slice(0,300),records:records.map(({name,path,size,modified})=>({name,path,size,modified}))});
}
export function readSnapshot(raw){
 try{const data=JSON.parse(raw);if(data?.version!==1||!Array.isArray(data.records)||data.records.length>50000||!Number.isFinite(data.saved))return null;
 const records=data.records.filter(r=>typeof r?.name==='string'&&r.name.length<4096&&typeof r.path==='string'&&r.path.length<32768&&Number.isFinite(r.size)&&r.size>=0&&Number.isFinite(r.modified)&&Math.abs(r.modified)<8640000000000000).map((r,i)=>({id:String(i),name:r.name,path:r.path,size:r.size,modified:r.modified,file:null}));
 return {records,saved:data.saved,label:typeof data.label==='string'?data.label.slice(0,300):'保存した一覧'};
 }catch{return null;}
}
export function openHandleStore(){
 return new Promise((resolve,reject)=>{if(!globalThis.indexedDB){reject(Error('保存に対応していません'));return;}const request=indexedDB.open('recsort-folder-v1',1);request.onupgradeneeded=()=>request.result.createObjectStore('folder');request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);});
}
export async function storedFolder(action,handle){
 const db=await openHandleStore();try{return await new Promise((resolve,reject)=>{const tx=db.transaction('folder',action==='get'?'readonly':'readwrite'),store=tx.objectStore('folder');const request=action==='put'?store.put(handle,'last'):action==='clear'?store.delete('last'):store.get('last');let result;request.onsuccess=()=>{result=request.result;};tx.oncomplete=()=>resolve(result);tx.onerror=()=>reject(tx.error);tx.onabort=()=>reject(tx.error||Error('保存を中止しました'));});}finally{db.close();}
}
