-- Kromix v2: fixes for profile storage, Visitor access, instructor certificates,
-- department membership, career dates and UP/DOWN history.
-- Run AFTER the existing schema and all Kromix migrations.

-- 1) New accounts start as Visitor, not as an operational officer.
alter table public.user_roles alter column role set default 'visitor';
alter table public.user_roles drop constraint if exists user_roles_role_check;
update public.user_roles set role='officer' where role='instructor';
alter table public.user_roles add constraint user_roles_role_check check (role in (
 'visitor','super_admin','commander','hr','officer','dcco','dcco_conducere','sas','sas_conducere',
 'instructor_radio','instructor_mdt','instructor_heli','instructor_moto','instructor_hs'
));
insert into public.user_roles(user_id,role)
select u.id,'visitor' from auth.users u
where not exists(select 1 from public.user_roles ur where ur.user_id=u.id)
on conflict(user_id) do nothing;

-- Keep RP signup provisioning, but give every newly-created account Visitor access.
create or replace function public.provision_flash_rp_account()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_character_id text; v_first text; v_last text; v_phone text;
begin
 v_character_id:=lower(trim(coalesce(new.raw_user_meta_data->>'character_id','')));
 v_first:=trim(coalesce(new.raw_user_meta_data->>'rp_first_name',''));
 v_last:=trim(coalesce(new.raw_user_meta_data->>'rp_last_name',''));
 v_phone:=trim(coalesce(new.raw_user_meta_data->>'rp_phone',''));
 if v_character_id='' or v_first='' or v_last='' or v_phone='' then
   raise exception 'Datele de înregistrare RP sunt incomplete';
 end if;
 insert into public.rp_accounts(user_id,character_id,rp_first_name,rp_last_name,rp_phone)
 values(new.id,v_character_id,v_first,v_last,v_phone)
 on conflict(user_id) do update set character_id=excluded.character_id,rp_first_name=excluded.rp_first_name,rp_last_name=excluded.rp_last_name,rp_phone=excluded.rp_phone;
 insert into public.user_roles(user_id,role) values(new.id,'visitor') on conflict(user_id) do nothing;
 insert into public.officers(user_id,full_name,badge_number,internal_id,phone,status,joined_at,profile_name)
 values(new.id,concat_ws(' ',v_first,v_last),v_character_id,v_character_id,v_phone,'Activ',current_date,concat_ws(' ',v_first,v_last))
 on conflict(user_id) do update set full_name=excluded.full_name,badge_number=excluded.badge_number,internal_id=excluded.internal_id,phone=excluded.phone,profile_name=excluded.profile_name;
 update public.officers set rank_id=(select id from public.ranks where lower(name)='vizitator' limit 1) where user_id=new.id and rank_id is null;
 return new;
end; $$;

drop trigger if exists on_auth_user_created_officer on auth.users;
drop trigger if exists on_auth_user_created_flash_rp on auth.users;
create trigger on_auth_user_created_flash_rp after insert on auth.users
for each row execute function public.provision_flash_rp_account();

-- Normalize legacy instructor rank labels and reassign generic Instructor by certificate role.
update public.ranks set name=case lower(name)
 when 'instructor radio' then 'Instructor Radio' when 'instructor mdt' then 'Instructor MDT'
 when 'instructor heli' then 'Instructor Heli' when 'instructor moto' then 'Instructor Moto'
 when 'instructor hs' then 'Instructor HS' else name end
where lower(name) in ('instructor radio','instructor mdt','instructor heli','instructor moto','instructor hs');
update public.officers o set rank_id=r.id from public.user_roles ur,public.ranks r
where ur.user_id=o.user_id and r.name=case ur.role
 when 'instructor_radio' then 'Instructor Radio' when 'instructor_mdt' then 'Instructor MDT'
 when 'instructor_heli' then 'Instructor Heli' when 'instructor_moto' then 'Instructor Moto'
 when 'instructor_hs' then 'Instructor HS' else '' end;
