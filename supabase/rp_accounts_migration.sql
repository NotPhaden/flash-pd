-- Kromix RP identity + account provisioning. Run AFTER schema.sql.
-- Supabase Auth uses a reserved synthetic address; no real email is collected.
create table if not exists public.rp_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  character_id text not null unique,
  rp_first_name text not null,
  rp_last_name text not null,
  rp_phone text not null,
  created_at timestamptz not null default now()
);
alter table public.rp_accounts enable row level security;
drop policy if exists "rp account own read" on public.rp_accounts;
create policy "rp account own read" on public.rp_accounts for select to authenticated
  using (user_id = auth.uid() or public.has_role(array['super_admin','commander','hr']));
-- Deliberately no client INSERT/UPDATE/DELETE policy. Only the trusted Auth trigger writes identity fields.

create or replace function public.provision_flash_rp_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_character_id text;
  v_first text;
  v_last text;
  v_phone text;
begin
  v_character_id := lower(trim(coalesce(new.raw_user_meta_data->>'character_id','')));
  v_first := trim(coalesce(new.raw_user_meta_data->>'rp_first_name',''));
  v_last := trim(coalesce(new.raw_user_meta_data->>'rp_last_name',''));
  v_phone := trim(coalesce(new.raw_user_meta_data->>'rp_phone',''));
  if v_character_id = '' or v_first = '' or v_last = '' or v_phone = '' then
    raise exception 'Kromix RP registration metadata is incomplete';
  end if;
  insert into public.rp_accounts(user_id, character_id, rp_first_name, rp_last_name, rp_phone)
  values(new.id, v_character_id, v_first, v_last, v_phone);
  insert into public.user_roles(user_id, role) values(new.id, 'officer')
    on conflict (user_id) do nothing;
  insert into public.officers(user_id, full_name, badge_number, internal_id, phone, status, joined_at)
  values(new.id, v_first || ' ' || v_last, v_character_id, v_character_id, v_phone, 'Activ', current_date)
  on conflict (user_id) do update set full_name = excluded.full_name;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created_flash_rp on auth.users;
create trigger on_auth_user_created_flash_rp
  after insert on auth.users
  for each row execute function public.provision_flash_rp_account();

-- Protect account identity and role records from self-promotion or client-side edits.
drop policy if exists "users read own role" on public.user_roles;
create policy "users read own role" on public.user_roles for select to authenticated using (user_id = auth.uid());
-- Ensure no broad client write policies exist on user_roles/rp_accounts.
revoke insert, update, delete on public.user_roles from anon, authenticated;
revoke insert, update, delete on public.rp_accounts from anon, authenticated;

