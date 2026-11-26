-- GAV · Gestão de limpeza: estrutura do banco no Supabase.
-- Cole este arquivo inteiro em SQL Editor > New query e clique em Run.
-- Pode ser executado de novo sem perder dados.

-- Perfis: um por login. role = 'gestor', 'asg' ou 'garcom' (lista ampliada no fim do arquivo).
create table if not exists public.profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  email text not null,
  role text not null check (role in ('gestor','asg')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Cômodos, tarefas e listas (um único documento editado pela gestão).
create table if not exists public.app_state(
  id int primary key default 1 check (id = 1),
  data jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

-- Conclusões e justificativas, uma linha por tarefa do dia.
create table if not exists public.records(
  key text primary key,
  data jsonb not null,
  date date,
  updated_at timestamptz not null default now()
);

-- Lista(s) que cada ASG assumiu em cada dia.
create table if not exists public.picks(
  key text primary key,
  asg_id uuid not null references public.profiles(id) on delete cascade,
  date date not null,
  lists jsonb not null,
  at timestamptz not null default now()
);

-- Dias finalizados por cada ASG.
create table if not exists public.closed(
  key text primary key,
  asg_id uuid not null references public.profiles(id) on delete cascade,
  date date not null,
  time text
);

create index if not exists records_date_idx on public.records(date);
create index if not exists picks_date_idx on public.picks(date);
create index if not exists closed_date_idx on public.closed(date);

create or replace function public.is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and active)
$$;

create or replace function public.is_manager() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and active and role = 'gestor')
$$;

alter table public.profiles enable row level security;
alter table public.app_state enable row level security;
alter table public.records enable row level security;
alter table public.picks enable row level security;
alter table public.closed enable row level security;

grant select, insert, update, delete on public.profiles, public.app_state, public.records, public.picks, public.closed to authenticated;

drop policy if exists "perfis: leitura" on public.profiles;
create policy "perfis: leitura" on public.profiles for select to authenticated using (public.is_member() or id = auth.uid());
drop policy if exists "perfis: gestão" on public.profiles;
create policy "perfis: gestão" on public.profiles for all to authenticated using (public.is_manager()) with check (public.is_manager());

drop policy if exists "estrutura: leitura" on public.app_state;
create policy "estrutura: leitura" on public.app_state for select to authenticated using (public.is_member());
drop policy if exists "estrutura: gestão" on public.app_state;
create policy "estrutura: gestão" on public.app_state for all to authenticated using (public.is_manager()) with check (public.is_manager());

-- A equipe registra as tarefas das listas que assume (inclusive a de uma colega que faltou).
drop policy if exists "registros: equipe" on public.records;
create policy "registros: equipe" on public.records for all to authenticated using (public.is_member()) with check (public.is_member());

drop policy if exists "escolhas: leitura" on public.picks;
create policy "escolhas: leitura" on public.picks for select to authenticated using (public.is_member());
drop policy if exists "escolhas: própria ou gestão" on public.picks;
create policy "escolhas: própria ou gestão" on public.picks for all to authenticated
  using (public.is_manager() or (asg_id = auth.uid() and public.is_member()))
  with check (public.is_manager() or (asg_id = auth.uid() and public.is_member()));

drop policy if exists "fechamentos: leitura" on public.closed;
create policy "fechamentos: leitura" on public.closed for select to authenticated using (public.is_member());
drop policy if exists "fechamentos: própria ou gestão" on public.closed;
create policy "fechamentos: própria ou gestão" on public.closed for all to authenticated
  using (public.is_manager() or (asg_id = auth.uid() and public.is_member()))
  with check (public.is_manager() or (asg_id = auth.uid() and public.is_member()));

-- A gestão confirma o acesso, troca e-mail ou senha de outra pessoa.
create or replace function public.admin_set_login(target uuid, new_email text default null, new_password text default null)
returns void language plpgsql security definer set search_path = public, auth, extensions as $$
begin
  if not public.is_manager() then raise exception 'Somente a gestão pode alterar acessos.'; end if;
  if new_email is not null and new_email <> '' then
    update auth.users set email = lower(new_email), updated_at = now() where id = target;
    update auth.identities set identity_data = identity_data || jsonb_build_object('email', lower(new_email)) where user_id = target and provider = 'email';
  end if;
  if new_password is not null and new_password <> '' then
    update auth.users set encrypted_password = extensions.crypt(new_password, extensions.gen_salt('bf')), updated_at = now() where id = target;
  end if;
  update auth.users set email_confirmed_at = coalesce(email_confirmed_at, now()) where id = target;
end $$;

create or replace function public.admin_delete_user(target uuid)
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.is_manager() then raise exception 'Somente a gestão pode excluir acessos.'; end if;
  if target = auth.uid() then raise exception 'Você não pode excluir o próprio acesso.'; end if;
  delete from auth.users where id = target;
end $$;

revoke all on function public.admin_set_login(uuid, text, text) from public, anon;
revoke all on function public.admin_delete_user(uuid) from public, anon;
grant execute on function public.admin_set_login(uuid, text, text) to authenticated;
grant execute on function public.admin_delete_user(uuid) to authenticated;

-- Primeiro gestor: quando o login de Carlos existir em Authentication > Users, ele vira gestor.
create or replace function public.gav_first_manager() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if lower(new.email) = 'carlos.santos@gavresorts.com.br' then
    insert into public.profiles(id, name, email, role) values (new.id, 'Carlos Santos', lower(new.email), 'gestor')
    on conflict (id) do update set role = 'gestor', active = true;
  end if;
  return new;
end $$;
drop trigger if exists gav_first_manager on auth.users;
create trigger gav_first_manager after insert on auth.users for each row execute function public.gav_first_manager();
insert into public.profiles(id, name, email, role)
  select id, 'Carlos Santos', lower(email), 'gestor' from auth.users where lower(email) = 'carlos.santos@gavresorts.com.br'
    and not exists(select 1 from public.profiles where role = 'gestor' and active)
  on conflict (id) do update set role = 'gestor', active = true;

-- Fotos das tarefas concluídas.
insert into storage.buckets(id, name, public) values ('fotos', 'fotos', true) on conflict (id) do nothing;
drop policy if exists "fotos: envio pela equipe" on storage.objects;
create policy "fotos: envio pela equipe" on storage.objects for insert to authenticated with check (bucket_id = 'fotos' and public.is_member());
drop policy if exists "fotos: leitura" on storage.objects;
create policy "fotos: leitura" on storage.objects for select using (bucket_id = 'fotos');

