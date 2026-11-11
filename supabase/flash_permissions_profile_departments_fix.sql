-- Kromix: corectare acces pe baza gradului/departamentului + departamente de conducere
-- Rulează după migrările Kromix anterioare. Nu șterge date.

-- Departamente folosite de interfață. Numele sunt păstrate consecvent.
insert into public.departments(name, description) values
 ('DCCO','Direcția de Combatere a Criminalității Organizate'),
 ('SAS','Serviciul pentru Acțiuni Speciale'),
 ('INSTRUCTORI','Structură de instructori'),
 ('RADIO','Instructori Radio'),
 ('MDT','Instructori MDT'),
 ('FINAL','Instructori Final'),
 ('HELI','Instructori Heli'),
 ('HS','Instructori HS'),
 ('Conducere DCCO','Conducerea DCCO'),
 ('Conducere SAS','Conducerea SAS')
on conflict(name) do nothing;

-- Asigură gradele de conducere în ierarhie, fără a suprascrie nivelurile existente.
do $$
declare v integer;
begin
 if not exists(select 1 from public.ranks where lower(name)='conducere dcco') then
   select coalesce(max(level),0)+1 into v from public.ranks;
   insert into public.ranks(name,level,category) values('Conducere DCCO',v,'Conducere');
 end if;
 if not exists(select 1 from public.ranks where lower(name)='conducere sas') then
   select coalesce(max(level),0)+1 into v from public.ranks;
   insert into public.ranks(name,level,category) values('Conducere SAS',v,'Conducere');
 end if;
end $$;

-- Rolurile de conducere sunt recunoscute fie din user_roles, fie din gradul atribuit.
create or replace function public.has_dcco_access()
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_role(array['super_admin','commander','dcco','dcco_conducere']) or exists(
  select 1 from public.officers o left join public.departments d on d.id=o.department_id left join public.ranks r on r.id=o.rank_id
  where o.user_id=auth.uid() and (upper(coalesce(d.name,''))='DCCO' or r.name='Conducere DCCO')
 ) or exists(
  select 1 from public.officer_departments od join public.departments d on d.id=od.department_id join public.officers o on o.id=od.officer_id
  where o.user_id=auth.uid() and upper(d.name)='DCCO'
 );
$$;
create or replace function public.has_sas_access()
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_role(array['super_admin','commander','sas','sas_conducere']) or exists(
  select 1 from public.officers o left join public.departments d on d.id=o.department_id left join public.ranks r on r.id=o.rank_id
  where o.user_id=auth.uid() and (upper(coalesce(d.name,''))='SAS' or r.name='Conducere SAS')
 ) or exists(
  select 1 from public.officer_departments od join public.departments d on d.id=od.department_id join public.officers o on o.id=od.officer_id
  where o.user_id=auth.uid() and upper(d.name)='SAS'
 );
$$;

create or replace function public.can_manage_unit_documents(p_unit text)
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_role(array['super_admin','commander']) or
  (upper(p_unit)='DCCO' and (public.has_role(array['dcco_conducere']) or exists(
    select 1 from public.officers o join public.ranks r on r.id=o.rank_id where o.user_id=auth.uid() and r.name='Conducere DCCO'))) or
  (upper(p_unit)='SAS' and (public.has_role(array['sas_conducere']) or exists(
    select 1 from public.officers o join public.ranks r on r.id=o.rank_id where o.user_id=auth.uid() and r.name='Conducere SAS')));
$$;

-- Instructorii pot gestiona exclusiv categoria departamentului lor, chiar dacă rolul user_roles nu a fost setat.
create or replace function public.has_certificate_instructor(cert text)
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_role(array['super_admin','commander']) or exists(
  select 1 from public.user_roles ur where ur.user_id=auth.uid() and ur.role=case cert
   when 'Radio' then 'instructor_radio' when 'MDT' then 'instructor_mdt' when 'Heli' then 'instructor_heli'
   when 'Moto' then 'instructor_moto' when 'HS' then 'instructor_hs' else '' end
 ) or exists(
  select 1 from public.officers o join public.ranks r on r.id=o.rank_id
  where o.user_id=auth.uid() and r.name=case cert when 'Radio' then 'Instructor Radio' when 'MDT' then 'Instructor MDT'
   when 'Heli' then 'Instructor Heli' when 'Moto' then 'Instructor Moto' when 'HS' then 'Instructor HS' else '' end
 ) or exists(
  select 1 from public.officers o left join public.departments d on d.id=o.department_id
  where o.user_id=auth.uid() and upper(coalesce(d.name,''))=case cert
   when 'Radio' then 'RADIO' when 'MDT' then 'MDT' when 'Heli' then 'HELI' when 'Moto' then 'FINAL' when 'HS' then 'HS' else '' end
 ) or exists(
  select 1 from public.officer_departments od join public.departments d on d.id=od.department_id join public.officers o on o.id=od.officer_id
  where o.user_id=auth.uid() and upper(d.name)=case cert
   when 'Radio' then 'RADIO' when 'MDT' then 'MDT' when 'Heli' then 'HELI' when 'Moto' then 'FINAL' when 'HS' then 'HS' else '' end
 );
