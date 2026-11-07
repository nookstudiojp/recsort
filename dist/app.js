import {readReviewDates,reviewDue,nextFive,makeSnapshot,readSnapshot,storedFolder} from './workflow.mjs';
import {isVideo,reasons,formatSize,makeCSV,demoRecords} from './core.mjs';
import {decisionKey,getDecision,canSelect,readDecisions,setDecision} from './decisions.mjs';
import {scanDirectory,deleteConfirmed} from './file-access.mjs';
const $=id=>document.getElementById(id);
const STORAGE_KEY='recsort-decisions-v1',REVIEW_KEY='recsort-review-dates-v1',SNAPSHOT_KEY='recsort-library-snapshot-v1';
let savedReviewDates={},demoReviewDates={},lastSnapshot=null,rememberedRoot=null;
try{savedReviewDates=readReviewDates(localStorage.getItem(REVIEW_KEY));lastSnapshot=readSnapshot(localStorage.getItem(SNAPSHOT_KEY));}catch{}
const reviewDates=()=>mode==='demo'?demoReviewDates:savedReviewDates;
const saveReviewDates=()=>{if(mode!=='demo')try{localStorage.setItem(REVIEW_KEY,JSON.stringify(savedReviewDates));}catch{storageOK=false;}};
let savedDecisions=Object.create(null),demoDecisions=Object.create(null),storageOK=true;
try{savedDecisions=readDecisions(localStorage.getItem(STORAGE_KEY));}catch{storageOK=false;}
let view='all',page=0,activeRecord=null,undo=null,toastTimer=null;
const PAGE_SIZE=50;
const decisions=()=>mode==='demo'?demoDecisions:savedDecisions;
const decision=r=>getDecision(r,decisions());
const selectable=r=>canSelect(r,decisions());
const isCandidate=(r,days,gb)=>selectable(r)&&(decision(r)!=='later'||reviewDue(r,decisions(),reviewDates()))&&reasons(r,days,gb).length>0;
const chosenRecords=()=>records.filter(r=>selected.has(r.id)&&selectable(r));
function saveDecisions(){try{localStorage.setItem(STORAGE_KEY,JSON.stringify(savedDecisions));storageOK=true;}catch{storageOK=false;}}
function showToast(message,allowUndo=true){clearTimeout(toastTimer);$('toastText').textContent=message;$('undoButton').hidden=!allowUndo;$('toast').hidden=false;toastTimer=setTimeout(()=>{$('toast').hidden=true;},8000);}

