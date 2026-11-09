-- FLASH RP canonical synchronization repair (additive / non-destructive).
-- Apply only after 00_backup_existing_data.sql and after exporting a full
-- Supabase backup (schema + data + auth settings + Storage policies).
-- Canonical current rank: public.officers.rank_id -> public.ranks.id.
-- user_roles.role remains an independent authorization grant, not a rank store.
-- officer_promotions is history. officer_ranks is legacy/multi-rank data and is
-- deliberately retained; it must not be used to render the current rank.

begin;

-- Required columns are added defensively for older installations.
alter table public.officers
  add column if not exists updated_at timestamptz not null default now();
create index if not exists officers_rank_id_idx on public.officers(rank_id);
create index if not exists officers_department_id_idx on public.officers(department_id);
create index if not exists officers_user_id_idx on public.officers(user_id);
create index if not exists user_roles_role_idx on public.user_roles(role);
do $indexes$
begin
  if to_regclass('public.officer_departments') is not null then
    execute 'create index if not exists officer_departments_department_id_idx on public.officer_departments(department_id)';
  end if;
  if to_regclass('public.officer_promotions') is not null then
    execute 'create index if not exists officer_promotions_officer_created_idx on public.officer_promotions(officer_id, created_at desc)';
  end if;
end
$indexes$;

-- Keep updated_at accurate for direct administrative edits as well as RPC writes.
create or replace function public.flash_touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $flash$
begin
  new.updated_at := now();
  return new;
end;
$flash$;

drop trigger if exists flash_officers_touch_updated_at on public.officers;
create trigger flash_officers_touch_updated_at
before update on public.officers
for each row execute function public.flash_touch_updated_at();

-- Read access to rank metadata is needed for the joined officers -> ranks query.
alter table public.ranks enable row level security;
grant select on public.ranks to authenticated;
drop policy if exists flash_authenticated_read_ranks on public.ranks;
create policy flash_authenticated_read_ranks
  on public.ranks for select to authenticated using (true);

-- Ensure the realtime publication includes tables whose changes affect the UI.
-- This is what makes Table Editor edits to ranks/user_roles visible without
-- forcing users to sign out. Existing publication membership is left intact.
do $realtime$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname='supabase_realtime') then
    foreach t in array array['officers','ranks','user_roles','departments'] loop
      if to_regclass(format('public.%I',t)) is not null
         and not exists (
           select 1 from pg_publication_tables
           where pubname='supabase_realtime'
             and schemaname='public' and tablename=t
         ) then
        execute format('alter publication supabase_realtime add table public.%I',t);
      end if;
    end loop;
  end if;
end
$realtime$;

-- Fail early with actionable diagnostics instead of silently choosing a rank.
do $validate$
declare duplicates text;
begin
  select string_agg(user_id::text, ', ')
    into duplicates
  from (
    select user_id
    from public.officers
    where user_id is not null
    group by user_id
    having count(*) > 1
  ) d;
  if duplicates is not null then
    raise exception 'Duplicate officers.user_id values detected: %. Resolve these records before adding uniqueness.', duplicates;
  end if;
end
$validate$;


-- Atomic personnel update: profile fields, rank, departments and promotion
-- history are committed together. This avoids the old two-RPC partial-save
-- behavior and records the old rank before changing officers.rank_id.
create or replace function public.save_officer_record_with_career(
  p_officer_id uuid,
  p_full_name text,
  p_cnp text,
  p_call_sign text,
  p_badge_number text,
  p_status text,
  p_joined_at date,
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
  v_old_rank_id uuid;
  v_old_rank_name text;
  v_new_rank_name text;
  v_primary_department_id uuid;
  v_department_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Autentificare necesară';
  end if;
  if not public.is_flash_leadership() then
    raise exception 'Editarea personalului este disponibilă de la gradul Subcomisar';
  end if;
  if nullif(btrim(coalesce(p_full_name,'')), '') is null then
    raise exception 'Numele complet este obligatoriu';
  end if;
  if p_status is null or p_status not in ('Activ','În serviciu','Liber','Suspendat','Inactiv') then
    raise exception 'Status invalid';
  end if;
  if coalesce(p_update_assignments,false) and not public.is_flash_top_command() then
    raise exception 'Doar Chestorul general și Chestorul secundar pot modifica gradul și departamentele';
  end if;

  select rank_id into v_old_rank_id
  from public.officers
  where id=p_officer_id
  for update;
  if not found then
    raise exception 'Membrul selectat nu există';
  end if;

  if v_old_rank_id is not null then
    select name into v_old_rank_name from public.ranks where id=v_old_rank_id;
  end if;
  if coalesce(p_update_assignments,false) and p_rank_id is not null then
    select name into v_new_rank_name from public.ranks where id=p_rank_id;
    if not found then
      raise exception 'Gradul selectat nu există';
    end if;
  end if;

  if coalesce(p_update_assignments,false)
     and p_rank_id is distinct from v_old_rank_id then
    insert into public.officer_promotions(
      officer_id,change_type,old_rank_id,new_rank_id,
      old_rank_name,new_rank_name,changed_by
    ) values (
      p_officer_id,'EDITARE',v_old_rank_id,p_rank_id,
      v_old_rank_name,v_new_rank_name,auth.uid()
    );
  end if;

  if coalesce(p_update_assignments,false) then
    select d.id into v_primary_department_id
    from unnest(coalesce(p_department_ids,'{}'::uuid[]))
         with ordinality as d(id,ord)
    where d.id is not null
    order by d.ord
    limit 1;
  end if;

  update public.officers
  set full_name=btrim(p_full_name),
      cnp=nullif(btrim(coalesce(p_cnp,'')),''),
      call_sign=nullif(btrim(coalesce(p_call_sign,'')),''),
      badge_number=coalesce(nullif(btrim(coalesce(p_badge_number,'')),''),badge_number),
      status=p_status,
      joined_at=coalesce(p_joined_at,joined_at),
      rank_id=case when coalesce(p_update_assignments,false) then p_rank_id else rank_id end,
      department_id=case when coalesce(p_update_assignments,false) then v_primary_department_id else department_id end,
      updated_at=now()
  where id=p_officer_id;

  if coalesce(p_update_assignments,false) then
    delete from public.officer_departments where officer_id=p_officer_id;
    foreach v_department_id in array coalesce(p_department_ids,'{}'::uuid[]) loop
      if v_department_id is not null then
        insert into public.officer_departments(officer_id,department_id)
        values(p_officer_id,v_department_id)
        on conflict(officer_id,department_id) do nothing;
      end if;
    end loop;
  end if;
end;
$flash$;

revoke all on function public.save_officer_record_with_career(uuid,text,text,text,text,text,date,boolean,uuid,uuid[]) from public, anon;
grant execute on function public.save_officer_record_with_career(uuid,text,text,text,text,text,date,boolean,uuid,uuid[]) to authenticated;

commit;

-- Verification queries: one row per officer, with the one authoritative rank.
select o.id, o.user_id, o.full_name, o.rank_id, r.name as current_rank, r.level
from public.officers o
left join public.ranks r on r.id=o.rank_id
order by o.full_name;

-- Legacy/duplicate rank data audit; do not delete automatically.
select o.id as officer_id, o.full_name, o.rank_id as canonical_rank_id,
       count(orx.id) as legacy_officer_rank_rows
from public.officers o
left join public.officer_ranks orx on orx.officer_id=o.id
group by o.id,o.full_name,o.rank_id
having count(orx.id)>0
order by o.full_name;
