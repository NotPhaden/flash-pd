-- Kromix: conducerea SAS/DCCO doar ca departament + moderare Policegram.
-- Rulează în Supabase SQL Editor după migrațiile Policegram și profile/departments.

-- 1) Mută încadrarea de conducere din Grade în Departamente, păstrând membrii.
insert into public.departments(name, description) values
 ('Conducere SAS','Conducerea Serviciului pentru Acțiuni Speciale'),
 ('Conducere DCCO','Conducerea Direcției de Combatere a Criminalității Organizate')
on conflict (name) do nothing;

-- Adaugă departamentul de conducere ca încadrare secundară pentru persoanele
-- care încă au unul dintre aceste două grade. Nu suprascrie departamentul principal.
insert into public.officer_departments(officer_id, department_id)
select o.id, d.id
from public.officers o
join public.ranks r on r.id=o.rank_id
join public.departments d on lower(d.name)=lower(case
  when lower(r.name)='conducere sas' then 'Conducere SAS'
  when lower(r.name)='conducere dcco' then 'Conducere DCCO'
end)
where lower(r.name) in ('conducere sas','conducere dcco')
on conflict (officer_id, department_id) do nothing;

-- Elimină gradele speciale din lista de grade după migrarea încadrărilor.
update public.officers set rank_id=null
where rank_id in (select id from public.ranks where lower(name) in ('conducere sas','conducere dcco'));
delete from public.ranks where lower(name) in ('conducere sas','conducere dcco');

-- Departamentele de conducere conferă exact accesul de conducere al unității.
create or replace function public.has_sas_access()
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_role(array['super_admin','commander','sas','sas_conducere'])
 or exists (
   select 1 from public.officers o
   left join public.departments d on d.id=o.department_id
   where o.user_id=auth.uid() and upper(trim(coalesce(d.name,''))) in ('SAS','CONDUCERE SAS')
 )
 or exists (
   select 1 from public.officer_departments od
   join public.departments d on d.id=od.department_id
   join public.officers o on o.id=od.officer_id
   where o.user_id=auth.uid() and upper(trim(d.name)) in ('SAS','CONDUCERE SAS')
 );
$$;

create or replace function public.has_dcco_access()
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_role(array['super_admin','commander','dcco','dcco_conducere'])
 or exists (
   select 1 from public.officers o
   left join public.departments d on d.id=o.department_id
   where o.user_id=auth.uid() and upper(trim(coalesce(d.name,''))) in ('DCCO','CONDUCERE DCCO')
 )
 or exists (
   select 1 from public.officer_departments od
   join public.departments d on d.id=od.department_id
   join public.officers o on o.id=od.officer_id
   where o.user_id=auth.uid() and upper(trim(d.name)) in ('DCCO','CONDUCERE DCCO')
 );
$$;

create or replace function public.can_manage_unit_documents(p_unit text)
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_role(array['super_admin','commander'])
 or (upper(trim(p_unit))='SAS' and (public.has_role(array['sas_conducere']) or exists (
   select 1 from public.officers o
   left join public.departments d on d.id=o.department_id
   where o.user_id=auth.uid() and upper(trim(coalesce(d.name,'')))='CONDUCERE SAS'
   union all
   select 1 from public.officer_departments od join public.departments d on d.id=od.department_id
   join public.officers o on o.id=od.officer_id where o.user_id=auth.uid() and upper(trim(d.name))='CONDUCERE SAS'
 )))
 or (upper(trim(p_unit))='DCCO' and (public.has_role(array['dcco_conducere']) or exists (
   select 1 from public.officers o
   left join public.departments d on d.id=o.department_id
   where o.user_id=auth.uid() and upper(trim(coalesce(d.name,'')))='CONDUCERE DCCO'
   union all
   select 1 from public.officer_departments od join public.departments d on d.id=od.department_id
   join public.officers o on o.id=od.officer_id where o.user_id=auth.uid() and upper(trim(d.name))='CONDUCERE DCCO'
 )));
$$;

grant execute on function public.has_sas_access() to authenticated;
grant execute on function public.has_dcco_access() to authenticated;
grant execute on function public.can_manage_unit_documents(text) to authenticated;

-- 2) Moderatori Policegram: Chestor general (nivel 12) și Chestor secundar (nivel 13).
create or replace function public.is_policegram_moderator()
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_role(array['super_admin','commander'])
   or public.current_officer_rank_level() in (12,13);
$$;
grant execute on function public.is_policegram_moderator() to authenticated;

create table if not exists public.policegram_bans (
 user_id uuid primary key references auth.users(id) on delete cascade,
 banned_by uuid not null references auth.users(id) on delete restrict,
 reason text,
 created_at timestamptz not null default now()
);
alter table public.policegram_bans enable row level security;
drop policy if exists policegram_bans_read_moderators on public.policegram_bans;
drop policy if exists policegram_bans_insert_moderators on public.policegram_bans;
drop policy if exists policegram_bans_delete_moderators on public.policegram_bans;
create policy policegram_bans_read_moderators on public.policegram_bans
 for select to authenticated using (public.is_policegram_moderator());