let accessRoot=null,deleteBusy=false,scanBusy=false,deleteAbort=null,reviewRecords=[];
let records=[],selected=new Set(),mode='empty',matching=[],visible=[],previewURL=null,exportURL=null,loadSequence=0;
const units=n=>formatSize(n).join(' ');
const thresholds=()=>[Number($('days').value)||90,Number($('size').value)||2];
function element(tag,text,className){const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(className)e.className=className;return e;}
function metric(id,n){const [value,unit]=formatSize(n);$(id).replaceChildren(document.createTextNode(value+' '),element('small',unit));}
function updateSelection(){
  const chosen=chosenRecords();
  $('selectedCount').textContent=`${chosen.length} 件を選択`;
  $('selectedSize').textContent=`合計 ${units(chosen.reduce((s,r)=>s+r.size,0))}`;
  $('reviewButton').disabled=!chosen.length;
  $('clearSelection').disabled=!chosen.length;
  const eligible=visible.filter(selectable);
  $('selectAll').disabled=!eligible.length;
  $('selectAll').checked=eligible.length>0&&eligible.every(r=>selected.has(r.id));
  $('selectAll').indeterminate=eligible.some(r=>selected.has(r.id))&&!$('selectAll').checked;
  const visibleIDs=new Set(visible.map(r=>r.id));const hidden=chosen.filter(r=>!visibleIDs.has(r.id)).length;
  $('hiddenSelection').textContent=hidden?`うち非表示 ${hidden} 件`:'';
}
function render(){
  const [days,gb]=thresholds();
  const candidates=records.filter(r=>isCandidate(r,days,gb));
  const due=records.filter(r=>reviewDue(r,decisions(),reviewDates()));
  $('coachTitle').textContent=due.length?`見直し時期の動画が ${due.length} 件あります。`:'まずは5本、見直そう。';
  $('coachText').textContent=mode==='snapshot'?'保存した一覧を表示中。再生・削除は元動画を選び直してから。':`${records.filter(r=>decision(r)==='keep').length} 件を「残す」に設定。期限が来ても自動で削除しません。`;
  $('dueReview').disabled=!due.length;$('dueReview').textContent=`見直し時期 ${due.length} 件を見る`;
  $('nextFive').disabled=!nextFive(records,decisions(),reviewDates(),r=>isCandidate(r,days,gb)).length;
  $('saveList').disabled=mode==='demo'||!records.length;$('restoreList').disabled=!lastSnapshot;
  $('rememberFolder').hidden=!accessRoot;$('forgetFolder').hidden=!rememberedRoot;

  $('totalCount').replaceChildren(document.createTextNode(records.length+' '),element('small','件'));
  $('candidateCount').replaceChildren(document.createTextNode(candidates.length+' '),element('small','件'));
  metric('totalSize',records.reduce((s,r)=>s+r.size,0));metric('candidateSize',candidates.reduce((s,r)=>s+r.size,0));
  $('allPill').textContent=records.length;$('candidatePill').textContent=candidates.length;
  $('keepPill').textContent=records.filter(r=>decision(r)==='keep').length;
  $('laterPill').textContent=records.filter(r=>decision(r)==='later').length;
  for(const [id,value] of [['allView','all'],['candidateView','candidate'],['keepView','keep'],['laterView','later']]){
    $(id).classList.toggle('active',(view===value||(view==='due'&&value==='later')));$(id).setAttribute('aria-pressed',String(view===value||(view==='due'&&value==='later')));
  }
  const total=records.reduce((sum,r)=>sum+r.size,0),candidateBytes=candidates.reduce((sum,r)=>sum+r.size,0),kept=records.filter(r=>decision(r)==='keep'),keptBytes=kept.reduce((sum,r)=>sum+r.size,0);
  $('storageSummary').hidden=!records.length;
  $('candidateBar').style.width=(total?candidateBytes/total*100:0)+'%';$('keptBar').style.width=(total?keptBytes/total*100:0)+'%';
  $('storageText').textContent=`整理候補 ${units(candidateBytes)}（${total?Math.round(candidateBytes/total*100):0}%） / 残す ${units(keptBytes)} / その他 ${units(total-candidateBytes-keptBytes)}`;
  const query=$('search').value.trim().toLocaleLowerCase();
  let filtered=records.filter(r=>(view==='all'||(view==='candidate'?isCandidate(r,days,gb):view==='due'?reviewDue(r,decisions(),reviewDates()):decision(r)===view))&&r.path.toLocaleLowerCase().includes(query));
  const sort=$('sort').value;
  filtered.sort((a,b)=>sort==='size-desc'?b.size-a.size:sort==='date-asc'?a.modified-b.modified:sort==='name'?a.name.localeCompare(b.name,'ja'):b.modified-a.modified);
  matching=filtered;
  $('nextFive').disabled=!nextFive(matching,decisions(),reviewDates(),r=>isCandidate(r,days,gb)).length;
  const bulkCandidates=matching.filter(r=>isCandidate(r,days,gb));
  $('selectCandidates').disabled=!bulkCandidates.length;
  $('selectCandidates').textContent=bulkCandidates.length?`候補 ${bulkCandidates.length} 件をまとめて選ぶ`:'候補だけをまとめて選ぶ';
  for(const [id,key] of [['sortBig','size-desc'],['sortOld','date-asc'],['sortNew','date-desc']])$(id).setAttribute('aria-pressed',String(sort===key));
  const pages=Math.max(1,Math.ceil(filtered.length/PAGE_SIZE));page=Math.min(page,pages-1);
  visible=filtered.slice(page*PAGE_SIZE,(page+1)*PAGE_SIZE);
  $('pageLabel').textContent=`${page+1} / ${pages}`;$('prevPage').disabled=page===0;$('nextPage').disabled=page>=pages-1;
  const fragment=document.createDocumentFragment();
  for(const r of visible){
    const tr=element('tr');const checkbox=document.createElement('input');checkbox.type='checkbox';checkbox.checked=selected.has(r.id);checkbox.disabled=!selectable(r);checkbox.setAttribute('aria-label',r.name+'を選択');
    checkbox.addEventListener('change',()=>{checkbox.checked?selected.add(r.id):selected.delete(r.id);updateSelection();});
    const check=element('td',undefined,'check-cell');check.append(checkbox);tr.append(check);
    const nameCell=element('td');const nameWrap=element('button',undefined,'filename filename-button');nameWrap.setAttribute('aria-label',r.name+'の詳細');nameWrap.addEventListener('click',()=>preview(r));const info=element('div');info.append(element('div',r.name,'file-name'),element('span',r.path.substring(0,r.path.lastIndexOf('/'))||'選択した動画','file-meta'));nameWrap.append(element('span','▷','file-icon'),info);nameCell.append(nameWrap);nameCell.title=r.path;tr.append(nameCell);
    tr.append(element('td',units(r.size),'size-cell'),element('td',new Date(r.modified).toLocaleDateString('ja-JP')+' '+new Date(r.modified).toLocaleTimeString('ja-JP',{hour:'2-digit',minute:'2-digit'}),'date-cell'));
    const reasonCell=element('td');const why=reasons(r,days,gb);
    if(decision(r)==='keep')reasonCell.append(element('span','♡ 残す・候補から除外','reason kept'));
    else{if(decision(r)==='later'){const due=reviewDates()[decisionKey(r)];reasonCell.append(element('span',reviewDue(r,decisions(),reviewDates())?'◷ 見直し時期':`◷ ${new Date(due).toLocaleDateString('ja-JP')}に見直す`,'reason later'));}if(why.length)why.forEach(reason=>reasonCell.append(element('span',reason,'reason')));else if(decision(r)!=='later')reasonCell.append(element('span','—','no-reason'));}tr.append(reasonCell);
    const action=element('td');const play=element('button','詳細 ↗','play-button');play.setAttribute('aria-label',r.name+'の詳細を開く');play.title='プレビューと整理の判断';play.addEventListener('click',()=>preview(r));action.append(play);tr.append(action);fragment.append(tr);
  }
  $('rows').replaceChildren(fragment);$('empty').hidden=visible.length>0;
  if(records.length&&!visible.length){$('empty').querySelector('h3').textContent='条件に合う動画がありません';$('empty').querySelector('p').textContent='検索語や候補の条件を変えてみてください。';$('emptyDemo').hidden=true;}
  else{$('empty').querySelector('h3').textContent='録画のお片づけ、はじめよう。';$('empty').querySelector('p').textContent='動画を選ぶと、容量や見直し候補がひと目で分かります。';$('emptyDemo').hidden=false;}
  $('visibleCount').textContent=`${filtered.length} / ${records.length} 件に一致 · ${visible.length} 件を表示`;
  $('modeBadge').textContent=mode==='demo'?'DEMO':mode==='local'?'LOCAL':mode==='snapshot'?'保存一覧':'未選択';$('modeBadge').classList.toggle('demo',mode==='demo');updateSelection();
}
function resetFilters(){selected.clear();$('sort').value='size-desc';$('search').value='';view='all';page=0;undo=null;$('toast').hidden=true;}
function loadDemo(){if(deleteBusy||scanBusy)return;accessRoot=null;loadSequence++;records=demoRecords(1793664000000);mode='demo';resetFilters();$('folderLabel').textContent='サンプル録画 / 6件の架空のライブラリ';$('status').textContent='デモモード：実ファイルはありません。候補の条件変更や整理リストの保存を試せます。';render();}
async function loadFiles(files,source='files'){
  if(deleteBusy||scanBusy)return;accessRoot=null;const sequence=++loadSequence;let list=Array.from(files);if(!list.length)return;
  $('status').textContent='ファイル情報を読み込み中…';
  await new Promise(resolve=>setTimeout(resolve,0));
  let next=[];let skipped=0;
  for(let i=0;i<list.length;i++){
    const file=list[i];if(isVideo(file.name,file.type))next.push({id:String(i),name:file.name,path:file.webkitRelativePath||file.name,size:file.size,modified:file.lastModified,file});else skipped++;
    if(i%500===0){await new Promise(resolve=>setTimeout(resolve,0));if(sequence!==loadSequence)return;}
  }
  if(sequence!==loadSequence)return;
  records=next;mode='local';resetFilters();
  const root=list[0].webkitRelativePath?.split('/')[0];$('folderLabel').textContent=root?`${root} / サブフォルダを含む`:source==='photos'?'写真ライブラリから選んだ動画':'個別に選択した動画';
  $('status').textContent=`読み込み完了：動画 ${records.length} 件 / 対象外 ${skipped} 件。動画は送信していません。${source==='photos'?'容量・日時は選択時に渡された情報です。':''}再読み込みで一覧は消えます。`;
  render();
}
$('demoButton').addEventListener('click',loadDemo);$('emptyDemo').addEventListener('click',loadDemo);
$('photosButton').addEventListener('click',()=>$('photosInput').click());
$('folderButton').addEventListener('click',()=>$('folderInput').click());$('filesButton').addEventListener('click',()=>$('filesInput').click());
for(const id of ['folderInput','filesInput','photosInput'])$(id).addEventListener('change',async e=>{const files=Array.from(e.target.files);e.target.value='';try{await loadFiles(files,id==='photosInput'?'photos':'files');}catch(error){$('status').textContent='読み込めませんでした。選ぶ動画を少なくして、写真ライブラリまたはファイルから選び直してください。';}});
$('search').addEventListener('input',()=>{page=0;render();});$('sort').addEventListener('change',()=>{page=0;render();});
for(const id of ['days','size'])$(id).addEventListener('change',()=>{if(!$(id).checkValidity()){$(id).value=id==='days'?'90':'2';}render();});
for(const [id,value] of [['allView','all'],['candidateView','candidate'],['keepView','keep'],['laterView','later']])$(id).addEventListener('click',()=>{view=value;page=0;render();});
$('prevPage').addEventListener('click',()=>{page--;render();});$('nextPage').addEventListener('click',()=>{page++;render();});
for(const [id,key] of [['sortBig','size-desc'],['sortOld','date-asc'],['sortNew','date-desc']])$(id).addEventListener('click',()=>{$('sort').value=key;page=0;render();});
$('selectCandidates').addEventListener('click',()=>{
  const [days,gb]=thresholds();selected=new Set(matching.filter(r=>isCandidate(r,days,gb)).map(r=>r.id));render();
  $('status').textContent=`候補 ${selected.size} 件をまとめて選択しました。内容を確認してから整理リストを保存できます。元動画はまだ変更していません。`;
});
$('selectAll').addEventListener('change',e=>{visible.filter(selectable).forEach(r=>e.target.checked?selected.add(r.id):selected.delete(r.id));render();});
$('clearSelection').addEventListener('click',()=>{selected.clear();render();});
$('helpButton').addEventListener('click',()=>$('helpDialog').showModal());
document.querySelectorAll('[data-close]').forEach(button=>button.addEventListener('click',()=>$(button.dataset.close).close()));
$('reviewButton').addEventListener('click',()=>{
  const chosen=chosenRecords();if(!chosen.length)return;reviewRecords=[...chosen];
  $('deleteSection').hidden=!accessRoot||!chosen.every(r=>r.root===accessRoot&&r.handle);$('deleteConsent').checked=false;$('deleteButton').disabled=true;$('deleteResults').hidden=true;$('deleteResults').replaceChildren();$('deleteProgress').textContent='';
  $('reviewNotice').textContent=accessRoot?'CSV保存では元動画を変更しません。下の削除操作は元動画を直接削除します。':'この選び方では元動画を削除しません。CSVを参考に写真アプリなどで整理してください。';
  $('reviewSummary').textContent=`${chosen.length} 件 / 合計 ${units(chosen.reduce((s,r)=>s+r.size,0))}${mode==='demo'?'（デモの架空データ）':''}`;
  const fragment=document.createDocumentFragment();for(const r of chosen){const item=element('div',r.path,'review-item');item.append(element('small',`${units(r.size)} / ${reasons(r,...thresholds()).join('・')||'候補条件には該当しません'} / ${decision(r)==='later'?'あとで確認':'未整理'}`));fragment.append(item);}
  $('reviewList').replaceChildren(fragment);$('consent').checked=false;$('exportButton').disabled=true;$('reviewDialog').showModal();
});
$('consent').addEventListener('change',()=>{$('exportButton').disabled=!$('consent').checked;});
$('exportButton').addEventListener('click',()=>{
  if(!$('consent').checked)return;const chosen=chosenRecords();if(!chosen.length)return;
  if(exportURL)URL.revokeObjectURL(exportURL);
  exportURL=URL.createObjectURL(new Blob([makeCSV(chosen,...thresholds(),Date.now(),decisions(),reviewDates())],{type:'text/csv;charset=utf-8'}));
  const a=document.createElement('a');a.href=exportURL;a.download=`RecSort-${mode==='demo'?'demo-':''}${new Date().toISOString().slice(0,10)}.csv`;document.body.append(a);a.click();a.remove();
  $('reviewDialog').close();$('status').textContent='整理リストを保存しました。動画の削除・移動は行っていません。';
});
function preview(record){
  activeRecord=record;if(previewURL){URL.revokeObjectURL(previewURL);previewURL=null;}
  $('previewTitle').textContent=record.name;$('video').hidden=!record.file;
  if(record.file){previewURL=URL.createObjectURL(record.file);$('video').src=previewURL;}
  $('previewStatus').textContent=record.file?'ブラウザが対応する形式のみ再生できます。動画を外部に送信しません。':(mode==='snapshot'?'保存した一覧です。再生・削除には元動画を選び直してください。':'デモの架空データです。実際の動画はありません。フォルダを選ぶとプレビューできます。');
  const dl=$('previewDetails');dl.replaceChildren();
  for(const [label,value] of [['ファイル',record.path],['容量',units(record.size)],['最終更新',new Date(record.modified).toLocaleString('ja-JP')],['形式',record.file?.type||record.name.split('.').pop().toUpperCase()]])dl.append(element('dt',label),element('dd',value));
  $('previewReasons').replaceChildren(...reasons(record,...thresholds()).map(reason=>element('span',reason,'reason')));
  updateInspector();$('previewDialog').showModal();
}
function updateInspector(){
  if(!activeRecord)return;const value=decision(activeRecord);
  $('decisionPersistence').textContent=mode==='demo'?'デモ中の判断はこのページ内だけで保持します。実ファイルには影響しません。':storageOK?'判断はこのブラウザに保存。同じフォルダを読み込むと引き継ぎます。':'この環境では判断を保存できません。ページを閉じると判断は消えます。';
  $('decisionFeedback').textContent=value==='keep'?'「残す」に設定済み。候補と整理リストの選択から除外しています。':value==='later'?`見直し日：${reviewDates()[decisionKey(activeRecord)]?new Date(reviewDates()[decisionKey(activeRecord)]).toLocaleDateString('ja-JP'):'未設定・見直し対象'}。期限が来ても自動削除しません。`:'まだ判断していない録画です。';
  $('inspectorUndo').disabled=!undo||undo.mode!==mode;
  for(const [id,key] of [['markKeep','keep'],['markLater','later'],['markNone','none']]){$(id).classList.toggle('chosen',value===key);$(id).setAttribute('aria-pressed',String(value===key));}
}
function applyDecision(value){
  if(!activeRecord)return;
  undo={record:activeRecord,previous:decision(activeRecord),previousDue:reviewDates()[decisionKey(activeRecord)],selection:new Set(selected),mode};
  const key=decisionKey(activeRecord);if(value==='later')reviewDates()[key]=Date.now()+Number($('reviewDays').value)*86400000;else delete reviewDates()[key];saveReviewDates();
  if(mode==='demo')demoDecisions=setDecision(activeRecord,demoDecisions,value);
  else{savedDecisions=setDecision(activeRecord,savedDecisions,value);saveDecisions();}
  if(value==='keep')selected.delete(activeRecord.id);
  render();updateInspector();
  const message=value==='keep'?'「残す」にしました。整理候補から除外しました。':value==='later'?'「あとで確認」にしました。':'未整理に戻しました。';
  showToast(message+(mode==='demo'?'（デモ内のみ）':storageOK?'':' この環境では保存できないため、ページを閉じると判断は消えます。'));
}
$('markKeep').addEventListener('click',()=>applyDecision('keep'));$('markLater').addEventListener('click',()=>applyDecision('later'));$('markNone').addEventListener('click',()=>applyDecision('none'));
function undoDecision(){
  if(!undo||undo.mode!==mode)return;
  if(mode==='demo')demoDecisions=setDecision(undo.record,demoDecisions,undo.previous);
  else{savedDecisions=setDecision(undo.record,savedDecisions,undo.previous);saveDecisions();}
  if(undo.previousDue===undefined)delete reviewDates()[decisionKey(undo.record)];else reviewDates()[decisionKey(undo.record)]=undo.previousDue;saveReviewDates();
  selected=new Set(undo.selection);undo=null;render();updateInspector();showToast('直前の判断を元に戻しました。',false);
}
$('undoButton').addEventListener('click',undoDecision);$('inspectorUndo').addEventListener('click',undoDecision);
$('video').addEventListener('error',()=>{$('previewStatus').textContent='この動画はブラウザで再生できません。PCの動画プレイヤーで確認してください。';});
$('previewDialog').addEventListener('close',()=>{$('video').pause();$('video').removeAttribute('src');$('video').load();if(previewURL){URL.revokeObjectURL(previewURL);previewURL=null;}});
render();