$$;

-- Instructor forums: vizualizare doar pentru categoria proprie, conducere (Comisar+) și superuseri.
alter table public.instructor_forums enable row level security;
drop policy if exists instructor_forums_read on public.instructor_forums;
drop policy if exists instructor_forums_insert on public.instructor_forums;
drop policy if exists instructor_forums_update on public.instructor_forums;
drop policy if exists instructor_forums_delete on public.instructor_forums;
create policy instructor_forums_read on public.instructor_forums for select to authenticated
using (public.current_officer_rank_level()>=10 or public.has_role(array['super_admin','commander']) or public.has_certificate_instructor(case category when 'RADIO' then 'Radio' when 'MDT' then 'MDT' when 'HELI' then 'Heli' when 'FINAL' then 'Moto' when 'HS' then 'HS' else '' end));
create policy instructor_forums_insert on public.instructor_forums for insert to authenticated
with check (created_by=auth.uid() and (public.has_role(array['super_admin','commander']) or public.has_certificate_instructor(case category when 'RADIO' then 'Radio' when 'MDT' then 'MDT' when 'HELI' then 'Heli' when 'FINAL' then 'Moto' when 'HS' then 'HS' else '' end)));
create policy instructor_forums_update on public.instructor_forums for update to authenticated
using (public.has_role(array['super_admin','commander']) or public.has_certificate_instructor(case category when 'RADIO' then 'Radio' when 'MDT' then 'MDT' when 'HELI' then 'Heli' when 'FINAL' then 'Moto' when 'HS' then 'HS' else '' end))
with check (public.has_role(array['super_admin','commander']) or public.has_certificate_instructor(case category when 'RADIO' then 'Radio' when 'MDT' then 'MDT' when 'HELI' then 'Heli' when 'FINAL' then 'Moto' when 'HS' then 'HS' else '' end));
create policy instructor_forums_delete on public.instructor_forums for delete to authenticated
using (public.has_role(array['super_admin','commander']) or public.has_certificate_instructor(case category when 'RADIO' then 'Radio' when 'MDT' then 'MDT' when 'HELI' then 'Heli' when 'FINAL' then 'Moto' when 'HS' then 'HS' else '' end));

-- Extinde tipurile de documente SAS/DCCO.
alter table public.unit_documents drop constraint if exists unit_documents_type_check;
alter table public.unit_documents add constraint unit_documents_type_check check (
 (unit_key='SAS' and doc_type in ('Regulament SAS','Instructaj SAS','Tactici jaf')) or
 (unit_key='DCCO' and doc_type in ('Regulament DCCO','Instructaj DCCO','Filaj','Raport organizație'))
);

-- Listează și membrii identificați prin departament/grad, nu doar prin user_roles.
create or replace function public.get_unit_members(p_unit text)
returns table(user_id uuid, role text)
language plpgsql stable security definer set search_path=public as $$
declare v_unit text:=upper(p_unit);
begin
 if v_unit='SAS' and not public.has_sas_access() then raise exception 'Acces interzis la lista SAS';
 elsif v_unit='DCCO' and not public.has_dcco_access() then raise exception 'Acces interzis la lista DCCO';
 elsif v_unit not in ('SAS','DCCO') then raise exception 'Unitate invalidă'; end if;
 return query
 select distinct o.user_id,
  case when r.name='Conducere SAS' then 'sas_conducere' when r.name='Conducere DCCO' then 'dcco_conducere'
       when ur.role in ('sas','sas_conducere','dcco','dcco_conducere') then ur.role
       when v_unit='SAS' then 'sas' else 'dcco' end::text
 from public.officers o
 left join public.departments d on d.id=o.department_id
 left join public.ranks r on r.id=o.rank_id
 left join public.user_roles ur on ur.user_id=o.user_id
 where o.user_id is not null and (
   (v_unit='SAS' and (upper(coalesce(d.name,''))='SAS' or r.name='Conducere SAS' or exists(
      select 1 from public.officer_departments od join public.departments dx on dx.id=od.department_id
      where od.officer_id=o.id and upper(dx.name)='SAS')))
   or
   (v_unit='DCCO' and (upper(coalesce(d.name,''))='DCCO' or r.name='Conducere DCCO' or exists(
      select 1 from public.officer_departments od join public.departments dx on dx.id=od.department_id
      where od.officer_id=o.id and upper(dx.name)='DCCO')))
 );
end; $$;
grant execute on function public.get_unit_members(text) to authenticated;