-- Atualização em tempo real entre aparelhos.
do $$ begin alter publication supabase_realtime add table public.profiles; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.app_state; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.records; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.picks; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.closed; exception when duplicate_object then null; end $$;

-- ATUALIZAÇÃO DE INTEGRIDADE INCLUÍDA
-- GAV: atualização de integridade. Executar após schema.sql; transação, sem apagar dados.
begin;
alter table public.app_state add column if not exists version bigint not null default 1;
alter table public.profiles add column if not exists archived boolean not null default false;
create or replace function public.is_member() returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from profiles where id=auth.uid() and active and not archived)
$$;
create or replace function public.is_manager() returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from profiles where id=auth.uid() and active and not archived and role='gestor')
$$;
create table if not exists public.config_history(
  version bigint primary key,
  data jsonb not null,
  recorded_at timestamptz not null default now()
);
alter table public.config_history enable row level security;
grant select on public.config_history to authenticated;
drop policy if exists "histórico: leitura" on public.config_history;
create policy "histórico: leitura" on public.config_history for select to authenticated using(public.is_member());
insert into public.config_history(version,data,recorded_at)
select version,data,updated_at from public.app_state on conflict do nothing;

create or replace function public.gav_config_history() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  insert into config_history(version,data,recorded_at) values(new.version,new.data,new.updated_at);
  return new;
end $$;
drop trigger if exists gav_config_history on public.app_state;
create trigger gav_config_history after insert or update on public.app_state for each row execute function public.gav_config_history();

create or replace function public.gav_today() returns date
language sql stable as $$ select (now() at time zone 'America/Sao_Paulo')::date $$;

create or replace function public.gav_occurs(a jsonb,d date) returns boolean
language plpgsql immutable set search_path=public as $$
declare s date:=(a->>'start')::date; e date:=nullif(a->>'end','')::date;
 r jsonb:=coalesce(a->'repeat','{"type":"once"}'); n int:=greatest(1,coalesce((r->>'every')::int,1));
 wd int; monthdiff int; md int;
begin
 if s is null or d<s or (e is not null and d>e) then return false; end if;
 case r->>'type'
 when 'once' then return d=s;
 when 'daily' then return (d-s)%n=0;
 when 'weekly' then
   wd:=extract(dow from d)::int;
   if jsonb_array_length(coalesce(r->'weekdays','[]'))>0 then
     if not (r->'weekdays' @> to_jsonb(array[wd])) then return false; end if;
   elsif wd<>extract(dow from s)::int then return false;
   end if;
   return ((d-(s-extract(dow from s)::int))/7)%n=0;
 when 'monthly' then
   md:=least(coalesce((r->>'day')::int,1),extract(day from (date_trunc('month',d)+interval '1 month - 1 day'))::int);
   monthdiff:=(extract(year from d)::int-extract(year from s)::int)*12+extract(month from d)::int-extract(month from s)::int;
   return extract(day from d)::int=md and monthdiff%n=0;
 else return false;
 end case;
end $$;

create or replace function public.gav_previous(a jsonb,d date) returns date
language plpgsql immutable set search_path=public as $$
declare s date:=(a->>'start')::date; u date:=least(d-1,coalesce(nullif(a->>'end','')::date,d-1));
 r jsonb:=coalesce(a->'repeat','{"type":"once"}'); n int:=greatest(1,coalesce((r->>'every')::int,1)); lowdate date; found date;
begin
 if u<s then return null; end if;
 if r->>'type'='once' then return s; end if;
 if r->>'type'='daily' then return s+((u-s)/n)*n; end if;
 lowdate:=greatest(s,u-(case when r->>'type'='weekly' then n*7+7 else n*32+32 end));
 select max(x::date) into found from generate_series(lowdate::timestamp,u::timestamp,interval '1 day') x where public.gav_occurs(a,x::date);
 return found;
end $$;

-- Calcula a obrigação no servidor usando a mesma frequência da interface.
create or replace function public.gav_expected(list_ids jsonb,d date)
returns table(key text,data jsonb) language plpgsql stable security definer set search_path=public as $$
declare cfg jsonb; l jsonb; i jsonb; t jsonb; room jsonb; prev date; oldrec jsonb; late boolean; k text;
begin
 select a.data into cfg from app_state a where id=1;
 for l in select x from jsonb_array_elements(coalesce(cfg->'lists','[]')) x where list_ids @> jsonb_build_array(x->>'id') loop
  for i in select x from jsonb_array_elements(coalesce(l->'items','[]')) x where coalesce((x->>'active')::boolean,false) and not coalesce((x->>'removed')::boolean,false) loop
   select x into t from jsonb_array_elements(cfg->'tasks') x where x->>'id'=i->>'taskId';
   if t is null then continue; end if;
   select x into room from jsonb_array_elements(cfg->'rooms') x where x->>'id'=t->>'roomId';
   late:=not gav_occurs(i,d); prev:=null;
   if late then
    prev:=gav_previous(i,d);
    if prev is null or prev<coalesce(((i->>'created')::timestamptz at time zone 'America/Sao_Paulo')::date,(i->>'start')::date) then continue; end if;
    select r.data into oldrec from records r where r.key=prev::text||':'||(i->>'id');
    if oldrec->>'status'='done' or nullif(oldrec->>'recovered','')::date<d or nullif(oldrec->>'dismissed','')::date<=d then continue; end if;
   end if;
   k:=case when late then 'atraso:'||d::text||':'||prev::text||':' else d::text||':' end||(i->>'id');
   key:=k;
   data:=jsonb_build_object('key',k,'date',d,'aid',i->>'id','listId',l->>'id','listName',l->>'name','title',t->>'title',
    'local',coalesce(room->>'name','Sem cômodo'),'instructions',t->>'instructions','materials',t->>'materials',
    'photoRequired',coalesce((t->>'photoRequired')::boolean,true),'essential',coalesce((t->>'essential')::boolean,false),
    'notes',i->>'notes','repeat',i->'repeat','start',i->>'start','end',i->>'end','overdue',late,'previousDate',prev,
    'previousReason',case when oldrec->>'status'='justified' then oldrec->>'reason' else 'Não houve registro no dia.' end);
   return next;
  end loop;
 end loop;
end $$;

