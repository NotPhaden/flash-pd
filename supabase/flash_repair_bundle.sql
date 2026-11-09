-- FLASH RP: core repairs for career actions, instructor departments,
-- certificate authorization and instructor case boards.
-- Run after the existing FLASH migrations. Review against production first.

-- 1) UP/DOWN: lock only the officers row, never the nullable side of a LEFT JOIN.
create or replace function public.manage_officer_career(
  p_officer_id uuid,
  p_joined_at date default null,
  p_rank_id uuid default null,
  p_change text default null
) returns void
language plpgsql security definer set search_path=public as $$
declare
  old_id uuid; new_id uuid; old_name text; new_name text;
  old_level integer; target record;
begin
  if auth.uid() is null then raise exception 'Autentificare necesară'; end if;
  if not (public.current_officer_rank_level() between 12 and 13
      or public.has_role(array['super_admin','commander'])) then
    raise exception 'UP/DOWN și editarea carierei sunt disponibile doar de la Chestor secundar';
  end if;

  select o.rank_id into old_id
  from public.officers o where o.id=p_officer_id for update;
  if not found then raise exception 'Membrul nu există'; end if;

  select r.name,r.level into old_name,old_level
  from public.ranks r where r.id=old_id;
  new_id:=old_id;

  if lower(coalesce(p_change,''))='up' then
    select r.id,r.name,r.level into target
    from public.ranks r
    where r.level>coalesce(old_level,-999999)
      and r.name not ilike 'Instructor%'
      and r.name not ilike 'Conducere DCCO%'
      and r.name not ilike 'Conducere SAS%'
    order by r.level asc limit 1;
    if target.id is null then raise exception 'Nu există un grad superior disponibil'; end if;
    new_id:=target.id;
  elsif lower(coalesce(p_change,''))='down' then
    select r.id,r.name,r.level into target
    from public.ranks r
    where r.level<coalesce(old_level,999999)
      and r.name not ilike 'Instructor%'
      and r.name not ilike 'Conducere DCCO%'
      and r.name not ilike 'Conducere SAS%'
    order by r.level desc limit 1;
    if target.id is null then raise exception 'Nu există un grad inferior disponibil'; end if;
    new_id:=target.id;
  elsif p_rank_id is not null then
    new_id:=p_rank_id;
  end if;

  select r.name into new_name from public.ranks r where r.id=new_id;
  update public.officers
  set joined_at=coalesce(p_joined_at,joined_at),rank_id=new_id,updated_at=now()
  where id=p_officer_id;

  if new_id is distinct from old_id then
    insert into public.officer_promotions(
      officer_id,change_type,old_rank_id,new_rank_id,old_rank_name,new_rank_name,changed_by
    ) values (
      p_officer_id,
      case when p_change is null then 'EDITARE' when lower(p_change)='up' then 'UP' else 'DOWN' end,
      old_id,new_id,old_name,new_name,auth.uid()
    );
  end if;
end; $$;
grant execute on function public.manage_officer_career(uuid,date,uuid,text) to authenticated;

-- 2) Instructorii sunt departamente, nu grade. Rolurile istorice sunt păstrate
-- temporar ca identificatori de autorizare pentru a nu bloca conturile existente.
insert into public.departments(name,description) values
 ('RADIO','Instructori și evaluări pentru certificatul Radio'),
 ('MDT','Instructori și evaluări pentru certificatul MDT'),
 ('FINAL','Instructori și evaluări finale'),
 ('HELI','Instructori și evaluări pentru certificatul Heli'),
 ('HS','Instructori și evaluări pentru certificatul HS')
on conflict(name) do nothing;

-- Mută membrii cu rol de instructor în departamentul aferent.
insert into public.officer_departments(officer_id,department_id)
select o.id,d.id
from public.officers o
join public.user_roles ur on ur.user_id=o.user_id
join public.departments d on d.name=case ur.role
  when 'instructor_radio' then 'RADIO'
  when 'instructor_mdt' then 'MDT'
  when 'instructor_heli' then 'HELI'
  when 'instructor_moto' then 'FINAL'
  when 'instructor_hs' then 'HS'
end
where ur.role in ('instructor_radio','instructor_mdt','instructor_heli','instructor_moto','instructor_hs')
on conflict(officer_id,department_id) do nothing;

-- Reassign any personnel still carrying the old instructor ranks to Agent,
-- then remove those rank rows only when no officer references them.
update public.officers o set rank_id=(select id from public.ranks where lower(name)='agent' limit 1)
where o.rank_id in (select id from public.ranks where lower(name) in
 ('instructor radio','instructor mdt','instructor heli','instructor moto','instructor hs'));
delete from public.ranks r
where lower(r.name) in ('instructor radio','instructor mdt','instructor heli','instructor moto','instructor hs')
  and not exists(select 1 from public.officers o where o.rank_id=r.id);

