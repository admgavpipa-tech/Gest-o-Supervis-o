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

-- Quem pode ver (p_write = false) e alterar (true) cada tipo. A gestão vê e altera tudo.
create or replace function public.gav_adm_can(p_kind text, p_write boolean) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select case p.role
    when 'gestor' then true
    when 'analista' then p_kind in ('tarefa_feita','parceiro','nota','pedido','pagamento') or (not p_write and p_kind in ('tarefa','caixa'))
    when 'contratos' then p_kind in ('tarefa_feita','chamado','contrato') or (not p_write and p_kind = 'tarefa')
    else false end
  from profiles p where p.id = auth.uid() and p.active and not p.archived), false) $$;
revoke all on function public.gav_adm_can(text, boolean) from public, anon;
grant execute on function public.gav_adm_can(text, boolean) to authenticated;

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
create policy "adm: leitura" on public.adm_items for select to authenticated using (public.gav_adm_can(kind, false));
drop policy if exists "adm: inclusão" on public.adm_items;
create policy "adm: inclusão" on public.adm_items for insert to authenticated with check (public.gav_adm_can(kind, true));
drop policy if exists "adm: alteração" on public.adm_items;
create policy "adm: alteração" on public.adm_items for update to authenticated
  using (public.gav_adm_can(kind, true) and (kind <> 'tarefa_feita' or created_by = auth.uid() or public.is_manager()))
  with check (public.gav_adm_can(kind, true));
drop policy if exists "adm: exclusão" on public.adm_items;
create policy "adm: exclusão" on public.adm_items for delete to authenticated
  using (public.gav_adm_can(kind, true) and (kind <> 'tarefa_feita' or created_by = auth.uid() or public.is_manager()));

-- Comprovantes (recibos assinados e notas fiscais dos caixas). Ficam guardados; não entram na limpeza de 30 dias das fotos.
insert into storage.buckets(id, name, public) values ('comprovantes', 'comprovantes', false) on conflict (id) do nothing;
drop policy if exists "comprovantes: leitura" on storage.objects;
create policy "comprovantes: leitura" on storage.objects for select to authenticated using (bucket_id = 'comprovantes' and public.gav_adm_can('pagamento', false));
drop policy if exists "comprovantes: envio" on storage.objects;
create policy "comprovantes: envio" on storage.objects for insert to authenticated with check (bucket_id = 'comprovantes' and public.gav_adm_can('pagamento', true));
drop policy if exists "comprovantes: exclusão" on storage.objects;
create policy "comprovantes: exclusão" on storage.objects for delete to authenticated using (bucket_id = 'comprovantes' and public.gav_adm_can('pagamento', true));

do $$ begin alter publication supabase_realtime add table public.adm_items; exception when duplicate_object then null; end $$;
commit;
