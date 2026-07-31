-- Internal helpers belong outside exposed schemas so end users cannot treat them
-- as API endpoints. They are reachable only through the security-definer
-- functions and triggers that this project controls.
create schema if not exists private;

revoke all privileges on schema private from public, anon, authenticated;
grant usage on schema private to service_role;

-- UUIDv7 keeps the globally unique, unguessable random low bits of a UUID while
-- putting the current millisecond epoch first. That gives IDs free time-ordering
-- and substantially better index locality than gen_random_uuid(), reducing
-- random-page writes and index bloat as a table grows.
create or replace function private.uuid_v7()
returns uuid
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  uuid_bytes bytea := pg_catalog.uuid_send(pg_catalog.gen_random_uuid());
  unix_ts_ms bigint :=
    pg_catalog.floor(
      extract(epoch from pg_catalog.clock_timestamp()) * 1000
    )::bigint;
begin
  -- Store the low 48 bits of the millisecond epoch in network byte order.
  uuid_bytes := pg_catalog.set_byte(
    uuid_bytes,
    0,
    ((unix_ts_ms >> 40) & 255)::integer
  );
  uuid_bytes := pg_catalog.set_byte(
    uuid_bytes,
    1,
    ((unix_ts_ms >> 32) & 255)::integer
  );
  uuid_bytes := pg_catalog.set_byte(
    uuid_bytes,
    2,
    ((unix_ts_ms >> 24) & 255)::integer
  );
  uuid_bytes := pg_catalog.set_byte(
    uuid_bytes,
    3,
    ((unix_ts_ms >> 16) & 255)::integer
  );
  uuid_bytes := pg_catalog.set_byte(
    uuid_bytes,
    4,
    ((unix_ts_ms >> 8) & 255)::integer
  );
  uuid_bytes := pg_catalog.set_byte(
    uuid_bytes,
    5,
    (unix_ts_ms & 255)::integer
  );

  -- Preserve randomness outside the RFC-mandated version and variant bits.
  uuid_bytes := pg_catalog.set_byte(
    uuid_bytes,
    6,
    (pg_catalog.get_byte(uuid_bytes, 6) & 15) | 112
  );
  uuid_bytes := pg_catalog.set_byte(
    uuid_bytes,
    8,
    (pg_catalog.get_byte(uuid_bytes, 8) & 63) | 128
  );

  return pg_catalog.encode(uuid_bytes, 'hex')::uuid;
end;
$function$;

-- Schema isolation is the primary boundary, and revoking the default function
-- privilege provides defense in depth against accidental direct exposure.
revoke all privileges on function private.uuid_v7()
  from public, anon, authenticated;
grant execute on function private.uuid_v7() to service_role;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text,
  display_name text not null default 'Jogador',
  avatar_url text,
  locale text not null default 'pt-BR',
  is_guest boolean not null default true,
  legacy_played int not null default 0,
  legacy_won int not null default 0,
  legacy_best int not null default 0,
  legacy_uploaded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_format
    check (username is null or username ~ '^[a-zA-Z0-9_]{3,20}$'),
  constraint profiles_display_name_length
    check (char_length(display_name) between 1 and 32)
);

-- Only populated usernames participate, so null remains a valid "not chosen
-- yet" state while every actual username is unique regardless of letter case.
create unique index profiles_username_lower_unique
  on public.profiles (lower(username))
  where username is not null;

comment on column public.profiles.legacy_uploaded_at is
  'Marks the one-time upload of pre-account local stats. These values are display-only and must never feed ratings or leaderboard computations.';

create table public.ladders (
  id text primary key,
  profile_id text not null,
  num_players int not null,
  is_ranked boolean not null default true,
  label text not null,
  is_active boolean not null default true,
  constraint ladders_num_players_check check (num_players in (2, 4))
);

-- Plain text on purpose: the rules profiles live in the app's engine
-- (lib/engine/profiles.dart), not in a database table, so there is nothing
-- here to reference. The engine is the single source of rule truth.
comment on column public.ladders.profile_id is
  'Engine rules-profile id (buraco, canasta, biriba, rummy) as accepted by loadProfile(). Unrelated to public.profiles.';

insert into public.ladders (
  id,
  profile_id,
  num_players,
  is_ranked,
  label
)
values
  ('buraco:2:ranked', 'buraco', 2, true, 'Buraco 1v1'),
  ('buraco:4:ranked', 'buraco', 4, true, 'Buraco 2v2'),
  ('canasta:2:ranked', 'canasta', 2, true, 'Canasta 1v1'),
  ('canasta:4:ranked', 'canasta', 4, true, 'Canasta 2v2'),
  ('biriba:2:ranked', 'biriba', 2, true, 'Biriba 1v1'),
  ('biriba:4:ranked', 'biriba', 4, true, 'Biriba 2v2'),
  ('rummy:2:ranked', 'rummy', 2, true, 'Rummy 1v1')
on conflict (id) do nothing;

-- raw_user_meta_data is user-editable at signup. It is a display hint only,
-- never a basis for authorization or trust decisions.
create or replace function private.handle_auth_user_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.profiles (
    id,
    display_name,
    is_guest
  )
  values (
    new.id,
    pg_catalog.left(
      coalesce(
        nullif(new.raw_user_meta_data ->> 'display_name', ''),
        nullif(new.raw_user_meta_data ->> 'full_name', ''),
        nullif(new.raw_user_meta_data ->> 'name', ''),
        nullif(
          pg_catalog.split_part(coalesce(new.email, ''), '@', 1),
          ''
        ),
        'Convidado ' || pg_catalog.upper(
          pg_catalog.substr(
            pg_catalog.replace(new.id::text, '-', ''),
            1,
            4
          )
        )
      ),
      32
    ),
    coalesce(new.is_anonymous, false)
  )
  on conflict (id) do nothing;

  return new;
