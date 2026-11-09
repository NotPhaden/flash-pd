-- FLASH Police Department Panel - SUPABASE COMPLETELY FRESH SCHEMA
-- Paste into Supabase SQL Editor only in a NEW/EMPTY project (or after intentionally wiping public schema).
-- Auth users remain managed by Supabase Auth. This schema does not drop auth.users.
-- Project code uses anon key + Supabase Auth; keep service_role key server-side only.

-- Police HQ schema for Supabase (PostgreSQL)
-- Run this file in Supabase SQL Editor as project owner.

create extension if not exists pgcrypto;

create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  commander_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.ranks (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  level integer not null unique,
  category text not null default 'Execuție',
  created_at timestamptz not null default now()
);

create table if not exists public.officers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete set null,
  full_name text not null,
  badge_number text not null unique,
  internal_id text unique,
  rank_id uuid references public.ranks(id) on delete set null,
  department_id uuid references public.departments(id) on delete set null,
  status text not null default 'Activ' check (status in ('Activ','În serviciu','Liber','Suspendat','Inactiv')),
  joined_at date default current_date,
  phone text,
  email text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.departments drop constraint if exists departments_commander_id_fkey;
alter table public.departments add constraint departments_commander_id_fkey
  foreign key (commander_id) references public.officers(id) on delete set null;

