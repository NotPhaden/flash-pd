-- Kromix functional fixes — run AFTER schema.sql, rp_accounts_migration.sql and flash_corrective_migration.sql.
-- This migration is idempotent. It does not delete user accounts or personal records.

-- Rank-based authority: Subcomisar (level 8) and above.
create or replace function public.has_rank_level(min_level integer)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.officers o
    join public.ranks r on r.id = o.rank_id
    where o.user_id = auth.uid() and r.level >= min_level
  );
$$;

-- Attendance: close old duplicate open shifts safely, then prevent new duplicates.
create or replace function public.set_attendance_hours()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.shift_end is not null then
    if new.shift_end < new.shift_start then
      raise exception 'Sfârșitul turei nu poate fi înainte de început.';
    end if;
    new.hours := round((extract(epoch from (new.shift_end - new.shift_start)) / 3600.0)::numeric, 2);
  else
    new.hours := null;
  end if;
  return new;
end;
$$;
drop trigger if exists attendance_calculate_hours on public.attendance;
create trigger attendance_calculate_hours
before insert or update of shift_start, shift_end on public.attendance
for each row execute function public.set_attendance_hours();

with duplicates as (
  select id, row_number() over (partition by officer_id order by shift_start desc, created_at desc) as rn
  from public.attendance where shift_end is null
)
update public.attendance a
set shift_end = greatest(now(), a.shift_start)
from duplicates d
where a.id = d.id and d.rn > 1;

create unique index if not exists attendance_one_open_shift_per_officer
on public.attendance(officer_id) where shift_end is null;

-- Attendance permissions: members may start/stop only their own shift; Subcomisar+ may manage all.
drop policy if exists "management write attendance" on public.attendance;
drop policy if exists "attendance own or leadership insert" on public.attendance;
drop policy if exists "attendance own or leadership update" on public.attendance;
create policy "attendance own or leadership insert" on public.attendance
for insert to authenticated
with check (
  officer_id in (select id from public.officers where user_id = auth.uid())
  or public.has_rank_level(8)
  or public.has_role(array['super_admin','commander'])
);
create policy "attendance own or leadership update" on public.attendance
for update to authenticated
using (
  officer_id in (select id from public.officers where user_id = auth.uid())
  or public.has_rank_level(8)
  or public.has_role(array['super_admin','commander'])
)
with check (
  officer_id in (select id from public.officers where user_id = auth.uid())
  or public.has_rank_level(8)
  or public.has_role(array['super_admin','commander'])
);

-- Sanctions use issued_at, not the nonexistent created_at column. Read access remains authenticated.
-- Academy applications: applicants only see their own; Subcomisar+ and HR can review all.
drop policy if exists "academy applicant or leadership read" on public.academy_applications;
drop policy if exists "academy leadership review" on public.academy_applications;
create policy "academy applicant or leadership read" on public.academy_applications
for select to authenticated
using (user_id = auth.uid() or public.has_rank_level(8) or public.has_role(array['super_admin','commander']));
create policy "academy leadership review" on public.academy_applications
for update to authenticated
using (public.has_rank_level(8) or public.has_role(array['super_admin','commander']))
with check (public.has_rank_level(8) or public.has_role(array['super_admin','commander']));

-- Leave requests: personal submission, review from Subcomisar+.
alter table public.absence_requests drop constraint if exists absence_requests_request_type_check;
alter table public.absence_requests add constraint absence_requests_request_type_check
  check (request_type in ('Concediu','Învoire ședință','Învoire'));
drop policy if exists "absence requests read own or management" on public.absence_requests;
drop policy if exists "management review absence requests" on public.absence_requests;
create policy "absence requests read own or management" on public.absence_requests
for select to authenticated
using (
  officer_id in (select id from public.officers where user_id = auth.uid())
  or public.has_rank_level(8)
  or public.has_role(array['super_admin','commander'])
);
create policy "management review absence requests" on public.absence_requests
for update to authenticated
using (public.has_rank_level(8) or public.has_role(array['super_admin','commander']))
with check (public.has_rank_level(8) or public.has_role(array['super_admin','commander']));

-- Broadcast notifications can be sent only by Subcomisar+ or explicit management roles.
drop policy if exists "notifications management insert" on public.notifications;
create policy "notifications management insert" on public.notifications
for insert to authenticated
with check (
  user_id = auth.uid()
  or public.has_rank_level(8)
  or public.has_role(array['super_admin','commander'])
);

-- Keep DCCO isolated from non-DCCO users. Membership/leadership must be explicit in user_roles.
alter table public.dcco_reports enable row level security;
drop policy if exists dcco_reports_access on public.dcco_reports;
create policy dcco_reports_access on public.dcco_reports
for all to authenticated
using (public.has_role(array['super_admin','commander','dcco','dcco_conducere']))
with check (public.has_role(array['super_admin','commander','dcco','dcco_conducere']));

-- Ensure the new request module has RLS enabled.
alter table public.absence_requests enable row level security;
