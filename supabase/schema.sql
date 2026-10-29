-- GAV · Gestão de limpeza: estrutura do banco no Supabase.
-- Cole este arquivo inteiro em SQL Editor > New query e clique em Run.
-- Pode ser executado de novo sem perder dados.

-- Perfis: um por login. role = 'gestor' ou 'asg'.
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

-- A gestão cria acessos sem envio de e-mail (sem limite de e-mails do Supabase).
create or replace function public.admin_create_user(new_email text, new_password text)
returns uuid language plpgsql security definer set search_path = public, auth, extensions as $$
declare uid uuid;
begin
  if not public.is_manager() then raise exception 'Somente a gestão pode criar acessos.'; end if;
  if length(coalesce(new_password, '')) < 6 then raise exception 'A senha precisa ter pelo menos 6 caracteres.'; end if;
  select id into uid from auth.users where lower(email) = lower(new_email);
  if uid is null then
    uid := gen_random_uuid();
    insert into auth.users(instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, email_change, email_change_token_new, recovery_token)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', lower(new_email),
      extensions.crypt(new_password, extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');
    insert into auth.identities(id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), uid, uid::text,
      jsonb_build_object('sub', uid::text, 'email', lower(new_email), 'email_verified', true),
      'email', now(), now(), now());
  else
    -- Acesso que já existia (por exemplo, criado pela metade): confirma e define a senha.
    update auth.users set encrypted_password = extensions.crypt(new_password, extensions.gen_salt('bf')),
      email_confirmed_at = coalesce(email_confirmed_at, now()), updated_at = now() where id = uid;
  end if;
  return uid;
end $$;
revoke all on function public.admin_create_user(text, text) from public, anon;
grant execute on function public.admin_create_user(text, text) to authenticated;

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
