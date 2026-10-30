const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {PGlite}=require('@electric-sql/pglite');
const root=path.join(__dirname,'..');
test('banco: autorização, fechamento, concorrência, fotos e histórico',async t=>{
 const db=new PGlite();
 try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema storage;create schema extensions;
 create table auth.users(id uuid primary key,email text,encrypted_password text,updated_at timestamptz,email_confirmed_at timestamptz);
 create table auth.identities(user_id uuid,provider text,identity_data jsonb);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;
 create table storage.buckets(id text primary key,name text,public boolean);
 create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);
 alter table storage.objects enable row level security;
 grant usage on schema storage to authenticated,anon;grant select,insert,update,delete on storage.objects to authenticated,anon;
 create publication supabase_realtime;`);
 await db.exec(fs.readFileSync(path.join(root,'supabase/schema.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.join(root,'supabase/reliability.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.join(root,'supabase/reliability.sql'),'utf8'));
 const manager='11111111-1111-4111-8111-111111111111',a='22222222-2222-4222-8222-222222222222',b='33333333-3333-4333-8333-333333333333';
 for(const [id,email,role] of [[manager,'manager@example.test','gestor'],[a,'a@example.test','asg'],[b,'b@example.test','asg']]){await db.query('insert into auth.users(id,email) values($1,$2)',[id,email]);await db.query('insert into public.profiles(id,name,email,role) values($1,$2,$2,$3)',[id,email,role])}
 const day=(await db.query('select gav_today()::text as d')).rows[0].d;
 const cfg={rooms:[{id:'r',name:'Salão'}],tasks:[{id:'t',roomId:'r',title:'Limpar',photoRequired:false}],lists:[{id:'l',name:'Lista',asgIds:[a,b],items:[{id:'i',taskId:'t',active:true,start:day,created:day+'T12:00:00Z',repeat:{type:'daily',every:1}}]}]};
 async function actor(id){await db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[id]);await db.exec('set role authenticated')}
 async function owner(){await db.exec('reset role')}
 async function apply(changes,expected=1){return (await db.query('select gav_apply_changes($1,$2::jsonb) as result',[expected,JSON.stringify(changes)])).rows[0].result}
 async function rejected(fn,regex){await assert.rejects(fn,regex)}
 await actor(manager);await apply({cfg},0);
 await t.test('nega escrita direta de ASG em registros',async()=>{await actor(a);await rejected(()=>db.query("insert into records(key,data,date) values('fake','{}',$1)",[day]),/permission denied/)});
 await t.test('nega alterar programação usando conta ASG',async()=>{await actor(a);await rejected(()=>apply({cfg}),/Somente a gestão/)});
 await t.test('nega escolher lista não liberada ou de outra pessoa',async()=>{await actor(a);await rejected(()=>apply({picks:{up:[{key:day+':'+b,date:day,asg_id:b,lists:['l']}]}}),/outra pessoa/);await rejected(()=>apply({picks:{up:[{key:day+':'+a,date:day,asg_id:a,lists:['inexistente']}]}}),/não liberada/)});
 await t.test('aceita escolha válida',async()=>{await actor(a);await apply({picks:{up:[{key:day+':'+a,date:day,asg_id:a,lists:['l']}]}})});
 await t.test('nega finalizar com tarefa pendente',async()=>{await actor(a);await rejected(()=>apply({closed:{up:[{key:day+':'+a,date:day,asg_id:a}]}}),/Ainda há tarefas/)});
 await t.test('nega ocorrência inventada e justificativa curta',async()=>{await actor(a);await rejected(()=>apply({records:{up:[{key:day+':fake',date:day,data:{status:'done'}}]}}),/não pertence/);await rejected(()=>apply({records:{up:[{key:day+':i',date:day,data:{status:'justified',reason:'não'}}]}}),/10 caracteres/)});
 await t.test('conclusão recebe autoria e metadados do servidor',async()=>{await actor(a);const r=await apply({records:{up:[{key:day+':i',date:day,data:{status:'done',by:b,byName:'Forjado',snapshot:{title:'Forjado'}}}]}});assert.equal(r.records[0].data.by,a);assert.equal(r.records[0].data.snapshot.title,'Limpar')});
 await t.test('outra ASG não altera nem apaga a conclusão',async()=>{await actor(b);await rejected(()=>apply({records:{up:[{key:day+':i',date:day,data:{status:'justified',reason:'Outro motivo qualquer'}}]}}),/outra pessoa/);await rejected(()=>apply({records:{del:[day+':i']}}),/outra pessoa/)});
 await t.test('aceita finalizar após resolver; bloqueia reabertura depois',async()=>{await actor(a);await apply({closed:{up:[{key:day+':'+a,date:day,asg_id:a}]}});await rejected(()=>apply({records:{del:[day+':i']}}),/encerrado/)});
 await t.test('conflito de versão não sobrescreve outra edição',async()=>{await actor(manager);const next=structuredClone(cfg);next.rooms.push({id:'r2',name:'Copa'});await apply({cfg:next},1);await rejected(()=>apply({cfg},1),/outro gestor/);const r=await db.query('select data,version from app_state');assert.equal(r.rows[0].version,2);assert.equal(r.rows[0].data.rooms.length,2)});
 await t.test('mantém versão anterior e conclusão após exclusão',async()=>{await actor(manager);await apply({cfg:{rooms:[],tasks:[],lists:[]}},2);const hist=await db.query('select data from config_history where version=1');assert.equal(hist.rows[0].data.tasks[0].title,'Limpar');const rec=await db.query('select data from records where key=$1',[day+':i']);assert.equal(rec.rows[0].data.snapshot.title,'Limpar')});
 await t.test('arquivar ASG não apaga escolhas nem fechamento',async()=>{await actor(manager);await db.query('select admin_delete_user($1)',[a]);assert.equal((await db.query('select archived,active from profiles where id=$1',[a])).rows[0].archived,true);assert.equal((await db.query('select count(*)::int as n from picks')).rows[0].n,1);assert.equal((await db.query('select count(*)::int as n from closed')).rows[0].n,1)});
 await t.test('foto é privada e envio exige pasta da pessoa autenticada',async()=>{await owner();assert.equal((await db.query("select public from storage.buckets where id='fotos'")).rows[0].public,false);await actor(b);await rejected(()=>db.query("insert into storage.objects(bucket_id,name) values('fotos','outra-pessoa/x.jpg')"),/row-level security/);await db.query("insert into storage.objects(bucket_id,name) values('fotos',$1)",[b+'/foto.jpg']);await owner();await db.exec('set role anon');assert.equal((await db.query('select * from storage.objects')).rows.length,0)});
 await t.test('servidor mantém atraso antigo e ajusta fevereiro',async()=>{await owner();assert.equal((await db.query(`select gav_previous($1::jsonb,'2026-10-29')::text as d`,[JSON.stringify({start:'2026-01-01',repeat:{type:'once'}})])).rows[0].d,'2026-01-01');assert.equal((await db.query(`select gav_previous($1::jsonb,'2026-03-20')::text as d`,[JSON.stringify({start:'2026-01-31',repeat:{type:'monthly',every:1,day:31}})])).rows[0].d,'2026-02-28')});
 await t.test('foto obrigatória, recuperação antiga e fechamento atômico',async()=>{
  await owner();const past=(await db.query('select (gav_today()-20)::text as d')).rows[0].d;
  const newer={rooms:[{id:'r',name:'Salão'}],tasks:[{id:'photo',roomId:'r',title:'Fotografar',photoRequired:true},{id:'late',roomId:'r',title:'Antiga',photoRequired:false}],lists:[{id:'l2',name:'Lista nova',asgIds:[b],items:[{id:'j',taskId:'photo',active:true,start:day,created:day+'T12:00:00Z',repeat:{type:'daily',every:1}},{id:'old',taskId:'late',active:true,start:past,created:past+'T12:00:00Z',repeat:{type:'once'}}]}]};
  await actor(manager);await apply({cfg:newer},3);await actor(b);await apply({picks:{up:[{key:day+':'+b,date:day,asg_id:b,lists:['l2']}]}});
  await rejected(()=>apply({records:{up:[{key:day+':j',date:day,data:{status:'done'}}]}}),/foto é obrigatória/);
  await rejected(()=>apply({records:{up:[{key:day+':j',date:day,data:{status:'done',photo:a+'/foto.jpg'}}]}}),/foto inválido/);
  await apply({records:{up:[{key:day+':j',date:day,data:{status:'done',photo:b+'/foto.jpg'}}]}});
  const latekey='atraso:'+day+':'+past+':old';await apply({records:{up:[{key:latekey,date:day,data:{status:'done'}}]}});
  assert.equal((await db.query('select data from records where key=$1',[past+':old'])).rows[0].data.recovered,day);
  await apply({records:{del:[latekey]}});assert.equal((await db.query('select data from records where key=$1',[past+':old'])).rows.length,0);
  await rejected(()=>apply({records:{up:[{key:latekey,date:day,data:{status:'justified',reason:'Ambiente ocupado hoje'}},{key:day+':inventado',date:day,data:{status:'done'}}]},closed:{up:[{key:day+':'+b,date:day,asg_id:b}]}}),/não pertence/);
  assert.equal((await db.query('select data from records where key=$1',[latekey])).rows.length,0);
  assert.equal((await db.query('select * from closed where asg_id=$1',[b])).rows.length,0);
  await apply({records:{up:[{key:latekey,date:day,data:{status:'justified',reason:'Ambiente ocupado hoje'}}]},closed:{up:[{key:day+':'+b,date:day,asg_id:b}]}});
 });
 await t.test('atualização preserva comprovante legado e preenche metadados',async()=>{
  await owner();const prev=(await db.query('select (gav_today()-1)::text as d')).rows[0].d;
  await db.query('insert into records(key,date,data) values($1,$2,$3)',[prev+':j',prev,JSON.stringify({aid:'j',by:b,byName:'Legado',date:prev,status:'done',photo:'https://lwegjqiavjfprrapxjle.supabase.co/storage/v1/object/public/fotos/antiga/foto.jpg'})]);
  await db.query('insert into records(key,date,data) values($1,$2,$3)',[prev+':removido',prev,JSON.stringify({aid:'removido',by:b,byName:'Legado',date:prev,status:'done',photo:'https://lwegjqiavjfprrapxjle.supabase.co/storage/v1/object/public/fotos/antiga/outra.jpg'})]);
  await db.exec(fs.readFileSync(path.join(root,'supabase/reliability.sql'),'utf8'));
  const legacy=(await db.query('select data from records where key=$1',[prev+':j'])).rows[0].data;
  assert.equal(legacy.snapshot.title,'Fotografar');assert.match(legacy.photo,/antiga\/foto.jpg/);
  const orphan=(await db.query('select data from records where key=$1',[prev+':removido'])).rows[0].data;
  assert.equal(orphan.snapshot.listId,'historico-anterior');assert.equal(orphan.snapshot.title,'Atividade de cadastro anterior');assert.match(orphan.photo,/antiga\/outra.jpg/);
 });
 }finally{await db.close()}
});
