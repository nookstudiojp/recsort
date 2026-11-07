import {getDecision} from './decisions.mjs';
export const EXTENSIONS = new Set(['mp4','mkv','mov','avi','ts','mts','m2ts','webm','m4v','wmv']);
export const isVideo = (name,mime='') => mime.toLowerCase().startsWith('video/') || EXTENSIONS.has(name.split('.').pop().toLowerCase());
export function reasons(record, days=90, gb=2, now=Date.now()) {
  const result=[];
  const age=Math.max(0,Math.floor((now-record.modified)/86400000));
  if (age>=days) result.push(`${age}日以上経過`);
  if (record.size>=gb*1024**3) result.push(`${gb} GB以上`);
  if (record.size===0) result.push('0バイト・録画失敗の可能性');
  return result;
}
export function formatSize(bytes) {
  let n=bytes; let i=0;
  const units=['B','KB','MB','GB','TB'];
  while(n>=1024 && i<units.length-1){n/=1024;i++;}
  return [n.toLocaleString('ja-JP',{maximumFractionDigits:1}), units[i]];
}
// Prevent spreadsheet formula execution when opening CSV containing user filenames.
export function csvCell(value) {
  let s=String(value);
  if (/^[\s]*[=+@\-]/.test(s)||/^[\t\r\n]/.test(s)) s="'"+s;
  return '"'+s.replaceAll('"','""')+'"';
}
export function makeCSV(records,days,gb,now=Date.now(),decisions={},reviewDates={}) {
  const rows=[['ファイルパス','容量（バイト）','最終更新日時','整理候補の理由','判断','見直し日'],...records.map(r=>[r.path,r.size,new Date(r.modified).toISOString(),reasons(r,days,gb,now).join(' / ')||'条件該当なし',({keep:'残す',later:'あとで確認',none:'未整理'})[getDecision(r,decisions)],getDecision(r,decisions)==='later'&&Number.isFinite(reviewDates[JSON.stringify([r.path,r.size,r.modified])])?new Date(reviewDates[JSON.stringify([r.path,r.size,r.modified])]).toISOString():''])];
  return '\uFEFF'+rows.map(row=>row.map(csvCell).join(',')).join('\r\n');
}
export function demoRecords(now=Date.now()) {
  return [ ['ゲーム実況_2026-06-15.mp4',4.8,141,'ゲーム実況'],['講義_プログラミング入門.mkv',.7,12,'授業'],['録画テスト_失敗.ts',0,2,'テスト'],['旅行の思い出.mov',2.4,38,'思い出'],['配信アーカイブ.mp4',1.3,110,'配信'],['学校発表_リハーサル.mp4',.15,1,'学校']].map(([name,gb,age,dir],id)=>({id:String(id),name,path:`サンプル録画/${dir}/${name}`,size:Math.round(gb*1024**3),modified:now-age*86400000,file:null}));
}