-- A exclusão de acessos é um arquivamento: preserva autoria, escolhas e fechamentos.
create or replace function public.admin_delete_user(target uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not is_manager() then raise exception 'Somente a gestão pode excluir acessos.'; end if;
 if target=auth.uid() then raise exception 'Você não pode excluir o próprio acesso.'; end if;
 update profiles set active=false,archived=true where id=target;
end $$;

-- Bloqueia escrita direta: todas as alterações operacionais passam pela transação abaixo.
revoke insert,update,delete on public.app_state,public.records,public.picks,public.closed from authenticated;
drop policy if exists "registros: equipe" on public.records;
drop policy if exists "registros: leitura" on public.records;
create policy "registros: leitura" on public.records for select to authenticated using(public.is_member());

create or replace function public.gav_apply_changes(expected_version bigint,changes jsonb)
returns jsonb language plpgsql security definer set search_path=public,storage as $$
declare actor uuid:=auth.uid(); d date:=gav_today(); rev bigint; v jsonb; olddata jsonb; task jsonb; ownlists jsonb;
 k text; itemkey text; photo text; previous_key text; recrows jsonb:='[]'; cfg jsonb;
begin
 if actor is null or not is_member() then raise exception 'Acesso não autorizado.' using errcode='42501'; end if;
 -- Serializa alterações de registros, escolhas e fechamentos; evita fechar enquanto outra chamada registra.
 perform pg_advisory_xact_lock(718293451);
 select version,data into rev,cfg from app_state where id=1 for update;
 if changes ? 'cfg' then
  if not is_manager() then raise exception 'Somente a gestão pode alterar a programação.' using errcode='42501'; end if;
  if coalesce(rev,0)<>expected_version then raise exception 'A programação foi alterada por outro gestor. Recarregue antes de editar.' using errcode='40001'; end if;
  if jsonb_typeof(changes->'cfg'->'rooms')<>'array' or jsonb_typeof(changes->'cfg'->'tasks')<>'array' or jsonb_typeof(changes->'cfg'->'lists')<>'array' then raise exception 'Programação inválida.'; end if;
  rev:=coalesce(rev,0)+1; cfg:=changes->'cfg';
  insert into app_state(id,data,version,updated_at,updated_by) values(1,cfg,rev,clock_timestamp(),actor)
   on conflict(id) do update set data=excluded.data,version=excluded.version,updated_at=excluded.updated_at,updated_by=actor;
 end if;
 -- Escolhas são validadas antes dos registros e do fechamento.
 for v in select x from jsonb_array_elements(coalesce(changes->'picks'->'up','[]')) x loop
  if (v->>'asg_id')::uuid<>actor and not is_manager() then raise exception 'Escolha pertence a outra pessoa.' using errcode='42501'; end if;
  if (v->>'date')::date<>d or v->>'key'<>d::text||':'||(v->>'asg_id') then raise exception 'Data de escolha inválida.'; end if;
  if exists(select 1 from closed where asg_id=(v->>'asg_id')::uuid and date=d) then raise exception 'Dia já finalizado.'; end if;
  if jsonb_typeof(v->'lists')<>'array' or jsonb_array_length(v->'lists')=0 then raise exception 'Escolha ao menos uma lista.'; end if;
  if exists(select 1 from jsonb_array_elements_text(v->'lists') id where not exists(
   select 1 from jsonb_array_elements(cfg->'lists') l where l->>'id'=id and l->'asgIds' @> jsonb_build_array(v->>'asg_id'))) then raise exception 'Lista não liberada para esta ASG.' using errcode='42501'; end if;
  if exists(select 1 from records r where r.date=d and r.data->>'by'=v->>'asg_id' and not (v->'lists' @> jsonb_build_array(r.data->'snapshot'->>'listId'))) then raise exception 'Não é possível deixar uma lista que já recebeu registros.'; end if;
  insert into picks(key,asg_id,date,lists,at) values(v->>'key',(v->>'asg_id')::uuid,d,v->'lists',now()) on conflict(key) do update set lists=excluded.lists,at=excluded.at;
 end loop;
 if jsonb_array_length(coalesce(changes->'picks'->'del','[]'))>0 or jsonb_array_length(coalesce(changes->'closed'->'del','[]'))>0 then raise exception 'Não é permitido apagar escolhas ou fechamentos.'; end if;
 select lists into ownlists from picks where asg_id=actor and date=d;
 if ownlists is null then
  select coalesce(jsonb_agg(l->>'id'),'[]') into ownlists from jsonb_array_elements(coalesce(cfg->'lists','[]')) l where l->'asgIds' @> jsonb_build_array(actor::text);
  if jsonb_array_length(ownlists)<>1 then ownlists:='[]'; end if;
 end if;
 select coalesce(jsonb_agg(l->>'id'),'[]') into ownlists from jsonb_array_elements(coalesce(cfg->'lists','[]')) l
 where ownlists @> jsonb_build_array(l->>'id') and l->'asgIds' @> jsonb_build_array(actor::text);
 for v in select x from jsonb_array_elements(coalesce(changes->'records'->'up','[]')) x loop
  k:=v->>'key'; olddata:=null; task:=null;
  select r.data into olddata from records r where r.key=k;
  -- Lista em conjunto: quem divide a lista pode concluir o que a colega justificou; o resto continua de quem registrou.
  if olddata is not null and olddata->>'by' is distinct from actor::text and not is_manager() and not (olddata->>'status'='justified' and v->'data'->>'status'='done') then raise exception 'Registro pertence a outra pessoa.' using errcode='42501'; end if;
  if (v->>'date')::date<>d then raise exception 'Só é possível registrar a rotina de hoje.'; end if;
  if exists(select 1 from closed where asg_id=actor and date=d) then raise exception 'Dia já finalizado.'; end if;
  select e.data into task from gav_expected(ownlists,d) e where e.key=k;
  if task is null then raise exception 'Tarefa não pertence à rotina assumida de hoje.' using errcode='42501'; end if;
  if v->'data'->>'status' not in ('done','justified') or v->'data'->>'status' is null then raise exception 'Situação inválida.'; end if;
  if v->'data'->>'status'='justified' and length(trim(coalesce(v->'data'->>'reason','')))<10 then raise exception 'Justifique com pelo menos 10 caracteres.'; end if;
  photo:=nullif(v->'data'->>'photo','');
  if v->'data'->>'status'='done' and (task->>'photoRequired')::boolean and photo is null then raise exception 'A foto é obrigatória.'; end if;
  if photo is not null and (split_part(photo,'/',1)<>actor::text or not exists(select 1 from storage.objects where bucket_id='fotos' and name=photo)) then raise exception 'Comprovante de foto inválido.'; end if;
  v:=jsonb_build_object('status',v->'data'->>'status','aid',task->>'aid','asgId',actor,'date',d,'by',actor,
    'byName',(select name from profiles where id=actor),'at',now(),'reason',v->'data'->>'reason','photo',photo,'snapshot',task);
  if coalesce((olddata->'snapshot'->>'overdue')::boolean,false) and olddata->>'status'='done' and v->>'status'<>'done' then
   previous_key:=(olddata->'snapshot'->>'previousDate')||':'||(olddata->>'aid');
   update records set data=data-'recovered' where key=previous_key and data->>'recovered'=d::text;
  end if;
  insert into records(key,data,date,updated_at) values(k,v,d,now()) on conflict(key) do update set data=excluded.data,updated_at=excluded.updated_at;
  if (task->>'overdue')::boolean and v->>'status'='done' then
   previous_key:=(task->>'previousDate')||':'||(task->>'aid');
   insert into records(key,date,data) values(previous_key,(task->>'previousDate')::date,jsonb_build_object('status','missed','date',task->>'previousDate','aid',task->>'aid','recovered',d))
    on conflict(key) do update set data=records.data||jsonb_build_object('recovered',d),updated_at=now();
  end if;
  recrows:=recrows||jsonb_build_array(jsonb_build_object('key',k,'data',v));
 end loop;
 for k in select jsonb_array_elements_text(coalesce(changes->'records'->'del','[]')) loop
  select r.data into olddata from records r where r.key=k;
  if olddata is null then continue; end if;
  if olddata->>'by' is distinct from actor::text and not is_manager() then raise exception 'Registro pertence a outra pessoa.' using errcode='42501'; end if;
  if (olddata->>'date')::date<>d or exists(select 1 from closed where asg_id=(olddata->>'by')::uuid and date=d) then raise exception 'Registro de dia encerrado não pode ser reaberto.'; end if;
  if coalesce((olddata->'snapshot'->>'overdue')::boolean,false) then
   previous_key:=(olddata->'snapshot'->>'previousDate')||':'||(olddata->>'aid');
   update records set data=data-'recovered' where key=previous_key and data->>'recovered'=d::text;
   delete from records where key=previous_key and data->>'status'='missed' and not(data ? 'by');
  end if;
  delete from records where key=k;
 end loop;
 for v in select x from jsonb_array_elements(coalesce(changes->'closed'->'up','[]')) x loop
  if (v->>'asg_id')::uuid<>actor or (v->>'date')::date<>d or v->>'key'<>d::text||':'||actor::text then raise exception 'Fechamento inválido.' using errcode='42501'; end if;
  if jsonb_array_length(ownlists)=0 then raise exception 'Assuma uma lista antes de finalizar.'; end if;
  if exists(select 1 from gav_expected(ownlists,d) e left join records r on r.key=e.key where coalesce(r.data->>'status','pending') not in ('done','justified')) then raise exception 'Ainda há tarefas sem conclusão ou justificativa.'; end if;
  insert into closed(key,asg_id,date,time) values(v->>'key',actor,d,to_char(now() at time zone 'America/Sao_Paulo','HH24:MI')) on conflict(key) do nothing;
 end loop;
 return jsonb_build_object('version',coalesce(rev,0),'records',recrows)||
  case when rev<>expected_version and not(changes ? 'cfg') then jsonb_build_object('cfg',cfg) else '{}'::jsonb end;
end $$;
revoke all on function public.gav_apply_changes(bigint,jsonb) from public,anon;
grant execute on function public.gav_apply_changes(bigint,jsonb) to authenticated;
revoke all on function public.gav_expected(jsonb,date) from public,anon,authenticated;

-- Comprovantes privados. Links antigos passam a exigir sessão/URL assinada.
update storage.buckets set public=false where id='fotos';
drop policy if exists "fotos: leitura" on storage.objects;
create policy "fotos: leitura" on storage.objects for select to authenticated using(bucket_id='fotos' and public.is_member());
drop policy if exists "fotos: envio pela equipe" on storage.objects;
create policy "fotos: envio pela equipe" on storage.objects for insert to authenticated with check(bucket_id='fotos' and public.is_member() and split_part(name,'/',1)=auth.uid()::text);

-- Índices para consultas paginadas e escolha de programação histórica.
create index if not exists config_history_time_idx on public.config_history(recorded_at,version);
create index if not exists records_date_key_idx on public.records(date,key);

-- Preserva as conclusões existentes com os metadados ainda disponíveis no cadastro atual.
-- Alterações/exclusões anteriores à atualização não podem ser reconstruídas automaticamente.
with meta as (
 select l, i, t, room from app_state a
 cross join lateral jsonb_array_elements(a.data->'lists') l
 cross join lateral jsonb_array_elements(l->'items') i
 join lateral jsonb_array_elements(a.data->'tasks') t on t->>'id'=i->>'taskId'
 left join lateral jsonb_array_elements(a.data->'rooms') room on room->>'id'=t->>'roomId'
 where a.id=1
)
update records r set data=r.data||jsonb_build_object('snapshot',jsonb_build_object(
 'key',r.key,'date',r.date,'aid',r.data->>'aid','listId',meta.l->>'id','listName',meta.l->>'name',
 'title',meta.t->>'title','local',coalesce(meta.room->>'name','Sem cômodo'),'instructions',meta.t->>'instructions',
 'materials',meta.t->>'materials','photoRequired',coalesce((meta.t->>'photoRequired')::boolean,true),
 'repeat',meta.i->'repeat','start',meta.i->>'start','end',meta.i->>'end','notes',meta.i->>'notes',
 'overdue',left(r.key,7)='atraso:','previousDate',case when left(r.key,7)='atraso:' then split_part(r.key,':',3) else null end))
from meta where meta.i->>'id'=r.data->>'aid' and not(r.data ? 'snapshot') and r.data ? 'by';
-- Não esconder comprovantes de cadastros que já tinham sido apagados antes desta atualização.
-- A descrição perdida é identificada como indisponível, sem atribuir uma tarefa inventada.
update records r set data=r.data||jsonb_build_object('snapshot',jsonb_build_object(
 'key',r.key,'date',r.date,'aid',r.data->>'aid','listId','historico-anterior','listName','Cadastros anteriores',
 'title',coalesce(nullif(r.data->>'title',''),'Atividade de cadastro anterior'),
 'local',coalesce(nullif(r.data->>'local',''),'Cadastro anterior'),
 'instructions','O cadastro desta atividade foi removido antes da atualização. A descrição original não está disponível.',
 'materials','','photoRequired',false,'repeat',jsonb_build_object('type','once'),'start',r.date,'end',r.date,
 'overdue',left(r.key,7)='atraso:','previousDate',case when left(r.key,7)='atraso:' then split_part(r.key,':',3) else null end))
where not(r.data ? 'snapshot') and r.data ? 'by' and r.data->>'status' in ('done','justified');
commit;

-- Equipe geral: garçom, autocadastro e contagem de estoque (o mesmo conteúdo de equipe.sql).
begin;
-- Perfis possíveis. Para incluir outro perfil no futuro, acrescente-o nesta lista.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('gestor','asg','garcom','contratos','analista'));

