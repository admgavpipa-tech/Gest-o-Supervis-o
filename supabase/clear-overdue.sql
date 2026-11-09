-- GAV · Limpar tarefas atrasadas (somente gestão).
-- Execute no SQL Editor depois de supabase/reliability.sql. Pode ser repetido; não apaga registros nem fotos.
-- A tarefa atrasada limpa deixa de ser cobrada da equipe. O dia original continua no histórico como "sem registro".
begin;
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
revoke all on function public.gav_expected(jsonb,date) from public,anon,authenticated;

create or replace function public.gav_clear_overdue()
returns integer language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid(); d date:=gav_today(); ids jsonb; who text; e record; prevkey text; n integer:=0;
begin
 if actor is null or not is_manager() then raise exception 'Somente a gestão pode limpar tarefas atrasadas.' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(718293451);
 select coalesce(jsonb_agg(l->>'id'),'[]') into ids from app_state a cross join lateral jsonb_array_elements(coalesce(a.data->'lists','[]')) l where a.id=1;
 select name into who from profiles where id=actor;
 for e in select x.key,x.data from gav_expected(ids,d) x where coalesce((x.data->>'overdue')::boolean,false) loop
  -- Atraso já concluído ou justificado hoje continua como está.
  if exists(select 1 from records r where r.key=e.key and r.data->>'status' in ('done','justified')) then continue; end if;
  prevkey:=(e.data->>'previousDate')||':'||(e.data->>'aid');
  insert into records(key,date,data) values(prevkey,(e.data->>'previousDate')::date,
   jsonb_build_object('status','missed','date',e.data->>'previousDate','aid',e.data->>'aid','dismissed',d,'dismissedBy',actor,'dismissedByName',who))
   on conflict(key) do update set data=records.data||jsonb_build_object('dismissed',d,'dismissedBy',actor,'dismissedByName',who),updated_at=now();
  n:=n+1;
 end loop;
 return n;
end $$;
revoke all on function public.gav_clear_overdue() from public,anon;
grant execute on function public.gav_clear_overdue() to authenticated;
commit;
