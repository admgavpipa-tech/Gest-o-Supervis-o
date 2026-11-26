const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {PGlite}=require('@electric-sql/pglite');
const root=path.join(__dirname,'..');
test('banco: lista em conjunto entre ASGs',async t=>{
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
 await t.test('colega conclui o que a outra justificou; conclusão alheia continua protegida',async()=>{
  await actor(a);await apply({picks:{up:[{key:day+':'+a,date:day,asg_id:a,lists:['l']}]}});await actor(b);await apply({picks:{up:[{key:day+':'+b,date:day,asg_id:b,lists:['l']}]}});
  await actor(a);await apply({records:{up:[{key:day+':i',date:day,data:{status:'justified',reason:'Não deu tempo hoje à noite'}}]}});
  await actor(b);const r=await apply({records:{up:[{key:day+':i',date:day,data:{status:'done'}}]}});assert.equal(r.records[0].data.by,b);assert.equal(r.records[0].data.status,'done');
  await actor(a);await rejected(()=>apply({records:{up:[{key:day+':i',date:day,data:{status:'justified',reason:'Tentando voltar atrás'}}]}}),/outra pessoa/);
  await actor(b);await apply({closed:{up:[{key:day+':'+b,date:day,asg_id:b}]}});await actor(a);await apply({closed:{up:[{key:day+':'+a,date:day,asg_id:a}]}})});
 }finally{await db.close()}
});