-- Duas contagens por dia: uma no turno do dia e outra no da noite. Guarda quem enviou.
-- Os itens ficam na ordem em que foram contados.
create table if not exists public.counts(
  key text primary key,
  date date not null,
  shift text not null check (shift in ('DIA','NOITE')),
  waiter_id uuid not null references public.profiles(id),
  waiter_name text not null,
  items jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.counts add column if not exists notes text;
create index if not exists counts_date_idx on public.counts(date, shift);
alter table public.counts enable row level security;
revoke insert, update, delete on public.counts from authenticated, anon;
grant select on public.counts to authenticated;
-- A gestão vê todo o histórico; o garçom vê só as contagens de hoje (para saber se o turno já foi enviado e corrigir).
drop policy if exists "contagens: leitura" on public.counts;
create policy "contagens: leitura" on public.counts for select to authenticated
  using (public.is_manager() or (date = gav_today() and public.is_member() and exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'garcom')));

-- Uma contagem por turno, feita em equipe: quem está contando salva o progresso aqui; os outros garçons
-- acompanham e podem assumir de onde a pessoa parou ("Continuar daqui"). Só quem está com a contagem edita.
alter table public.counts add column if not exists team jsonb not null default '[]';      -- quem participou: [{id,name}]
alter table public.counts add column if not exists correction jsonb;                       -- correção aguardando a gestão
alter table public.counts add column if not exists history jsonb not null default '[]';   -- correções aprovadas e recusadas
create table if not exists public.count_progress(
  key text primary key,
  date date not null,
  shift text not null check (shift in ('DIA','NOITE')),
  waiter_id uuid not null references public.profiles(id),   -- quem está com a contagem agora
  waiter_name text not null,
  items jsonb not null default '[]',
  notes text,
  team jsonb not null default '[]',
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists count_progress_date_idx on public.count_progress(date);
alter table public.count_progress enable row level security;
revoke insert, update, delete on public.count_progress from authenticated, anon;
grant select on public.count_progress to authenticated;
drop policy if exists "contagem em andamento: leitura" on public.count_progress;
create policy "contagem em andamento: leitura" on public.count_progress for select to authenticated
  using (public.is_manager() or (date = gav_today() and public.is_member() and exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'garcom')));