update public.officers o set rank_id=(select id from public.ranks where name='Agent' limit 1)
where o.rank_id in(select id from public.ranks where lower(name)='instructor');
delete from public.ranks where lower(name)='instructor'
 and not exists(select 1 from public.officers o where o.rank_id=public.ranks.id);

-- Chestor general is above Chestor secundar in the promotion ladder.
update public.ranks set level=(select coalesce(max(level),0)+1 from public.ranks) where name='Chestor general';
update public.ranks set level=12 where name='Chestor secundar';
update public.ranks set level=13 where name='Chestor general';

-- 2) Explicit rank records. Do not collide with existing unique rank levels.
do $$
declare n text; v_level integer;
begin
 foreach n in array array['Instructor Radio','Instructor MDT','Instructor Heli','Instructor Moto','Instructor HS'] loop
   if not exists(select 1 from public.ranks where lower(name)=lower(n)) then
     select coalesce(max(level),0)+1 into v_level from public.ranks;
     insert into public.ranks(name,level,category) values(n,v_level,'Instructor');
   end if;
 end loop;
 if not exists(select 1 from public.ranks where lower(name)='vizitator') then
   select coalesce(min(level),0)-1 into v_level from public.ranks;
   insert into public.ranks(name,level,category) values('Vizitator',v_level,'Acces inițial');
 end if;
end $$;
update public.officers o set rank_id=r.id
from public.ranks r,public.user_roles ur
where ur.user_id=o.user_id and ur.role='visitor' and lower(r.name)='vizitator' and o.rank_id is null;


-- Consolidate retired departments into the retained Patrulare structure.
insert into public.departments(name,description) values
 ('Patrulare','Structură operațională generală'),('Academie','Formare și pregătire profesională')
on conflict(name) do nothing;
update public.officers o set department_id=(select id from public.departments where name='Patrulare' limit 1)
where o.department_id in(select id from public.departments where lower(name) in
 ('intervenții speciale','criminalistică','intervenții criminale','ordine publică','poliția rutieră','poliție rutieră'));
insert into public.officer_departments(officer_id,department_id)
select distinct od.officer_id,(select id from public.departments where name='Patrulare' limit 1)
from public.officer_departments od join public.departments d on d.id=od.department_id
where lower(d.name) in ('intervenții speciale','criminalistică','intervenții criminale','ordine publică','poliția rutieră','poliție rutieră')
on conflict(officer_id,department_id) do nothing;
delete from public.officer_departments od using public.departments d
where od.department_id=d.id and lower(d.name) in
 ('intervenții speciale','criminalistică','intervenții criminale','ordine publică','poliția rutieră','poliție rutieră');
delete from public.departments where lower(name) in
 ('intervenții speciale','criminalistică','intervenții criminale','ordine publică','poliția rutieră','poliție rutieră');

-- 3) Moto certificate and instructor authorization must match the certificate.
alter table public.officer_certificates drop constraint if exists officer_certificates_certificate_check;
alter table public.officer_certificates add constraint officer_certificates_certificate_check
 check(certificate in ('Radio','MDT','Heli','Moto','HS'));
alter table public.certificate_applications drop constraint if exists certificate_applications_certificate_check;
alter table public.certificate_applications add constraint certificate_applications_certificate_check
 check(certificate in ('Radio','MDT','Heli','Moto','HS'));

create or replace function public.has_certificate_instructor(cert text)
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_role(array['super_admin','commander']) or exists(
   select 1 from public.user_roles ur where ur.user_id=auth.uid() and ur.role=case cert
    when 'Radio' then 'instructor_radio' when 'MDT' then 'instructor_mdt'
    when 'Heli' then 'instructor_heli' when 'Moto' then 'instructor_moto'
    when 'HS' then 'instructor_hs' else '' end
 ) or exists(
   select 1 from public.officers o join public.ranks r on r.id=o.rank_id
   where o.user_id=auth.uid() and r.name=case cert
    when 'Radio' then 'Instructor Radio' when 'MDT' then 'Instructor MDT'
    when 'Heli' then 'Instructor Heli' when 'Moto' then 'Instructor Moto'
    when 'HS' then 'Instructor HS' else '' end
 );
