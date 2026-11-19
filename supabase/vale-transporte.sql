-- Respostas do formulário de vale-transporte (vale-transporte/).
-- Qualquer pessoa com o link envia uma resposta pela função gav_vt_responder;
-- só a gestão (is_manager) lê e apaga. Rode depois de schema.sql.

create table if not exists public.vt_respostas(
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  nome text not null,
  setor text not null,
  regiao text not null,
  bairro text not null,
  rua text not null,
  referencia text not null,
  valor_ida numeric(8,2) not null check (valor_ida >= 0 and valor_ida <= 1000)
);

alter table public.vt_respostas enable row level security;
revoke all on public.vt_respostas from anon, authenticated;
grant select, delete on public.vt_respostas to authenticated;

drop policy if exists vt_respostas_gestao_le on public.vt_respostas;
create policy vt_respostas_gestao_le on public.vt_respostas for select to authenticated using (public.is_manager());
drop policy if exists vt_respostas_gestao_apaga on public.vt_respostas;
create policy vt_respostas_gestao_apaga on public.vt_respostas for delete to authenticated using (public.is_manager());

create or replace function public.gav_vt_responder(
  p_nome text, p_setor text, p_regiao text, p_bairro text, p_rua text, p_referencia text, p_valor numeric
) returns bigint
language plpgsql security definer set search_path = public as $$
declare novo bigint;
begin
  p_nome := btrim(coalesce(p_nome,'')); p_setor := btrim(coalesce(p_setor,'')); p_regiao := btrim(coalesce(p_regiao,''));
  p_bairro := btrim(coalesce(p_bairro,'')); p_rua := btrim(coalesce(p_rua,'')); p_referencia := btrim(coalesce(p_referencia,''));
  if length(p_nome) < 3 or length(p_nome) > 120 then raise exception 'Informe o nome completo.'; end if;
  if p_setor = '' or length(p_setor) > 80 then raise exception 'Informe o setor.'; end if;
  if p_regiao = '' or length(p_regiao) > 120 then raise exception 'Informe a região.'; end if;
  if p_bairro = '' or length(p_bairro) > 120 then raise exception 'Informe o bairro.'; end if;
  if p_rua = '' or length(p_rua) > 200 then raise exception 'Informe a rua e o número.'; end if;
  if p_referencia = '' or length(p_referencia) > 300 then raise exception 'Informe um ponto de referência.'; end if;
  if p_valor is null or p_valor < 0 or p_valor > 1000 then raise exception 'Valor da passagem inválido.'; end if;
  -- limite simples contra envio em massa
  if (select count(*) from vt_respostas where created_at > now() - interval '1 minute') >= 30 then
    raise exception 'Muitos envios agora. Tente de novo em um minuto.';
  end if;
  insert into vt_respostas(nome, setor, regiao, bairro, rua, referencia, valor_ida)
  values (p_nome, p_setor, p_regiao, p_bairro, p_rua, p_referencia, round(p_valor, 2))
  returning id into novo;
  return novo;
end $$;

revoke all on function public.gav_vt_responder(text,text,text,text,text,text,numeric) from public;
grant execute on function public.gav_vt_responder(text,text,text,text,text,text,numeric) to anon, authenticated;

-- a página de respostas atualiza sozinha quando chega resposta nova
do $$ begin alter publication supabase_realtime add table public.vt_respostas; exception when duplicate_object then null; end $$;
grant execute on function public.is_manager() to authenticated;
