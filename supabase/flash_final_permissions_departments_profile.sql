-- Kromix final corrections: appearance save, department deduplication,
-- top-command permissions, deletions and certificate applications.
-- Run AFTER all previously supplied Kromix migrations.

-- 1) Rank-based permission helpers. Rank 12 = Chestor general, 13 = Chestor secundar.
create or replace function public.current_officer_rank_level()
returns integer language sql stable security definer set search_path=public
as 'select coalesce(max(r.level),0) from public.officers o left join public.ranks r on r.id=o.rank_id where o.user_id=auth.uid()';
grant execute on function public.current_officer_rank_level() to authenticated;

create or replace function public.is_flash_leadership()
returns boolean language sql stable security definer set search_path=public
as 'select public.has_role(array[''super_admin'',''commander'']) or public.current_officer_rank_level() between 8 and 13';
grant execute on function public.is_flash_leadership() to authenticated;

create or replace function public.is_flash_top_command()
returns boolean language sql stable security definer set search_path=public
as 'select public.has_role(array[''super_admin'',''commander'']) or public.current_officer_rank_level() between 12 and 13';
grant execute on function public.is_flash_top_command() to authenticated;

-- Ensure the access-role vocabulary and unit-specific ranks are present.
alter table public.user_roles drop constraint if exists user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check (role in (
  'super_admin','commander','hr','officer','instructor','dcco','dcco_conducere','sas','sas_conducere',
  'instructor_radio','instructor_mdt','instructor_hs','instructor_heli'
));

insert into public.ranks(name,level,category) values
 ('Chestor general',12,'Conducere'),('Chestor secundar',13,'Conducere'),
 ('Conducere DCCO',14,'Conducere'),('Instructor radio',15,'Instructor'),
 ('Instructor MDT',16,'Instructor'),('Instructor HS',17,'Instructor'),
 ('Instructor Heli',18,'Instructor'),('Conducere SAS',19,'Conducere')
on conflict do nothing;

insert into public.departments(name,description) values
 ('Conducere','Coordonare și management instituțional'),
 ('Ordine publică','Menținerea ordinii și siguranței publice'),
 ('Poliția Rutieră','Siguranța circulației și control rutier'),
 ('Investigații criminale','Investigații și cercetare'),
 ('Criminalistică','Cercetare tehnico-științifică'),
 ('DCCO','Direcția de Combatere a Criminalității Organizate'),
 ('SAS','Serviciul pentru Acțiuni Speciale'),
 ('Instructori','Instructori și certificări'),
 ('Intervenții speciale','Intervenții și operațiuni speciale')
on conflict(name) do update set description=excluded.description;

-- 2) Consolidate duplicate department rows (e.g. Instructori / INSTRUCTORI)
-- and preserve both the legacy primary department and all multi-department links.
create temp table if not exists flash_department_merge (
  old_id uuid primary key,
  canonical_id uuid not null
) on commit preserve rows;
truncate table flash_department_merge;
insert into flash_department_merge(old_id,canonical_id)
select id as old_id,
       first_value(id) over (partition by lower(btrim(name)) order by created_at, id) as canonical_id
from public.departments;

create table if not exists public.officer_departments (
  id uuid primary key default gen_random_uuid(),
  officer_id uuid not null references public.officers(id) on delete cascade,
  department_id uuid not null references public.departments(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(officer_id, department_id)
);

insert into public.officer_departments(officer_id,department_id)
select od.officer_id, m.canonical_id
from public.officer_departments od
join flash_department_merge m on m.old_id=od.department_id
where m.old_id<>m.canonical_id
on conflict(officer_id,department_id) do nothing;

insert into public.officer_departments(officer_id,department_id)
select o.id,m.canonical_id
from public.officers o
join flash_department_merge m on m.old_id=o.department_id
where o.department_id is not null
on conflict(officer_id,department_id) do nothing;

update public.officers o
set department_id=m.canonical_id
from flash_department_merge m
where o.department_id=m.old_id and m.old_id<>m.canonical_id;

delete from public.officer_departments od
using flash_department_merge m
where od.department_id=m.old_id and m.old_id<>m.canonical_id;

delete from public.departments d
using flash_department_merge m
where d.id=m.old_id and m.old_id<>m.canonical_id;

insert into public.officer_departments(officer_id,department_id)
select o.id,d.id
from public.officers o
join public.user_roles ur on ur.user_id=o.user_id
join public.departments d on lower(btrim(d.name))=case
  when ur.role in ('sas','sas_conducere') then 'sas'
  when ur.role in ('dcco','dcco_conducere') then 'dcco'
  when ur.role in ('super_admin','commander') then 'conducere'
  when ur.role in ('instructor_radio','instructor_mdt','instructor_hs','instructor_heli') then 'instructori'
end
where ur.role in ('sas','sas_conducere','dcco','dcco_conducere','super_admin','commander','instructor','instructor_radio','instructor_mdt','instructor_hs','instructor_heli')
on conflict(officer_id,department_id) do nothing;

create unique index if not exists departments_name_ci_unique on public.departments(lower(btrim(name)));

-- 3) Ensure profile fields exist and make the profile appearance RPC reliable.
alter table public.officers add column if not exists avatar_url text;
alter table public.officers add column if not exists background_url text;
alter table public.officers add column if not exists call_sign text;
alter table public.officers add column if not exists cnp text;
alter table public.officers alter column badge_number drop not null;

