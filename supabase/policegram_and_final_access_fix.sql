-- Kromix: repararea finală a accesului SAS/DCCO și modulul Policegram.
-- Rulează o singură dată în Supabase SQL Editor, după migrațiile existente.

-- Rolurile SAS/DCCO sunt valide în user_roles și pot fi atribuite explicit.
alter table public.user_roles drop constraint if exists user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check (role in (
 'super_admin','commander','hr','officer','visitor',
 'sas','sas_conducere','dcco','dcco_conducere',
 'instructor_radio','instructor_mdt','instructor_moto','instructor_hs','instructor_heli'
));

-- Accesul la unitate se calculează din rol, grad și toate departamentele asociate.
create or replace function public.has_sas_access()
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_role(array['super_admin','commander','sas','sas_conducere'])
 or exists (
   select 1 from public.officers o
   left join public.departments d on d.id=o.department_id
   left join public.ranks r on r.id=o.rank_id
   where o.user_id=auth.uid() and (upper(coalesce(d.name,''))='SAS' or lower(coalesce(r.name,''))='conducere sas')
 ) or exists (
   select 1 from public.officer_departments od
   join public.departments d on d.id=od.department_id
   join public.officers o on o.id=od.officer_id
   where o.user_id=auth.uid() and upper(d.name)='SAS'
 );
$$;

create or replace function public.has_dcco_access()
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_role(array['super_admin','commander','dcco','dcco_conducere'])
 or exists (
   select 1 from public.officers o
   left join public.departments d on d.id=o.department_id
   left join public.ranks r on r.id=o.rank_id
   where o.user_id=auth.uid() and (upper(coalesce(d.name,''))='DCCO' or lower(coalesce(r.name,''))='conducere dcco')
 ) or exists (
   select 1 from public.officer_departments od
   join public.departments d on d.id=od.department_id
   join public.officers o on o.id=od.officer_id
   where o.user_id=auth.uid() and upper(d.name)='DCCO'
 );
$$;

create or replace function public.can_manage_unit_documents(p_unit text)
returns boolean language sql stable security definer set search_path=public as $$
 select public.has_role(array['super_admin','commander'])
 or (upper(p_unit)='SAS' and (
   public.has_role(array['sas_conducere']) or exists (
    select 1 from public.officers o join public.ranks r on r.id=o.rank_id
    where o.user_id=auth.uid() and lower(r.name)='conducere sas'
   )
 ))
 or (upper(p_unit)='DCCO' and (
   public.has_role(array['dcco_conducere']) or exists (
    select 1 from public.officers o join public.ranks r on r.id=o.rank_id
    where o.user_id=auth.uid() and lower(r.name)='conducere dcco'
   )
 ));
$$;

-- Clasificarea membrilor include atât departamentul principal, cât și departamentele secundare.
create or replace function public.get_unit_members(p_unit text)
returns table(user_id uuid, role text)
language plpgsql stable security definer set search_path=public as $$
declare v_unit text:=upper(p_unit);
begin
 if v_unit='SAS' and not public.has_sas_access() then raise exception 'Acces interzis la lista SAS';
 elsif v_unit='DCCO' and not public.has_dcco_access() then raise exception 'Acces interzis la lista DCCO';
 elsif v_unit not in ('SAS','DCCO') then raise exception 'Unitate invalidă'; end if;
 return query
 select distinct o.user_id,
  case when v_unit='SAS' and (lower(coalesce(r.name,''))='conducere sas' or ur.role='sas_conducere') then 'sas_conducere'
       when v_unit='DCCO' and (lower(coalesce(r.name,''))='conducere dcco' or ur.role='dcco_conducere') then 'dcco_conducere'
       when v_unit='SAS' then 'sas' else 'dcco' end::text
 from public.officers o
 left join public.departments d on d.id=o.department_id
 left join public.ranks r on r.id=o.rank_id
 left join public.user_roles ur on ur.user_id=o.user_id
 where o.user_id is not null and (
  upper(coalesce(d.name,''))=v_unit
  or (v_unit='SAS' and lower(coalesce(r.name,''))='conducere sas')
  or (v_unit='DCCO' and lower(coalesce(r.name,''))='conducere dcco')
  or exists(select 1 from public.officer_departments od join public.departments dx on dx.id=od.department_id
            where od.officer_id=o.id and upper(dx.name)=v_unit)
 );
