-- Kromix corrective migration: personnel relationships, trusted RP identity, and least-privilege access.
-- Run AFTER schema.sql and rp_accounts_migration.sql in Supabase SQL Editor.

-- Keep officer names sourced from the RP registration record, never from a CNP/character identifier.
update public.officers o
set full_name = concat_ws(' ', a.rp_first_name, a.rp_last_name),
    profile_name = concat_ws(' ', a.rp_first_name, a.rp_last_name)
from public.rp_accounts a
where a.user_id = o.user_id
  and nullif(trim(concat_ws(' ', a.rp_first_name, a.rp_last_name)), '') is not null;

-- Ensure future auth accounts are provisioned with their RP name and character identifier.
create or replace function public.provision_flash_rp_account()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_character_id text; v_first text; v_last text; v_phone text;
begin
  v_character_id := lower(trim(coalesce(new.raw_user_meta_data->>'character_id','')));
  v_first := trim(coalesce(new.raw_user_meta_data->>'rp_first_name',''));
  v_last := trim(coalesce(new.raw_user_meta_data->>'rp_last_name',''));
  v_phone := trim(coalesce(new.raw_user_meta_data->>'rp_phone',''));
  if v_character_id = '' or v_first = '' or v_last = '' or v_phone = '' then
    raise exception 'Kromix RP registration metadata is incomplete';
  end if;
  insert into public.rp_accounts(user_id,character_id,rp_first_name,rp_last_name,rp_phone)
  values(new.id,v_character_id,v_first,v_last,v_phone)
  on conflict(user_id) do update set character_id=excluded.character_id,
    rp_first_name=excluded.rp_first_name,rp_last_name=excluded.rp_last_name,rp_phone=excluded.rp_phone;
  insert into public.user_roles(user_id,role) values(new.id,'officer')
    on conflict(user_id) do nothing;
  insert into public.officers(user_id,full_name,badge_number,internal_id,phone,status,joined_at,profile_name)
  values(new.id,concat_ws(' ',v_first,v_last),v_character_id,v_character_id,v_phone,'Activ',current_date,concat_ws(' ',v_first,v_last))
  on conflict(user_id) do update set full_name=excluded.full_name,
    badge_number=excluded.badge_number,internal_id=excluded.internal_id,
    phone=excluded.phone,profile_name=excluded.profile_name;
  return new;
end; $$;

-- Recreate the Auth trigger so one authoritative provisioner handles the RP registration.
drop trigger if exists on_auth_user_created_officer on auth.users;
drop trigger if exists on_auth_user_created_flash_rp on auth.users;
create trigger on_auth_user_created_flash_rp after insert on auth.users
for each row execute function public.provision_flash_rp_account();

-- Explicit, unambiguous FK names for PostgREST embeds.
-- The officers -> departments relation must be selected as departments!officers_department_id_fkey
-- because departments.commander_id also references officers.
alter table public.officers drop constraint if exists officers_department_id_fkey;
alter table public.officers add constraint officers_department_id_fkey
  foreign key(department_id) references public.departments(id) on delete set null;

-- Do not allow members to update their own grade/department or other HR fields.
drop policy if exists "users update own officer profile" on public.officers;
drop policy if exists "management write officers" on public.officers;
create policy "officers leadership update" on public.officers for update to authenticated
  using(public.has_role(array['super_admin','commander']))
  with check(public.has_role(array['super_admin','commander']));
create policy "officers leadership insert" on public.officers for insert to authenticated
  with check(public.has_role(array['super_admin','commander']));
create policy "officers leadership delete" on public.officers for delete to authenticated
  using(public.has_role(array['super_admin','commander']));

-- RLS: DCCO reports are readable/writable only by DCCO members and authorized leadership.
alter table public.dcco_reports enable row level security;
drop policy if exists dcco_reports_access on public.dcco_reports;
drop policy if exists "dcco_reports_access" on public.dcco_reports;
create policy dcco_reports_access on public.dcco_reports for all to authenticated
  using(public.has_role(array['super_admin','commander','dcco','dcco_conducere']))
  with check(public.has_role(array['super_admin','commander','dcco','dcco_conducere']));

-- Academy/recruitment applications: applicants see their own; authorized leadership reviews.
alter table public.academy_applications enable row level security;
drop policy if exists "academy own or management read" on public.academy_applications;
drop policy if exists "academy own insert" on public.academy_applications;
drop policy if exists "academy management update" on public.academy_applications;
create policy "academy applicant or leadership read" on public.academy_applications for select to authenticated
  using(user_id=auth.uid() or public.has_role(array['super_admin','commander','hr']));
create policy "academy applicant insert" on public.academy_applications for insert to authenticated
  with check(user_id=auth.uid());
create policy "academy leadership review" on public.academy_applications for update to authenticated
  using(public.has_role(array['super_admin','commander','hr']))
  with check(public.has_role(array['super_admin','commander','hr']));

-- Role values used by the UI; do not assign these automatically.
alter table public.user_roles drop constraint if exists user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check(role in
 ('super_admin','commander','hr','officer','dcco','dcco_conducere',
  'instructor_radio','instructor_mdt','instructor_hs','instructor_heli'));