insert into storage.buckets(id,name,public)
values ('avatars','avatars',true)
on conflict(id) do update set public=true;

drop policy if exists flash_avatar_public_read on storage.objects;
create policy flash_avatar_public_read on storage.objects for select to anon, authenticated
using (bucket_id='avatars');
drop policy if exists flash_avatar_insert_own on storage.objects;
create policy flash_avatar_insert_own on storage.objects for insert to authenticated
with check (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists flash_avatar_update_own on storage.objects;
create policy flash_avatar_update_own on storage.objects for update to authenticated
using (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text)
with check (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);

create or replace function public.update_own_profile_appearance(p_avatar_url text, p_background_url text)
returns void language plpgsql security definer set search_path=public
as 'BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION ''Autentificare necesară''; END IF;
  UPDATE public.officers
  SET avatar_url=p_avatar_url, background_url=p_background_url, updated_at=now()
  WHERE user_id=auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION ''Nu există un profil de personal asociat contului''; END IF;
END;';
grant execute on function public.update_own_profile_appearance(text,text) to authenticated;

-- 4) Top command can assign ranks and departments even if the auth role is officer.
create or replace function public.protect_officer_assignment_fields()
returns trigger language plpgsql security definer set search_path=public
as 'BEGIN
  IF (NEW.rank_id IS DISTINCT FROM OLD.rank_id OR NEW.department_id IS DISTINCT FROM OLD.department_id)
     AND NOT public.is_flash_top_command() THEN
    RAISE EXCEPTION ''Doar Chestorul general și Chestorul secundar pot modifica gradul sau departamentul'';
  END IF;
  RETURN NEW;
END;';
drop trigger if exists protect_officer_assignment_fields on public.officers;
create trigger protect_officer_assignment_fields before update on public.officers
for each row execute function public.protect_officer_assignment_fields();

drop policy if exists officer_departments_manage on public.officer_departments;
drop policy if exists officer_departments_top_command on public.officer_departments;
create policy officer_departments_top_command on public.officer_departments for all to authenticated
using (public.is_flash_top_command()) with check (public.is_flash_top_command());

-- 5) Deletion rules: each owner can remove their own notifications;
-- Subcomisar+ can remove published resources/inventory and action forms;
-- only top command can delete recruitment applications.
drop policy if exists notifications_delete_own on public.notifications;
create policy notifications_delete_own on public.notifications for delete to authenticated
using (user_id=auth.uid());

drop policy if exists radio_codes_delete_leadership on public.radio_codes;
create policy radio_codes_delete_leadership on public.radio_codes for delete to authenticated
using (public.is_flash_leadership());
drop policy if exists processing_templates_delete_leadership on public.processing_templates;
create policy processing_templates_delete_leadership on public.processing_templates for delete to authenticated
using (public.is_flash_leadership());

drop policy if exists vehicles_delete_leadership on public.vehicles;
create policy vehicles_delete_leadership on public.vehicles for delete to authenticated
using (public.is_flash_leadership());
drop policy if exists equipment_delete_leadership on public.equipment;
create policy equipment_delete_leadership on public.equipment for delete to authenticated
using (public.is_flash_leadership());

