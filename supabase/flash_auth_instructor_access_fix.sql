-- Kromix RP: repair signup provisioning and instructor/Academy access.
-- Run once in Supabase SQL Editor after the existing Kromix migrations.
-- Does not delete existing Auth users or personnel records.

-- New registrations are Visitors until management assigns a rank/department.
alter table public.user_roles alter column role set default 'visitor';
alter table public.user_roles drop constraint if exists user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check (role in (
  'visitor','super_admin','commander','hr','officer','dcco','dcco_conducere',
  'sas','sas_conducere','instructor_radio','instructor_mdt','instructor_heli',
  'instructor_moto','instructor_hs'
));

-- A single Auth trigger must provision RP identity + officer profile. A collision
-- with a manually-entered badge/internal ID gets a generated fallback instead of
-- aborting auth.users insertion and returning "Database error saving new user".
create or replace function public.provision_flash_rp_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_character_id text := lower(trim(coalesce(new.raw_user_meta_data->>'character_id','')));
  v_first text := trim(coalesce(new.raw_user_meta_data->>'rp_first_name',''));
  v_last text := trim(coalesce(new.raw_user_meta_data->>'rp_last_name',''));
  v_phone text := trim(coalesce(new.raw_user_meta_data->>'rp_phone',''));
  v_badge text;
  v_internal text;
begin
  if v_character_id = '' or v_first = '' or v_last = '' or v_phone = '' then
    raise exception 'Kromix RP: completează numele, prenumele, ID-ul personajului și telefonul.';
  end if;

  -- character_id remains the unique RP identity; the app now maps it to a
  -- fixed-length SHA-256 synthetic Auth email, so IDs are not capped at 32 chars.
  insert into public.rp_accounts(user_id, character_id, rp_first_name, rp_last_name, rp_phone)
  values(new.id, v_character_id, v_first, v_last, v_phone)
  on conflict(user_id) do update set
    character_id=excluded.character_id,
    rp_first_name=excluded.rp_first_name,
    rp_last_name=excluded.rp_last_name,
    rp_phone=excluded.rp_phone;

  insert into public.user_roles(user_id, role)
  values(new.id, 'visitor')
  on conflict(user_id) do nothing;

  v_badge := v_character_id;
  if exists(select 1 from public.officers o where o.badge_number=v_badge and o.user_id is distinct from new.id) then
    v_badge := 'RP-' || upper(substr(replace(new.id::text,'-',''),1,20));
  end if;
  v_internal := v_character_id;
  if exists(select 1 from public.officers o where o.internal_id=v_internal and o.user_id is distinct from new.id) then
    v_internal := 'RP-' || upper(substr(replace(new.id::text,'-',''),1,20));
  end if;

  insert into public.officers(
    user_id, full_name, badge_number, internal_id, phone, cnp,
    status, joined_at, profile_name
  ) values (
    new.id, concat_ws(' ',v_first,v_last), v_badge, v_internal, v_phone,
    v_character_id, 'Activ', current_date, concat_ws(' ',v_first,v_last)
  )
  on conflict(user_id) do update set
    full_name=excluded.full_name,
    phone=excluded.phone,
    cnp=coalesce(public.officers.cnp, excluded.cnp),
    profile_name=excluded.profile_name;

  return new;
end;
$$;

-- Remove legacy duplicate provisioners; leave exactly one authoritative trigger.
drop trigger if exists on_auth_user_created_officer on auth.users;
drop trigger if exists on_auth_user_created_flash_rp on auth.users;
create trigger on_auth_user_created_flash_rp
after insert on auth.users
for each row execute function public.provision_flash_rp_account();

-- Instructor page permissions are based on department membership, not the old
-- instructor rank labels. FINAL is the existing Moto instructor category.
create or replace function public.has_certificate_instructor(cert text)
returns boolean
language sql stable security definer
set search_path=public
as $$
  select exists (
    select 1 from public.user_roles ur
    where ur.user_id=auth.uid()
      and ur.role=case cert
        when 'Radio' then 'instructor_radio'
        when 'MDT' then 'instructor_mdt'
        when 'Heli' then 'instructor_heli'
        when 'Moto' then 'instructor_moto'
        when 'HS' then 'instructor_hs'
        else '' end
  ) or exists (
    select 1
    from public.officers o
    left join public.departments d on d.id=o.department_id
    left join public.officer_departments od on od.officer_id=o.id
    left join public.departments d2 on d2.id=od.department_id
    where o.user_id=auth.uid()
      and (
        upper(coalesce(d.name,''))=case cert when 'Radio' then 'RADIO' when 'MDT' then 'MDT' when 'Heli' then 'HELI' when 'Moto' then 'FINAL' when 'HS' then 'HS' else '' end
        or upper(coalesce(d2.name,''))=case cert when 'Radio' then 'RADIO' when 'MDT' then 'MDT' when 'Heli' then 'HELI' when 'Moto' then 'FINAL' when 'HS' then 'HS' else '' end
      )
  );
$$;

-- Read access: matching instructor or Comisar+; write access: only the matching
-- instructor category (plus explicit super-admin/commander emergency authority).
alter table public.instructor_forums enable row level security;
drop policy if exists instructor_forums_read on public.instructor_forums;
drop policy if exists instructor_forums_insert on public.instructor_forums;
drop policy if exists instructor_forums_update on public.instructor_forums;
drop policy if exists instructor_forums_delete on public.instructor_forums;
create policy instructor_forums_read on public.instructor_forums
for select to authenticated
using (
  public.current_officer_rank_level() >= 10
  or public.has_role(array['super_admin','commander'])
  or public.has_certificate_instructor(case category
    when 'RADIO' then 'Radio' when 'MDT' then 'MDT'
    when 'FINAL' then 'Moto' when 'HELI' then 'Heli'
    when 'HS' then 'HS' else '' end)
);
create policy instructor_forums_insert on public.instructor_forums
for insert to authenticated
with check (
  created_by=auth.uid() and (
    public.has_role(array['super_admin','commander'])
    or public.has_certificate_instructor(case category
      when 'RADIO' then 'Radio' when 'MDT' then 'MDT'
      when 'FINAL' then 'Moto' when 'HELI' then 'Heli'
      when 'HS' then 'HS' else '' end)
  )
);
create policy instructor_forums_update on public.instructor_forums
for update to authenticated
using (
  public.has_role(array['super_admin','commander'])
  or public.has_certificate_instructor(case category
    when 'RADIO' then 'Radio' when 'MDT' then 'MDT'
    when 'FINAL' then 'Moto' when 'HELI' then 'Heli'
    when 'HS' then 'HS' else '' end)
)
with check (
  public.has_role(array['super_admin','commander'])
  or public.has_certificate_instructor(case category
    when 'RADIO' then 'Radio' when 'MDT' then 'MDT'
    when 'FINAL' then 'Moto' when 'HELI' then 'Heli'
    when 'HS' then 'HS' else '' end)
);
create policy instructor_forums_delete on public.instructor_forums
for delete to authenticated
using (
  public.has_role(array['super_admin','commander'])
  or public.has_certificate_instructor(case category
    when 'RADIO' then 'Radio' when 'MDT' then 'MDT'
    when 'FINAL' then 'Moto' when 'HELI' then 'Heli'
    when 'HS' then 'HS' else '' end)
);