end;
$function$;

revoke all privileges on function private.handle_auth_user_created()
  from public, anon, authenticated, service_role;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row
execute function private.handle_auth_user_created();

-- Converting an anonymous Auth user upgrades the existing identity in place.
-- Mirroring that transition keeps guest-only behavior out of a real account.
create or replace function private.handle_auth_user_upgraded()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update public.profiles
  set
    is_guest = false,
    updated_at = pg_catalog.now()
  where id = new.id;

  return new;
end;
$function$;

revoke all privileges on function private.handle_auth_user_upgraded()
  from public, anon, authenticated, service_role;

drop trigger if exists on_auth_user_upgraded on auth.users;
create trigger on_auth_user_upgraded
after update of is_anonymous on auth.users
for each row
when (old.is_anonymous and not new.is_anonymous)
execute function private.handle_auth_user_upgraded();

alter table public.profiles enable row level security;
alter table public.ladders enable row level security;

-- Table privileges are intentionally narrower than Supabase's common defaults:
-- RLS decides which rows are visible, while grants decide which operations exist
-- at all for each API role.
revoke all privileges on table public.profiles, public.ladders
  from public, anon, authenticated;
grant select, update on table public.profiles to authenticated;
grant select on table public.ladders to anon, authenticated;
grant all privileges on table public.profiles, public.ladders to service_role;

-- Opponent names and other profile presentation data must be discoverable by
-- signed-in players, while profile mutation remains owner-scoped.
create policy profiles_select_authenticated
on public.profiles
for select
to authenticated
using (true);

-- Wrapping auth.uid() in SELECT lets PostgreSQL cache it as an initplan once per
-- statement instead of invoking it for every candidate row.
create policy profiles_update_own
on public.profiles
for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

-- There are deliberately no client INSERT or DELETE policies for profiles.
-- Rows come only from on_auth_user_created (as a controlled security-definer
-- trigger) or service_role. Client inserts could fabricate a profile for
-- someone else's auth.users ID or bypass the trigger's guest detection.

-- The lobby needs the ladder catalog before login, but inactive ladders are
-- operationally hidden and no API role receives a ladder write path.
create policy ladders_select_active
on public.ladders
for select
to anon, authenticated
using (is_active);

-- The update-own RLS policy is not sufficient by itself: without this trigger,
-- a guest could set is_guest = false on their own row and sneak onto a future
-- ranked leaderboard without completing a real signup or account upgrade.
--
-- Legacy stats stay client-writable only as a first-write-wins migration path
-- for pre-account local data; they are not an ongoing client-controlled channel.
create or replace function private.pin_profile_immutables()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  -- PostgREST uses SET LOCAL ROLE for the JWT role, so this setting identifies
  -- a service-role request even though session_user may be the connection role.
  if pg_catalog.current_setting('role', true) = 'service_role' then
    new.updated_at := pg_catalog.now();
    return new;
  end if;

  new.id := old.id;
  new.created_at := old.created_at;

  -- Supabase Auth uses its own internal database role, so the controlled
  -- on_auth_user_upgraded trigger is not necessarily seen here as service_role.
  -- Permit only that nested true-to-false transition, and verify it against the
  -- server-owned auth.users state. A direct profile UPDATE from a client stays
  -- at trigger depth 1 and can never use this exception.
  if pg_catalog.pg_trigger_depth() > 1
    and old.is_guest
    and not new.is_guest
    and exists (
      select 1
      from auth.users as auth_user
      where auth_user.id = new.id
        and auth_user.is_anonymous is false
    )
  then
    new.is_guest := false;
  else
    new.is_guest := old.is_guest;
  end if;

  if old.legacy_uploaded_at is not null then
    new.legacy_played := old.legacy_played;
    new.legacy_won := old.legacy_won;
    new.legacy_best := old.legacy_best;
    new.legacy_uploaded_at := old.legacy_uploaded_at;
  end if;

  new.updated_at := pg_catalog.now();
  return new;
end;
$function$;

revoke all privileges on function private.pin_profile_immutables()
  from public, anon, authenticated, service_role;

drop trigger if exists pin_profile_immutables on public.profiles;
create trigger pin_profile_immutables
before update on public.profiles
for each row
execute function private.pin_profile_immutables();

create extension if not exists pg_cron with schema extensions;

-- The original cleanup guard referenced a match_players table that does not
-- exist yet in this migration; for now we only spare guests who uploaded legacy
-- stats. When match/game-history tables land in a later migration, extend this
-- guard to also keep guests who have recorded matches, so we do not delete a
-- guest mid-tournament or erase match history that references them.
select cron.schedule(
  'reap_stale_guests',
  '17 4 * * *',
  $cron$
    delete from auth.users u
    where u.is_anonymous
      and u.created_at < pg_catalog.now() - interval '45 days'
      and not exists (
        select 1
        from public.profiles p
        where p.id = u.id
          and p.legacy_uploaded_at is not null
      );
  $cron$
);
