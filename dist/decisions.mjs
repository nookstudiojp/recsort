export const decisionKey = record => JSON.stringify([record.path,record.size,record.modified]);
export const getDecision = (record,decisions) => decisions[decisionKey(record)] || 'none';
export const canSelect = (record,decisions) => getDecision(record,decisions) !== 'keep';
export function readDecisions(raw) {
  try {
    const parsed=JSON.parse(raw);
    if(!parsed||typeof parsed!=='object'||Array.isArray(parsed))return Object.create(null);
    return Object.fromEntries(Object.entries(parsed).filter(([key,value])=>key.startsWith('[')&&(value==='keep'||value==='later')));
  }catch{return Object.create(null);}
}
export function setDecision(record,decisions,value){
  const next={...decisions},key=decisionKey(record);
  if(value==='keep'||value==='later')next[key]=value;else delete next[key];
  return next;
}