$$;

drop policy if exists officer_certificates_manage on public.officer_certificates;
drop policy if exists officer_certificates_manage_by_instructors on public.officer_certificates;
create policy officer_certificates_manage on public.officer_certificates for all to authenticated
using(public.has_certificate_instructor(certificate) or public.current_officer_rank_level() between 12 and 13)
with check(public.has_certificate_instructor(certificate) or public.current_officer_rank_level() between 12 and 13);
drop policy if exists cert_apps_read on public.certificate_applications;
drop policy if exists certificate_apps_read_own_or_instructors on public.certificate_applications;
drop policy if exists "certificate apps read own or instructor management" on public.certificate_applications;
create policy cert_apps_read on public.certificate_applications for select to authenticated
using(user_id=auth.uid() or public.has_certificate_instructor(certificate) or public.current_officer_rank_level() between 12 and 13);
drop policy if exists cert_apps_review on public.certificate_applications;
drop policy if exists certificate_apps_review_instructors on public.certificate_applications;
drop policy if exists "instructors review certificate apps" on public.certificate_applications;
create policy cert_apps_review on public.certificate_applications for update to authenticated
using(public.has_certificate_instructor(certificate) or public.current_officer_rank_level() between 12 and 13)
with check(public.has_certificate_instructor(certificate) or public.current_officer_rank_level() between 12 and 13);
drop policy if exists certificate_apps_delete_own_or_instructor on public.certificate_applications;
create policy certificate_apps_delete_own_or_instructor on public.certificate_applications for delete to authenticated
using(user_id=auth.uid() or public.has_certificate_instructor(certificate) or public.current_officer_rank_level() between 12 and 13);

-- 4) Storage bucket, owner-only uploads, public image reads and safe profile update RPC.
alter table public.officers add column if not exists avatar_url text;
alter table public.officers add column if not exists background_url text;
alter table public.officers add column if not exists joined_at date default current_date;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('avatars','avatars',true,5242880,array['image/png','image/jpeg','image/webp','image/gif'])
on conflict(id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/png','image/jpeg','image/webp','image/gif'];
drop policy if exists flash_avatar_public_read on storage.objects;
create policy flash_avatar_public_read on storage.objects for select to anon,authenticated using(bucket_id='avatars');
drop policy if exists flash_avatar_insert_own on storage.objects;
create policy flash_avatar_insert_own on storage.objects for insert to authenticated
with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists flash_avatar_update_own on storage.objects;
create policy flash_avatar_update_own on storage.objects for update to authenticated
using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text)
with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists flash_avatar_delete_own on storage.objects;
create policy flash_avatar_delete_own on storage.objects for delete to authenticated
using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);

create or replace function public.update_own_profile_appearance(p_avatar_url text,p_background_url text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'Autentificare necesară'; end if;
 update public.officers set avatar_url=p_avatar_url,background_url=p_background_url,updated_at=now()
 where user_id=auth.uid();
 if not found then raise exception 'Nu există un profil asociat acestui cont'; end if;
end; $$;
grant execute on function public.update_own_profile_appearance(text,text) to authenticated;

-- 5) DCCO/SAS access follows actual personnel department assignment, not a stale role row.
create or replace function public.has_dcco_access()
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_role(array['super_admin','commander','dcco','dcco_conducere']) or exists(
  select 1 from public.officers o left join public.departments d on d.id=o.department_id left join public.ranks r on r.id=o.rank_id
  where o.user_id=auth.uid() and upper(coalesce(d.name,''))='DCCO' and (r.name='Conducere DCCO' or d.name='DCCO')
 ) or exists(
  select 1 from public.officer_departments od join public.departments d on d.id=od.department_id
  join public.officers o on o.id=od.officer_id where o.user_id=auth.uid() and upper(d.name)='DCCO'
 );
