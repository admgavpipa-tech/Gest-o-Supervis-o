-- GAV · Criação de acessos pela gestão sem envio de e-mail (sem limite de e-mails do Supabase).
-- Cole em SQL Editor > New query e clique em Run. Pode ser executado de novo.
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