-- Certificate instructor checks support both the old role and the new department.
create or replace function public.has_certificate_instructor(cert text)
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_role(array['super_admin','commander'])
 or exists (
   select 1 from public.user_roles ur where ur.user_id=auth.uid()
   and ur.role=case cert when 'Radio' then 'instructor_radio'
     when 'MDT' then 'instructor_mdt' when 'Heli' then 'instructor_heli'
     when 'Moto' then 'instructor_moto' when 'HS' then 'instructor_hs' else '' end
 )
 or exists (
   select 1 from public.officers o
   join public.officer_departments od on od.officer_id=o.id
   join public.departments d on d.id=od.department_id
   where o.user_id=auth.uid() and upper(d.name)=case cert
     when 'Radio' then 'RADIO' when 'MDT' then 'MDT'
     when 'Heli' then 'HELI' when 'Moto' then 'FINAL'
     when 'HS' then 'HS' else '' end
 )
 or exists (
   select 1 from public.officers o
   join public.departments d on d.id=o.department_id
   where o.user_id=auth.uid() and upper(d.name)=case cert
     when 'Radio' then 'RADIO' when 'MDT' then 'MDT'
     when 'Heli' then 'HELI' when 'Moto' then 'FINAL'
     when 'HS' then 'HS' else '' end
 );
$$;

-- Replace broad certificate policies with category-aware checks.
drop policy if exists cert_apps_read on public.certificate_applications;
drop policy if exists cert_apps_review on public.certificate_applications;
drop policy if exists certificate_apps_delete_own_or_instructor on public.certificate_applications;
drop policy if exists "certificate apps read own or instructor management" on public.certificate_applications;
drop policy if exists "instructors review certificate apps" on public.certificate_applications;
create policy cert_apps_read on public.certificate_applications for select to authenticated
using (user_id=auth.uid() or public.has_certificate_instructor(certificate)
  or public.has_role(array['super_admin','commander']));
create policy cert_apps_review on public.certificate_applications for update to authenticated
using (public.has_certificate_instructor(certificate))
with check (public.has_certificate_instructor(certificate));
create policy certificate_apps_delete_own_or_instructor on public.certificate_applications for delete to authenticated
using (public.has_certificate_instructor(certificate));

-- 3) Instructor forum/candidate records. Each instructor sees their own category;
-- Comisar+ can read all categories; only matching instructors can create/manage.
create table if not exists public.instructor_forums (
 id uuid primary key default gen_random_uuid(),
 category text not null check(category in ('RADIO','MDT','FINAL','HELI','HS')),
 candidate_name text not null,
 candidate_cnp text,
 decision text not null default 'În așteptare' check(decision in ('În așteptare','Aprobat','Respins')),
 evidence_url text,
 created_by uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.instructor_forums enable row level security;
drop policy if exists instructor_forums_read on public.instructor_forums;
drop policy if exists instructor_forums_insert on public.instructor_forums;
drop policy if exists instructor_forums_update on public.instructor_forums;
drop policy if exists instructor_forums_delete on public.instructor_forums;
create policy instructor_forums_read on public.instructor_forums for select to authenticated
using (
 public.current_officer_rank_level()>=10
 or public.has_role(array['super_admin','commander'])
 or public.has_certificate_instructor(case category when 'RADIO' then 'Radio' when 'MDT' then 'MDT' when 'FINAL' then 'Moto' when 'HELI' then 'Heli' when 'HS' then 'HS' else '' end)
);
create policy instructor_forums_insert on public.instructor_forums for insert to authenticated
with check (
 created_by=auth.uid() and public.has_certificate_instructor(case category
  when 'RADIO' then 'Radio' when 'MDT' then 'MDT' when 'FINAL' then 'Moto'
  when 'HELI' then 'Heli' when 'HS' then 'HS' else '' end)
);
create policy instructor_forums_update on public.instructor_forums for update to authenticated
using (public.has_certificate_instructor(case category when 'RADIO' then 'Radio' when 'MDT' then 'MDT' when 'FINAL' then 'Moto' when 'HELI' then 'Heli' when 'HS' then 'HS' else '' end))
with check (public.has_certificate_instructor(case category when 'RADIO' then 'Radio' when 'MDT' then 'MDT' when 'FINAL' then 'Moto' when 'HELI' then 'Heli' when 'HS' then 'HS' else '' end));
create policy instructor_forums_delete on public.instructor_forums for delete to authenticated
using (public.has_certificate_instructor(case category when 'RADIO' then 'Radio' when 'MDT' then 'MDT' when 'FINAL' then 'Moto' when 'HELI' then 'Heli' when 'HS' then 'HS' else '' end));

-- 4) Ensure the department page does not retain the legacy retired names.
delete from public.officer_departments od using public.departments d
where od.department_id=d.id and lower(trim(d.name)) in
 ('investigații','investigatii','investigații criminale','investigatii criminale');
delete from public.departments d where lower(trim(d.name)) in
 ('investigații','investigatii','investigații criminale','investigatii criminale');

-- Remove the obsolete department labels explicitly requested for cleanup.
delete from public.officer_departments od using public.departments d
where od.department_id=d.id and lower(trim(d.name)) in
 ('instructori','patrulare');
update public.officers o set department_id=null
where o.department_id in (select d.id from public.departments d
  where lower(trim(d.name)) in ('instructori','patrulare'));
delete from public.departments d
where lower(trim(d.name)) in ('instructori','patrulare');

-- Ensure the retained operational departments exist.
insert into public.departments(name,description) values
 ('DCCO','Direcția de Combatere a Criminalității Organizate'),
 ('SAS','Serviciul pentru Acțiuni Speciale'),
 ('Academie','Formare și pregătire profesională')
on conflict(name) do nothing;
