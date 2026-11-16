-- GAV: equipe geral — perfil de garçom, autocadastro com aprovação da gestão e contagem de estoque por turno.
-- Executar no SQL Editor depois de reliability.sql. Pode ser repetido; não apaga dados.
begin;
-- Perfis possíveis. Para incluir outro perfil no futuro, acrescente-o nesta lista.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('gestor','asg','garcom'));

-- Duas contagens por dia: uma no turno do dia e outra no da noite. Guarda quem enviou por último.
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
create index if not exists counts_date_idx on public.counts(date, shift);
alter table public.counts enable row level security;
revoke insert, update, delete on public.counts from authenticated, anon;
grant select on public.counts to authenticated;
-- A gestão vê todo o histórico; o garçom vê só as contagens de hoje (para saber se o turno já foi enviado e corrigir).
drop policy if exists "contagens: leitura" on public.counts;
create policy "contagens: leitura" on public.counts for select to authenticated
  using (public.is_manager() or (date = gav_today() and public.is_member() and exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'garcom')));

-- Gravação validada no servidor: só garçom (ou gestão), só no dia de hoje, quantidades inteiras e não negativas.
create or replace function public.gav_save_count(p_shift text, p_items jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare actor uuid := auth.uid(); d date := gav_today(); who_name text; who_role text; it jsonb; q numeric; clean jsonb := '[]'; k text; saved public.counts;
begin
  select name, role into who_name, who_role from profiles where id = actor and active and not archived;
  if not found or who_role not in ('garcom','gestor') then raise exception 'Somente garçons registram a contagem.' using errcode = '42501'; end if;
  if p_shift is null or p_shift not in ('DIA','NOITE') then raise exception 'Turno inválido.'; end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 200 then raise exception 'Contagem inválida.'; end if;
  for it in select x from jsonb_array_elements(p_items) x loop
    if jsonb_typeof(it->'name') is distinct from 'string' or length(trim(it->>'name')) = 0 or length(it->>'name') > 80 then raise exception 'Item inválido.'; end if;
    if jsonb_typeof(it->'qty') is distinct from 'number' then raise exception 'Quantidade inválida em %.', it->>'name'; end if;
    q := (it->>'qty')::numeric;
    if q < 0 or q > 1000000 or q <> trunc(q) then raise exception 'Quantidade inválida em %.', it->>'name'; end if;
    clean := clean || jsonb_build_array(jsonb_build_object('name', trim(it->>'name'), 'qty', q::bigint));
  end loop;
  k := d::text || ':' || p_shift;
  insert into counts(key, date, shift, waiter_id, waiter_name, items) values (k, d, p_shift, actor, who_name, clean)
    on conflict (key) do update set items = excluded.items, waiter_id = excluded.waiter_id, waiter_name = excluded.waiter_name, updated_at = now()
    returning * into saved;
  return to_jsonb(saved);
end $$;
revoke all on function public.gav_save_count(text, jsonb) from public, anon;
grant execute on function public.gav_save_count(text, jsonb) to authenticated;

-- Autocadastro: a pessoa cria o próprio login e pede acesso; fica inativa até a gestão aprovar.
alter table public.profiles add column if not exists pending boolean not null default false;
create or replace function public.gav_request_access(p_name text, p_role text)
returns void language plpgsql security definer set search_path = public, auth as $$
declare actor uuid := auth.uid(); mail text;
begin
  if actor is null then raise exception 'Entre com o e-mail e a senha cadastrados.' using errcode = '42501'; end if;
  if p_role is null or p_role not in ('asg','garcom') then raise exception 'Função inválida.'; end if;
  if length(trim(coalesce(p_name, ''))) < 3 or length(p_name) > 80 then raise exception 'Informe o nome completo.'; end if;
  if exists(select 1 from profiles where id = actor) then raise exception 'Este cadastro já existe.'; end if;
  select email into mail from auth.users where id = actor;
  insert into profiles(id, name, email, role, active, pending) values (actor, trim(p_name), lower(mail), p_role, false, true);
end $$;
revoke all on function public.gav_request_access(text, text) from public, anon;
grant execute on function public.gav_request_access(text, text) to authenticated;

do $$ begin alter publication supabase_realtime add table public.counts; exception when duplicate_object then null; end $$;
commit;
