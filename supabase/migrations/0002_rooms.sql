-- PostgreSQL has no create type if not exists form. These small catalog checks
-- keep a re-run from failing without hiding any other enum-definition error.
do $do$
begin
  if not exists (
    select 1
    from pg_catalog.pg_type as enum_type
    join pg_catalog.pg_namespace as type_namespace
      on type_namespace.oid = enum_type.typnamespace
    where type_namespace.nspname = 'public'
      and enum_type.typname = 'room_visibility'
  )
  then
    create type public.room_visibility as enum (
      'private',
      'public',
      'matchmade'
    );
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_type as enum_type
    join pg_catalog.pg_namespace as type_namespace
      on type_namespace.oid = enum_type.typnamespace
    where type_namespace.nspname = 'public'
      and enum_type.typname = 'room_status'
  )
  then
    create type public.room_status as enum (
      'open',
      'in_progress',
      'finished',
      'abandoned'
    );
  end if;
end;
$do$;

create table if not exists public.rooms (
  id uuid primary key default private.uuid_v7(),
  code text not null,
  owner_id uuid references public.profiles (id) on delete set null,
  visibility public.room_visibility not null default 'private',
  ladder_id text references public.ladders (id),
  profile_id text not null,
  num_players int not null
    constraint rooms_num_players_check check (num_players in (2, 4)),
  match_target int not null default 3000
    constraint rooms_match_target_check
      check (match_target between 500 and 10000),
  is_ranked boolean not null default false,
  allow_spectators boolean not null default false,
  allow_bot_fill boolean not null default true,
  status public.room_status not null default 'open',
  host_instance text,
  current_match_id uuid,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  closed_at timestamptz,
  expires_at timestamptz not null default now() + interval '4 hours'
);

-- Codes need to be unique only while a room is live. Releasing them after a
-- room finishes or is abandoned keeps the six-character code space from
-- permanently filling with dead tables.
create unique index if not exists rooms_live_code_unique
  on public.rooms (code)
  where status in ('open', 'in_progress');

create index if not exists rooms_owner_id_idx
  on public.rooms (owner_id);

-- The room reaper filters by status and then expiry on every run.
create index if not exists rooms_status_expires_at_idx
  on public.rooms (status, expires_at);

-- Covers the ladder foreign key; without it a ladder delete scans rooms.
create index if not exists rooms_ladder_id_idx
  on public.rooms (ladder_id);

create table if not exists public.room_seats (
  room_id uuid references public.rooms (id) on delete cascade,
  seat int check (seat between 0 and 3),
  user_id uuid references public.profiles (id) on delete set null,
  is_bot boolean not null default false,
  reserved_until timestamptz,
  joined_at timestamptz,
  left_at timestamptz,
  primary key (room_id, seat)
);

-- A profile may reconnect to its existing seat, but it may never occupy two
-- seats in the same room.
create unique index if not exists room_seats_room_user_unique
  on public.room_seats (room_id, user_id)
  where user_id is not null;

create index if not exists room_seats_user_id_idx
  on public.room_seats (user_id);

-- The alphabet deliberately omits I, L, O, 0, and 1 because room codes are
-- meant to be read aloud or typed from a screen without visual or aural
-- ambiguity.
create or replace function private.gen_room_code()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  candidate text;
  attempt integer;
  character_position integer;
begin
  for attempt in 1..10 loop
    candidate := '';

    for character_position in 1..6 loop
      candidate := candidate || pg_catalog.substr(
        alphabet,
        pg_catalog.floor(
          pg_catalog.random() * pg_catalog.length(alphabet)
        )::integer + 1,
        1
      );
    end loop;

    if not exists (
      select 1
      from public.rooms as room
      where room.code = candidate
        and room.status in ('open', 'in_progress')
    )
    then
      return candidate;
    end if;
  end loop;

  raise exception
    'Could not generate an unused room code after 10 attempts.';
end;
$function$;

-- This check-then-return is not the real uniqueness guarantee: concurrent
-- callers can straddle it (a TOCTOU race). The partial unique index on
-- public.rooms.code enforces live-code uniqueness, and public.create_room()
-- retries when that index raises unique_violation.
--
-- This helper is called only from the security-definer create_room RPC, so no
-- API role needs a direct execution path.
revoke all privileges on function private.gen_room_code()
  from public, anon, authenticated;
grant execute on function private.gen_room_code() to service_role;

-- Anonymous Supabase-Auth users are authenticated-role users and ARE allowed
-- to create private rooms here. Guests playing with friends without signing up
-- are the point of this RPC, so it deliberately does not inspect is_guest.
--
-- A future ranked-room creation path must not blindly inherit this
-- permissiveness: it needs its own is_guest/is_ranked authorization check.
-- This is a deliberate decision for this function, not a general room policy.
create or replace function public.create_room(
  p_profile_id text,
  p_num_players int,
  p_match_target int default 3000,
  p_allow_spectators boolean default false,
  p_allow_bot_fill boolean default true
)
returns public.rooms
language plpgsql
security definer
set search_path = ''
as $function$
declare
  requester_id uuid := (select auth.uid());
  open_room_count bigint;
  room_code text;
  created_room public.rooms%rowtype;
  insert_attempt integer;
