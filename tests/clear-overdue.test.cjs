const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {PGlite}=require('@electric-sql/pglite');
const root=path.join(__dirname,'..');
test('banco: gestão limpa tarefas atrasadas',async t=>{
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
 // Instalação existente: schema, atualização de confiabilidade e o script novo (repetido).
 for(const f of ['schema.sql','reliability.sql','clear-overdue.sql','clear-overdue.sql'])await db.exec(fs.readFileSync(path.join(root,'supabase',f),'utf8'));
 const manager='11111111-1111-4111-8111-111111111111',a='22222222-2222-4222-8222-222222222222';
 for(const [id,email,role] of [[manager,'m@example.test','gestor'],[a,'a@example.test','asg']]){await db.query('insert into auth.users(id,email) values($1,$2)',[id,email]);await db.query('insert into public.profiles(id,name,email,role) values($1,$2,$3,$4) on conflict(id) do update set role=excluded.role',[id,email,email,role])}
 const day=(await db.query('select gav_today()::text as d')).rows[0].d,past=(await db.query('select (gav_today()-3)::text as d')).rows[0].d;
 const cfg={rooms:[{id:'r',name:'Salão'}],tasks:[{id:'t1',roomId:'r',title:'Antiga',photoRequired:false},{id:'t2',roomId:'r',title:'Justificada hoje',photoRequired:false}],
  lists:[{id:'l',name:'Lista',asgIds:[a],items:[{id:'i1',taskId:'t1',active:true,start:past,created:past+'T12:00:00Z',repeat:{type:'once'}},{id:'i2',taskId:'t2',active:true,start:past,created:past+'T12:00:00Z',repeat:{type:'once'}}]}]};
 const actor=async id=>{await db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[id]);await db.exec('set role authenticated')};
 const apply=async(changes,v)=>(await db.query('select gav_apply_changes($1,$2::jsonb) as r',[v,JSON.stringify(changes)])).rows[0].r;
 const expected=async()=>{await db.exec('reset role');return (await db.query(`select key from gav_expected('["l"]'::jsonb,gav_today()) order by key`)).rows.map(r=>r.key)};
 await actor(manager);await apply({cfg},0);
 await actor(a);await apply({picks:{up:[{key:day+':'+a,date:day,asg_id:a,lists:['l']}]}},1);
 const late1='atraso:'+day+':'+past+':i1',late2='atraso:'+day+':'+past+':i2';
 await apply({records:{up:[{key:late2,date:day,data:{status:'justified',reason:'Ambiente ocupado hoje'}}]}},1);
 assert.deepEqual(await expected(),[late1,late2]);
 await t.test('ASG não pode limpar atrasadas',async()=>{await actor(a);await assert.rejects(()=>db.query('select gav_clear_overdue()'),/Somente a gestão/)});
 await t.test('gestão limpa só a atrasada pendente',async()=>{await actor(manager);assert.equal((await db.query('select gav_clear_overdue() as n')).rows[0].n,1);
  assert.deepEqual(await expected(),[late2]);
  const prev=(await db.query('select data from records where key=$1',[past+':i1'])).rows[0].data;assert.equal(prev.dismissed,day);assert.equal(prev.status,'missed');assert.equal(prev.dismissedBy,manager);
  await actor(manager);assert.equal((await db.query('select gav_clear_overdue() as n')).rows[0].n,0)});
 await t.test('ASG finaliza o dia depois da limpeza',async()=>{await actor(a);await apply({closed:{up:[{key:day+':'+a,date:day,asg_id:a}]}},1);await db.exec('reset role');assert.equal((await db.query('select count(*)::int as n from closed')).rows[0].n,1)});
 }finally{await db.close()}
});
