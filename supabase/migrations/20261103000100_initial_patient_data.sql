-- Sante patient data schema. Apply only after linking a Supabase project.
-- Patient health data and attachments are private and owned by one auth user.

create table if not exists public.profiles (
    user_id uuid primary key references auth.users (id) on delete cascade,
    display_name text not null default '',
    cpf text,
    country_code text not null default '+55',
    phone text,
    date_of_birth date,
    profile_photo_path text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint profiles_name_length check (char_length(display_name) <= 160),
    constraint profiles_photo_path_owner check (
        profile_photo_path is null
        or (storage.foldername(profile_photo_path))[1] = user_id::text
    )
);

create table if not exists public.health_profiles (
    user_id uuid primary key references auth.users (id) on delete cascade,
    weight_kg numeric(5, 2),
    height_cm numeric(5, 2),
    blood_type text,
    allergies text,
    health_conditions text,
    medications text,
    emergency_contact text,
    updated_at timestamptz not null default now(),
    constraint health_profiles_weight_range check (weight_kg is null or weight_kg between 0.1 and 500),
    constraint health_profiles_height_range check (height_cm is null or height_cm between 1 and 300),
    constraint health_profiles_blood_type check (
        blood_type is null or blood_type in ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')
    )
);

create table if not exists public.patient_documents (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    bucket_id text not null default 'patient-documents',
    object_path text not null,
    display_name text not null,
    mime_type text not null,
    file_size_bytes bigint,
    created_at timestamptz not null default now(),
    constraint patient_documents_bucket check (bucket_id = 'patient-documents'),
    constraint patient_documents_path_owner check ((storage.foldername(object_path))[1] = user_id::text),
    constraint patient_documents_size check (file_size_bytes is null or file_size_bytes between 1 and 26214400),
    constraint patient_documents_user_path_unique unique (user_id, object_path)
);

create index if not exists patient_documents_user_created_idx
    on public.patient_documents (user_id, created_at desc);

create unique index if not exists profiles_cpf_unique_idx
    on public.profiles (cpf) where cpf is not null;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
    before update on public.profiles
    for each row execute function public.set_updated_at();

drop trigger if exists health_profiles_set_updated_at on public.health_profiles;
create trigger health_profiles_set_updated_at
    before update on public.health_profiles
    for each row execute function public.set_updated_at();

-- Create a private profile and health row whenever Supabase Auth creates a user.
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

revoke all on function public.create_sante_profile_for_new_auth_user() from public, anon, authenticated;
drop trigger if exists on_sante_auth_user_created on auth.users;
create trigger on_sante_auth_user_created
    after insert on auth.users
    for each row execute function public.create_sante_profile_for_new_auth_user();

alter table public.profiles enable row level security;
alter table public.health_profiles enable row level security;
alter table public.patient_documents enable row level security;

revoke all on table public.profiles, public.health_profiles, public.patient_documents from anon, authenticated;
grant select, insert, update on table public.profiles, public.health_profiles to authenticated;
grant select, insert, delete on table public.patient_documents to authenticated;

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
    for select to authenticated
    using ((select auth.uid()) = user_id);

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
    for insert to authenticated
    with check (
        (select auth.uid()) = user_id
        and (
            profile_photo_path is null
            or (storage.foldername(profile_photo_path))[1] = (select auth.uid()::text)
        )
    );

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
    for update to authenticated
    using ((select auth.uid()) = user_id)
    with check (
        (select auth.uid()) = user_id
        and (
            profile_photo_path is null
            or (storage.foldername(profile_photo_path))[1] = (select auth.uid()::text)
        )
    );

drop policy if exists health_profiles_select_own on public.health_profiles;
create policy health_profiles_select_own on public.health_profiles
    for select to authenticated
    using ((select auth.uid()) = user_id);

drop policy if exists health_profiles_insert_own on public.health_profiles;
create policy health_profiles_insert_own on public.health_profiles
    for insert to authenticated
    with check ((select auth.uid()) = user_id);

drop policy if exists health_profiles_update_own on public.health_profiles;
create policy health_profiles_update_own on public.health_profiles
    for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

drop policy if exists patient_documents_select_own on public.patient_documents;
create policy patient_documents_select_own on public.patient_documents
    for select to authenticated
    using ((select auth.uid()) = user_id);

drop policy if exists patient_documents_insert_own on public.patient_documents;
create policy patient_documents_insert_own on public.patient_documents
    for insert to authenticated
    with check (
        (select auth.uid()) = user_id
        and bucket_id = 'patient-documents'
        and (storage.foldername(object_path))[1] = (select auth.uid()::text)
    );

drop policy if exists patient_documents_delete_own on public.patient_documents;
create policy patient_documents_delete_own on public.patient_documents
    for delete to authenticated
    using ((select auth.uid()) = user_id);

-- Private buckets. Objects are stored under <auth-user-id>/<uuid>.<extension>.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
    ('profile-photos', 'profile-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
    ('patient-documents', 'patient-documents', false, 26214400, array['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/heic'])
on conflict (id) do update set
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists profile_photos_select_own on storage.objects;
create policy profile_photos_select_own on storage.objects
    for select to authenticated
    using (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid()::text));

drop policy if exists profile_photos_insert_own on storage.objects;
create policy profile_photos_insert_own on storage.objects
    for insert to authenticated
    with check (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid()::text));

drop policy if exists profile_photos_update_own on storage.objects;
create policy profile_photos_update_own on storage.objects
    for update to authenticated
    using (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid()::text))
    with check (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid()::text));

drop policy if exists profile_photos_delete_own on storage.objects;
create policy profile_photos_delete_own on storage.objects
    for delete to authenticated
    using (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid()::text));

drop policy if exists patient_documents_storage_select_own on storage.objects;
create policy patient_documents_storage_select_own on storage.objects
    for select to authenticated
    using (bucket_id = 'patient-documents' and (storage.foldername(name))[1] = (select auth.uid()::text));

drop policy if exists patient_documents_storage_insert_own on storage.objects;
create policy patient_documents_storage_insert_own on storage.objects
    for insert to authenticated
    with check (bucket_id = 'patient-documents' and (storage.foldername(name))[1] = (select auth.uid()::text));

drop policy if exists patient_documents_storage_update_own on storage.objects;
create policy patient_documents_storage_update_own on storage.objects
    for update to authenticated
    using (bucket_id = 'patient-documents' and (storage.foldername(name))[1] = (select auth.uid()::text))
    with check (bucket_id = 'patient-documents' and (storage.foldername(name))[1] = (select auth.uid()::text));

drop policy if exists patient_documents_storage_delete_own on storage.objects;
create policy patient_documents_storage_delete_own on storage.objects
    for delete to authenticated
    using (bucket_id = 'patient-documents' and (storage.foldername(name))[1] = (select auth.uid()::text));
