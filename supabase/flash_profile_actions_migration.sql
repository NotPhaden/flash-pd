-- Kromix profile, actions, notification and leave-request improvements
-- Apply AFTER schema.sql and all previously supplied Kromix migrations.

-- Department directory: ensure the units shown in the UI exist in the database.
insert into public.departments(name, description) values
 ('Conducere','Coordonare și management instituțional'),
 ('DCCO','Direcția de Combatere a Criminalității Organizate'),
 ('SAS','Serviciul pentru Acțiuni Speciale'),
 ('Instructori','Instructori și certificări')
on conflict(name) do update set description=excluded.description;

-- Leave / permission request types required by the form.
alter table public.absence_requests drop constraint if exists absence_requests_request_type_check;
alter table public.absence_requests add constraint absence_requests_request_type_check
 check (request_type in ('Concediu','Învoire','Învoire ședință','Învoire probleme personale','Alt motiv'));
alter table public.absence_requests alter column cnp drop not null;

-- Reusable activity/action forms and participant accounting.
create table if not exists public.action_templates (
 id uuid primary key default gen_random_uuid(),
 form_type text not null check (form_type in ('Acțiune','Arest preventiv','Avertisment rutier')),
 title text not null,
 description text not null default '',
 fields jsonb not null default '[]'::jsonb,
 created_by uuid references auth.users(id) on delete set null default auth.uid(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.action_forms (
 id uuid primary key default gen_random_uuid(),
 form_type text not null check (form_type in ('Acțiune','Arest preventiv','Avertisment rutier')),
 title text not null,
 description text not null default '',
 location text,
 payload jsonb not null default '{}'::jsonb,
 created_by uuid not null references public.officers(id) on delete cascade,
 status text not null default 'Deschis',
 created_at timestamptz not null default now()
);
create table if not exists public.action_participants (
 id uuid primary key default gen_random_uuid(),
 action_id uuid not null references public.action_forms(id) on delete cascade,
 officer_id uuid not null references public.officers(id) on delete cascade,
 participation_status text not null default 'Participat' check (participation_status in ('Participat','Retras')),
 created_at timestamptz not null default now(),
 unique(action_id, officer_id)
);

create or replace function public.current_officer_rank_level()
returns integer language sql stable security definer set search_path=public as $$
 select coalesce(r.level,0)
 from public.officers o left join public.ranks r on r.id=o.rank_id
 where o.user_id=auth.uid() limit 1;
$$;
create or replace function public.can_create_action(p_type text)
returns boolean language sql stable security definer set search_path=public as $$
 select case
  when p_type in ('Arest preventiv','Avertisment rutier') then exists(select 1 from public.officers where user_id=auth.uid())
  when p_type='Acțiune' then public.current_officer_rank_level() >= 6
  else false end;
$$;
create or replace function public.can_manage_action_templates()
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_role(array['super_admin','commander']);
$$;

alter table public.action_templates enable row level security;
alter table public.action_forms enable row level security;
alter table public.action_participants enable row level security;
drop policy if exists action_templates_read on public.action_templates;
create policy action_templates_read on public.action_templates for select to authenticated using(true);
drop policy if exists action_templates_manage on public.action_templates;
create policy action_templates_manage on public.action_templates for all to authenticated
 using(public.can_manage_action_templates()) with check(public.can_manage_action_templates());
drop policy if exists action_forms_read on public.action_forms;
create policy action_forms_read on public.action_forms for select to authenticated using(true);
drop policy if exists action_forms_create on public.action_forms;
create policy action_forms_create on public.action_forms for insert to authenticated
 with check(public.can_create_action(form_type) and created_by in (select id from public.officers where user_id=auth.uid()));
drop policy if exists action_forms_update on public.action_forms;
create policy action_forms_update on public.action_forms for update to authenticated
 using(created_by in (select id from public.officers where user_id=auth.uid()) or public.has_role(array['super_admin','commander']))
 with check(created_by in (select id from public.officers where user_id=auth.uid()) or public.has_role(array['super_admin','commander']));
drop policy if exists action_participants_read on public.action_participants;
create policy action_participants_read on public.action_participants for select to authenticated using(true);
drop policy if exists action_participants_join on public.action_participants;
create policy action_participants_join on public.action_participants for insert to authenticated
 with check(officer_id in (select id from public.officers where user_id=auth.uid()));
drop policy if exists action_participants_leave on public.action_participants;
create policy action_participants_leave on public.action_participants for delete to authenticated
 using(officer_id in (select id from public.officers where user_id=auth.uid()) or public.has_role(array['super_admin','commander']));

-- Users may read their own notifications; the existing policy is retained.
-- Realtime subscriptions are used by the client when enabled; the client also polls as a fallback.
-- Add notifications and action_forms to supabase_realtime publication in the dashboard if desired.

grant execute on function public.current_officer_rank_level() to authenticated;
grant execute on function public.can_create_action(text) to authenticated;
grant execute on function public.can_manage_action_templates() to authenticated;

-- Subcomisar (rank level 8) and above may edit member contact/RP details;
-- only the two top command roles may change professional rank or department.
drop policy if exists "management write officers" on public.officers;
create policy "management write officers" on public.officers for all to authenticated
 using (public.has_role(array['super_admin','commander','hr']))
 with check (public.has_role(array['super_admin','commander','hr']));
drop policy if exists "subcomisar edit officer details" on public.officers;
create policy "subcomisar edit officer details" on public.officers for update to authenticated
 using (public.current_officer_rank_level() >= 8 or public.has_role(array['super_admin','commander']))
 with check (public.current_officer_rank_level() >= 8 or public.has_role(array['super_admin','commander']));

create or replace function public.protect_officer_assignment_fields()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if (new.rank_id is distinct from old.rank_id or new.department_id is distinct from old.department_id)
   and not public.has_role(array['super_admin','commander']) then
   raise exception 'Doar Chestorul General și Chestorul Secundar pot modifica gradul sau departamentul';
 end if;
 return new;
end;
$$;
drop trigger if exists protect_officer_assignment_fields on public.officers;
create trigger protect_officer_assignment_fields before update on public.officers
 for each row execute function public.protect_officer_assignment_fields();

-- Allow Subcomisar+ to send broadcast notifications; users can still insert only their own otherwise.
drop policy if exists "notifications management insert" on public.notifications;
create policy "notifications management insert" on public.notifications for insert to authenticated
 with check (user_id=auth.uid() or public.has_role(array['super_admin','commander']) or public.current_officer_rank_level() >= 8);

-- Subcomisar+ may review leave requests. Each user continues to see their own requests.
drop policy if exists "absence requests read own or management" on public.absence_requests;
create policy "absence requests read own or management" on public.absence_requests for select to authenticated
 using (officer_id in (select id from public.officers where user_id=auth.uid()) or public.has_role(array['super_admin','commander','hr']) or public.current_officer_rank_level() >= 8);
drop policy if exists "management review absence requests" on public.absence_requests;
create policy "management review absence requests" on public.absence_requests for update to authenticated
 using (public.has_role(array['super_admin','commander','hr']) or public.current_officer_rank_level() >= 8)
 with check (public.has_role(array['super_admin','commander','hr']) or public.current_officer_rank_level() >= 8);

-- Keep the RP character identifier visible as the profile CNP/ID field for existing and new accounts.
update public.officers o
set cnp = r.character_id
from public.rp_accounts r
where r.user_id = o.user_id and (o.cnp is null or btrim(o.cnp) = '');

create or replace function public.provision_flash_rp_account()
returns trigger language plpgsql security definer set search_path=public as $$
declare
 v_character_id text := lower(trim(coalesce(new.raw_user_meta_data->>'character_id','')));
 v_first text := trim(coalesce(new.raw_user_meta_data->>'rp_first_name',''));
 v_last text := trim(coalesce(new.raw_user_meta_data->>'rp_last_name',''));
 v_phone text := trim(coalesce(new.raw_user_meta_data->>'rp_phone',''));
begin
 if v_character_id='' or v_first='' or v_last='' or v_phone='' then
  raise exception 'Kromix RP registration metadata is incomplete';
 end if;
 insert into public.rp_accounts(user_id,character_id,rp_first_name,rp_last_name,rp_phone)
 values(new.id,v_character_id,v_first,v_last,v_phone)
 on conflict(user_id) do update set character_id=excluded.character_id,rp_first_name=excluded.rp_first_name,rp_last_name=excluded.rp_last_name,rp_phone=excluded.rp_phone;
 insert into public.user_roles(user_id,role) values(new.id,'officer') on conflict(user_id) do nothing;
 insert into public.officers(user_id,full_name,badge_number,internal_id,phone,cnp,status,joined_at)
 values(new.id,v_first||' '||v_last,v_character_id,v_character_id,v_phone,v_character_id,'Activ',current_date)
 on conflict(user_id) do update set full_name=excluded.full_name,phone=excluded.phone,cnp=excluded.cnp;
 return new;
end;
$$;

-- Keep the directory department_id in sync with the dedicated unit access roles.
create or replace function public.sync_unit_role_department()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_department_id uuid; v_old_department_id uuid;
begin
 if new.role in ('sas','sas_conducere') then
  select id into v_department_id from public.departments where name='SAS' limit 1;
 elsif new.role in ('dcco','dcco_conducere') then
  select id into v_department_id from public.departments where name='DCCO' limit 1;
 elsif new.role in ('super_admin','commander') then
  select id into v_department_id from public.departments where name='Conducere' limit 1;
 elsif new.role in ('instructor_radio','instructor_mdt','instructor_hs','instructor_heli') then
  select id into v_department_id from public.departments where name='Instructori' limit 1;
 end if;
 if v_department_id is not null then
  update public.officers set department_id=v_department_id where user_id=new.user_id;
 elsif tg_op='UPDATE' and old.role in ('sas','sas_conducere','dcco','dcco_conducere','super_admin','commander','instructor_radio','instructor_mdt','instructor_hs','instructor_heli') then
  select id into v_old_department_id from public.departments where name=case when old.role like 'sas%' then 'SAS' when old.role like 'dcco%' then 'DCCO' when old.role in ('super_admin','commander') then 'Conducere' else 'Instructori' end limit 1;
  update public.officers set department_id=null where user_id=new.user_id and department_id=v_old_department_id;
 end if;
 return new;
end;
$$;
drop trigger if exists sync_unit_role_department on public.user_roles;
create trigger sync_unit_role_department after insert or update of role on public.user_roles
 for each row execute function public.sync_unit_role_department();
-- Backfill existing SAS/DCCO assignments into the real department directory.
update public.officers o set department_id=d.id
from public.user_roles ur join public.departments d on d.name=case when ur.role in ('sas','sas_conducere') then 'SAS' else 'DCCO' end
where ur.user_id=o.user_id and ur.role in ('sas','sas_conducere','dcco','dcco_conducere','super_admin','commander','instructor_radio','instructor_mdt','instructor_hs','instructor_heli');