$$;
create or replace function public.has_sas_access()
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_role(array['super_admin','commander','sas','sas_conducere']) or exists(
  select 1 from public.officers o left join public.departments d on d.id=o.department_id left join public.ranks r on r.id=o.rank_id
  where o.user_id=auth.uid() and upper(coalesce(d.name,''))='SAS' and (r.name='Conducere SAS' or d.name='SAS')
 ) or exists(
  select 1 from public.officer_departments od join public.departments d on d.id=od.department_id
  join public.officers o on o.id=od.officer_id where o.user_id=auth.uid() and upper(d.name)='SAS'
 );
$$;

create or replace function public.get_unit_members(p_unit text)
returns table(user_id uuid,role text) language plpgsql stable security definer set search_path=public as $$
declare v_unit text:=upper(p_unit);
begin
 if v_unit='SAS' and not public.has_sas_access() then raise exception 'Acces interzis la lista SAS';
 elsif v_unit='DCCO' and not public.has_dcco_access() then raise exception 'Acces interzis la lista DCCO';
 elsif v_unit not in ('SAS','DCCO') then raise exception 'Unitate invalidă'; end if;
 return query
 select distinct o.user_id,case when r.name='Conducere SAS' then 'sas_conducere' when r.name='Conducere DCCO' then 'dcco_conducere' when ur.role in ('sas','sas_conducere','dcco','dcco_conducere') then ur.role else case when v_unit='SAS' then 'sas' else 'dcco' end end
 from public.officers o left join public.departments d on d.id=o.department_id
 left join public.ranks r on r.id=o.rank_id left join public.user_roles ur on ur.user_id=o.user_id
 where o.user_id is not null and upper(coalesce(d.name,''))=v_unit
 union
 select distinct o.user_id,case when r.name='Conducere SAS' then 'sas_conducere' when r.name='Conducere DCCO' then 'dcco_conducere' when ur.role in ('sas','sas_conducere','dcco','dcco_conducere') then ur.role else case when v_unit='SAS' then 'sas' else 'dcco' end end
 from public.officer_departments od join public.departments d on d.id=od.department_id
 join public.officers o on o.id=od.officer_id left join public.ranks r on r.id=o.rank_id left join public.user_roles ur on ur.user_id=o.user_id
 where o.user_id is not null and upper(d.name)=v_unit;
end; $$;
grant execute on function public.get_unit_members(text) to authenticated;

create or replace function public.can_manage_unit_documents(p_unit text)
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_role(array['super_admin','commander']) or exists(
  select 1 from public.officers o left join public.departments d on d.id=o.department_id left join public.ranks r on r.id=o.rank_id
  where o.user_id=auth.uid() and upper(coalesce(d.name,''))=upper(p_unit)
    and ((upper(p_unit)='DCCO' and r.name='Conducere DCCO') or (upper(p_unit)='SAS' and r.name='Conducere SAS'))
 ) or exists(
  select 1 from public.officer_departments od join public.departments d on d.id=od.department_id
  join public.officers o on o.id=od.officer_id join public.ranks r on r.id=o.rank_id
  where o.user_id=auth.uid() and upper(d.name)=upper(p_unit)
    and ((upper(p_unit)='DCCO' and r.name='Conducere DCCO') or (upper(p_unit)='SAS' and r.name='Conducere SAS'))
 );
$$;
grant execute on function public.can_manage_unit_documents(text) to authenticated;


-- 6) UP/DOWN audit trail and server-side authorization.
create table if not exists public.officer_promotions(
 id uuid primary key default gen_random_uuid(),
 officer_id uuid not null references public.officers(id) on delete cascade,
 change_type text not null check(change_type in ('UP','DOWN','EDITARE')),
 old_rank_id uuid references public.ranks(id) on delete set null,
 new_rank_id uuid references public.ranks(id) on delete set null,
 old_rank_name text,new_rank_name text,
 changed_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now()
);
alter table public.officer_promotions enable row level security;
drop policy if exists officer_promotions_read_own_or_command on public.officer_promotions;
create policy officer_promotions_read_own_or_command on public.officer_promotions for select to authenticated
using(officer_id in(select id from public.officers where user_id=auth.uid()) or public.has_role(array['super_admin','commander']) or public.current_officer_rank_level() between 12 and 13);