const accessSupported=window.isSecureContext&&typeof window.showDirectoryPicker==='function';
$('accessFolderButton').hidden=!accessSupported;
function sourceBusy(busy){for(const id of ['accessFolderButton','folderButton','filesButton','photosButton','demoButton','emptyDemo','rememberFolder','reopenFolder','saveList','restoreList','forgetList','forgetFolder'])$(id).disabled=busy;}
async function loadAccessRoot(root){
 if(deleteBusy||scanBusy)return;
 scanBusy=true;sourceBusy(true);const sequence=++loadSequence;
 try{
  $('status').textContent='フォルダの動画情報を読み込み中…';
  const next=await scanDirectory(root,isVideo,{onProgress:n=>{if(n%50===0)$('status').textContent=`動画 ${n} 件を読み込み中…`;}});
  if(sequence!==loadSequence)return;
  records=next.records;mode='local';accessRoot=root;resetFilters();
  $('folderLabel').textContent=root.name+' / PC削除対応フォルダ';
  $('status').textContent=`動画 ${records.length} 件を読み込みました。読めなかった動画 ${next.skipped} 件。削除時には書き込み許可と最終確認が必要です。`;
  render();
 }finally{scanBusy=false;sourceBusy(false);render();}
}
$('accessFolderButton').addEventListener('click',async()=>{
 if(deleteBusy||scanBusy)return;
 try{const root=await window.showDirectoryPicker({mode:'read'});await loadAccessRoot(root);}
 catch(error){if(error.name!=='AbortError')$('status').textContent='フォルダを開けませんでした。対応PCのChrome／Edgeか、通常のフォルダ選択をご利用ください。';}
});
$('deleteConsent').addEventListener('change',()=>{$('deleteButton').disabled=deleteBusy||!$('deleteConsent').checked;});
$('stopDelete').addEventListener('click',()=>{deleteAbort?.abort();$('stopDelete').disabled=true;$('deleteProgress').textContent='実行中の1件が終わり次第、残りを中止します。';});
$('reviewDialog').addEventListener('cancel',e=>{if(deleteBusy)e.preventDefault();});
$('deleteButton').addEventListener('click',async()=>{
 if(deleteBusy||!$('deleteConsent').checked||!accessRoot||!reviewRecords.length)return;
 const chosen=[...reviewRecords];
 if(!chosen.every(r=>records.includes(r)&&r.root===accessRoot&&selectable(r)))return;
 deleteBusy=true;deleteAbort=new AbortController();sourceBusy(true);
 const controls=[...$('reviewDialog').querySelectorAll('button,input')];controls.forEach(e=>e.disabled=true);$('stopDelete').hidden=false;$('stopDelete').disabled=false;
 let results=[];
 try{
  // Called directly from the explicit delete-button gesture, never on scan/load.
  const permission=await accessRoot.requestPermission({mode:'readwrite'});
  if(permission!=='granted')throw new Error('書き込みが許可されなかったため、削除していません。');
 if(!window.confirm(`${chosen.length} 件 / ${units(chosen.reduce((n,r)=>n+r.size,0))} の元動画を削除します。\nゴミ箱には入らず、元に戻せない可能性があります。\n確認画面のファイル名を確認しましたか？`))return;
  results=await deleteConfirmed(chosen,{confirmed:true,isKept:r=>!selectable(r),signal:deleteAbort.signal,onProgress:(n,total)=>{$('deleteProgress').textContent=`${n} / ${total} 件の処理が完了`;}});
  const removed=new Set(results.filter(r=>!r.error).map(r=>r.record));
  records=records.filter(r=>!removed.has(r));removed.forEach(r=>selected.delete(r.id));undo=null;
  const failed=results.filter(r=>r.error);const remaining=chosen.length-results.length;
  const message=`削除 ${removed.size} 件 / 失敗 ${failed.length} 件 / 未処理 ${remaining} 件。空き容量への反映はOSに依存します。`;
  $('status').textContent=message;$('deleteProgress').textContent=message;
  $('deleteResults').replaceChildren(...failed.map(({record,error})=>{const e=element('div',record.path,'review-item');e.append(element('small',error));return e;}));$('deleteResults').hidden=!failed.length;
  render();
 }catch(error){$('deleteProgress').textContent=error.message||'削除を開始できませんでした。';}
 finally{
  deleteBusy=false;sourceBusy(false);controls.forEach(e=>e.disabled=false);$('stopDelete').hidden=true;$('stopDelete').disabled=false;$('deleteConsent').checked=false;$('deleteButton').disabled=true;
  reviewRecords=chosen.filter(r=>records.includes(r));
  const fragment=document.createDocumentFragment();for(const r of reviewRecords){const e=element('div',r.path,'review-item');e.append(element('small',units(r.size)));fragment.append(e);}$('reviewList').replaceChildren(fragment);
  $('reviewSummary').textContent=`残っている選択 ${reviewRecords.length} 件 / ${units(reviewRecords.reduce((n,r)=>n+r.size,0))}`;
  $('deleteSection').hidden=!reviewRecords.length;$('consent').checked=false;$('exportButton').disabled=true;
 }
});

