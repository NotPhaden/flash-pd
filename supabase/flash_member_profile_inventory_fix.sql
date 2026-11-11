-- Kromix member/profile, multiple departments, inventory and RLS repairs.
-- Run AFTER schema.sql and the existing Kromix migrations.
-- This file deliberately avoids DO blocks and dollar-quoted SQL bodies.

-- Profile appearance fields.
alter table public.officers add column if not exists avatar_url text;
alter table public.officers add column if not exists background_url text;
alter table public.officers add column if not exists call_sign text;
alter table public.officers add column if not exists cnp text;

-- A member can belong to multiple departments. Keep department_id as a legacy primary unit.
create table if not exists public.officer_departments (
  id uuid primary key default gen_random_uuid(),
  officer_id uuid not null references public.officers(id) on delete cascade,
  department_id uuid not null references public.departments(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(officer_id, department_id)
);
insert into public.officer_departments(officer_id,department_id)
select id,department_id from public.officers where department_id is not null
on conflict(officer_id,department_id) do nothing;
insert into public.officer_departments(officer_id,department_id)
select o.id,d.id from public.officers o
join public.user_roles ur on ur.user_id=o.user_id
join public.departments d on d.name=case
  when ur.role in ('sas','sas_conducere') then 'SAS'
  when ur.role in ('dcco','dcco_conducere') then 'DCCO'
  when ur.role in ('super_admin','commander') then 'Conducere'
  when ur.role in ('instructor_radio','instructor_mdt','instructor_hs','instructor_heli') then 'Instructori'
end
where ur.role in ('sas','sas_conducere','dcco','dcco_conducere','super_admin','commander','instructor_radio','instructor_mdt','instructor_hs','instructor_heli')
on conflict(officer_id,department_id) do nothing;

alter table public.officer_departments enable row level security;
drop policy if exists officer_departments_read on public.officer_departments;
create policy officer_departments_read on public.officer_departments for select to authenticated using (true);
drop policy if exists officer_departments_manage on public.officer_departments;
create policy officer_departments_manage on public.officer_departments for all to authenticated
using (public.has_role(array['super_admin','commander']))
with check (public.has_role(array['super_admin','commander']));

-- Allow each user to update only their profile image/background. The rank/department guard trigger remains in force.
drop policy if exists officers_update_own_profile_appearance on public.officers;
create or replace function public.update_own_profile_appearance(p_avatar_url text, p_background_url text)
returns void language sql security definer set search_path=public
as 'update public.officers set avatar_url=p_avatar_url, background_url=p_background_url where user_id=auth.uid()';
grant execute on function public.update_own_profile_appearance(text,text) to authenticated;

-- Sanctions: Subcomisar+ may issue; only Chestor secundar / Chestor general may delete.
drop policy if exists "management write sanctions" on public.sanctions;
drop policy if exists sanctions_leadership_insert on public.sanctions;
create policy sanctions_leadership_insert on public.sanctions for insert to authenticated
with check (
  issued_by in (select id from public.officers where user_id=auth.uid())
  and (public.current_officer_rank_level() >= 8 or public.has_role(array['super_admin','commander']))
);
drop policy if exists sanctions_command_delete on public.sanctions;
create policy sanctions_command_delete on public.sanctions for delete to authenticated
using (public.has_role(array['super_admin','commander']));

-- Radio codes and processing templates: rank-based management, rather than role-only checks.
drop policy if exists "radio management write" on public.radio_codes;
create policy radio_management_write on public.radio_codes for all to authenticated
using (public.current_officer_rank_level() >= 8 or public.has_role(array['super_admin','commander']))
with check (public.current_officer_rank_level() >= 8 or public.has_role(array['super_admin','commander']));
drop policy if exists "templates management write" on public.processing_templates;
create policy templates_management_write on public.processing_templates for all to authenticated
using (public.current_officer_rank_level() >= 8 or public.has_role(array['super_admin','commander']))
with check (public.current_officer_rank_level() >= 8 or public.has_role(array['super_admin','commander']));

-- Inventory and fleet write access. Read access remains available to authenticated personnel.
drop policy if exists "management write equipment" on public.equipment;
create policy equipment_leadership_write on public.equipment for all to authenticated
using (public.current_officer_rank_level() >= 8 or public.has_role(array['super_admin','commander']))
with check (public.current_officer_rank_level() >= 8 or public.has_role(array['super_admin','commander']));
drop policy if exists "management write vehicles" on public.vehicles;
create policy vehicles_leadership_write on public.vehicles for all to authenticated
using (public.current_officer_rank_level() >= 8 or public.has_role(array['super_admin','commander']))
with check (public.current_officer_rank_level() >= 8 or public.has_role(array['super_admin','commander']));

-- Leave requests: applicant insert/read own; Subcomisar+ can review.
drop policy if exists absence_requests_insert_own on public.absence_requests;
create policy absence_requests_insert_own on public.absence_requests for insert to authenticated
with check (officer_id in (select id from public.officers where user_id=auth.uid()));
drop policy if exists "absence requests read own or management" on public.absence_requests;
create policy absence_requests_read_own_or_leadership on public.absence_requests for select to authenticated
using (officer_id in (select id from public.officers where user_id=auth.uid()) or public.current_officer_rank_level() >= 8 or public.has_role(array['super_admin','commander']));
drop policy if exists "management review absence requests" on public.absence_requests;
create policy absence_requests_review_leadership on public.absence_requests for update to authenticated
using (public.current_officer_rank_level() >= 8 or public.has_role(array['super_admin','commander']))
with check (public.current_officer_rank_level() >= 8 or public.has_role(array['super_admin','commander']));

-- Remove self-withdrawal of action participation. Participants remain visible to all authenticated members.
drop policy if exists action_participants_leave on public.action_participants;
drop policy if exists action_participants_join on public.action_participants;
create policy action_participants_join on public.action_participants for insert to authenticated
with check (officer_id in (select id from public.officers where user_id=auth.uid()));

-- Activity log is a leadership audit view; event insertion remains available to authenticated members.
drop policy if exists activities_member_insert on public.activities;
create policy activities_member_insert on public.activities for insert to authenticated
with check (officer_id in (select id from public.officers where user_id=auth.uid()) or public.has_role(array['super_admin','commander']));

-- Notifications: clients also poll periodically, so this migration does not depend on publication DDL.

-- Avatar/background storage bucket and per-user upload isolation.
insert into storage.buckets(id,name,public) values ('avatars','avatars',true) on conflict(id) do update set public=true;
drop policy if exists flash_avatar_read on storage.objects;
create policy flash_avatar_read on storage.objects for select to authenticated using (bucket_id='avatars');
drop policy if exists flash_avatar_insert_own on storage.objects;
create policy flash_avatar_insert_own on storage.objects for insert to authenticated with check (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists flash_avatar_update_own on storage.objects;
create policy flash_avatar_update_own on storage.objects for update to authenticated using (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text) with check (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);

-- Audit journal access for Subcomisar+ and command roles.
drop policy if exists "admins read audit logs" on public.audit_logs;
create policy audit_logs_read_leadership on public.audit_logs for select to authenticated
using (public.current_officer_rank_level() >= 8 or public.has_role(array['super_admin','commander']));

-- Capture key administrative events for the leadership-only audit journal.
create or replace function public.write_flash_audit_log()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_row jsonb;
  v_id uuid;
begin
  if tg_op='DELETE' then
    v_row := to_jsonb(old);
  else
    v_row := to_jsonb(new);
  end if;
  v_id := nullif(v_row->>'id','')::uuid;
  insert into public.audit_logs(actor_id,action,entity,entity_id,details)
  values(auth.uid(),tg_op,tg_table_name,v_id,jsonb_build_object('record_id',v_id));
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists flash_audit_officers on public.officers;
create trigger flash_audit_officers after insert or update or delete on public.officers for each row execute function public.write_flash_audit_log();
drop trigger if exists flash_audit_sanctions on public.sanctions;
create trigger flash_audit_sanctions after insert or update or delete on public.sanctions for each row execute function public.write_flash_audit_log();
drop trigger if exists flash_audit_equipment on public.equipment;
create trigger flash_audit_equipment after insert or update or delete on public.equipment for each row execute function public.write_flash_audit_log();
drop trigger if exists flash_audit_vehicles on public.vehicles;
create trigger flash_audit_vehicles after insert or update or delete on public.vehicles for each row execute function public.write_flash_audit_log();
drop trigger if exists flash_audit_action_forms on public.action_forms;
create trigger flash_audit_action_forms after insert or update or delete on public.action_forms for each row execute function public.write_flash_audit_log();
drop trigger if exists flash_audit_absence_requests on public.absence_requests;
create trigger flash_audit_absence_requests after insert or update or delete on public.absence_requests for each row execute function public.write_flash_audit_log();
drop trigger if exists flash_audit_radio_codes on public.radio_codes;
create trigger flash_audit_radio_codes after insert or update or delete on public.radio_codes for each row execute function public.write_flash_audit_log();
drop trigger if exists flash_audit_processing_templates on public.processing_templates;
create trigger flash_audit_processing_templates after insert or update or delete on public.processing_templates for each row execute function public.write_flash_audit_log();
