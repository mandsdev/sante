-- Store the validated CPF entered during signup, under the same user-only RLS policy.
alter table public.profiles add column if not exists cpf text;
create unique index if not exists profiles_cpf_unique_idx
    on public.profiles (cpf) where cpf is not null;

create or replace function public.create_sante_profile_for_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.profiles (user_id, display_name, cpf, country_code, phone)
    values (
        new.id,
        coalesce(new.raw_user_meta_data ->> 'full_name', ''),
        new.raw_user_meta_data ->> 'cpf',
        coalesce(new.raw_user_meta_data ->> 'country_code', '+55'),
        new.raw_user_meta_data ->> 'phone'
    )
    on conflict (user_id) do nothing;

    insert into public.health_profiles (user_id)
    values (new.id)
    on conflict (user_id) do nothing;

    return new;
end;
$$;