-- Valida e limpa os itens: nome até 80 caracteres, quantidade inteira entre 0 e 1.000.000.
create or replace function public.gav_count_items(p_items jsonb, p_min int)
returns jsonb language plpgsql immutable set search_path = public as $$
declare it jsonb; q numeric; clean jsonb := '[]';
begin
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) < p_min or jsonb_array_length(p_items) > 200 then raise exception 'Contagem inválida.'; end if;
  for it in select x from jsonb_array_elements(p_items) x loop
    if jsonb_typeof(it->'name') is distinct from 'string' or length(trim(it->>'name')) = 0 or length(it->>'name') > 80 then raise exception 'Item inválido.'; end if;
    if jsonb_typeof(it->'qty') is distinct from 'number' then raise exception 'Quantidade inválida em %.', it->>'name'; end if;
    q := (it->>'qty')::numeric;
    if q < 0 or q > 1000000 or q <> trunc(q) then raise exception 'Quantidade inválida em %.', it->>'name'; end if;
    clean := clean || jsonb_build_array(jsonb_build_object('name', trim(it->>'name'), 'qty', q::bigint));
  end loop;
  return clean;
end $$;
revoke all on function public.gav_count_items(jsonb, int) from public, anon, authenticated;

create or replace function public.gav_shift_name(p_shift text) returns text language sql immutable as $$
  select case when p_shift = 'NOITE' then 'da noite' else 'do dia' end $$;