end;
$$;
grant execute on function public.get_unit_members(text) to authenticated;
grant execute on function public.has_sas_access() to authenticated;
grant execute on function public.has_dcco_access() to authenticated;
grant execute on function public.can_manage_unit_documents(text) to authenticated;

-- Policegram: postări media, comentarii și aprecieri.
create table if not exists public.policegram_posts (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 caption text,
 media_url text not null,
 media_type text not null check(media_type in ('image','video')),
 created_at timestamptz not null default now()
);
create table if not exists public.policegram_likes (
 id uuid primary key default gen_random_uuid(),
 post_id uuid not null references public.policegram_posts(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 unique(post_id,user_id)
);
create table if not exists public.policegram_comments (
 id uuid primary key default gen_random_uuid(),
 post_id uuid not null references public.policegram_posts(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 content text not null check(length(trim(content)) between 1 and 2000),
 created_at timestamptz not null default now()
);
create index if not exists policegram_posts_created_at_idx on public.policegram_posts(created_at desc);
create index if not exists policegram_likes_post_id_idx on public.policegram_likes(post_id);
create index if not exists policegram_comments_post_id_idx on public.policegram_comments(post_id,created_at);

alter table public.policegram_posts enable row level security;
alter table public.policegram_likes enable row level security;
alter table public.policegram_comments enable row level security;
drop policy if exists policegram_posts_read on public.policegram_posts;
drop policy if exists policegram_posts_insert on public.policegram_posts;
drop policy if exists policegram_posts_delete on public.policegram_posts;
drop policy if exists policegram_likes_read on public.policegram_likes;
drop policy if exists policegram_likes_insert on public.policegram_likes;
drop policy if exists policegram_likes_delete on public.policegram_likes;
drop policy if exists policegram_comments_read on public.policegram_comments;
drop policy if exists policegram_comments_insert on public.policegram_comments;
drop policy if exists policegram_comments_delete on public.policegram_comments;
create policy policegram_posts_read on public.policegram_posts for select to authenticated using(true);
create policy policegram_posts_insert on public.policegram_posts for insert to authenticated with check(user_id=auth.uid());
create policy policegram_posts_delete on public.policegram_posts for delete to authenticated using(user_id=auth.uid() or public.has_role(array['super_admin','commander']));
create policy policegram_likes_read on public.policegram_likes for select to authenticated using(true);
create policy policegram_likes_insert on public.policegram_likes for insert to authenticated with check(user_id=auth.uid());
create policy policegram_likes_delete on public.policegram_likes for delete to authenticated using(user_id=auth.uid());
create policy policegram_comments_read on public.policegram_comments for select to authenticated using(true);
create policy policegram_comments_insert on public.policegram_comments for insert to authenticated with check(user_id=auth.uid());
create policy policegram_comments_delete on public.policegram_comments for delete to authenticated using(user_id=auth.uid() or public.has_role(array['super_admin','commander']));

grant select,insert,delete on public.policegram_posts to authenticated;
grant select,insert,delete on public.policegram_likes to authenticated;
grant select,insert,delete on public.policegram_comments to authenticated;

-- Bucket public pentru redarea imaginilor/video; încărcarea este permisă utilizatorilor autentificați.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('policegram-media','policegram-media',true,104857600,array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','video/quicktime'])
on conflict(id) do update set public=true,file_size_limit=104857600,
 allowed_mime_types=array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','video/quicktime'];
drop policy if exists policegram_media_read on storage.objects;
drop policy if exists policegram_media_insert on storage.objects;
drop policy if exists policegram_media_delete on storage.objects;
create policy policegram_media_read on storage.objects for select to public using(bucket_id='policegram-media');
create policy policegram_media_insert on storage.objects for insert to authenticated with check(bucket_id='policegram-media' and (storage.foldername(name))[1]=auth.uid()::text);
create policy policegram_media_delete on storage.objects for delete to authenticated using(bucket_id='policegram-media' and ((storage.foldername(name))[1]=auth.uid()::text or public.has_role(array['super_admin','commander'])));
