export const MAX_MEMORY_OUTPUT=128*1024*1024;
export function fitDimensions(width,height,maxEdge=1280){
 if(!Number.isFinite(width)||!Number.isFinite(height)||width<=0||height<=0)throw Error('動画の大きさを取得できません');
 const ratio=Math.min(1,maxEdge/Math.max(width,height));
 return {width:Math.max(2,Math.floor(width*ratio/2)*2),height:Math.max(2,Math.floor(height*ratio/2)*2)};
}
export function outputName(name,extension){return 'RecSort-small-'+name.replace(/\.[^.]*$/,'').replace(/[\\/:\r\n]/g,'_').slice(0,160)+'.'+extension;}
export function recordingType(recorder=globalThis.MediaRecorder){
 if(!recorder)return null;
 return ['video/mp4;codecs=avc1.42E01E,mp4a.40.2','video/webm;codecs=vp9,opus','video/webm;codecs=vp8,opus','video/webm','video/mp4'].find(t=>recorder.isTypeSupported(t))||null;
}
export function canCompress(){return !!(recordingType()&&globalThis.HTMLCanvasElement?.prototype.captureStream&&(globalThis.AudioContext||globalThis.webkitAudioContext));}
export function compressionSummary(before,after){return after<before?`${Math.round((1-after/before)*100)}% 小さくなりました。元動画は残っています。`:'元動画より小さくなりませんでした。元動画は残っています。';}
export async function compressVideo(file,{maxEdge=1280,bitrate=1800000,signal,onProgress=()=>{},video,onWriter,sourceHandle,direct=false}={}){
 if(!file||!canCompress())throw Error('このブラウザでは圧縮できません。対応するPCのChrome／Edgeをお試しください。');
 const mime=recordingType(),extension=mime.startsWith('video/mp4')?'mp4':'webm',name=outputName(file.name,extension);
 let writer=null,outputHandle=null,outputClosed=false,stream=null,audio=null,url=null,recorder=null,frame=null,aborted=false,recordingError=null;
 const chunks=[];let total=0,pendingWrites=0,writeQueue=Promise.resolve();
 try{
  if(direct){
   if(typeof window.showSaveFilePicker!=='function')throw Error('直接保存に対応していません。チェックを外してください。');
   outputHandle=await window.showSaveFilePicker({suggestedName:name,types:[{description:'圧縮した動画',accept:{[mime.split(';')[0]]:['.'+extension]}}]});
   if(outputHandle.name.normalize('NFC').toLocaleLowerCase()===file.name.normalize('NFC').toLocaleLowerCase()||(sourceHandle&&await outputHandle.isSameEntry(sourceHandle)))throw Error('元動画への上書きはできません。新しいファイル名を選んでください。');
   writer=await outputHandle.createWritable();onWriter?.();
  }
  if(signal?.aborted)throw new DOMException('中止しました','AbortError');
  // Resume inside the explicit Start gesture. This records file audio, never a microphone.
  audio=new (globalThis.AudioContext||globalThis.webkitAudioContext)();await audio.resume();
  const source=audio.createMediaElementSource(video),destination=audio.createMediaStreamDestination();source.connect(destination);
  url=URL.createObjectURL(file);video.src=url;video.controls=false;video.playsInline=true;video.muted=false;
  await new Promise((resolve,reject)=>{const timer=setTimeout(()=>done(Error('動画を読み込めませんでした')),20000);const done=error=>{clearTimeout(timer);video.removeEventListener('loadeddata',loaded);video.removeEventListener('error',failed);signal?.removeEventListener('abort',cancel);error?reject(error):resolve();};const loaded=()=>done();const failed=()=>done(Error('この形式の動画はブラウザで読み込めません'));const cancel=()=>done(new DOMException('中止しました','AbortError'));video.addEventListener('loadeddata',loaded,{once:true});video.addEventListener('error',failed,{once:true});signal?.addEventListener('abort',cancel,{once:true});video.load();});
  if(!Number.isFinite(video.duration)||video.duration<=0)throw Error('長さを取得できない動画は圧縮できません');
  const canvas=document.createElement('canvas'),dimensions=fitDimensions(video.videoWidth,video.videoHeight,maxEdge);Object.assign(canvas,dimensions);
  const context=canvas.getContext('2d');if(!context)throw Error('動画の描画に対応していません');
  context.drawImage(video,0,0,canvas.width,canvas.height);
  stream=canvas.captureStream(30);destination.stream.getAudioTracks().forEach(track=>stream.addTrack(track));
  recorder=new MediaRecorder(stream,{mimeType:mime,videoBitsPerSecond:bitrate,audioBitsPerSecond:128000});
  let endRecorder;
  const completed=new Promise((resolve,reject)=>{
   const stop=()=>{if(recorder.state!=='inactive')recorder.stop();};endRecorder=stop;
   const cancel=()=>{aborted=true;video.pause();stop();};signal?.addEventListener('abort',cancel,{once:true});
   recorder.ondataavailable=event=>{
    if(!event.data.size)return;total+=event.data.size;
    if(writer){pendingWrites++;if(pendingWrites>32){recordingError=Error('保存先への書き込みが追いつかないため中止しました');cancel();return;}writeQueue=writeQueue.then(()=>writer.write(event.data)).then(()=>{pendingWrites--;}).catch(error=>{recordingError=error;cancel();});}
    else if(total>MAX_MEMORY_OUTPUT){recordingError=Error('出力が128MBを超えたため中止しました。対応PCの直接保存を使うか、短い動画でお試しください。');cancel();}
    else chunks.push(event.data);
   };
   recorder.onerror=()=>{recordingError=Error('動画の変換に失敗しました');cancel();};
   recorder.onstop=async()=>{signal?.removeEventListener('abort',cancel);await writeQueue;if(recordingError)reject(recordingError);else if(aborted)reject(new DOMException('中止しました','AbortError'));else resolve();};
   video.onended=stop;
  });
  const draw=()=>{context.drawImage(video,0,0,canvas.width,canvas.height);onProgress(Math.min(1,video.currentTime/video.duration),video.currentTime,video.duration);frame=requestAnimationFrame(draw);};
  recorder.start(1000);frame=requestAnimationFrame(draw);
  try{await video.play();}catch(error){recordingError=Error('動画を再生できませんでした。画面を前面にして再試行してください。');endRecorder();}
  await completed;
  if(!total)throw Error('圧縮結果が空でした');
  let result;
  if(writer){await writer.close();outputClosed=true;result=await outputHandle.getFile();}
  else result=new File(chunks,name,{type:recorder.mimeType||mime});
  onProgress(1,video.duration,video.duration);
  return {file:result,name:outputHandle?.name||name,direct:!!writer,width:canvas.width,height:canvas.height};
 }finally{
  if(frame!==null)cancelAnimationFrame(frame);video.pause();video.onended=null;video.controls=true;video.removeAttribute('src');video.load();
  if(recorder?.state==='recording')recorder.stop();stream?.getTracks().forEach(t=>t.stop());
  if(audio)await audio.close().catch(()=>{});if(url)URL.revokeObjectURL(url);
  if(writer&&!outputClosed)await writer.abort().catch(()=>{});
 }
}
