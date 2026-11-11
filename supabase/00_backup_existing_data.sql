-- Kromix RP: logical row backup before database reconciliation.
-- Run once in Supabase SQL Editor. This copies every public BASE TABLE into a
-- dated private schema. It does not replace a provider-level pg_dump backup:
-- functions, grants, RLS policies, triggers, auth.users and Storage objects
-- must also be exported from Supabase Dashboard / CLI.
begin;
create schema if not exists flash_backup_20261109;
revoke all on schema flash_backup_20261109 from public, anon, authenticated;
do $backup$
declare r record; target_name text;
begin
  for r in
    select tablename
    from pg_tables
    where schemaname = 'public'
    order by tablename
  loop
    target_name := r.tablename;
    if to_regclass(format('%I.%I','flash_backup_20261109',target_name)) is null then
      execute format(
        'create table %I.%I (like public.%I including all)',
        'flash_backup_20261109', target_name, target_name
      );
      execute format(
        'insert into %I.%I select * from public.%I',
        'flash_backup_20261109', target_name, target_name
      );
    end if;
  end loop;
end
$backup$;
commit;

-- Review copied row counts. Compare with the source before proceeding.
select table_name
from information_schema.tables
where table_schema='flash_backup_20261109' and table_type='BASE TABLE'
order by table_name;
