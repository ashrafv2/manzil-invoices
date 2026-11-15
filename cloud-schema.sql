-- Run after creating the single owner in Supabase Authentication > Users.
-- Replace OWNER_USER_UUID below with that user's UUID before running.
begin;
create schema if not exists invoice_private;
revoke all on schema invoice_private from public, anon, authenticated;
create table if not exists invoice_private.owner (singleton boolean primary key default true check (singleton), user_id uuid not null references auth.users(id));
insert into invoice_private.owner(singleton,user_id) values(true,'OWNER_USER_UUID'::uuid)
on conflict(singleton) do update set user_id=excluded.user_id;
create or replace function public.invoice_is_owner() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from invoice_private.owner where user_id=auth.uid());
$$;
revoke all on function public.invoice_is_owner() from public, anon;
grant execute on function public.invoice_is_owner() to authenticated;
create table if not exists public.invoice_cloud_state (
 owner_id uuid primary key references auth.users(id),
 payload jsonb not null,
 version bigint not null default 1,
 updated_at timestamptz not null default now()
);
alter table public.invoice_cloud_state enable row level security;
revoke all on public.invoice_cloud_state from anon;
grant select,insert,update on public.invoice_cloud_state to authenticated;
drop policy if exists single_owner on public.invoice_cloud_state;
create policy single_owner on public.invoice_cloud_state for all to authenticated
using(owner_id=auth.uid() and public.invoice_is_owner())
with check(owner_id=auth.uid() and public.invoice_is_owner());
create or replace function public.invoice_sync(expected_version bigint, new_payload jsonb)
returns bigint language plpgsql security invoker set search_path='' as $$
declare current_version bigint;
begin
 if not public.invoice_is_owner() then raise exception 'access_denied'; end if;
 if jsonb_typeof(new_payload->'invoices') is distinct from 'array' or jsonb_typeof(new_payload->'catalog') is distinct from 'array' or jsonb_typeof(new_payload->'settings') is distinct from 'object' then raise exception 'invalid_payload'; end if;
 if expected_version=0 then
  insert into public.invoice_cloud_state(owner_id,payload,version) values(auth.uid(),new_payload,1) on conflict(owner_id) do nothing;
  if found then return 1; end if;
 end if;
 select version into current_version from public.invoice_cloud_state where owner_id=auth.uid() for update;
 if current_version is null or current_version<>expected_version then raise exception 'version_conflict'; end if;
 update public.invoice_cloud_state set payload=new_payload,version=version+1,updated_at=now() where owner_id=auth.uid();
 return current_version+1;
end;
$$;
revoke all on function public.invoice_sync(bigint,jsonb) from public,anon;
grant execute on function public.invoice_sync(bigint,jsonb) to authenticated;
commit;
