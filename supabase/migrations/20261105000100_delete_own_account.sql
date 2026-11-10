-- Permite que a pessoa exclua a própria conta pelo app (exigência da App Store).
-- O app apaga os arquivos do Storage antes; aqui apaga o login e, em cascata,
-- o perfil, os dados de saúde e a lista de documentos.

create or replace function public.delete_own_account()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  delete from auth.users where id = auth.uid();
end; $$;

revoke all on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;