create table if not exists public.activities (
  id uuid primary key default gen_random_uuid(),
  officer_id uuid references public.officers(id) on delete set null,
  title text not null,
  activity_type text not null default 'General',
  description text,
  location text,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.attendance (
  id uuid primary key default gen_random_uuid(),
  officer_id uuid not null references public.officers(id) on delete cascade,
  shift_start timestamptz not null,
  shift_end timestamptz,
  hours numeric(7,2),
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.sanctions (
  id uuid primary key default gen_random_uuid(),
  officer_id uuid not null references public.officers(id) on delete cascade,
  sanction_type text not null,
  reason text not null,
  issued_by uuid references public.officers(id) on delete set null,
  issued_at timestamptz not null default now(),
  details text
);

create table if not exists public.cases (
  id uuid primary key default gen_random_uuid(),
  case_number text not null unique,
  title text not null,
  description text,
  status text not null default 'În lucru',
  priority text not null default 'Normal',
  assigned_to uuid references public.officers(id) on delete set null,
  created_at timestamptz not null default now(),
  closed_at timestamptz
);

create table if not exists public.vehicles (
  id uuid primary key default gen_random_uuid(),
  plate_number text not null unique,
  model text not null,
  vehicle_type text,
  status text not null default 'Disponibil',
  assigned_department uuid references public.departments(id) on delete set null,
  assigned_officer uuid references public.officers(id) on delete set null,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.equipment (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  inventory_code text unique,
  category text,
  status text not null default 'Disponibil',
  assigned_officer uuid references public.officers(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  document_type text not null default 'General',
  storage_path text,
  description text,
  uploaded_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.recruitments (
  id uuid primary key default gen_random_uuid(),
  candidate_name text not null,
  contact text,
  status text not null default 'Candidat nou',
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'officer' check (role in ('super_admin','commander','hr','officer')),
  created_at timestamptz not null default now()
);

-- Helper function used by RLS policies. New accounts are NOT admins automatically.
create or replace function public.has_role(allowed_roles text[])
returns boolean language sql stable security definer set search_path = public
as $flash$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid() and role = any(allowed_roles)
  );
$flash$;

alter table public.departments enable row level security;
alter table public.ranks enable row level security;
alter table public.officers enable row level security;
alter table public.activities enable row level security;
alter table public.attendance enable row level security;
alter table public.sanctions enable row level security;
alter table public.cases enable row level security;
alter table public.vehicles enable row level security;
alter table public.equipment enable row level security;
alter table public.documents enable row level security;
alter table public.recruitments enable row level security;
alter table public.audit_logs enable row level security;
alter table public.user_roles enable row level security;

-- Authenticated users may read operational directory data.
drop policy if exists "authenticated read departments" on public.departments;
create policy "authenticated read departments" on public.departments for select to authenticated using (true);
drop policy if exists "authenticated read ranks" on public.ranks;
create policy "authenticated read ranks" on public.ranks for select to authenticated using (true);
drop policy if exists "authenticated read officers" on public.officers;
create policy "authenticated read officers" on public.officers for select to authenticated using (true);
drop policy if exists "authenticated read activities" on public.activities;
create policy "authenticated read activities" on public.activities for select to authenticated using (true);
drop policy if exists "authenticated read attendance" on public.attendance;
create policy "authenticated read attendance" on public.attendance for select to authenticated using (true);
drop policy if exists "authenticated read sanctions" on public.sanctions;
create policy "authenticated read sanctions" on public.sanctions for select to authenticated using (true);
drop policy if exists "authenticated read cases" on public.cases;
create policy "authenticated read cases" on public.cases for select to authenticated using (true);
drop policy if exists "authenticated read vehicles" on public.vehicles;
create policy "authenticated read vehicles" on public.vehicles for select to authenticated using (true);
drop policy if exists "authenticated read equipment" on public.equipment;
create policy "authenticated read equipment" on public.equipment for select to authenticated using (true);
drop policy if exists "authenticated read documents" on public.documents;
create policy "authenticated read documents" on public.documents for select to authenticated using (true);
drop policy if exists "authenticated read recruitments" on public.recruitments;
create policy "authenticated read recruitments" on public.recruitments for select to authenticated using (true);
drop policy if exists "users read own role" on public.user_roles;
create policy "users read own role" on public.user_roles for select to authenticated using (user_id = auth.uid());
drop policy if exists "admins read audit logs" on public.audit_logs;
create policy "admins read audit logs" on public.audit_logs for select to authenticated using (public.has_role(array['super_admin','commander']));

-- Write permissions restricted to management roles.
drop policy if exists "management write departments" on public.departments;
create policy "management write departments" on public.departments for all to authenticated
  using (public.has_role(array['super_admin','commander'])) with check (public.has_role(array['super_admin','commander']));
drop policy if exists "management write ranks" on public.ranks;
create policy "management write ranks" on public.ranks for all to authenticated
  using (public.has_role(array['super_admin','commander'])) with check (public.has_role(array['super_admin','commander']));
drop policy if exists "management write officers" on public.officers;
create policy "management write officers" on public.officers for all to authenticated
  using (public.has_role(array['super_admin','commander','hr'])) with check (public.has_role(array['super_admin','commander','hr']));
drop policy if exists "management write activities" on public.activities;
create policy "management write activities" on public.activities for all to authenticated
  using (public.has_role(array['super_admin','commander','officer'])) with check (public.has_role(array['super_admin','commander','officer']));
drop policy if exists "management write attendance" on public.attendance;
create policy "management write attendance" on public.attendance for all to authenticated
  using (public.has_role(array['super_admin','commander','officer'])) with check (public.has_role(array['super_admin','commander','officer']));
drop policy if exists "management write sanctions" on public.sanctions;
create policy "management write sanctions" on public.sanctions for all to authenticated
  using (public.has_role(array['super_admin','commander'])) with check (public.has_role(array['super_admin','commander']));
drop policy if exists "management write cases" on public.cases;
create policy "management write cases" on public.cases for all to authenticated
  using (public.has_role(array['super_admin','commander','officer'])) with check (public.has_role(array['super_admin','commander','officer']));
drop policy if exists "management write vehicles" on public.vehicles;
create policy "management write vehicles" on public.vehicles for all to authenticated
  using (public.has_role(array['super_admin','commander'])) with check (public.has_role(array['super_admin','commander']));
drop policy if exists "management write equipment" on public.equipment;
create policy "management write equipment" on public.equipment for all to authenticated
  using (public.has_role(array['super_admin','commander'])) with check (public.has_role(array['super_admin','commander']));
drop policy if exists "management write documents" on public.documents;
create policy "management write documents" on public.documents for all to authenticated
  using (public.has_role(array['super_admin','commander','hr'])) with check (public.has_role(array['super_admin','commander','hr']));
drop policy if exists "management write recruitments" on public.recruitments;
create policy "management write recruitments" on public.recruitments for all to authenticated
  using (public.has_role(array['super_admin','commander','hr'])) with check (public.has_role(array['super_admin','commander','hr']));
drop policy if exists "super admin manage roles" on public.user_roles;
create policy "super admin manage roles" on public.user_roles for all to authenticated
  using (public.has_role(array['super_admin'])) with check (public.has_role(array['super_admin']));
drop policy if exists "management insert audit logs" on public.audit_logs;
create policy "management insert audit logs" on public.audit_logs for insert to authenticated
  with check (actor_id = auth.uid() and public.has_role(array['super_admin','commander','hr']));

-- Seed data: initial ranks and departments
insert into public.ranks(name, level, category) values
('Agent',1,'Execuție'),('Agent principal',2,'Execuție'),('Agent șef adjunct',3,'Execuție'),
('Agent șef',4,'Execuție'),('Subinspector',5,'Ofițer'),('Inspector',6,'Ofițer'),
('Inspector principal',7,'Ofițer'),('Subcomisar',8,'Ofițer'),('Comisar',9,'Ofițer'),
('Comisar-șef',10,'Ofițer'),('Chestor',11,'Conducere')
on conflict(name) do nothing;

insert into public.departments(name, description) values
('Conducere','Coordonare și management instituțional'),
('Ordine publică','Menținerea ordinii și siguranței publice'),
('Poliția Rutieră','Siguranța circulației și control rutier'),
('Investigații criminale','Investigații și cercetare'),
('Criminalistică','Cercetare tehnico-științifică'),
('Intervenții speciale','Intervenții și operațiuni speciale')
on conflict(name) do nothing;

-- IMPORTANT: create your first user in Supabase Authentication, then promote that UUID:
-- insert into public.user_roles(user_id, role) values ('AUTH_USER_UUID', 'super_admin');




-- FLASH feature pack: academy, radio codes, processing templates, profile, notifications.
alter table public.officers add column if not exists call_sign text;
alter table public.officers add column if not exists avatar_url text;

create table if not exists public.academy_applications (
 id uuid primary key default gen_random_uuid(),
 user_id uuid references auth.users(id) on delete cascade,
 candidate_name text not null,
 contact text,
 status text not null default 'În așteptare' check(status in ('În așteptare','Acceptată','Respinsă')),
 reviewed_by uuid references auth.users(id) on delete set null,
 reviewed_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists public.radio_codes (
 id uuid primary key default gen_random_uuid(),
 code text not null unique,
 meaning text not null,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now()
);
create table if not exists public.processing_templates (
 id uuid primary key default gen_random_uuid(),
 title text not null,
 content text not null,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now()
);
create table if not exists public.notifications (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 title text not null,
 message text not null,
 kind text not null default 'general',
 read_at timestamptz,
 created_at timestamptz not null default now()
);

alter table public.academy_applications enable row level security;
alter table public.radio_codes enable row level security;
alter table public.processing_templates enable row level security;
alter table public.notifications enable row level security;

drop policy if exists "academy own or management read" on public.academy_applications;
drop policy if exists "academy own or management read" on public.academy_applications;
create policy "academy own or management read" on public.academy_applications for select to authenticated
 using (user_id=auth.uid() or public.has_role(array['super_admin','commander']));
drop policy if exists "academy own insert" on public.academy_applications;
drop policy if exists "academy own insert" on public.academy_applications;
create policy "academy own insert" on public.academy_applications for insert to authenticated with check (user_id=auth.uid());
drop policy if exists "academy management update" on public.academy_applications;
drop policy if exists "academy management update" on public.academy_applications;
create policy "academy management update" on public.academy_applications for update to authenticated
 using(public.has_role(array['super_admin','commander'])) with check(public.has_role(array['super_admin','commander']));
drop policy if exists "radio public read" on public.radio_codes;
create policy "radio public read" on public.radio_codes for select to authenticated using(true);
drop policy if exists "radio management write" on public.radio_codes;
create policy "radio management write" on public.radio_codes for all to authenticated
 using(public.has_role(array['super_admin','commander'])) with check(public.has_role(array['super_admin','commander']));
drop policy if exists "templates public read" on public.processing_templates;
create policy "templates public read" on public.processing_templates for select to authenticated using(true);
drop policy if exists "templates management write" on public.processing_templates;
create policy "templates management write" on public.processing_templates for all to authenticated
 using(public.has_role(array['super_admin','commander'])) with check(public.has_role(array['super_admin','commander']));
drop policy if exists "notifications own read" on public.notifications;
create policy "notifications own read" on public.notifications for select to authenticated using(user_id=auth.uid());
drop policy if exists "notifications own update" on public.notifications;
create policy "notifications own update" on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists "notifications management insert" on public.notifications;
create policy "notifications management insert" on public.notifications for insert to authenticated
 with check(public.has_role(array['super_admin','commander']) or user_id=auth.uid());

-- A user may update only their own profile fields.
drop policy if exists "users update own officer profile" on public.officers;
drop policy if exists "users update own officer profile" on public.officers;
create policy "users update own officer profile" on public.officers for update to authenticated
 using(user_id=auth.uid()) with check(user_id=auth.uid());

-- Calculate shift hours when a shift is closed.
create or replace function public.calculate_attendance_hours()
returns trigger language plpgsql as $flash$
begin
 if new.shift_end is not null then
   if new.shift_end < new.shift_start then raise exception 'Sfârșitul turei precedă începutul'; end if;
   new.hours := round((extract(epoch from (new.shift_end-new.shift_start))/3600)::numeric,2);
 end if;
 return new;
end; $flash$;
drop trigger if exists attendance_calculate_hours on public.attendance;
create trigger attendance_calculate_hours before insert or update on public.attendance
for each row execute function public.calculate_attendance_hours();

-- Notify the affected officer when management records a sanction.
create or replace function public.notify_officer_sanction()
returns trigger language plpgsql security definer set search_path=public as $flash$
declare target_user uuid;
begin
 select user_id into target_user from public.officers where id=new.officer_id;
 if target_user is not null then
  insert into public.notifications(user_id,title,message,kind)
  values(target_user,'Ai primit o sancțiune',new.sanction_type||': '||new.reason,'sanction');
 end if;
 return new;
end; $flash$;
drop trigger if exists sanctions_notify_officer on public.sanctions;
create trigger sanctions_notify_officer after insert on public.sanctions
for each row execute function public.notify_officer_sanction();

-- Create a personnel row for every new auth account so it appears in the directory.
create or replace function public.create_officer_for_auth_user()
returns trigger language plpgsql security definer set search_path=public as $flash$
declare label text;
begin
 label := coalesce(nullif(new.raw_user_meta_data->>'full_name',''), split_part(coalesce(new.email,'Membru'), '@', 1));
 insert into public.officers(user_id,full_name,badge_number,status,email)
 values(new.id,label,'USR-'||substr(replace(new.id::text,'-',''),1,12),'Activ',new.email)
 on conflict(user_id) do nothing;
 return new;
end; $flash$;
drop trigger if exists on_auth_user_created_officer on auth.users;
create trigger on_auth_user_created_officer after insert on auth.users
for each row execute function public.create_officer_for_auth_user();

-- Storage bucket for profile photos. Public URLs are read-only; uploads are owner-scoped.
insert into storage.buckets(id,name,public) values('avatars','avatars',true) on conflict(id) do nothing;
drop policy if exists "avatar owner upload" on storage.objects;
drop policy if exists "avatar owner upload" on storage.objects;
create policy "avatar owner upload" on storage.objects for insert to authenticated
 with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "avatar owner update" on storage.objects;
drop policy if exists "avatar owner update" on storage.objects;
create policy "avatar owner update" on storage.objects for update to authenticated
 using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "avatar public read" on storage.objects;
drop policy if exists "avatar public read" on storage.objects;
create policy "avatar public read" on storage.objects for select to public using(bucket_id='avatars');

-- Backfill existing authentication accounts that predate this migration.
insert into public.officers(user_id,full_name,badge_number,status,email)
select u.id,
 coalesce(nullif(u.raw_user_meta_data->>'full_name',''),split_part(coalesce(u.email,'Membru'),'@',1)),
 'USR-'||substr(replace(u.id::text,'-',''),1,12),'Activ',u.email
from auth.users u
where not exists(select 1 from public.officers o where o.user_id=u.id)
on conflict(user_id) do nothing;

-- Replace the template attendance write rule: members may edit only their own shifts.
drop policy if exists "management write attendance" on public.attendance;
drop policy if exists "attendance insert own or management" on public.attendance;
drop policy if exists "attendance update own or management" on public.attendance;
drop policy if exists "attendance insert own or management" on public.attendance;
create policy "attendance insert own or management" on public.attendance for insert to authenticated
 with check (
  public.has_role(array['super_admin','commander'])
  or exists(select 1 from public.officers o where o.id=officer_id and o.user_id=auth.uid())
 );
drop policy if exists "attendance update own or management" on public.attendance;
create policy "attendance update own or management" on public.attendance for update to authenticated
 using (
  public.has_role(array['super_admin','commander'])
  or exists(select 1 from public.officers o where o.id=officer_id and o.user_id=auth.uid())
 )
 with check (
  public.has_role(array['super_admin','commander'])
  or exists(select 1 from public.officers o where o.id=officer_id and o.user_id=auth.uid())
 );


-- FLASH DCCO + certificate systems. Apply after schema.sql and flash_migration.sql.
create table if not exists public.officer_ranks (
 id uuid primary key default gen_random_uuid(),
 officer_id uuid not null references public.officers(id) on delete cascade,
 rank_id uuid not null references public.ranks(id) on delete cascade,
 assigned_by uuid references auth.users(id),
 assigned_at timestamptz not null default now(),
 unique(officer_id,rank_id)
);
create table if not exists public.officer_certificates (
 id uuid primary key default gen_random_uuid(),
 officer_id uuid not null references public.officers(id) on delete cascade,
 certificate text not null check(certificate in ('Radio','MDT','HS','Heli')),
 instructor_id uuid references public.officers(id) on delete set null,
 granted_at timestamptz not null default now(),
 unique(officer_id,certificate)
);
create table if not exists public.certificate_applications (
 id uuid primary key default gen_random_uuid(),
 user_id uuid references auth.users(id) on delete cascade,
 officer_id uuid references public.officers(id) on delete cascade,
 certificate text not null check(certificate in ('Radio','MDT','HS','Heli')),
 candidate_name text not null,
 cnp text,
 call_sign text,
 test_evidence text,
 status text not null default 'În așteptare' check(status in ('În așteptare','Acceptată','Respinsă')),
 reviewed_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 reviewed_at timestamptz
);
create table if not exists public.dcco_reports (
 id uuid primary key default gen_random_uuid(),
 kind text not null check(kind in ('Filaj','Interogatoriu','Raport organizație')),
 title text not null,
 subject_name text,
 cnp text,
 started_at timestamptz,
 ended_at timestamptz,
 evidence text,
 details text not null default '',
 organization_name text,
 leadership text,
 members text,
 allies text,
 status text not null default 'În așteptare' check(status in ('În așteptare','Aprobat','Respins')),
 created_by uuid references auth.users(id),
 reviewed_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.officers add column if not exists cnp text;
alter table public.officers add column if not exists avatar_url text;
alter table public.officers add column if not exists call_sign text;
alter table public.officers add column if not exists profile_name text;

-- Keep auth account display names, rather than falling back to the email local-part.
create or replace function public.create_officer_for_auth_user()
returns trigger language plpgsql security definer set search_path=public as $flash$
declare label text;
begin
 label := coalesce(nullif(trim(concat_ws(' ',new.raw_user_meta_data->>'first_name',new.raw_user_meta_data->>'last_name')),''),
 nullif(new.raw_user_meta_data->>'full_name',''), nullif(new.raw_user_meta_data->>'name',''), 'Membru nou');
 insert into public.officers(user_id,full_name,badge_number,status,email,profile_name)
 values(new.id,label,'USR-'||substr(replace(new.id::text,'-',''),1,12),'Activ',new.email,label)
 on conflict(user_id) do update set email=excluded.email,
 full_name=case when officers.full_name like '%@%' then excluded.full_name else officers.full_name end;
 return new;
end; $flash$;
drop trigger if exists on_auth_user_created_officer on auth.users;
create trigger on_auth_user_created_officer after insert on auth.users
for each row execute function public.create_officer_for_auth_user();

insert into public.officers(user_id,full_name,badge_number,status,email,profile_name)
select u.id,
 coalesce(nullif(trim(concat_ws(' ',u.raw_user_meta_data->>'first_name',u.raw_user_meta_data->>'last_name')),''),
 nullif(u.raw_user_meta_data->>'full_name',''),nullif(u.raw_user_meta_data->>'name',''),'Membru nou'),
 'USR-'||substr(replace(u.id::text,'-',''),1,12),'Activ',u.email,
 coalesce(nullif(trim(concat_ws(' ',u.raw_user_meta_data->>'first_name',u.raw_user_meta_data->>'last_name')),''),
 nullif(u.raw_user_meta_data->>'full_name',''),nullif(u.raw_user_meta_data->>'name',''),'Membru nou')
from auth.users u where not exists(select 1 from public.officers o where o.user_id=u.id)
on conflict(user_id) do nothing;

create or replace function public.has_dcco_access()
returns boolean language sql stable security definer set search_path=public as $flash$
 select public.has_role(array['super_admin','commander','dcco','dcco_conducere']);
$flash$;
create or replace function public.has_certificate_instructor(cert text)
returns boolean language sql stable security definer set search_path=public as $flash$
 select public.has_role(array['super_admin','commander']) or exists(
 select 1 from public.user_roles ur where ur.user_id=auth.uid() and ur.role=case cert
 when 'Radio' then 'instructor_radio' when 'MDT' then 'instructor_mdt'
 when 'HS' then 'instructor_hs' when 'Heli' then 'instructor_heli' else '' end);
$flash$;

alter table public.officer_ranks enable row level security;
alter table public.officer_certificates enable row level security;
alter table public.certificate_applications enable row level security;
alter table public.dcco_reports enable row level security;
drop policy if exists officer_ranks_read on public.officer_ranks;
drop policy if exists "officer_ranks_read" on public.officer_ranks;
create policy officer_ranks_read on public.officer_ranks for select to authenticated using(true);
drop policy if exists officer_ranks_manage on public.officer_ranks;
drop policy if exists "officer_ranks_manage" on public.officer_ranks;
create policy officer_ranks_manage on public.officer_ranks for all to authenticated using(public.has_role(array['super_admin','commander'])) with check(public.has_role(array['super_admin','commander']));
drop policy if exists officer_certificates_read on public.officer_certificates;
drop policy if exists "officer_certificates_read" on public.officer_certificates;
create policy officer_certificates_read on public.officer_certificates for select to authenticated using(true);
drop policy if exists officer_certificates_manage on public.officer_certificates;
drop policy if exists "officer_certificates_manage" on public.officer_certificates;
create policy officer_certificates_manage on public.officer_certificates for all to authenticated using(public.has_role(array['super_admin','commander']) or public.has_role(array['instructor_radio','instructor_mdt','instructor_hs','instructor_heli'])) with check(public.has_role(array['super_admin','commander']) or public.has_role(array['instructor_radio','instructor_mdt','instructor_hs','instructor_heli']));
drop policy if exists cert_apps_read on public.certificate_applications;
drop policy if exists "cert_apps_read" on public.certificate_applications;
create policy cert_apps_read on public.certificate_applications for select to authenticated using(user_id=auth.uid() or public.has_role(array['super_admin','commander','instructor_radio','instructor_mdt','instructor_hs','instructor_heli']));
drop policy if exists cert_apps_insert on public.certificate_applications;
drop policy if exists "cert_apps_insert" on public.certificate_applications;
create policy cert_apps_insert on public.certificate_applications for insert to authenticated with check(user_id=auth.uid());
drop policy if exists cert_apps_review on public.certificate_applications;
drop policy if exists "cert_apps_review" on public.certificate_applications;
create policy cert_apps_review on public.certificate_applications for update to authenticated using(public.has_role(array['super_admin','commander','instructor_radio','instructor_mdt','instructor_hs','instructor_heli'])) with check(public.has_role(array['super_admin','commander','instructor_radio','instructor_mdt','instructor_hs','instructor_heli']));
drop policy if exists dcco_reports_access on public.dcco_reports;
drop policy if exists "dcco_reports_access" on public.dcco_reports;
create policy dcco_reports_access on public.dcco_reports for all to authenticated using(public.has_dcco_access()) with check(public.has_dcco_access());

alter table public.user_roles drop constraint if exists user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check(role in
 ('super_admin','commander','hr','officer','dcco','dcco_conducere','instructor_radio','instructor_mdt','instructor_hs','instructor_heli'));

-- The new role values are documented here; assign them explicitly to users via user_roles.
-- Roles: dcco, dcco_conducere, instructor_radio, instructor_mdt, instructor_hs, instructor_heli.


-- Additional application fields and seed values used by the FLASH UI.
alter table public.officers add column if not exists profile_name text;
alter table public.officers add column if not exists cnp text;

insert into public.ranks(name,level,category) values
 ('Chestor general',12,'Conducere'),('Chestor secundar',13,'Conducere'),
 ('Conducere DCCO',14,'Conducere'),
 ('Instructor radio',15,'Instructor'),('Instructor MDT',16,'Instructor'),
 ('Instructor HS',17,'Instructor'),('Instructor Heli',18,'Instructor')
on conflict(name) do nothing;

insert into public.departments(name,description) values
 ('DCCO','Direcția de Combatere a Criminalității Organizate')
on conflict(name) do nothing;

-- Rebuild allowed role list with FLASH access roles.
alter table public.user_roles drop constraint if exists user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check(role in
 ('super_admin','commander','hr','officer','dcco','dcco_conducere',
  'instructor_radio','instructor_mdt','instructor_hs','instructor_heli'));

-- Access helpers. Explicit role assignment is required; never auto-promote new accounts.
create or replace function public.has_dcco_access()
returns boolean language sql stable security definer set search_path=public as $flash$
 select public.has_role(array['super_admin','commander','dcco','dcco_conducere']);
$flash$;

-- Repair/replace Auth signup profile trigger: prefer actual first/last name metadata.
create or replace function public.create_officer_for_auth_user()
returns trigger language plpgsql security definer set search_path=public as $flash$
declare label text;
begin
 label := coalesce(
  nullif(trim(concat_ws(' ',new.raw_user_meta_data->>'first_name',new.raw_user_meta_data->>'last_name')),''),
  nullif(new.raw_user_meta_data->>'full_name',''),
  nullif(new.raw_user_meta_data->>'name',''),
  'Membru nou');
 insert into public.officers(user_id,full_name,badge_number,status,email,profile_name)
 values(new.id,label,'USR-'||substr(replace(new.id::text,'-',''),1,12),'Activ',new.email,label)
 on conflict(user_id) do update set email=excluded.email,
 full_name=case when officers.full_name like '%@%' then excluded.full_name else officers.full_name end,
 profile_name=coalesce(officers.profile_name,excluded.profile_name);
 return new;
end; $flash$;
drop trigger if exists on_auth_user_created_officer on auth.users;
create trigger on_auth_user_created_officer after insert on auth.users
for each row execute function public.create_officer_for_auth_user();

-- Backfill every Auth account missing its personnel record.
insert into public.officers(user_id,full_name,badge_number,status,email,profile_name)
select u.id,
 coalesce(nullif(trim(concat_ws(' ',u.raw_user_meta_data->>'first_name',u.raw_user_meta_data->>'last_name')),''),
  nullif(u.raw_user_meta_data->>'full_name',''),nullif(u.raw_user_meta_data->>'name',''),'Membru nou'),
 'USR-'||substr(replace(u.id::text,'-',''),1,12),'Activ',u.email,
 coalesce(nullif(trim(concat_ws(' ',u.raw_user_meta_data->>'first_name',u.raw_user_meta_data->>'last_name')),''),
  nullif(u.raw_user_meta_data->>'full_name',''),nullif(u.raw_user_meta_data->>'name',''),'Membru nou')
from auth.users u
where not exists(select 1 from public.officers o where o.user_id=u.id)
on conflict(user_id) do nothing;

-- Enable realtime for the directory (safe if already added).
do $flash$ begin
 alter publication supabase_realtime add table public.officers;
exception when duplicate_object then null; when undefined_object then null;
end $flash$;

-- First administrator: after signup, run with your own Auth user UUID:
-- update public.user_roles set role='super_admin' where user_id='YOUR_AUTH_UUID';
-- Or insert if no role row exists:
-- insert into public.user_roles(user_id,role) values ('YOUR_AUTH_UUID','super_admin')
-- on conflict(user_id) do update set role=excluded.role;

-- FLASH: cereri concediu/invoire si certificari pentru instructori
create table if not exists public.absence_requests (
 id uuid primary key default gen_random_uuid(),
 officer_id uuid not null references public.officers(id) on delete cascade,
 request_type text not null check (request_type in ('Concediu','Învoire ședință')),
 cnp text not null,
 starts_on date not null,
 ends_on date not null,
 reason text not null,
 status text not null default 'În așteptare' check (status in ('În așteptare','Aprobată','Respinsă')),
 reviewed_by uuid references auth.users(id),
 reviewed_at timestamptz,
 reviewer_note text,
 created_at timestamptz not null default now(),
 check (ends_on >= starts_on)
);
create table if not exists public.certificates (
 id uuid primary key default gen_random_uuid(),
 name text not null unique,
 description text,
 instructor_officer_id uuid references public.officers(id) on delete set null,
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists public.certificate_applications (
 id uuid primary key default gen_random_uuid(),
 officer_id uuid not null references public.officers(id) on delete cascade,
 certificate_id uuid not null references public.certificates(id) on delete cascade,
 motivation text,
 evidence_url text,
 status text not null default 'În așteptare' check (status in ('În așteptare','Acceptată','Respinsă')),
 reviewed_by uuid references auth.users(id),
 reviewed_at timestamptz,
 reviewer_note text,
 created_at timestamptz not null default now()
);
create table if not exists public.certificate_evidence (
 id uuid primary key default gen_random_uuid(),
 application_id uuid not null references public.certificate_applications(id) on delete cascade,
 officer_id uuid not null references public.officers(id) on delete cascade,
 evidence_url text not null,
 description text,
 created_at timestamptz not null default now()
);
insert into public.departments(name,description) values
 ('CONDUCERE','Conducerea departamentului'),('DCCO','Direcția de combatere a criminalității organizate'),
 ('SAS','Serviciul pentru acțiuni speciale'),('INSTRUCTORI','Instructori și certificări')
on conflict(name) do nothing;
alter table public.absence_requests enable row level security;
alter table public.certificates enable row level security;
alter table public.certificate_applications enable row level security;
alter table public.certificate_evidence enable row level security;
-- Authenticated users can read their own requests; command staff (subcomisar and above is
-- enforced by the assigned role/permission model) can review via management roles.
drop policy if exists "absence requests read own or management" on public.absence_requests;
create policy "absence requests read own or management" on public.absence_requests for select to authenticated
 using (officer_id in (select id from public.officers where user_id=auth.uid()) or public.has_role(array['super_admin','commander','hr']));
drop policy if exists "absence requests create own" on public.absence_requests;
create policy "absence requests create own" on public.absence_requests for insert to authenticated
 with check (officer_id in (select id from public.officers where user_id=auth.uid()));
drop policy if exists "management review absence requests" on public.absence_requests;
create policy "management review absence requests" on public.absence_requests for update to authenticated
 using (public.has_role(array['super_admin','commander','hr'])) with check (public.has_role(array['super_admin','commander','hr']));
drop policy if exists "authenticated read active certificates" on public.certificates;
create policy "authenticated read active certificates" on public.certificates for select to authenticated using (active=true or public.has_role(array['super_admin','commander']));
drop policy if exists "management manage certificates" on public.certificates;
create policy "management manage certificates" on public.certificates for all to authenticated
 using (public.has_role(array['super_admin','commander'])) with check (public.has_role(array['super_admin','commander']));
drop policy if exists "certificate apps read own or instructor management" on public.certificate_applications;
create policy "certificate apps read own or instructor management" on public.certificate_applications for select to authenticated
 using (officer_id in (select id from public.officers where user_id=auth.uid()) or public.has_role(array['super_admin','commander','instructor']));
drop policy if exists "certificate apps create own" on public.certificate_applications;
create policy "certificate apps create own" on public.certificate_applications for insert to authenticated
 with check (officer_id in (select id from public.officers where user_id=auth.uid()));
drop policy if exists "instructors review certificate apps" on public.certificate_applications;
create policy "instructors review certificate apps" on public.certificate_applications for update to authenticated
 using (public.has_role(array['super_admin','commander','instructor'])) with check (public.has_role(array['super_admin','commander','instructor']));
drop policy if exists "certificate evidence read own or instructor" on public.certificate_evidence;
create policy "certificate evidence read own or instructor" on public.certificate_evidence for select to authenticated
 using (officer_id in (select id from public.officers where user_id=auth.uid()) or public.has_role(array['super_admin','commander','instructor']));
drop policy if exists "certificate evidence add own" on public.certificate_evidence;
create policy "certificate evidence add own" on public.certificate_evidence for insert to authenticated
 with check (officer_id in (select id from public.officers where user_id=auth.uid()));
