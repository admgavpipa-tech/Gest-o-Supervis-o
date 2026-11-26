const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {PGlite}=require('@electric-sql/pglite');
const root=path.join(__dirname,'..');
test('banco: área administrativa',async t=>{
 const db=new PGlite();
 try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema storage;create schema extensions;
 create table auth.users(id uuid primary key,email text,encrypted_password text,updated_at timestamptz,email_confirmed_at timestamptz);
 create table auth.identities(user_id uuid,provider text,identity_data jsonb);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;
 create table storage.buckets(id text primary key,name text,public boolean);
 create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,created_at timestamptz default now());
 alter table storage.objects enable row level security;
 grant usage on schema storage to authenticated,anon;grant select,insert,update,delete on storage.objects to authenticated,anon;
 create publication supabase_realtime;`);
 // Instalação existente (schema antigo + atualização) e o script novo, repetido.
 for(const f of ['schema.sql','reliability.sql','equipe.sql','administrativo.sql','administrativo.sql'])await db.exec(fs.readFileSync(path.join(root,'supabase',f),'utf8'));
 const actor=async id=>{await db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[id]);await db.exec('set role authenticated')};
 const owner=()=>db.exec('reset role');
 const ids={gestor:'a1111111-1111-4111-8111-111111111111',analista:'a2222222-2222-4222-8222-222222222222',contratos:'a3333333-3333-4333-8333-333333333333',garcom:'a4444444-4444-4444-8444-444444444444',outro:'a5555555-5555-4555-8555-555555555555'};
 const add=async(kind,data={})=>(await db.query('insert into adm_items(kind,data) values($1,$2) returning *',[kind,JSON.stringify(data)])).rows[0];
 const n=async kind=>(await db.query('select count(*)::int n from adm_items where kind=$1',[kind])).rows[0].n;
 await t.test('perfis novos existem e a gestão os cadastra',async()=>{await owner();for(const [role,id] of Object.entries(ids)){await db.query('insert into auth.users(id,email) values($1,$2)',[id,role+'@x']);await db.query('insert into profiles(id,name,email,role) values($1,$2,$3,$4)',[id,role==='outro'?'Outro Analista':'Pessoa '+role,id+'@x',role==='outro'?'analista':role])}
  await assert.rejects(()=>db.query(`insert into profiles(id,name,email,role) values(gen_random_uuid(),'X','x@x','recepcao')`),/check constraint/)});
 await t.test('pedido de acesso aceita os perfis administrativos',async()=>{const novo='a6666666-6666-4666-8666-666666666666';await owner();await db.query(`insert into auth.users(id,email) values($1,'novo@x')`,[novo]);await actor(novo);await db.query(`select gav_request_access('Nova Analista','analista')`);await owner();assert.equal((await db.query('select role,pending from profiles where id=$1',[novo])).rows[0].role,'analista')});
 await t.test('cronograma: cada um vê só o seu; cada um cria tarefa para si',async()=>{await actor(ids.gestor);const tk=await add('tarefa',{title:'Checklist da sala',assignees:[ids.contratos]});assert.equal(tk.created_by,ids.gestor);assert.equal(tk.created_by_name,'Pessoa gestor');await add('caixa',{name:'SPIF'});
  await actor(ids.analista);assert.equal(await n('tarefa'),1,'analista vê a tarefa da colega do administrativo');assert.equal(await n('caixa'),1);await assert.rejects(()=>add('caixa',{name:'x'}),/row-level security/);
  await assert.rejects(()=>add('tarefa',{title:'Para o outro',assignees:[ids.contratos]}),/row-level security/);const mine=await add('tarefa',{title:'Minha',assignees:[ids.analista]});assert.equal(await n('tarefa'),2);
  await db.query(`update adm_items set data=data||'{"title":"Minha editada"}' where id=$1`,[mine.id]);const fd=await add('tarefa_feita',{task:tk.id,date:'2026-11-25'});assert.equal(fd.created_by,ids.analista,'conclui a tarefa da colega');
  await actor(ids.contratos);assert.equal(await n('tarefa'),2,'vê a própria e a da colega');assert.equal(await n('caixa'),0,'contratos não vê caixas');await db.query(`update adm_items set data=data||'{"title":"x"}' where id=$1`,[tk.id]);await owner();assert.equal((await db.query('select data->>$2 t from adm_items where id=$1',[tk.id,'title'])).rows[0].t,'Checklist da sala','não altera tarefa da gestão')});
 await t.test('gestão libera funções extras por pessoa',async()=>{await actor(ids.contratos);assert.equal(await n('pedido'),0);await owner();await db.query(`update profiles set adm_modules=array['contratos','chamados','pedidos'] where id=$1`,[ids.contratos]);await actor(ids.analista);await add('pedido',{month:'2026-11'});await actor(ids.contratos);assert.equal(await n('pedido'),1);await add('pedido',{month:'2026-12'});await owner();await db.query(`update profiles set adm_modules=null where id=$1`,[ids.contratos]);await db.query(`delete from adm_items where kind='pedido'`)});
 await t.test('analista registra notas, pedidos e pagamentos com autoria do servidor; contratos não vê',async()=>{await actor(ids.analista);const p=await add('parceiro',{name:'Parceiro X',type:'parceiro'});await add('nota',{partner:p.id,month:'2026-11'});await add('pedido',{month:'2026-11'});const pg=await add('pagamento',{value:300});assert.equal(pg.created_by_name,'Pessoa analista');
  await db.query(`update adm_items set data=data||'{"value":350}', created_by=$2, kind='caixa' where id=$1`,[pg.id,ids.outro]);const after=(await db.query('select * from adm_items where id=$1',[pg.id])).rows[0];assert.equal(after.data.value,350);assert.equal(after.created_by,ids.analista,'autoria não muda');assert.equal(after.kind,'pagamento','tipo não muda');
  await actor(ids.contratos);for(const k of ['parceiro','nota','pedido','pagamento'])assert.equal(await n(k),0,k);await assert.rejects(()=>add('pagamento',{}),/row-level security/);
  await actor(ids.gestor);assert.equal(await n('pagamento'),1)});
 await t.test('contratos registra chamados; analista não vê',async()=>{await actor(ids.contratos);await add('chamado',{number:'123',status:'aberto'});await actor(ids.analista);assert.equal(await n('chamado'),0);await assert.rejects(()=>add('chamado',{}),/row-level security/);await actor(ids.gestor);assert.equal(await n('chamado'),1)});
 await t.test('conclusão de tarefa: só da própria tarefa e cada um apaga só a sua; garçom não acessa nada',async()=>{await actor(ids.gestor);const tk=await add('tarefa',{title:'Rasgar caixas',assignees:[ids.analista,ids.outro]});
  await actor(ids.analista);const d=await add('tarefa_feita',{task:tk.id,date:'2026-11-25'});await actor(ids.outro);assert.equal((await db.query(`select count(*)::int n from adm_items where kind='tarefa_feita' and data->>'task'=$1`,[tk.id])).rows[0].n,1,'colega da mesma tarefa vê a conclusão');await db.query('delete from adm_items where id=$1',[d.id]);await owner();assert.equal((await db.query(`select count(*)::int n from adm_items where kind='tarefa_feita' and data->>'task'=$1`,[tk.id])).rows[0].n,1,'outro analista não apaga');
  await actor(ids.analista);await db.query('delete from adm_items where id=$1',[d.id]);await owner();assert.equal((await db.query(`select count(*)::int n from adm_items where kind='tarefa_feita' and data->>'task'=$1`,[tk.id])).rows[0].n,0);
  await actor(ids.garcom);assert.equal((await db.query('select count(*)::int n from adm_items')).rows[0].n,0);await assert.rejects(()=>add('chamado',{}),/row-level security/);await assert.rejects(()=>add('tarefa',{title:'x',assignees:[ids.garcom]}),/row-level security/)});
 await t.test('quem lançou pode auditar o próprio contrato; pagamento não é apagado por quem não é gestão',async()=>{await actor(ids.contratos);const c=await add('contrato',{cliente:'X',lancamento:{name:'C',id:ids.contratos}});
  await db.query(`update adm_items set data=data||'{"audit":{"by":"C"}}' where id=$1`,[c.id]);
  await actor(ids.analista);const pg=await add('pagamento',{value:1});await db.query('delete from adm_items where id=$1',[pg.id]);await owner();assert.equal((await db.query('select count(*)::int n from adm_items where id=$1',[pg.id])).rows[0].n,1,'analista não apaga');await actor(ids.gestor);await db.query('delete from adm_items where id=$1',[pg.id]);await owner();assert.equal((await db.query('select count(*)::int n from adm_items where id=$1',[pg.id])).rows[0].n,0)});
 await t.test('perfil inativo perde o acesso',async()=>{await owner();await db.query('update profiles set active=false where id=$1',[ids.contratos]);await actor(ids.contratos);assert.equal(await n('chamado'),0)});
 await t.test('equipe do administrativo: transfere a tarefa do dia, mas não cria para outra; tarefa só da gestão fica fora',async()=>{await actor(ids.gestor);const tk=await add('tarefa',{title:'Relatório',assignees:[ids.contratos]});const priv=await add('tarefa',{title:'Só gestão',assignees:[ids.gestor]});
  await actor(ids.analista);const tr=await add('tarefa_transf',{task:tk.id,date:'2026-11-26',from:ids.contratos,to:ids.analista});assert.equal(tr.created_by,ids.analista);
  await assert.rejects(()=>add('tarefa_transf',{task:priv.id,date:'2026-11-26',from:ids.gestor,to:ids.analista}),/row-level security/,'não transfere tarefa só da gestão');
  await assert.rejects(()=>add('tarefa_feita',{task:priv.id,date:'2026-11-26'}),/row-level security/);assert.equal((await db.query('select count(*)::int n from adm_items where id=$1',[priv.id])).rows[0].n,0,'não vê tarefa só da gestão');
  await assert.rejects(()=>add('tarefa',{title:'Para a colega',assignees:[ids.contratos]}),/row-level security/,'não cria tarefa para outra');
  await actor(ids.outro);assert.equal((await db.query(`select count(*)::int n from adm_items where kind='tarefa_transf'`)).rows[0].n,1,'a colega vê a transferência');await db.query('delete from adm_items where id=$1',[tr.id]);
  await actor(ids.analista);assert.equal((await db.query(`select count(*)::int n from adm_items where kind='tarefa_transf'`)).rows[0].n,1,'só quem transferiu (ou a gestão) desfaz');await db.query('delete from adm_items where id=$1',[tr.id]);assert.equal((await db.query(`select count(*)::int n from adm_items where kind='tarefa_transf'`)).rows[0].n,0);
  await actor(ids.garcom);await assert.rejects(()=>add('tarefa_transf',{task:tk.id}),/row-level security/)});
 await t.test('privacidade: e-mail só para a gestão e a própria pessoa; sem login nada é lido; gestor automático não volta',async()=>{
  for(const who of ['garcom','analista','contratos']){await actor(ids[who]);await assert.rejects(()=>db.query('select email from profiles'),/permission denied/,who+' não lê e-mails');await assert.rejects(()=>db.query('select * from profiles'),/permission denied/);
   if(who!=='contratos')assert.ok((await db.query('select id,name,role from profiles')).rows.length>3,who+' ainda vê nomes');const m=(await db.query('select * from gav_profile_emails()')).rows;assert.deepEqual(m.map(x=>x.id),[ids[who]],who+' recebe só o próprio e-mail')}
  await owner();await db.query(`insert into records(key,data,date) values('k1','{}','2026-11-25') on conflict do nothing`);await db.query(`insert into storage.objects(bucket_id,name) values('fotos','x/1.jpg')`);
  for(const who of ['garcom','analista']){await actor(ids[who]);assert.equal((await db.query('select count(*)::int n from records')).rows[0].n,0,who+' não lê registros da limpeza');assert.equal((await db.query(`select count(*)::int n from storage.objects where bucket_id='fotos'`)).rows[0].n,0,who+' não vê fotos')}
  await actor(ids.gestor);assert.ok((await db.query('select * from gav_profile_emails()')).rows.length>4,'gestão recebe todos');
  assert.equal((await db.query('select count(*)::int n from records')).rows[0].n,1,'gestão lê registros');
  await db.query(`update profiles set name='Pessoa gestor' where id=$1`,[ids.gestor]);
  await owner();await db.exec('set role anon');for(const tb of ['profiles','app_state','records','counts','adm_items'])await assert.rejects(()=>db.query(`select 1 from ${tb} limit 1`),/permission denied/,'anon '+tb);
  await assert.rejects(()=>db.query('select * from gav_profile_emails()'),/permission denied/);
  await owner();const intruso='a7777777-7777-4777-8777-777777777777';await db.query(`insert into auth.users(id,email) values($1,'carlos.santos@gavresorts.com.br')`,[intruso]);
  assert.equal((await db.query('select count(*)::int n from profiles where id=$1',[intruso])).rows[0].n,0,'com gestão ativa, o e-mail do primeiro gestor não vira gestor')});
 }finally{await db.close()}
});