-- Salva o progresso de quem está contando. Se outra pessoa estiver com a contagem, devolve como está
-- (o app mostra quem é); com p_take, a pessoa assume a contagem de onde parou.
create or replace function public.gav_count_progress(p_shift text, p_items jsonb, p_notes text default null, p_take boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare actor uuid := auth.uid(); d date := gav_today(); who text; k text; done public.counts; cur public.count_progress; clean jsonb; me jsonb;
begin
  select name into who from profiles where id = actor and active and not archived and role = 'garcom';
  if not found then raise exception 'Somente garçons registram a contagem.' using errcode = '42501'; end if;
  if p_shift is null or p_shift not in ('DIA','NOITE') then raise exception 'Turno inválido.'; end if;
  if length(coalesce(p_notes, '')) > 500 then raise exception 'Observação muito longa (máximo de 500 caracteres).'; end if;
  clean := gav_count_items(coalesce(p_items, '[]'), 0);
  k := d::text || ':' || p_shift;
  select * into done from counts where key = k;
  if found then raise exception 'A contagem % já foi enviada por %.', gav_shift_name(p_shift), done.waiter_name; end if;
  me := jsonb_build_object('id', actor, 'name', who);
  insert into count_progress(key, date, shift, waiter_id, waiter_name, items, notes, team)
    values (k, d, p_shift, actor, who, clean, nullif(trim(p_notes), ''), jsonb_build_array(me)) on conflict (key) do nothing;
  if found then select * into cur from count_progress where key = k; return to_jsonb(cur); end if;
  select * into cur from count_progress where key = k for update;
  if cur.waiter_id <> actor then
    if not coalesce(p_take, false) then return to_jsonb(cur); end if;
    update count_progress set waiter_id = actor, waiter_name = who, updated_at = now(),
      team = case when team @> jsonb_build_array(jsonb_build_object('id', actor)) then team else team || jsonb_build_array(me) end
      where key = k returning * into cur;
    return to_jsonb(cur);
  end if;
  update count_progress set items = clean, notes = nullif(trim(p_notes), ''), updated_at = now() where key = k returning * into cur;
  return to_jsonb(cur);
end $$;
revoke all on function public.gav_count_progress(text, jsonb, text, boolean) from public, anon;
grant execute on function public.gav_count_progress(text, jsonb, text, boolean) to authenticated;

-- Envio da contagem: só garçom, só hoje, todos os itens da lista contados. Cada turno tem uma contagem só.
-- Depois de enviada, quem participou pode pedir correção; ela só vale quando a gestão aprovar.
drop function if exists public.gav_save_count(text, jsonb);
create or replace function public.gav_save_count(p_shift text, p_items jsonb, p_notes text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare actor uuid := auth.uid(); d date := gav_today(); who text; k text; saved public.counts; done public.counts; cur public.count_progress;
  clean jsonb; expected jsonb; note text := nullif(trim(p_notes), ''); team jsonb; me jsonb;
begin
  select name into who from profiles where id = actor and active and not archived and role = 'garcom';
  if not found then raise exception 'Somente garçons registram a contagem.' using errcode = '42501'; end if;
  if p_shift is null or p_shift not in ('DIA','NOITE') then raise exception 'Turno inválido.'; end if;
  if length(coalesce(p_notes, '')) > 500 then raise exception 'Observação muito longa (máximo de 500 caracteres).'; end if;
  clean := gav_count_items(p_items, 1);
  -- Nenhum item da lista da gestão pode ficar sem contagem.
  select a.data->'countItems' into expected from app_state a where a.id = 1;
  if jsonb_typeof(expected) = 'array' and exists(select 1 from jsonb_array_elements_text(expected) n
     where not exists(select 1 from jsonb_array_elements(clean) c where c->>'name' = trim(n))) then
    raise exception 'Contagem incompleta: conte todos os itens da lista antes de enviar.';
  end if;
  k := d::text || ':' || p_shift;
  me := jsonb_build_object('id', actor, 'name', who);
  select * into done from counts where key = k for update;
  if found then
    if not (done.waiter_id = actor or done.team @> jsonb_build_array(jsonb_build_object('id', actor))) then
      raise exception 'A contagem % já foi enviada por %. Só quem participou dela pode pedir correção.', gav_shift_name(p_shift), done.waiter_name;
    end if;
    if done.items = clean and coalesce(done.notes, '') = coalesce(note, '') then raise exception 'Nenhum número mudou.'; end if;
    update counts set correction = jsonb_build_object('items', clean, 'notes', note, 'waiter_id', actor, 'waiter_name', who, 'requested_at', now())
      where key = k returning * into saved;
    return to_jsonb(saved);
  end if;
  select * into cur from count_progress where key = k for update;
  if found and cur.waiter_id <> actor then
    raise exception 'A contagem % está com %. Toque em "Continuar daqui" para assumir.', gav_shift_name(p_shift), cur.waiter_name;
  end if;
  team := coalesce(cur.team, '[]');
  if not team @> jsonb_build_array(jsonb_build_object('id', actor)) then team := team || jsonb_build_array(me); end if;
  insert into counts(key, date, shift, waiter_id, waiter_name, items, notes, team) values (k, d, p_shift, actor, who, clean, note, team)
    returning * into saved;
  delete from count_progress where key = k;
  return to_jsonb(saved);
end $$;
revoke all on function public.gav_save_count(text, jsonb, text) from public, anon;
grant execute on function public.gav_save_count(text, jsonb, text) to authenticated;

-- A gestão aprova (os números passam a valer) ou recusa (ficam os enviados) a correção pedida.
create or replace function public.gav_review_correction(p_key text, p_approve boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare done public.counts; saved public.counts; who text; entry jsonb;
begin
  if not public.is_manager() then raise exception 'Somente a gestão aprova correções.' using errcode = '42501'; end if;
  select * into done from counts where key = p_key for update;
  if not found then raise exception 'Contagem não encontrada.'; end if;
  if done.correction is null then raise exception 'Não há correção pendente nesta contagem.'; end if;
  select name into who from profiles where id = auth.uid();
  entry := done.correction || jsonb_build_object('status', case when p_approve then 'aprovada' else 'recusada' end, 'reviewed_at', now(), 'reviewed_by', who,
    'before', jsonb_build_object('items', done.items, 'notes', done.notes));
  if p_approve then
    update counts set items = done.correction->'items', notes = done.correction->>'notes', updated_at = now(), correction = null, history = history || jsonb_build_array(entry)
      where key = p_key returning * into saved;
  else
    update counts set correction = null, history = history || jsonb_build_array(entry) where key = p_key returning * into saved;
  end if;
  return to_jsonb(saved);
end $$;
revoke all on function public.gav_review_correction(text, boolean) from public, anon;
grant execute on function public.gav_review_correction(text, boolean) to authenticated;

-- Autocadastro: a pessoa cria o próprio login e pede acesso; fica inativa até a gestão aprovar.
alter table public.profiles add column if not exists pending boolean not null default false;
create or replace function public.gav_request_access(p_name text, p_role text)
returns void language plpgsql security definer set search_path = public, auth as $$
declare actor uuid := auth.uid(); mail text;
begin
  if actor is null then raise exception 'Entre com o e-mail e a senha cadastrados.' using errcode = '42501'; end if;
  if p_role is null or p_role not in ('asg','garcom','contratos','analista') then raise exception 'Função inválida.'; end if;
  if length(trim(coalesce(p_name, ''))) < 3 or length(p_name) > 80 then raise exception 'Informe o nome completo.'; end if;
  if exists(select 1 from profiles where id = actor) then raise exception 'Este cadastro já existe.'; end if;
  select email into mail from auth.users where id = actor;
  insert into profiles(id, name, email, role, active, pending) values (actor, trim(p_name), lower(mail), p_role, false, true);
end $$;
revoke all on function public.gav_request_access(text, text) from public, anon;
grant execute on function public.gav_request_access(text, text) to authenticated;

do $$ begin alter publication supabase_realtime add table public.counts; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.count_progress; exception when duplicate_object then null; end $$;
commit;

-- Área administrativa: contratos, analista, cronograma, chamados, notas, pedidos e caixas (o mesmo conteúdo de administrativo.sql).
begin;
-- Perfis possíveis (mesma lista de equipe.sql).
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('gestor','asg','garcom','contratos','analista'));

-- Autocadastro pelo site também para os perfis administrativos.
create or replace function public.gav_request_access(p_name text, p_role text)
returns void language plpgsql security definer set search_path = public, auth as $$
declare actor uuid := auth.uid(); mail text;
begin
  if actor is null then raise exception 'Entre com o e-mail e a senha cadastrados.' using errcode = '42501'; end if;
  if p_role is null or p_role not in ('asg','garcom','contratos','analista') then raise exception 'Função inválida.'; end if;
  if length(trim(coalesce(p_name, ''))) < 3 or length(p_name) > 80 then raise exception 'Informe o nome completo.'; end if;
  if exists(select 1 from profiles where id = actor) then raise exception 'Este cadastro já existe.'; end if;
  select email into mail from auth.users where id = actor;
  insert into profiles(id, name, email, role, active, pending) values (actor, trim(p_name), lower(mail), p_role, false, true);
end $$;
revoke all on function public.gav_request_access(text, text) from public, anon;
grant execute on function public.gav_request_access(text, text) to authenticated;

-- Registros da área administrativa. Cada linha tem um tipo (kind) e os dados em JSON.
--   tarefa / tarefa_feita: cronograma criado pela gestão e as conclusões do dia
--   chamado: chamados abertos em outro sistema e acompanhados aqui
--   parceiro / nota: parceiros e notas fiscais por mês (parceiros e alimentação PJ)
--   pedido: pedido mensal ao setor de compras, conferência e comentários
--   caixa / pagamento: caixas configurados pela gestão e os pagamentos lançados
--   contrato: auditoria de contratos (próxima etapa)
create table if not exists public.adm_items(
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('tarefa','tarefa_feita','chamado','parceiro','nota','pedido','caixa','pagamento','contrato')),
  data jsonb not null default '{}',
  created_by uuid references public.profiles(id),
  created_by_name text,
  created_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id),
  updated_by_name text,
  updated_at timestamptz not null default now()
);
create index if not exists adm_items_kind_idx on public.adm_items(kind, created_at);
--   tarefa_transf: tarefa do dia passada de uma pessoa para outra (atestado, folga). Não muda o cadastro da tarefa.
alter table public.adm_items drop constraint if exists adm_items_kind_check;
alter table public.adm_items add constraint adm_items_kind_check check (kind in ('tarefa','tarefa_feita','tarefa_transf','chamado','parceiro','nota','pedido','caixa','pagamento','contrato'));