$('nextFive').addEventListener('click',()=>{selected=new Set(nextFive(matching,decisions(),reviewDates(),r=>isCandidate(r,...thresholds())).map(r=>r.id));render();$('status').textContent=`${selected.size} 件を選びました。選択は削除ではありません。内容を確認し、残す・保留・整理を判断してください。`;});
$('dueReview').addEventListener('click',()=>{view='due';page=0;$('sort').value='date-asc';render();$('status').textContent='見直し時期になった動画だけを表示しています。';});
$('saveList').addEventListener('click',()=>{if(mode==='demo'||!records.length)return;try{const raw=makeSnapshot(records,$('folderLabel').textContent);localStorage.setItem(SNAPSHOT_KEY,raw);lastSnapshot=readSnapshot(raw);render();$('status').textContent='名前・容量・日時をこのブラウザに保存しました。動画本体は保存していません。';}catch{$('status').textContent='一覧を保存できませんでした。保存領域やブラウザの設定を確認してください。';}});
$('restoreList').addEventListener('click',()=>{if(!lastSnapshot||deleteBusy||scanBusy)return;loadSequence++;accessRoot=null;mode='snapshot';records=lastSnapshot.records.map(r=>({...r}));resetFilters();$('folderLabel').textContent=lastSnapshot.label+' / '+new Date(lastSnapshot.saved).toLocaleString('ja-JP')+'時点';$('status').textContent='保存した一覧です。実際のファイルの有無や容量は再確認していません。動画を選び直すと再生・実ファイルの操作ができます。';render();});
$('forgetList').addEventListener('click',()=>{try{localStorage.removeItem(SNAPSHOT_KEY);lastSnapshot=null;render();$('status').textContent='保存した一覧を消しました。元動画と「残す・保留」の判断は変更していません。';}catch{$('status').textContent='保存した一覧を消せませんでした。ブラウザのサイトデータ設定を確認してください。';}});
$('rememberFolder').addEventListener('click',async()=>{if(!accessRoot)return;try{await storedFolder('put',accessRoot);rememberedRoot=accessRoot;$('reopenFolder').hidden=false;render();$('status').textContent='このブラウザにフォルダの参照を保存しました。次回は「前回のフォルダを開く」から再許可して読み込めます。';}catch{$('status').textContent='この環境ではフォルダを記憶できません。一覧の保存または通常の選択をご利用ください。';}});
$('reopenFolder').addEventListener('click',async()=>{if(!rememberedRoot||deleteBusy||scanBusy)return;try{if(await rememberedRoot.requestPermission({mode:'read'})!=='granted'){$('status').textContent='読み込みを許可しなかったため、フォルダは開いていません。';return;}await loadAccessRoot(rememberedRoot);}catch{$('status').textContent='前回のフォルダを開けません。移動・削除や許可の変更を確認し、フォルダを選び直してください。';}});
$('forgetFolder').addEventListener('click',async()=>{try{await storedFolder('clear');rememberedRoot=null;$('reopenFolder').hidden=true;render();$('status').textContent='保存したフォルダの参照を解除しました。OS側の許可取り消しはブラウザのサイト設定から行えます。';}catch{$('status').textContent='参照を解除できませんでした。ブラウザのサイトデータ設定を確認してください。';}});
if(accessSupported)storedFolder('get').then(root=>{if(root){rememberedRoot=root;$('reopenFolder').hidden=false;$('forgetFolder').hidden=false;}}).catch(()=>{});
$('guideButton').addEventListener('click',()=>$('guideDialog').showModal());
$('downloadFeedback').addEventListener('click',()=>{const text='RecSort 利用メモ（未送信）\n\n整理できない理由：\n'+$('researchReason').value+'\n\n圧縮・クラウドを使わない理由：\n'+$('researchAlternative').value+'\n\n改善・有料利用の条件：\n'+$('researchValue').value;const url=URL.createObjectURL(new Blob([text],{type:'text/plain;charset=utf-8'}));const a=document.createElement('a');a.href=url;a.download='RecSort-feedback.txt';document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);});
