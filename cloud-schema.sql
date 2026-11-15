-- Configure invoice_private.owner privately after applying this schema.
-- Access requires the approved email to be confirmed by Supabase Auth.
begin;
create schema if not exists invoice_private;
revoke all on schema invoice_private from public, anon, authenticated;
grant usage on schema invoice_private to authenticated;
create table if not exists invoice_private.owner (singleton boolean primary key default true check (singleton), email text not null);
alter table invoice_private.owner enable row level security;
revoke all on invoice_private.owner from public,anon,authenticated;
create or replace function invoice_private.invoice_is_owner() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from invoice_private.owner o join auth.users u on lower(u.email)=lower(o.email) where u.id=auth.uid() and u.email_confirmed_at is not null);
$$;
revoke all on function invoice_private.invoice_is_owner() from public, anon;
grant execute on function invoice_private.invoice_is_owner() to authenticated;
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
using(owner_id=(select auth.uid()) and (select invoice_private.invoice_is_owner()))
with check(owner_id=(select auth.uid()) and (select invoice_private.invoice_is_owner()));
create or replace function public.invoice_sync(expected_version bigint, new_payload jsonb)
returns bigint language plpgsql security invoker set search_path='' as $$
declare current_version bigint;
begin
 if not invoice_private.invoice_is_owner() then raise exception 'access_denied'; end if;
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