drop policy if exists action_forms_delete_leadership on public.action_forms;
create policy action_forms_delete_leadership on public.action_forms for delete to authenticated
using (public.is_flash_leadership());

drop policy if exists academy_applications_delete_top_command on public.academy_applications;
create policy academy_applications_delete_top_command on public.academy_applications for delete to authenticated
using (public.is_flash_top_command());

-- 6) DCCO members may submit and read reports; only DCCO leadership can review/delete.
alter table public.dcco_reports enable row level security;
drop policy if exists dcco_reports_access on public.dcco_reports;
drop policy if exists dcco_reports_member_read on public.dcco_reports;
drop policy if exists dcco_reports_member_insert on public.dcco_reports;
drop policy if exists dcco_reports_leadership_update on public.dcco_reports;
drop policy if exists dcco_reports_leadership_delete on public.dcco_reports;
create policy dcco_reports_member_read on public.dcco_reports for select to authenticated
using (public.has_role(array['super_admin','commander','dcco','dcco_conducere']));
create policy dcco_reports_member_insert on public.dcco_reports for insert to authenticated
with check (public.has_role(array['super_admin','commander','dcco','dcco_conducere']) and created_by=auth.uid());
create policy dcco_reports_leadership_update on public.dcco_reports for update to authenticated
using (public.has_role(array['super_admin','commander','dcco_conducere']))
with check (public.has_role(array['super_admin','commander','dcco_conducere']));
create policy dcco_reports_leadership_delete on public.dcco_reports for delete to authenticated
using (public.has_role(array['super_admin','commander','dcco_conducere']));

-- 7) Extend SAS documentation choices to the requested tactical guides.
alter table public.unit_documents drop constraint if exists unit_documents_type_check;
alter table public.unit_documents add constraint unit_documents_type_check check (
  (unit_key='SAS' and doc_type in ('Regulament SAS','Instructaj SAS','Tactici jaf','Tactici Cayo','Poziții jaf')) or
  (unit_key='DCCO' and doc_type in ('Regulament DCCO','Instructaj DCCO'))
);

-- 8) Certificate applications: applicants see/create their own; instructors and leadership review.
alter table public.certificate_applications enable row level security;
drop policy if exists certificate_apps_read_own_or_instructors on public.certificate_applications;
drop policy if exists certificate_apps_insert_own on public.certificate_applications;
drop policy if exists certificate_apps_review_instructors on public.certificate_applications;
drop policy if exists officer_certificates_manage_by_instructors on public.officer_certificates;
drop policy if exists cert_apps_read on public.certificate_applications;
drop policy if exists "certificate apps read own or instructor management" on public.certificate_applications;
create policy certificate_apps_read_own_or_instructors on public.certificate_applications for select to authenticated
using (user_id=auth.uid() or public.has_role(array['super_admin','commander','instructor','instructor_radio','instructor_mdt','instructor_hs','instructor_heli']));
drop policy if exists cert_apps_insert on public.certificate_applications;
drop policy if exists "certificate apps create own" on public.certificate_applications;
create policy certificate_apps_insert_own on public.certificate_applications for insert to authenticated
with check (user_id=auth.uid() and officer_id in (select id from public.officers where user_id=auth.uid()));
drop policy if exists cert_apps_review on public.certificate_applications;
drop policy if exists "instructors review certificate apps" on public.certificate_applications;
create policy certificate_apps_review_instructors on public.certificate_applications for update to authenticated
using (public.has_role(array['super_admin','commander','instructor','instructor_radio','instructor_mdt','instructor_hs','instructor_heli']))
with check (public.has_role(array['super_admin','commander','instructor','instructor_radio','instructor_mdt','instructor_hs','instructor_heli']));

-- Allow certificate awards to designated instructors and top command.
drop policy if exists officer_certificates_manage on public.officer_certificates;
drop policy if exists officer_certificates_manage_by_instructors on public.officer_certificates;
create policy officer_certificates_manage_by_instructors on public.officer_certificates for all to authenticated
using (public.has_role(array['super_admin','commander','instructor','instructor_radio','instructor_mdt','instructor_hs','instructor_heli']))
with check (public.has_role(array['super_admin','commander','instructor','instructor_radio','instructor_mdt','instructor_hs','instructor_heli']));

-- 9) Make sure the unit-document type check and RLS remain explicit.
-- Do not expose any database/provider configuration in the public UI.