-- Funções de cada pessoa do administrativo. Vazio (null) = padrão da função:
-- analista: notas, pedidos e caixas; assistente de contratos: contratos e chamados. A gestão pode liberar outras.
alter table public.profiles add column if not exists adm_modules text[];
create or replace function public.gav_adm_modules() returns text[]
language sql stable security definer set search_path = public as $$
  select case when p.role = 'gestor' then array['contratos','chamados','notas','pedidos','caixas']
    else coalesce(p.adm_modules, case p.role when 'analista' then array['notas','pedidos','caixas'] when 'contratos' then array['contratos','chamados'] else array[]::text[] end) end
  from profiles p where p.id = auth.uid() and p.active and not p.archived and p.role in ('gestor','contratos','analista') $$;
revoke all on function public.gav_adm_modules() from public, anon;
grant execute on function public.gav_adm_modules() to authenticated;
create or replace function public.gav_adm_office() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from profiles where id = auth.uid() and active and not archived and role in ('contratos','analista')) $$;
revoke all on function public.gav_adm_office() from public, anon;
grant execute on function public.gav_adm_office() to authenticated;

-- Quem pode ver (p_write = false) e alterar (true) cada tipo. A gestão vê e altera tudo.
-- Cronograma (tarefa e tarefa_feita) tem regra própria nas políticas: cada um só vê o seu.
create or replace function public.gav_adm_can(p_kind text, p_write boolean) returns boolean
language sql stable security definer set search_path = public as $$
  select case when public.is_manager() then true when not public.gav_adm_office() then false else coalesce((select case p_kind
    when 'tarefa' then not p_write
    when 'tarefa_feita' then true
    when 'tarefa_transf' then true
    when 'chamado' then 'chamados' = any(m)
    when 'contrato' then 'contratos' = any(m)
    when 'parceiro' then 'notas' = any(m)
    when 'nota' then 'notas' = any(m)
    when 'pedido' then 'pedidos' = any(m)
    when 'caixa' then not p_write and 'caixas' = any(m)
    when 'pagamento' then 'caixas' = any(m)
    else false end from (select public.gav_adm_modules() m) x), false) end $$;
revoke all on function public.gav_adm_can(text, boolean) from public, anon;
grant execute on function public.gav_adm_can(text, boolean) to authenticated;

-- A tarefa é minha: fui escolhido para fazer ou eu mesmo criei.
create or replace function public.gav_adm_task_mine(p_task text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from adm_items where id::text = p_task and kind = 'tarefa' and (data->'assignees' ? auth.uid()::text or created_by = auth.uid())) $$;
revoke all on function public.gav_adm_task_mine(text) from public, anon;
grant execute on function public.gav_adm_task_mine(text) to authenticated;

-- Tarefa da equipe do administrativo: tem alguém do administrativo entre os responsáveis.
-- As assistentes veem as tarefas umas das outras, concluem e transferem no dia (atestado, folga), mas não criam tarefa para outra pessoa.
create or replace function public.gav_adm_office_assigned(p_data jsonb) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from jsonb_array_elements_text(case when jsonb_typeof(p_data->'assignees') = 'array' then p_data->'assignees' else '[]'::jsonb end) a
    join profiles p on p.id::text = a where p.role in ('contratos','analista')) $$;
revoke all on function public.gav_adm_office_assigned(jsonb) from public, anon;
grant execute on function public.gav_adm_office_assigned(jsonb) to authenticated;
create or replace function public.gav_adm_task_office(p_task text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from adm_items where id::text = p_task and kind = 'tarefa' and public.gav_adm_office_assigned(data)) $$;
revoke all on function public.gav_adm_task_office(text) from public, anon;
grant execute on function public.gav_adm_task_office(text) to authenticated;

