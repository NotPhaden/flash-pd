-- Ensure SAS/DCCO and their leadership entries are present in the Departments directory.
-- Safe to run repeatedly; existing rows are preserved.
insert into public.departments(name, description) values
  ('SAS', 'Serviciul pentru Acțiuni Speciale'),
  ('DCCO', 'Direcția de Combatere a Criminalității Organizate'),
  ('Conducere SAS', 'Conducerea Serviciului pentru Acțiuni Speciale'),
  ('Conducere DCCO', 'Conducerea Direcției de Combatere a Criminalității Organizate')
on conflict (name) do nothing;

-- Ensure leadership ranks exist without changing existing rank levels.
do $$
declare v integer;
begin
  if not exists (select 1 from public.ranks where lower(name) = lower('Conducere SAS')) then
    select coalesce(max(level), 0) + 1 into v from public.ranks;
    insert into public.ranks(name, level, category) values ('Conducere SAS', v, 'Conducere');
  end if;
  if not exists (select 1 from public.ranks where lower(name) = lower('Conducere DCCO')) then
    select coalesce(max(level), 0) + 1 into v from public.ranks;
    insert into public.ranks(name, level, category) values ('Conducere DCCO', v, 'Conducere');
  end if;
end $$;