begin
  if requester_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required to create a room.';
  end if;

  if p_num_players is null or p_num_players not in (2, 4) then
    raise exception
      'num_players must be either 2 or 4.';
  end if;

  -- lib/engine/profiles.dart is the source of truth for rules-profile IDs.
  -- PostgreSQL cannot reference that Dart registry, so this validation list
  -- must be kept in sync with it manually.
  if p_profile_id is null
    or p_profile_id not in ('buraco', 'canasta', 'biriba', 'rummy')
  then
    raise exception
      'profile_id must be one of buraco, canasta, biriba, or rummy.';
  end if;

  if p_match_target is null
    or p_match_target not between 500 and 10000
  then
    raise exception
      'match_target must be between 500 and 10000.';
  end if;

  -- Five simultaneously open rooms signals either a client bug or abuse; both
  -- cases should be rejected rather than creating more abandoned tables.
  select pg_catalog.count(*)
  into open_room_count
  from public.rooms as room
  where room.owner_id = requester_id
    and room.status = 'open';

  if open_room_count >= 5 then
    raise exception
      'A user may own at most 5 open rooms.';
  end if;

  for insert_attempt in 1..5 loop
    room_code := private.gen_room_code();

    begin
      insert into public.rooms (
        code,
        owner_id,
        profile_id,
        num_players,
        match_target,
        allow_spectators,
        allow_bot_fill
      )
      values (
        room_code,
        requester_id,
        p_profile_id,
        p_num_players,
        p_match_target,
        p_allow_spectators,
        p_allow_bot_fill
      )
      returning *
      into created_room;

      exit;
    exception
      when unique_violation then
        if insert_attempt = 5 then
          raise;
        end if;
    end;
  end loop;

  insert into public.room_seats (
    room_id,
    seat,
    user_id,
    reserved_until
  )
  select
    created_room.id,
    generated_seat.seat,
    case
      when generated_seat.seat = 0 then requester_id
      else null::uuid
    end,
    case
      when generated_seat.seat = 0
        then pg_catalog.now() + interval '5 minutes'
      else null::timestamptz
    end
  from pg_catalog.generate_series(
    0,
    p_num_players - 1
  ) as generated_seat(seat);

  return created_room;
end;
$function$;

revoke all privileges on function public.create_room(
  text,
  int,
  int,
  boolean,
  boolean
) from public, anon, authenticated;
grant execute on function public.create_room(
  text,
  int,
  int,
  boolean,
  boolean
) to authenticated;