create or replace function public.manage_officer_career(p_officer_id uuid,p_joined_at date default null,p_rank_id uuid default null,p_change text default null)
returns void language plpgsql security definer set search_path=public as $$
declare old_id uuid; new_id uuid; old_name text; new_name text; old_level integer; target record;
begin
 if auth.uid() is null then raise exception 'Autentificare necesară'; end if;
 if not (public.current_officer_rank_level() between 12 and 13 or public.has_role(array['super_admin','commander'])) then
  raise exception 'UP/DOWN și editarea carierei sunt disponibile doar de la Chestor secundar'; end if;
 select o.rank_id,r.name,r.level into old_id,old_name,old_level from public.officers o left join public.ranks r on r.id=o.rank_id where o.id=p_officer_id for update;
 if not found then raise exception 'Membrul nu există'; end if;
 new_id:=old_id;
 if p_change='UP' or p_change='up' then
  select id,name,level into target from public.ranks where level>coalesce(old_level,-999) and name not ilike 'Instructor%' and name not ilike 'Conducere DCCO%' and name not ilike 'Conducere SAS%' order by level asc limit 1;
  if target.id is null then raise exception 'Nu există un grad superior disponibil'; end if; new_id:=target.id;
 elsif p_change='DOWN' or p_change='down' then
  select id,name,level into target from public.ranks where level<coalesce(old_level,999999) and name not ilike 'Instructor%' and name not ilike 'Conducere DCCO%' and name not ilike 'Conducere SAS%' order by level desc limit 1;
  if target.id is null then raise exception 'Nu există un grad inferior disponibil'; end if; new_id:=target.id;
 elsif p_rank_id is not null then new_id:=p_rank_id;
 end if;
 select name into new_name from public.ranks where id=new_id;
 update public.officers set joined_at=coalesce(p_joined_at,joined_at),rank_id=new_id,updated_at=now() where id=p_officer_id;
 if new_id is distinct from old_id then
  insert into public.officer_promotions(officer_id,change_type,old_rank_id,new_rank_id,old_rank_name,new_rank_name,changed_by)
  values(p_officer_id,case when p_change is null then 'EDITARE' when upper(p_change)='UP' then 'UP' else 'DOWN' end,old_id,new_id,old_name,new_name,auth.uid());
 end if;
end; $$;
grant execute on function public.manage_officer_career(uuid,date,uuid,text) to authenticated;

-- DCCO members can read and submit; only unit leadership can review or delete.
drop policy if exists dcco_reports_access on public.dcco_reports;
drop policy if exists dcco_reports_member_read on public.dcco_reports;
drop policy if exists dcco_reports_member_insert on public.dcco_reports;
drop policy if exists dcco_reports_leadership_update on public.dcco_reports;
drop policy if exists dcco_reports_leadership_delete on public.dcco_reports;
create policy dcco_reports_member_read on public.dcco_reports for select to authenticated
using(public.has_dcco_access());
create policy dcco_reports_member_insert on public.dcco_reports for insert to authenticated
with check(public.has_dcco_access() and created_by=auth.uid());
create policy dcco_reports_leadership_update on public.dcco_reports for update to authenticated
using(public.can_manage_unit_documents('DCCO')) with check(public.can_manage_unit_documents('DCCO'));
create policy dcco_reports_leadership_delete on public.dcco_reports for delete to authenticated
using(public.can_manage_unit_documents('DCCO'));

-- 7) Remove the dashboard-only weekly hours chart; retain the detailed profile activity view.
-- (The UI change is in components/Dashboard.tsx.)
