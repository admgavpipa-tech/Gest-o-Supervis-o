/* Integridade e sincronização das rotinas. Não guarda senhas ou sessões neste arquivo. */
let configVersion=0,configHistory=[],pendingSave=false,lastSaveError='',journalOwner=null,conflictDraft=null,dataEpoch=0;
const PAGE_SIZE=300;
function dateInSP(value){const p=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(value);return ['year','month','day'].map(t=>p.find(x=>x.type===t).value).join('-')}
function configAt(date=today()){
 if(typeof date!=='string'||date>=today()||!configHistory.length)return db;
 let found=configHistory[0];for(const row of configHistory){if(dateInSP(new Date(row.recorded_at))<=date)found=row;else break}
 return found.data;
}
async function fetchAll(table,columns='*',filter=q=>q,order='key'){
 const out=[];let offset=0;
 for(;;){const {data,error}=await filter(sb.from(table).select(columns)).order(order,{ascending:true}).range(offset,offset+PAGE_SIZE-1);
  if(error)throw error;if(!data.length)break;out.push(...data);offset+=data.length;
  // Mesmo com um limite do projeto menor que PAGE_SIZE, segue até receber página vazia.
 }
 return out;
}
function changesBetween(now,base){const changes={};if(now.cfg!==base.cfg)changes.cfg=JSON.parse(now.cfg);
 for(const table of ['records','picks','closed']){const a=now[table],b=base[table];changes[table]={up:Object.keys(a).filter(k=>a[k]!==b[k]).map(k=>rowFor(table,k,JSON.parse(a[k]))),del:Object.keys(b).filter(k=>!(k in a))}}
 return changes;
}
function hasChanges(c){return 'cfg' in c||['records','picks','closed'].some(t=>c[t].up.length||c[t].del.length)}
function journalKey(){return `gav-pendente:${authId}`}
function keepJournal(target){try{localStorage.setItem(journalKey(),JSON.stringify({version:configVersion,changes:changesBetween(target,synced)}));return true}catch(e){return false}}
function clearJournal(){try{localStorage.removeItem(journalKey())}catch(e){}}
function restoreJournal(){if(journalOwner===authId)return;journalOwner=authId;const saved=readKey(journalKey());conflictDraft=readKey(`gav-conflito:${authId}`);
 if(!saved?.changes)return;
 const change=saved.changes;
 if(change.cfg&&saved.version!==configVersion){conflictDraft={exported:new Date().toISOString(),...change.cfg};try{localStorage.setItem(`gav-conflito:${authId}`,JSON.stringify(conflictDraft))}catch(e){}clearJournal();lastSaveError='Outra gestão alterou a programação. Sua edição anterior está disponível em Baixar edição preservada.';return}
 if(change.cfg)Object.assign(db,change.cfg);
 for(const table of ['records','picks','closed']){for(const row of change[table].up){db[table][row.key]=table==='records'?row.data:table==='picks'?{lists:row.lists,at:row.at}:{time:row.time}}for(const key of change[table].del)delete db[table][key]}
 pendingSave=hasChanges(changesBetween(snapshot(),synced));if(pendingSave)lastSaveError='Há alterações deste aparelho aguardando envio.';
}
async function loadAll(force=false){
 const epoch=dataEpoch,loadedFor=authId;
 const [users,state,records,picks,closedRows,hist]=await Promise.all([
  fetchAll('profiles','*',x=>x,'id'),sb.from('app_state').select('data,version').eq('id',1).maybeSingle(),
  fetchAll('records','key,data'),fetchAll('picks'),fetchAll('closed'),fetchAll('config_history','*',x=>x,'version')]);
 if(state.error)throw state.error;
 if(loadedFor!==authId||(!force&&(epoch!==dataEpoch||saving||pendingSave)))return false;
 db.users=users.map(u=>({...u,created:u.created_at}));
 if(!state.data&&isManager()){
  const seeded=await sb.rpc('gav_apply_changes',{expected_version:0,changes:{cfg:initialConfig()}});if(seeded.error)throw seeded.error;
  return loadAll();
 }
 const cfg=state.data?.data||{rooms:[],tasks:[],lists:[]};Object.assign(db,cfg);configVersion=state.data?.version||0;configHistory=hist;
 db.records=Object.fromEntries(records.map(x=>[x.key,x.data]));db.picks=Object.fromEntries(picks.map(x=>[x.key,{lists:x.lists,at:x.at}]));db.closed=Object.fromEntries(closedRows.map(x=>[x.key,{time:x.time}]));
 synced=snapshot();restoreJournal();
}
async function persist(){
 if(!synced||!me()||saving)return false;
 const target=snapshot(),changes=changesBetween(target,synced);if(!hasChanges(changes)){pendingSave=false;lastSaveError='';renderSyncNotice();return true}
 dataEpoch++;pendingSave=true;const durable=keepJournal(target);saving++;renderSyncNotice();
 try{
  const {data,error}=await sb.rpc('gav_apply_changes',{expected_version:configVersion,changes});if(error)throw error;
  configVersion=data.version;if(data.cfg)Object.assign(db,data.cfg);for(const r of data.records||[])db.records[r.key]=r.data;
  if(changes.cfg){const row={version:configVersion,data:JSON.parse(target.cfg),recorded_at:new Date().toISOString()};configHistory.push(row)}
  synced=snapshot();pendingSave=false;lastSaveError='';clearJournal();return true;
 }catch(e){
  console.error('Falha ao salvar:',e.message);lastSaveError=e.message||'Não foi possível salvar. Tente novamente.';
  if(e.code==='40001'){
   if(changes.cfg){conflictDraft={exported:new Date().toISOString(),...changes.cfg};try{localStorage.setItem(`gav-conflito:${authId}`,JSON.stringify(conflictDraft))}catch(x){}}
   // Não reenviar uma configuração antiga sobre a edição de outro gestor.
   clearJournal();pendingSave=false;lastSaveError='Outro gestor alterou a programação. Recarregamos a versão atual; baixe sua edição preservada para conferir o que deseja reaplicar.';
   await loadAll(true);render();
  }else if(e.code==='42501'||e.code==='P0001'){
   // Recusas do servidor não são reenvios de internet; a interface volta ao estado confirmado.
   if(changes.cfg){conflictDraft={exported:new Date().toISOString(),...changes.cfg};try{localStorage.setItem(`gav-conflito:${authId}`,JSON.stringify(conflictDraft))}catch(x){}}
   clearJournal();pendingSave=false;await loadAll(true);render();
  }
  toast(pendingSave?(durable?'Ainda não foi salvo. A alteração ficou neste aparelho para tentar novamente.':'Ainda não foi salvo. Mantenha esta página aberta e tente novamente.'):lastSaveError);
  return false;
 }finally{saving--;renderSyncNotice()}
}
async function refresh(){
 if(!authId)return;if(saving||pendingSave)return;
 const busy=document.querySelector('.dialog')||view.page==='g-add'||document.activeElement?.matches?.('input,textarea,select');
 if(busy){clearTimeout(refresh.t);refresh.t=setTimeout(refresh,2000);return}
 try{await loadAll()}catch(e){console.error(e.message);return}
 if(!me()){signOutLocal('Seu acesso foi desativado.');return}
 render();
}
function renderSyncNotice(){
 let el=document.getElementById('sync-notice');if(!el){el=document.createElement('div');el.id='sync-notice';el.setAttribute('role','status');document.body.appendChild(el)}
 if(!me()||(!saving&&!pendingSave&&!lastSaveError&&!conflictDraft)){el.hidden=true;return}
 el.hidden=false;el.className='sync-notice';el.innerHTML=saving?'Salvando no servidor…':`${esc(lastSaveError||'Alterações aguardando envio.')}${pendingSave?'<button class="button compact" data-action="retry-save">Tentar salvar novamente</button>':''}${conflictDraft?'<button class="button compact" data-action="recover-draft">Baixar edição preservada</button>':''}`;
 document.querySelectorAll('[data-action="finish"],[data-action="review"]').forEach(b=>b.disabled=!!(saving||pendingSave));
}
function previousOccurrence(a,date){
 const end=a.end&&a.end<date?a.end:addDays(date,-1),r=a.repeat||{type:'once'},every=Math.max(1,Number(r.every)||1);
 if(end<a.start)return null;if(r.type==='once')return a.start;
 if(r.type==='daily')return addDays(a.start,Math.floor(diffDays(a.start,end)/every)*every);
 const windowDays=r.type==='weekly'?every*7+7:every*32+32;
 for(let i=0;i<=windowDays;i++){const d=addDays(end,-i);if(d<a.start)break;if(occursOn(a,d))return d}return null;
}
function occurrenceOf(l,i,date,asgId,extra={}){const t=taskById(i.taskId,date)||{},r=roomById(t.roomId,date);return {aid:i.id,listId:l.id,listName:l.name,asgId,title:t.title||'Tarefa removida',local:r?.name||'Sem cômodo',instructions:t.instructions,materials:t.materials,essential:t.essential,photoRequired:t.photoRequired!==false,notes:i.notes,repeat:i.repeat,start:i.start,end:i.end,date,key:`${date}:${i.id}`,overdue:false,...extra}}
function listsForDate(date){const lists=new Map(configAt(date).lists.map(l=>[l.id,l]));for(const r of Object.values(db.records)){const t=r.snapshot;if(r.date===date&&t?.listId&&!lists.has(t.listId))lists.set(t.listId,{id:t.listId,name:t.listName,items:[],asgIds:[]})}return [...lists.values()]}
function tasksForList(l,date=today(),asgId=null){
 l=listsForDate(date).find(x=>x.id===l.id)||l;const list=[],items=l.items.filter(i=>i.active&&!i.removed&&taskById(i.taskId,date));
 for(const i of items){if(occursOn(i,date)){list.push(occurrenceOf(l,i,date,asgId));continue}
  const prev=previousOccurrence(i,date),created=i.created?dateInSP(new Date(i.created)):i.start;if(!prev||prev<created)continue;
  const r=db.records[`${prev}:${i.id}`];if(r?.status==='done'||(r?.recovered&&r.recovered<date))continue;
  list.push(occurrenceOf(l,i,date,asgId,{key:`atraso:${date}:${prev}:${i.id}`,overdue:true,previousDate:prev,previousReason:r?.status==='justified'?r.reason:'Não houve registro no dia.'}));
 }
 const map=new Map(list.map(t=>[t.key,t]));for(const [key,r] of Object.entries(db.records)){if(r.date===date&&r.snapshot?.listId===l.id)map.set(key,{...r.snapshot,key,date,asgId:r.asgId||asgId})}
 return sortTasks([...map.values()]);
}
function pickOf(asgId,date=today()){const p=db.picks[`${date}:${asgId}`];return p&&(p.lists||[]).some(id=>listById(id,date))?p:null}
function assumedLists(asgId,date=today()){const p=pickOf(asgId,date);if(p)return p.lists.map(id=>listById(id,date)).filter(Boolean);const one=date>=today()&&soleList(asgId);return one?[one]:[]}
function takersOf(listId,date=today()){return db.users.filter(u=>u.role==='asg'&&(date<today()||u.active)&&assumedLists(u.id,date).some(l=>l.id===listId))}
function tasksFor(asgId,date=today()){
 const map=new Map(assumedLists(asgId,date).flatMap(l=>tasksForList(l,date,asgId)).map(t=>[t.key,t]));
 for(const [key,r] of Object.entries(db.records))if(r.date===date&&r.by===asgId&&r.snapshot)map.set(key,{...r.snapshot,key,date,asgId});
 return sortTasks([...map.values()]);
}
async function saveRecord(t,status,extra={}){
 if(saving||closed())return false;const u=me();db.records[t.key]={status,aid:t.aid,asgId:u.id,date:t.date,by:u.id,byName:u.name,at:new Date().toISOString(),snapshot:{...t},...extra};
 if(!await persist())return false;closeModal();render();toast(status==='done'?'Conclusão salva no servidor.':'Justificativa salva no servidor.');return true;
}
async function reopenRecord(t){delete db.records[t.key];return persist()}
function autoPick(u){const one=soleList(u.id);if(one&&!pickOf(u.id)&&!saving&&!pendingSave){db.picks[`${today()}:${u.id}`]={lists:[one.id],at:new Date().toISOString()};void persist()}return !!pickOf(u.id)}
function photoPath(value){if(!value||value==='demo')return null;if(!value.startsWith('http'))return value;try{const u=new URL(value),prefix='/storage/v1/object/public/fotos/';if(u.origin!==SUPABASE_URL||!u.pathname.startsWith(prefix))return null;return decodeURIComponent(u.pathname.slice(prefix.length))}catch(e){return null}}
async function privatePhotoUrl(value){const path=photoPath(value);if(!path)throw new Error('Foto não disponível.');const {data,error}=await sb.storage.from('fotos').createSignedUrl(path,120);if(error)throw error;return data.signedUrl}
async function hydratePhotos(){for(const img of document.querySelectorAll('img[data-private-photo]')){const value=img.dataset.privatePhoto;delete img.dataset.privatePhoto;try{const url=await privatePhotoUrl(value);if(!img.isConnected)continue;img.src=url;img.addEventListener('load',()=>img.previousElementSibling?.classList.contains('photo-loading')&&img.previousElementSibling.remove(),{once:true})}catch(e){img.alt='Não foi possível carregar a foto. Feche e abra novamente.';if(img.previousElementSibling?.classList.contains('photo-loading'))img.previousElementSibling.textContent=img.alt}}}
async function uploadPhoto(t,dataUrl){const blob=await(await fetch(dataUrl)).blob(),path=`${me().id}/${today()}/${t.aid}-${randomHex(8)}.jpg`;const {error}=await sb.storage.from('fotos').upload(path,blob,{contentType:'image/jpeg',upsert:false});if(error)throw error;return path}
async function confirmPhoto(button){const t=getTasks().find(t=>t.key===photoTask);if(!t||!stagedPhoto||closed())return;button.disabled=true;button.textContent='Enviando e salvando…';try{const path=await uploadPhoto(t,stagedPhoto);await saveRecord(t,'done',{photo:path})}catch(e){toast('A foto ainda não foi salva. Confira a conexão e tente novamente.')}finally{if(button.isConnected){button.disabled=false;button.textContent='Confirmar e concluir'}}}
// Fotos com mais de 30 dias: a gestão apaga uma vez por dia ao abrir o app (regras em supabase/photo-retention.sql).
async function purgeOldPhotos(){
 if(!isManager())return;const mark=`gav-limpeza-fotos:${today()}`;if(readKey(mark))return;
 try{
  for(let round=0;round<20;round++){const {data,error}=await sb.rpc('gav_expired_photos');if(error)throw error;
   const paths=(data||[]).map(x=>typeof x==='string'?x:Object.values(x)[0]).filter(Boolean);if(!paths.length)break;
   const r=await sb.storage.from('fotos').remove(paths);if(r.error)throw r.error;if(paths.length<500)break}
  const {error}=await sb.rpc('gav_forget_missing_photos');if(error)throw error;
  try{localStorage.setItem(mark,'1')}catch(e){}
 }catch(e){console.warn('Limpeza de fotos antigas não concluída:',e.message)}
}
async function exportBackup(){if(saving||pendingSave){toast('Salve as alterações pendentes antes de exportar.');return}try{const [records,picks,closedRows,hist]=await Promise.all([fetchAll('records'),fetchAll('picks'),fetchAll('closed'),fetchAll('config_history','*',q=>q,'version')]);download(`gav-gestao-backup-${today()}.json`,JSON.stringify({version:6,exported:new Date().toISOString(),...db,configHistory:hist,records:Object.fromEntries(records.map(x=>[x.key,x.data])),picks:Object.fromEntries(picks.map(x=>[x.key,{lists:x.lists,at:x.at}])),closed:Object.fromEntries(closedRows.map(x=>[x.key,{time:x.time}]))}));toast('Backup completo exportado.')}catch(e){toast('Não foi possível exportar. Nenhum backup parcial foi gerado.')}}
const syncStyle=document.createElement('style');syncStyle.textContent='.sync-notice{position:fixed;z-index:1000;top:8px;left:50%;transform:translateX(-50%);width:min(94%,640px);background:#fff5dd;color:#423018;padding:12px 16px;border:1px solid #c59a5d;border-radius:12px;box-shadow:0 4px 20px #0002;font-size:14px}.sync-notice[hidden]{display:none}.sync-notice button{margin-top:8px}';document.head.appendChild(syncStyle);