create policy policegram_bans_insert_moderators on public.policegram_bans
 for insert to authenticated with check (public.is_policegram_moderator() and banned_by=auth.uid());
create policy policegram_bans_update_moderators on public.policegram_bans
 for update to authenticated using (public.is_policegram_moderator())
 with check (public.is_policegram_moderator() and banned_by=auth.uid());
create policy policegram_bans_delete_moderators on public.policegram_bans
 for delete to authenticated using (public.is_policegram_moderator());
grant select,insert,update,delete on public.policegram_bans to authenticated;

-- Interdicția blochează postările noi; moderatorii pot șterge orice postare.
drop policy if exists policegram_posts_insert on public.policegram_posts;
drop policy if exists policegram_posts_delete on public.policegram_posts;
create policy policegram_posts_insert on public.policegram_posts
 for insert to authenticated with check (
   user_id=auth.uid()
   and not exists(select 1 from public.policegram_bans b where b.user_id=auth.uid())
 );
create policy policegram_posts_delete on public.policegram_posts
 for delete to authenticated using (user_id=auth.uid() or public.is_policegram_moderator());

-- Moderatorii pot șterge și comentariile nepotrivite, fără a modifica drepturile de like.
drop policy if exists policegram_comments_delete on public.policegram_comments;
create policy policegram_comments_delete on public.policegram_comments
 for delete to authenticated using (user_id=auth.uid() or public.is_policegram_moderator());

-- Membrii din departamentele de conducere apar în roster-ul unității respective.
create or replace function public.get_unit_members(p_unit text)
returns table(user_id uuid, role text)
language plpgsql stable security definer set search_path=public as $$
declare v_unit text:=upper(trim(p_unit));
begin
 if v_unit='SAS' and not public.has_sas_access() then raise exception 'Acces interzis la lista SAS';
 elsif v_unit='DCCO' and not public.has_dcco_access() then raise exception 'Acces interzis la lista DCCO';
 elsif v_unit not in ('SAS','DCCO') then raise exception 'Unitate invalidă'; end if;
 return query
 select distinct o.user_id,
  case when v_unit='SAS' and (
       upper(trim(coalesce(d.name,'')))='CONDUCERE SAS'
       or exists(select 1 from public.officer_departments od2 join public.departments dx2 on dx2.id=od2.department_id where od2.officer_id=o.id and upper(trim(dx2.name))='CONDUCERE SAS')
       or ur.role='sas_conducere') then 'sas_conducere'
       when v_unit='DCCO' and (
       upper(trim(coalesce(d.name,'')))='CONDUCERE DCCO'
       or exists(select 1 from public.officer_departments od2 join public.departments dx2 on dx2.id=od2.department_id where od2.officer_id=o.id and upper(trim(dx2.name))='CONDUCERE DCCO')
       or ur.role='dcco_conducere') then 'dcco_conducere'
       when v_unit='SAS' then 'sas' else 'dcco' end::text
 from public.officers o
 left join public.departments d on d.id=o.department_id
 left join public.user_roles ur on ur.user_id=o.user_id
 where o.user_id is not null and (
  upper(trim(coalesce(d.name,'')))=v_unit
  or (v_unit='SAS' and upper(trim(coalesce(d.name,'')))='CONDUCERE SAS')
  or (v_unit='DCCO' and upper(trim(coalesce(d.name,'')))='CONDUCERE DCCO')
  or exists(select 1 from public.officer_departments od join public.departments dx on dx.id=od.department_id
            where od.officer_id=o.id and (upper(trim(dx.name))=v_unit or upper(trim(dx.name))=case when v_unit='SAS' then 'CONDUCERE SAS' else 'CONDUCERE DCCO' end))
 );
end;
$$;
grant execute on function public.get_unit_members(text) to authenticated;

create or replace function public.is_policegram_banned()
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.policegram_bans where user_id=auth.uid());
$$;
grant execute on function public.is_policegram_banned() to authenticated;


-- DCCO reports: departamentul Conducere DCCO primește drepturile de conducere.
alter table public.dcco_reports enable row level security;
drop policy if exists dcco_reports_access on public.dcco_reports;
drop policy if exists dcco_reports_member_read on public.dcco_reports;
drop policy if exists dcco_reports_member_insert on public.dcco_reports;
drop policy if exists dcco_reports_leadership_update on public.dcco_reports;
drop policy if exists dcco_reports_leadership_delete on public.dcco_reports;
create policy dcco_reports_member_read on public.dcco_reports for select to authenticated using (public.has_dcco_access());
create policy dcco_reports_member_insert on public.dcco_reports for insert to authenticated with check (public.has_dcco_access() and created_by=auth.uid());
create policy dcco_reports_leadership_update on public.dcco_reports for update to authenticated using (public.can_manage_unit_documents('DCCO')) with check (public.can_manage_unit_documents('DCCO'));
create policy dcco_reports_leadership_delete on public.dcco_reports for delete to authenticated using (public.can_manage_unit_documents('DCCO'));