-- This is the game host's authorization seam. Clients cannot redeem a code or
-- assign a seat by calling the database directly; only service_role may invoke
-- this RPC.
create or replace function public.authorize_room_join(
  p_room_code text,
  p_user_id uuid,
  p_spectator boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  locked_room public.rooms%rowtype;
  resolved_seat integer;
  player_display_name text;
begin
  select candidate_room.*
  into locked_room
  from public.rooms as candidate_room
  where pg_catalog.upper(p_room_code) = pg_catalog.upper(candidate_room.code)
    and candidate_room.status in ('open', 'in_progress')
  for update;

  if not found then
    return pg_catalog.jsonb_build_object(
      'ok', false,
      'reason', 'no such room'
    );
  end if;

  if locked_room.expires_at < pg_catalog.now() then
    return pg_catalog.jsonb_build_object(
      'ok', false,
      'reason', 'room expired'
    );
  end if;

  if p_spectator then
    if not locked_room.allow_spectators then
      return pg_catalog.jsonb_build_object(
        'ok', false,
        'reason', 'spectators are not allowed'
      );
    end if;

    return pg_catalog.jsonb_build_object(
      'ok', true,
      'spectator', true,
      'room_id', locked_room.id,
      'rules', pg_catalog.jsonb_build_object(
        'profile', locked_room.profile_id,
        'num_players', locked_room.num_players,
        'match_target', locked_room.match_target
      )
    );
  end if;

  -- Reconnects retain their original seat even if another empty seat has a
  -- lower number.
  select room_seat.seat
  into resolved_seat
  from public.room_seats as room_seat
  where room_seat.room_id = locked_room.id
    and room_seat.user_id = p_user_id
  order by room_seat.seat
  limit 1
  for update;

  if not found then
    select room_seat.seat
    into resolved_seat
    from public.room_seats as room_seat
    where room_seat.room_id = locked_room.id
      and room_seat.user_id is null
      and not room_seat.is_bot
      and (
        room_seat.reserved_until is null
        or room_seat.reserved_until < pg_catalog.now()
      )
    order by room_seat.seat
    limit 1
    for update;
  end if;

  if resolved_seat is null then
    return pg_catalog.jsonb_build_object(
      'ok', false,
      'reason', 'room is full'
    );
  end if;

  update public.room_seats
  set
    user_id = p_user_id,
    joined_at = coalesce(joined_at, pg_catalog.now()),
    left_at = null,
    reserved_until = null
  where room_id = locked_room.id
    and seat = resolved_seat;

  select coalesce(profile.username, profile.display_name)
  into player_display_name
  from public.profiles as profile
  where profile.id = p_user_id;

  -- Filling the final seat does not change room status here. The game host
  -- owns transitions such as flipping a room to in_progress; this RPC only
  -- authorizes admission and assigns the seat.
  return pg_catalog.jsonb_build_object(
    'ok', true,
    'spectator', false,
    'room_id', locked_room.id,
    'seat', resolved_seat,
    'display_name', player_display_name,
    'is_owner', p_user_id = locked_room.owner_id,
    'is_ranked', locked_room.is_ranked,
    'ladder_id', locked_room.ladder_id,
    'allow_bot_fill', locked_room.allow_bot_fill,
    'rules', pg_catalog.jsonb_build_object(
      'profile', locked_room.profile_id,
      'num_players', locked_room.num_players,
      'match_target', locked_room.match_target
    )
  );
end;
$function$;

revoke all privileges on function public.authorize_room_join(
  text,
  uuid,
  boolean
) from public, anon, authenticated;
grant execute on function public.authorize_room_join(
  text,
  uuid,
  boolean
) to service_role;

alter table public.rooms enable row level security;
alter table public.room_seats enable row level security;

-- Table privileges are narrower than Supabase's common defaults: authenticated
-- clients can read only the rows admitted by RLS, while unauthenticated anon
-- requests have no table access at all.
revoke all privileges on table public.rooms, public.room_seats
  from public, anon, authenticated;
grant select on table public.rooms, public.room_seats to authenticated;
grant all privileges on table public.rooms, public.room_seats to service_role;

-- There are deliberately no client INSERT, UPDATE, or DELETE grants or
-- policies on either table. Only create_room (as a controlled
-- security-definer RPC) and the game host under service_role may write them.

-- A direct rooms-policy subquery against room_seats would apply room_seats RLS.
-- Because the room_seats policy must inspect its parent room, that literal
-- rooms -> room_seats -> rooms chain would be genuinely recursive. This helper
-- performs the requested seat-membership EXISTS check as the function owner,
-- so room_seats RLS is bypassed and policy evaluation terminates here.
--
-- The helper cannot test another identity: auth.uid() is read inside the
-- function. Authenticated needs EXECUTE because its RLS policy invokes the
-- function, but the private schema remains outside the exposed API schemas.
create or replace function private.is_room_seat_holder(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.room_seats as room_seat
    where room_seat.room_id = p_room_id
      and room_seat.user_id = (select auth.uid())
  );
$function$;

revoke all privileges on function private.is_room_seat_holder(uuid)
  from public, anon, authenticated;
grant execute on function private.is_room_seat_holder(uuid) to authenticated;

-- There is deliberately no select-by-code policy or other REST path. Knowing a
-- code must never let anon or authenticated callers enumerate or read a room
-- by filtering public.rooms.code. A private room becomes visible only after
-- the game host redeems its code under service_role and assigns the caller a
-- seat; visibility then derives from public/owner/seat membership alone.
drop policy if exists rooms_select_authenticated on public.rooms;
create policy rooms_select_authenticated
on public.rooms
for select
to authenticated
using (
  visibility = 'public'
  or owner_id = (select auth.uid())
  or private.is_room_seat_holder(id)
);

-- This policy may inspect the parent room, whose policy ends any seat lookup
-- inside private.is_room_seat_holder() under security-definer privileges. That
-- bypass is the concrete non-recursion boundary: evaluating room_seats can
-- evaluate rooms once, but it cannot re-enter the room_seats policy.
--
-- Seat membership alone exposes only a player's own seat. Owners may inspect
-- every seat in their room, and public-room seats are visible to authenticated
-- users.
drop policy if exists room_seats_select_authenticated on public.room_seats;
create policy room_seats_select_authenticated
on public.room_seats
for select
to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1
    from public.rooms as room
    where room.id = room_seats.room_id
      and (
        room.owner_id = (select auth.uid())
        or room.visibility = 'public'
      )
  )
);

-- Match history will reference rooms in a later migration. Once that
-- dependency exists, this hard-delete policy may need to tighten to a
-- soft-delete or archival strategy.
select cron.schedule(
  'reap_stale_rooms',
  '*/15 * * * *',
  $cron$
    update public.rooms
    set
      status = 'abandoned',
      closed_at = pg_catalog.now()
    where status = 'open'
      and expires_at < pg_catalog.now();

    delete from public.rooms
    where status in ('abandoned', 'finished')
      and closed_at < pg_catalog.now() - interval '7 days';
  $cron$
);
