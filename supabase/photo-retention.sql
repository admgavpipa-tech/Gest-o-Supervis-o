-- Retenção das fotos: comprovantes com mais de 30 dias são apagados.
-- O Supabase só permite apagar arquivos pela API de Storage. O app da gestão faz a limpeza
-- uma vez por dia: lista as fotos vencidas, apaga os arquivos e marca os registros.
-- Pode ser executado de novo sem efeito colateral.
begin;

-- A gestão só consegue apagar fotos que já passaram do prazo.
drop policy if exists "fotos: exclusão de vencidas pela gestão" on storage.objects;
create policy "fotos: exclusão de vencidas pela gestão" on storage.objects for delete to authenticated
 using(bucket_id='fotos' and public.is_manager() and created_at<now()-interval '30 days');

create or replace function public.gav_expired_photos()
returns setof text language plpgsql stable security definer set search_path=public,storage as $$
begin
 if not is_manager() then raise exception 'Somente a gestão pode limpar fotos.' using errcode='42501'; end if;
 return query select o.name from storage.objects o
  where o.bucket_id='fotos' and o.created_at<now()-interval '30 days' order by o.created_at limit 500;
end $$;

-- Registros cujo arquivo não existe mais deixam de apontar para ele e ficam marcados como foto apagada.
-- Links públicos antigos são comparados pelo caminho dentro do bucket.
create or replace function public.gav_forget_missing_photos()
returns integer language plpgsql security definer set search_path=public,storage as $$
declare n integer;
begin
 if not is_manager() then raise exception 'Somente a gestão pode limpar fotos.' using errcode='42501'; end if;
 update records r set data=(r.data-'photo')||jsonb_build_object('photoExpired',true),updated_at=now()
 where coalesce(r.data->>'photo','') not in ('','demo')
  and not exists(select 1 from storage.objects o where o.bucket_id='fotos' and o.name=coalesce(
   nullif(split_part(r.data->>'photo','/storage/v1/object/public/fotos/',2),''),r.data->>'photo'));
 get diagnostics n=row_count;
 return n;
end $$;

revoke all on function public.gav_expired_photos() from public,anon;
revoke all on function public.gav_forget_missing_photos() from public,anon;
grant execute on function public.gav_expired_photos() to authenticated;
grant execute on function public.gav_forget_missing_photos() to authenticated;

commit;
