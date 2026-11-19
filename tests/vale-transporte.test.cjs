const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {PGlite}=require('@electric-sql/pglite');
const root=path.join(__dirname,'..');
test('vale-transporte: qualquer um envia, só a gestão lê e apaga',async t=>{
 const db=new PGlite();
 try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema storage;create schema extensions;
 create table auth.users(id uuid primary key,email text,encrypted_password text,updated_at timestamptz,email_confirmed_at timestamptz);
 create table auth.identities(user_id uuid,provider text,identity_data jsonb);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;
 create table storage.buckets(id text primary key,name text,public boolean);
 create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,created_at timestamptz default now());
 alter table storage.objects enable row level security;
 grant usage on schema storage to authenticated,anon;grant select,insert,update,delete on storage.objects to authenticated,anon;
 create publication supabase_realtime;`);
 await db.exec(fs.readFileSync(path.join(root,'supabase/schema.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.join(root,'supabase/reliability.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.join(root,'supabase/equipe.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.join(root,'supabase/vale-transporte.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.join(root,'supabase/vale-transporte.sql'),'utf8'));
 await db.exec('grant usage on schema public to anon,authenticated');
 const manager='11111111-1111-4111-8111-111111111111',asg='22222222-2222-4222-8222-222222222222';
 for(const [id,email,role] of [[manager,'m@example.test','gestor'],[asg,'a@example.test','asg']]){await db.query('insert into auth.users(id,email) values($1,$2)',[id,email]);await db.query('insert into public.profiles(id,name,email,role) values($1,$2,$2,$3)',[id,email,role])}
 async function as(role,id=''){await db.exec('reset role');await db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[id]);await db.exec('set role '+role)}
 const send=(v=7.5,nome='Maria da Silva')=>db.query('select gav_vt_responder($1,$2,$3,$4,$5,$6,$7) as id',[nome,'Recepção','Pipa','Centro','Rua A, 10','Perto da igreja',v]);
 await t.test('visitante sem login envia',async()=>{await as('anon');const r=await send();assert.ok(r.rows[0].id>0)});
 await t.test('rejeita valor negativo e nome vazio',async()=>{await as('anon');await assert.rejects(()=>send(-1),/inválido/);await assert.rejects(()=>send(5,' '),/nome/)});
 await t.test('visitante não lê nem escreve direto',async()=>{await as('anon');await assert.rejects(()=>db.query('select * from vt_respostas'),/permission denied/);await assert.rejects(()=>db.query("insert into vt_respostas(nome,setor,regiao,bairro,rua,referencia,valor_ida) values('x','x','x','x','x','x',1)"),/permission denied/)});
 await t.test('ASG logada não vê respostas',async()=>{await as('authenticated',asg);const r=await db.query('select * from vt_respostas');assert.equal(r.rows.length,0)});
 await t.test('gestão lê e apaga',async()=>{await as('authenticated',manager);const r=await db.query('select * from vt_respostas');assert.equal(r.rows.length,1);assert.equal(Number(r.rows[0].valor_ida),7.5);await db.query('delete from vt_respostas where id=$1',[r.rows[0].id]);assert.equal((await db.query('select count(*)::int n from vt_respostas')).rows[0].n,0)});
 }finally{await db.close()}
});
