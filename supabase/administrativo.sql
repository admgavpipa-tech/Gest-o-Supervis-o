-- GAV: área administrativa — perfis de assistente de contratos e analista administrativo,
-- cronograma de tarefas, chamados, notas de parceiros e de alimentação PJ, pedidos mensais e caixas.
-- Executar no SQL Editor depois de equipe.sql. Pode ser repetido; não apaga dados.
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
    and (kind <> 'tarefa_transf' or ((public.is_manager() or public.gav_adm_task_office(data->>'task'))
      -- transferência para outra pessoa nasce pendente: só vale depois que quem recebe aceitar
      and (data->>'status' = 'pendente' or data->>'to' = auth.uid()::text or public.is_manager()))))
  or (kind = 'tarefa' and public.gav_adm_office() and data->'assignees' = jsonb_build_array(auth.uid()::text)));
drop policy if exists "adm: alteração" on public.adm_items;
create policy "adm: alteração" on public.adm_items for update to authenticated
  using ((public.gav_adm_can(kind, true) and (kind not in ('tarefa_feita','tarefa_transf') or created_by = auth.uid() or public.is_manager()
      or (kind = 'tarefa_transf' and data->>'to' = auth.uid()::text)))
    or (kind = 'tarefa' and created_by = auth.uid() and public.gav_adm_office()))
  -- quem recebe a transferência só responde (aceita ou recusa); não passa a tarefa para outra pessoa
  with check ((public.gav_adm_can(kind, true) and (kind <> 'tarefa_transf' or created_by = auth.uid() or public.is_manager() or data->>'to' = auth.uid()::text)) or (kind = 'tarefa' and created_by = auth.uid() and public.gav_adm_office() and data->'assignees' = jsonb_build_array(auth.uid()::text)));
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
