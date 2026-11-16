-- GAV: equipe geral — perfil de garçom, autocadastro com aprovação da gestão e contagem de estoque por turno.
-- Executar no SQL Editor depois de reliability.sql. Pode ser repetido; não apaga dados.
begin;
-- Perfis possíveis. Para incluir outro perfil no futuro, acrescente-o nesta lista.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('gestor','asg','garcom'));

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
  if p_role is null or p_role not in ('asg','garcom') then raise exception 'Função inválida.'; end if;
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
