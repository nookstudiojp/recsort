// Native handles stay in memory and are never reconstructed from path strings.
export async function scanDirectory(root,isVideo,{signal,onProgress=()=>{}}={}){
 const records=[],stack=[{dir:root,path:root.name}];let skipped=0;
 while(stack.length){
  if(signal?.aborted)throw new DOMException('Cancelled','AbortError');
  const {dir,path}=stack.pop();
  for await(const handle of dir.values()){
   if(signal?.aborted)throw new DOMException('Cancelled','AbortError');
   if(handle.kind==='directory'){stack.push({dir:handle,path:path+'/'+handle.name});continue;}
   if(!isVideo(handle.name,''))continue;
   try{const file=await handle.getFile();records.push({id:String(records.length),name:file.name,path:path+'/'+file.name,size:file.size,modified:file.lastModified,file,handle,parent:dir,root});}
   catch{skipped++;}
   onProgress(records.length);
  }
 }
 return {records,skipped};
}
export async function deleteConfirmed(records,{confirmed=false,isKept=()=>false,signal,onProgress=()=>{}}={}){
 if(!confirmed)throw new Error('Confirmation required');
 const results=[];
 for(const record of records){
  if(signal?.aborted)break;
  let error=null;
  try{
   if(isKept(record))throw new Error('「残す」に設定されているため削除しませんでした');
   if(!record.handle||!record.parent||!record.root)throw new Error('削除用フォルダから読み込んだ動画ではありません');
   if(await record.root.queryPermission({mode:'readwrite'})!=='granted')throw new Error('書き込み許可がありません');
   const current=await record.parent.getFileHandle(record.name);
   if(!await current.isSameEntry(record.handle))throw new Error('ファイルが置き換わっています。再読み込みしてください');
   const file=await current.getFile();
   if(file.size!==record.size||file.lastModified!==record.modified)throw new Error('ファイルが更新されています。再読み込みしてください');
   if(signal?.aborted)break;
   // Never recurse: only this exact file name in its original parent directory.
   await record.parent.removeEntry(record.name,{recursive:false});
  }catch(e){error=e?.message||'削除できませんでした';}
  results.push({record,error});onProgress(results.length,records.length);
 }
 return results;
}