-- Autoria e horário gravados pelo servidor.
create or replace function public.gav_adm_stamp() returns trigger
language plpgsql security definer set search_path = public as $$
declare who text;
begin
  select name into who from profiles where id = auth.uid();
  if tg_op = 'INSERT' then
    new.created_by := auth.uid(); new.created_by_name := who; new.created_at := now();
  else
    new.kind := old.kind; new.created_by := old.created_by; new.created_by_name := old.created_by_name; new.created_at := old.created_at;
  end if;
  new.updated_by := auth.uid(); new.updated_by_name := who; new.updated_at := now();
  return new;
end $$;
drop trigger if exists adm_items_stamp on public.adm_items;
create trigger adm_items_stamp before insert or update on public.adm_items for each row execute function public.gav_adm_stamp();

alter table public.adm_items enable row level security;
revoke all on public.adm_items from anon;
grant select, insert, update, delete on public.adm_items to authenticated;
drop policy if exists "adm: leitura" on public.adm_items;
create policy "adm: leitura" on public.adm_items for select to authenticated using (
  public.gav_adm_can(kind, false) and (public.is_manager() or kind not in ('tarefa','tarefa_feita')
    or (kind = 'tarefa' and (data->'assignees' ? auth.uid()::text or created_by = auth.uid() or (public.gav_adm_office() and public.gav_adm_office_assigned(data))))
    or (kind = 'tarefa_feita' and (created_by = auth.uid() or public.gav_adm_task_mine(data->>'task') or (public.gav_adm_office() and public.gav_adm_task_office(data->>'task'))))));
drop policy if exists "adm: inclusão" on public.adm_items;
create policy "adm: inclusão" on public.adm_items for insert to authenticated with check (
  (public.gav_adm_can(kind, true)
    and (kind <> 'tarefa_feita' or public.is_manager() or public.gav_adm_task_mine(data->>'task') or public.gav_adm_task_office(data->>'task'))
    and (kind <> 'tarefa_transf' or public.is_manager() or public.gav_adm_task_office(data->>'task')))
  or (kind = 'tarefa' and public.gav_adm_office() and data->'assignees' = jsonb_build_array(auth.uid()::text)));
drop policy if exists "adm: alteração" on public.adm_items;
create policy "adm: alteração" on public.adm_items for update to authenticated
  using ((public.gav_adm_can(kind, true) and (kind not in ('tarefa_feita','tarefa_transf') or created_by = auth.uid() or public.is_manager()))
    or (kind = 'tarefa' and created_by = auth.uid() and public.gav_adm_office()))
  with check (public.gav_adm_can(kind, true) or (kind = 'tarefa' and created_by = auth.uid() and public.gav_adm_office() and data->'assignees' = jsonb_build_array(auth.uid()::text)));
drop policy if exists "adm: exclusão" on public.adm_items;
create policy "adm: exclusão" on public.adm_items for delete to authenticated
  using ((public.gav_adm_can(kind, true) and (kind not in ('tarefa_feita','tarefa_transf') or created_by = auth.uid() or public.is_manager()) and (kind <> 'pagamento' or public.is_manager()))
    or (kind = 'tarefa' and created_by = auth.uid() and public.gav_adm_office()));

do $$ begin alter publication supabase_realtime add table public.adm_items; exception when duplicate_object then null; end $$;
-- Privacidade. O e-mail de cada pessoa só aparece para a gestão e para a própria pessoa;
-- o resto da equipe vê apenas nome e função (para mostrar quem fez cada coisa).
revoke select on public.profiles from authenticated, anon;
grant select (id, name, role, active, archived, pending, created_at, adm_modules) on public.profiles to authenticated;
create or replace function public.gav_profile_emails() returns table(id uuid, email text)
language sql stable security definer set search_path = public as $$
  select p.id, p.email from profiles p where public.is_manager() or p.id = auth.uid() $$;
revoke all on function public.gav_profile_emails() from public, anon;
grant execute on function public.gav_profile_emails() to authenticated;
-- O aviso em tempo real de perfis não leva o e-mail.
do $$ begin
  begin alter publication supabase_realtime drop table public.profiles; exception when others then null; end;
  begin alter publication supabase_realtime add table public.profiles (id, name, role, active, archived, pending, created_at, adm_modules);
  exception when others then null; end;
end $$;
-- Sem login, nada é lido nem gravado.
revoke all on public.profiles, public.app_state, public.records, public.picks, public.closed, public.config_history,
  public.counts, public.count_progress, public.adm_items from anon;
-- Limpeza: registros, escolhas, fechamentos e fotos só para a gestão e as ASGs.
create or replace function public.gav_cleaning() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from profiles where id = auth.uid() and active and not archived and role in ('gestor','asg')) $$;
revoke all on function public.gav_cleaning() from public, anon;
grant execute on function public.gav_cleaning() to authenticated;
drop policy if exists "registros: leitura" on public.records;
create policy "registros: leitura" on public.records for select to authenticated using (public.gav_cleaning());
drop policy if exists "escolhas: leitura" on public.picks;
create policy "escolhas: leitura" on public.picks for select to authenticated using (public.gav_cleaning());
drop policy if exists "fechamentos: leitura" on public.closed;
create policy "fechamentos: leitura" on public.closed for select to authenticated using (public.gav_cleaning());
drop policy if exists "histórico: leitura" on public.config_history;
create policy "histórico: leitura" on public.config_history for select to authenticated using (public.gav_cleaning());
drop policy if exists "fotos: leitura" on storage.objects;
create policy "fotos: leitura" on storage.objects for select to authenticated using (bucket_id = 'fotos' and public.gav_cleaning());
drop policy if exists "fotos: envio pela equipe" on storage.objects;
create policy "fotos: envio pela equipe" on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos' and public.gav_cleaning() and split_part(name, '/', 1) = auth.uid()::text);
-- Primeiro gestor automático só enquanto não existir nenhuma gestão ativa (evita que alguém assuma esse e-mail depois).
create or replace function public.gav_first_manager() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if lower(new.email) = 'carlos.santos@gavresorts.com.br'
     and not exists(select 1 from public.profiles where role = 'gestor' and active and not archived) then
    insert into public.profiles(id, name, email, role) values (new.id, 'Carlos Santos', lower(new.email), 'gestor')
    on conflict (id) do update set role = 'gestor', active = true;
  end if;
  return new;
end $$;
commit;
