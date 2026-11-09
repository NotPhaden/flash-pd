-- FLASH verified permission and profile repair.
-- Run AFTER flash_final_permissions_departments_profile.sql.
-- This migration intentionally contains no DO blocks or publication changes.

-- Keep one rank/permission rule for all top-command operations.
create or replace function public.protect_officer_assignment_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $flash$
begin
  if (new.rank_id is distinct from old.rank_id
      or new.department_id is distinct from old.department_id)
     and not public.is_flash_top_command() then
    raise exception 'Doar Chestorul general sau Chestorul secundar poate modifica gradul ori departamentul';
  end if;
  return new;
end;
$flash$;

drop trigger if exists protect_officer_assignment_fields on public.officers;
create trigger protect_officer_assignment_fields
before update on public.officers
for each row execute function public.protect_officer_assignment_fields();

-- Every authenticated officer can read department memberships; only top command can change them.
alter table public.officer_departments enable row level security;
drop policy if exists officer_departments_read on public.officer_departments;
create policy officer_departments_read
on public.officer_departments for select to authenticated
using (true);
drop policy if exists officer_departments_top_command on public.officer_departments;
drop policy if exists officer_departments_manage on public.officer_departments;
create policy officer_departments_top_command
on public.officer_departments for all to authenticated
using (public.is_flash_top_command())
with check (public.is_flash_top_command());

-- Atomic member edit: profile details for Subcomisar+, rank and multiple departments only for top command.
create or replace function public.update_officer_record(
  p_officer_id uuid,
  p_full_name text,
  p_cnp text,
  p_call_sign text,
  p_badge_number text,
  p_status text,
  p_update_assignments boolean,
  p_rank_id uuid,
  p_department_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $flash$
declare
  v_department_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Autentificare necesară';
  end if;
  if not public.is_flash_leadership() then
    raise exception 'Editarea personalului este disponibilă de la gradul Subcomisar';
  end if;
  if nullif(btrim(coalesce(p_full_name, '')), '') is null then
    raise exception 'Numele complet este obligatoriu';
  end if;
  if p_status not in ('Activ','În serviciu','Liber','Suspendat','Inactiv') then
    raise exception 'Status invalid';
  end if;
  if p_update_assignments and not public.is_flash_top_command() then
    raise exception 'Doar Chestorul general și Chestorul secundar pot modifica gradul și departamentele';
  end if;

  update public.officers
  set full_name = btrim(p_full_name),
      cnp = nullif(btrim(coalesce(p_cnp, '')), ''),
      call_sign = nullif(btrim(coalesce(p_call_sign, '')), ''),
      badge_number = nullif(btrim(coalesce(p_badge_number, '')), ''),
      status = p_status,
      rank_id = case when p_update_assignments then p_rank_id else rank_id end,
      department_id = case
        when p_update_assignments then (coalesce(p_department_ids, '{}'::uuid[]))[1]
        else department_id
      end,
      updated_at = now()
  where id = p_officer_id;

  if not found then
    raise exception 'Membrul selectat nu există';
  end if;

  if p_update_assignments then
    delete from public.officer_departments where officer_id = p_officer_id;
    foreach v_department_id in array coalesce(p_department_ids, '{}'::uuid[]) loop
      if v_department_id is not null then
        insert into public.officer_departments(officer_id, department_id)
        values (p_officer_id, v_department_id)
        on conflict (officer_id, department_id) do nothing;
      end if;
    end loop;
  end if;
end;
$flash$;
grant execute on function public.update_officer_record(uuid,text,text,text,text,text,boolean,uuid,uuid[]) to authenticated;

-- Deletion and publishing permissions use the same rank-aware helpers as the UI.
drop policy if exists sanctions_command_delete on public.sanctions;
create policy sanctions_command_delete
on public.sanctions for delete to authenticated
using (public.is_flash_top_command());

drop policy if exists radio_codes_delete_leadership on public.radio_codes;
create policy radio_codes_delete_leadership
on public.radio_codes for delete to authenticated
using (public.is_flash_leadership());
drop policy if exists processing_templates_delete_leadership on public.processing_templates;
create policy processing_templates_delete_leadership
on public.processing_templates for delete to authenticated
using (public.is_flash_leadership());
drop policy if exists vehicles_delete_leadership on public.vehicles;
create policy vehicles_delete_leadership
on public.vehicles for delete to authenticated
using (public.is_flash_leadership());
drop policy if exists equipment_delete_leadership on public.equipment;
create policy equipment_delete_leadership
on public.equipment for delete to authenticated
using (public.is_flash_leadership());
drop policy if exists action_forms_delete_leadership on public.action_forms;
create policy action_forms_delete_leadership
on public.action_forms for delete to authenticated
using (public.is_flash_leadership());
drop policy if exists academy_applications_delete_top_command on public.academy_applications;
create policy academy_applications_delete_top_command
on public.academy_applications for delete to authenticated
using (public.is_flash_top_command());

-- Chestor general / Chestor secundar may publish shared action templates even if their user_roles row is officer.
create or replace function public.can_manage_action_templates()
returns boolean
language sql
stable
security definer
set search_path = public
as $flash$
  select public.is_flash_top_command();
$flash$;
grant execute on function public.can_manage_action_templates() to authenticated;

-- Users may delete only their own notifications, regardless of rank.
drop policy if exists notifications_delete_own on public.notifications;
create policy notifications_delete_own
on public.notifications for delete to authenticated
using (user_id = auth.uid());

-- Profile appearance: user-scoped uploads, public image reads, and a server-side profile update.
insert into storage.buckets(id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;
drop policy if exists flash_avatar_public_read on storage.objects;
create policy flash_avatar_public_read
on storage.objects for select to anon, authenticated
using (bucket_id = 'avatars');
drop policy if exists flash_avatar_insert_own on storage.objects;
create policy flash_avatar_insert_own
on storage.objects for insert to authenticated
with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists flash_avatar_update_own on storage.objects;
create policy flash_avatar_update_own
on storage.objects for update to authenticated
using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create or replace function public.update_own_profile_appearance(
  p_avatar_url text,
  p_background_url text
)
returns void
language plpgsql
security definer
set search_path = public
as $flash$
begin
  if auth.uid() is null then
    raise exception 'Autentificare necesară';
  end if;
  update public.officers
  set avatar_url = p_avatar_url,
      background_url = p_background_url,
      updated_at = now()
  where user_id = auth.uid();
  if not found then
    raise exception 'Nu există un profil de personal asociat contului';
  end if;
end;
$flash$;
grant execute on function public.update_own_profile_appearance(text,text) to authenticated;

-- Only the two requested absence types remain available.
alter table public.absence_requests
  drop constraint if exists absence_requests_request_type_check;
alter table public.absence_requests
  add constraint absence_requests_request_type_check
  check (request_type in ('Concediu', 'Învoire ședință'));
