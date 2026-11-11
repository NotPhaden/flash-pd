-- Kromix: SAS + DCCO unit workspace, documentation and membership
-- Apply AFTER schema.sql and the existing Kromix migrations.

-- Add the SAS membership and leadership access roles.
alter table public.user_roles drop constraint if exists user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check (role in (
  'super_admin','commander','hr','officer','dcco','dcco_conducere','sas','sas_conducere',
  'instructor_radio','instructor_mdt','instructor_hs','instructor_heli'
));

-- SAS is a real department and Conducere SAS is a rank as well as a restricted access role.
insert into public.departments(name,description)
values ('SAS','Serviciul pentru Acțiuni Speciale')
on conflict(name) do update set description=excluded.description;
insert into public.ranks(name,level,category)
values ('Conducere SAS',19,'Conducere')
on conflict(name) do update set category=excluded.category;

create table if not exists public.unit_documents (
  id uuid primary key default gen_random_uuid(),
  unit_key text not null check (unit_key in ('SAS','DCCO')),
  doc_type text not null,
  title text not null,
  content text not null,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint unit_documents_unit_type_unique unique(unit_key,doc_type),
  constraint unit_documents_type_check check (
    (unit_key='SAS' and doc_type in ('Regulament SAS','Instructaj SAS','Poziții jaf')) or
    (unit_key='DCCO' and doc_type in ('Regulament DCCO','Instructaj DCCO'))
  )
);

create or replace function public.has_sas_access()
returns boolean language sql stable security definer set search_path=public as $$
  select public.has_role(array['super_admin','commander','sas','sas_conducere']);
$$;

create or replace function public.can_manage_unit_documents(p_unit text)
returns boolean language sql stable security definer set search_path=public as $$
  select case upper(p_unit)
    when 'SAS' then public.has_role(array['super_admin','commander','sas_conducere'])
    when 'DCCO' then public.has_role(array['super_admin','commander','dcco_conducere'])
    else false
  end;
$$;

-- Return only the roster for a unit the caller is allowed to access.
create or replace function public.get_unit_members(p_unit text)
returns table(user_id uuid, role text)
language plpgsql stable security definer set search_path=public as $$
begin
  if upper(p_unit)='SAS' and not public.has_sas_access() then
    raise exception 'Acces interzis la lista SAS';
  elsif upper(p_unit)='DCCO' and not public.has_dcco_access() then
    raise exception 'Acces interzis la lista DCCO';
  elsif upper(p_unit) not in ('SAS','DCCO') then
    raise exception 'Unitate invalidă';
  end if;
  return query
    select ur.user_id, ur.role
    from public.user_roles ur
    where (upper(p_unit)='SAS' and ur.role in ('sas','sas_conducere'))
       or (upper(p_unit)='DCCO' and ur.role in ('dcco','dcco_conducere'));
end;
$$;

grant execute on function public.get_unit_members(text) to authenticated;
grant execute on function public.has_sas_access() to authenticated;
grant execute on function public.can_manage_unit_documents(text) to authenticated;

alter table public.unit_documents enable row level security;
drop policy if exists unit_documents_read on public.unit_documents;
create policy unit_documents_read on public.unit_documents for select to authenticated
using ((unit_key='SAS' and public.has_sas_access()) or (unit_key='DCCO' and public.has_dcco_access()));
drop policy if exists unit_documents_insert on public.unit_documents;
create policy unit_documents_insert on public.unit_documents for insert to authenticated
with check (public.can_manage_unit_documents(unit_key));
drop policy if exists unit_documents_update on public.unit_documents;
create policy unit_documents_update on public.unit_documents for update to authenticated
using (public.can_manage_unit_documents(unit_key)) with check (public.can_manage_unit_documents(unit_key));
drop policy if exists unit_documents_delete on public.unit_documents;
create policy unit_documents_delete on public.unit_documents for delete to authenticated
using (public.can_manage_unit_documents(unit_key));

-- Restrict the SAS/DCCO membership RPC to authenticated users; it checks unit access internally.
