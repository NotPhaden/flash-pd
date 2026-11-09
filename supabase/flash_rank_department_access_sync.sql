-- FLASH permission correction: assigned rank + instructor departments are authoritative.
-- Run once in Supabase SQL Editor AFTER the existing FLASH migrations.

-- Resolve instructor authorization from either the legacy role OR actual department membership.
create or replace function public.has_certificate_instructor(cert text)
returns boolean
language sql stable security definer set search_path=public
as $$
  select public.has_role(array['super_admin','commander'])
  or exists (
    select 1
    from public.user_roles ur
    where ur.user_id=auth.uid()
      and ur.role=case upper(trim(cert))
        when 'RADIO' then 'instructor_radio'
        when 'MDT' then 'instructor_mdt'
        when 'HELI' then 'instructor_heli'
        when 'MOTO' then 'instructor_moto'
        when 'FINAL' then 'instructor_moto'
        when 'HS' then 'instructor_hs'
        else '' end
  )
  or exists (
    select 1
    from public.officers o
    left join public.departments d on d.id=o.department_id
    where o.user_id=auth.uid()
      and (
        upper(trim(coalesce(d.name,'')))=case upper(trim(cert))
          when 'RADIO' then 'RADIO'
          when 'MDT' then 'MDT'
          when 'HELI' then 'HELI'
          when 'MOTO' then 'FINAL'
          when 'FINAL' then 'FINAL'
          when 'HS' then 'HS'
          else '___' end
        or exists (
          select 1 from public.officer_departments od
          join public.departments dx on dx.id=od.department_id
          where od.officer_id=o.id
            and upper(trim(dx.name))=case upper(trim(cert))
              when 'RADIO' then 'RADIO'
              when 'MDT' then 'MDT'
              when 'HELI' then 'HELI'
              when 'MOTO' then 'FINAL'
              when 'FINAL' then 'FINAL'
              when 'HS' then 'HS'
              else '___' end
        )
      )
  );
$$;
grant execute on function public.has_certificate_instructor(text) to authenticated;

-- Instructor forum read: instructor of own category, command, or Subcomisar+.
alter table public.instructor_forums enable row level security;
drop policy if exists instructor_forums_read on public.instructor_forums;
drop policy if exists instructor_forums_insert on public.instructor_forums;
drop policy if exists instructor_forums_update on public.instructor_forums;
drop policy if exists instructor_forums_delete on public.instructor_forums;
create policy instructor_forums_read on public.instructor_forums for select to authenticated
using (
  public.current_officer_rank_level() >= 8
  or public.has_role(array['super_admin','commander'])
  or public.has_certificate_instructor(case upper(category)
    when 'RADIO' then 'Radio' when 'MDT' then 'MDT' when 'HELI' then 'Heli'
    when 'FINAL' then 'Final' when 'HS' then 'HS' else '' end)
);
create policy instructor_forums_insert on public.instructor_forums for insert to authenticated
with check (
  created_by=auth.uid() and (
    public.has_role(array['super_admin','commander'])
    or public.has_certificate_instructor(case upper(category)
      when 'RADIO' then 'Radio' when 'MDT' then 'MDT' when 'HELI' then 'Heli'
      when 'FINAL' then 'Final' when 'HS' then 'HS' else '' end)
  )
);
create policy instructor_forums_update on public.instructor_forums for update to authenticated
using (
  public.has_role(array['super_admin','commander'])
  or public.has_certificate_instructor(case upper(category)
    when 'RADIO' then 'Radio' when 'MDT' then 'MDT' when 'HELI' then 'Heli'
    when 'FINAL' then 'Final' when 'HS' then 'HS' else '' end)
)
with check (
  public.has_role(array['super_admin','commander'])
  or public.has_certificate_instructor(case upper(category)
    when 'RADIO' then 'Radio' when 'MDT' then 'MDT' when 'HELI' then 'Heli'
    when 'FINAL' then 'Final' when 'HS' then 'HS' else '' end)
);
create policy instructor_forums_delete on public.instructor_forums for delete to authenticated
using (
  public.has_role(array['super_admin','commander'])
  or public.has_certificate_instructor(case upper(category)
    when 'RADIO' then 'Radio' when 'MDT' then 'MDT' when 'HELI' then 'Heli'
    when 'FINAL' then 'Final' when 'HS' then 'HS' else '' end)
);

-- Certificate applications: each instructor can review/delete only their own certificate type.
drop policy if exists cert_apps_read on public.certificate_applications;
drop policy if exists cert_apps_review on public.certificate_applications;
drop policy if exists certificate_apps_delete_own_or_instructor on public.certificate_applications;
drop policy if exists certificate_apps_read_own_or_instructors on public.certificate_applications;
drop policy if exists certificate_apps_review_instructors on public.certificate_applications;
create policy cert_apps_read_own_or_instructors on public.certificate_applications for select to authenticated
using (user_id=auth.uid() or public.has_certificate_instructor(certificate) or public.current_officer_rank_level() between 12 and 13);
create policy certificate_apps_review_instructors on public.certificate_applications for update to authenticated
using (public.has_certificate_instructor(certificate) or public.current_officer_rank_level() between 12 and 13)
with check (public.has_certificate_instructor(certificate) or public.current_officer_rank_level() between 12 and 13);
create policy certificate_apps_delete_own_or_instructor on public.certificate_applications for delete to authenticated
using (user_id=auth.uid() or public.has_certificate_instructor(certificate) or public.current_officer_rank_level() between 12 and 13);

-- Officer certificate grants are similarly scoped by certificate category.
drop policy if exists officer_certificates_manage on public.officer_certificates;
drop policy if exists officer_certificates_manage_by_instructors on public.officer_certificates;
create policy officer_certificates_manage_by_instructors on public.officer_certificates for all to authenticated
using (public.has_certificate_instructor(certificate) or public.current_officer_rank_level() between 12 and 13)
with check (public.has_certificate_instructor(certificate) or public.current_officer_rank_level() between 12 and 13);
