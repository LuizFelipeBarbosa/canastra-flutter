-- PostgreSQL has no create type if not exists form. This catalog check keeps a
-- re-run from failing without hiding any other enum-definition error.
do $do$
begin
  if not exists (
    select 1
    from pg_catalog.pg_type as enum_type
    join pg_catalog.pg_namespace as type_namespace
      on type_namespace.oid = enum_type.typnamespace
    where type_namespace.nspname = 'public'
      and enum_type.typname = 'queue_status'
  )
  then
    create type public.queue_status as enum (
      'waiting',
      'matched',
      'cancelled',
      'expired'
    );
  end if;
end;
$do$;

create table if not exists public.matchmaking_queue (
  user_id uuid primary key
    references public.profiles (id) on delete cascade,
  ladder_id text not null references public.ladders (id),
  rating int not null,
  status public.queue_status not null default 'waiting',
  enqueued_at timestamptz not null default now(),
  matched_room_id uuid references public.rooms (id) on delete set null,
  matched_at timestamptz,
  expires_at timestamptz not null default now() + interval '10 minutes'
);

-- This snapshot is always copied from the server-owned ratings table at
-- enqueue time. A client-supplied rating would let a player fabricate an easy
-- matchup, so no client write path accepts this value.
comment on column public.matchmaking_queue.rating is
  'Server-side rating snapshot captured at enqueue time; never client-supplied.';

-- This is the one hot query the matcher runs. Keeping only waiting rows makes
-- the index track the live queue rather than the whole eventually large table.
create index if not exists matchmaking_queue_waiting_ladder_rating_idx
  on public.matchmaking_queue (ladder_id, rating, enqueued_at)
  where status = 'waiting';

-- PostgreSQL does not automatically index foreign keys; this keeps room
-- deletion from scanning the eventually large queue history.
create index if not exists matchmaking_queue_matched_room_id_idx
  on public.matchmaking_queue (matched_room_id);

-- Postgres Changes checks the table's RLS SELECT policy for every subscriber.
-- Adding the queue to Realtime therefore lets a client learn that its own row
-- was matched without exposing another player's queue entry.
do $do$
begin
  if not exists (
    select 1
    from pg_catalog.pg_publication_tables as publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'matchmaking_queue'
  )
  then
    alter publication supabase_realtime
      add table public.matchmaking_queue;
  end if;
end;
$do$;

create or replace function public.enqueue_matchmaking(p_ladder_id text)
returns public.matchmaking_queue
language plpgsql
security definer
set search_path = ''
as $function$
declare
  requester_id uuid := (select auth.uid());
  ladder_is_active boolean;
  rating_snapshot int;
  queue_entry public.matchmaking_queue%rowtype;
begin
  if requester_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required to enter matchmaking.';
  end if;

  -- The JWT claim and profiles.is_guest are populated by different code paths:
  -- Auth owns is_anonymous in the token, while 0001's on_auth_user_upgraded
  -- trigger owns the profile column. They can disagree transiently around an
  -- account-upgrade race, so checking both is necessary defense in depth.
  if coalesce(
    ((select auth.jwt()) ->> 'is_anonymous')::boolean,
    false
  )
  then
    raise exception using
      errcode = '42501',
      message = 'Create an account to play ranked matches.';
  end if;

  if coalesce(
    (
      select profile.is_guest
      from public.profiles as profile
      where profile.id = requester_id
    ),
    true
  )
  then
    raise exception using
      errcode = '42501',
      message = 'Create an account to play ranked matches.';
  end if;

  select ladder.is_active
  into ladder_is_active
  from public.ladders as ladder
  where ladder.id = p_ladder_id;

  if not found or not ladder_is_active then
    raise exception
      'The requested ladder does not exist or is not active.';
  end if;

  select coalesce(
    (
      select player_rating.rating
      from public.ratings as player_rating
      where player_rating.user_id = requester_id
        and player_rating.ladder_id = p_ladder_id
    ),
    1200
  )
  into rating_snapshot;

  -- Re-enqueueing replaces any prior entry for this user. In particular, it
  -- refreshes the rating snapshot and expiry while clearing any old match.
  insert into public.matchmaking_queue (
    user_id,
    ladder_id,
    rating,
    status,
    enqueued_at,
    matched_room_id,
    matched_at,
    expires_at
  )
  values (
    requester_id,
    p_ladder_id,
    rating_snapshot,
    'waiting',
    pg_catalog.now(),
    null,
    null,
    pg_catalog.now() + interval '10 minutes'
  )
  on conflict (user_id)
  do update
  set
    ladder_id = excluded.ladder_id,
    rating = excluded.rating,
    status = 'waiting',
    enqueued_at = pg_catalog.now(),
    matched_room_id = null,
    matched_at = null,
    expires_at = pg_catalog.now() + interval '10 minutes'
  returning *
  into queue_entry;

  return queue_entry;
end;
$function$;

revoke all privileges on function public.enqueue_matchmaking(text)
  from public, anon, authenticated;
grant execute on function public.enqueue_matchmaking(text) to authenticated;

-- RLS also grants a caller DELETE access to its own row below. This RPC is a
-- single-call client convenience, not the only supported cancellation path.
create or replace function public.cancel_matchmaking()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  delete from public.matchmaking_queue
  where user_id = (select auth.uid());
end;
$function$;

revoke all privileges on function public.cancel_matchmaking()
  from public, anon, authenticated;
grant execute on function public.cancel_matchmaking() to authenticated;

-- Hand-traced sliding-window checks:
--
-- 1. One fresh 2-player ladder queue is sorted A=1200, B=1210, C=1900.
--    All three have waited approximately 0 seconds, so each window is
--    least(1200, 100 + 40 * (0 / 10)) = 100.
--
--    i=1: group = [A(1200), B(1210)]. group_min_window =
--    min(100, 100) = 100. spread = 1210 - 1200 = 10. Since 10 <= 100,
--    create one room for A+B and advance i to hi+1 = 3.
--
--    i=3: a 2-player group would require indices [3,4], but n=3. The loop
--    condition i + 2 - 1 <= n becomes 3 + 1 <= 3, or 4 <= 3, which is
--    false, so the loop ends. Expected outcome: exactly ONE room is created
--    for A+B, and C remains waiting this tick.
--
-- 2. The same trio is scanned with A and B still fresh at window 100, while C
--    has waited 300 seconds. C's window is
--    least(1200, 100 + 40 * (300 / 10)) =
--    least(1200, 100 + 1200) = 1200.
--
--    i=1: group = [A(1200), B(1210)]. group_min_window =
--    min(100, 100) = 100 and spread = 10 <= 100, so A+B match first. The
--    left-to-right greedy scan advances i to 3 and never reconsiders them.
--
--    i=3: the same [3,4] bound check fails with n=3. Expected outcome: still
--    exactly ONE room is created for A+B, and C is STILL unmatched despite
--    C's 1200-point window. That wide window can help C only in a future tick
--    whose queue shape compares C directly with another available player.
--
-- 3. Without A, consider B=1210 (fresh, window 100) and C=1900 (waited 300
--    seconds, window 1200) as one hypothetical 2-player group.
--    group_min_window = min(100, 1200) = 100, because B's fresh window is
--    binding. spread = 1900 - 1210 = 690, and 690 <= 100 is false.
--    Expected outcome: B and C do NOT match. C's wide window cannot drag B
--    outside B's own narrow acceptance range, which confirms that the group
--    minimum rather than any one player's window must govern the match.
create or replace function private.run_matchmaking()
returns int
language plpgsql
security definer
set search_path = ''
as $function$
declare
  ladder record;
  waiting_entry record;
  uids uuid[];
  ratings int[];
  windows int[];
  seated_user_ids uuid[];
  ladder_num_players int;
  n int;
  i int;
  lo int;
  hi int;
  group_index int;
  group_min_window int;
  created_matchmade_room_id uuid;
  rooms_created int := 0;
begin
  -- Casual ladders have no competitive rating contract, so only active ranked
  -- ladders participate in this queue.
  for ladder in
    select
      active_ladder.id,
      active_ladder.profile_id,
      active_ladder.num_players
    from public.ladders as active_ladder
    where active_ladder.is_active
      and active_ladder.is_ranked
    order by active_ladder.id
  loop
    uids := array[]::uuid[];
    ratings := array[]::int[];
    windows := array[]::int[];
    ladder_num_players := ladder.num_players;

    -- SKIP LOCKED lets concurrent runs or overlapping cron ticks claim
    -- different rows instead of double-processing or waiting on each other.
    for waiting_entry in
      select
        queue_entry.user_id,
        queue_entry.rating,
        queue_entry.enqueued_at
      from public.matchmaking_queue as queue_entry
      where queue_entry.ladder_id = ladder.id
        and queue_entry.status = 'waiting'
        and queue_entry.expires_at > pg_catalog.now()
      order by queue_entry.rating, queue_entry.enqueued_at
      for update of queue_entry skip locked
    loop
      uids := pg_catalog.array_append(uids, waiting_entry.user_id);
      ratings := pg_catalog.array_append(
        ratings,
        waiting_entry.rating
      );
      -- Fresh players start in a narrow, fair window. It widens by 40 rating
      -- points per 10 seconds, capped at 1200, so long-waiters eventually match.
      windows := pg_catalog.array_append(
        windows,
        least(
          1200,
          100 + 40 * (
            extract(
              epoch from pg_catalog.now() - waiting_entry.enqueued_at
            )::int / 10
          )
        )
      );
    end loop;

    n := coalesce(pg_catalog.array_length(uids, 1), 0);
    i := 1;

    -- PostgreSQL arrays are 1-indexed. A valid group must fit wholly inside
    -- the arrays before lo/hi slices are read.
    while i + ladder_num_players - 1 <= n loop
      lo := i;
      hi := i + ladder_num_players - 1;
      group_min_window := windows[lo];

      for group_index in lo..hi loop
        if windows[group_index] < group_min_window then
          group_min_window := windows[group_index];
        end if;
      end loop;

      -- The narrowest window is the group's real acceptance threshold. A
      -- fresh player must not be dragged into a spread justified only by a
      -- long-waiter's wider window.
      if ratings[hi] - ratings[lo] <= group_min_window then
        if ladder_num_players = 4 then
          -- The engine assigns side = seat % numSides, so seats 0+2 form one
          -- team and seats 1+3 the other. A naive rating-order array would
          -- yield p1+p3 versus p2+p4 under that rule, not the balanced
          -- lowest+highest versus two-middles pairing. Ordering the array as
          -- [p1,p2,p4,p3] puts p1+p4 in seats 0+2 and p2+p3 in seats 1+3,
          -- balancing the sides' average ratings.
          seated_user_ids := array[
            uids[lo],
            uids[lo + 1],
            uids[hi],
            uids[hi - 1]
          ];
        else
          -- In 1v1, seat 0 versus seat 1 is already the only pairing.
          seated_user_ids := array[uids[lo], uids[hi]];
        end if;

        created_matchmade_room_id := private.create_matchmade_room(
          ladder.id,
          ladder.profile_id,
          ladder_num_players,
          seated_user_ids
        );

        update public.matchmaking_queue
        set
          status = 'matched',
          matched_room_id = created_matchmade_room_id,
          matched_at = pg_catalog.now()
        where user_id = any (uids[lo:hi]);

        rooms_created := rooms_created + 1;
        i := hi + 1;
      else
        i := i + 1;
      end if;
    end loop;
  end loop;

  -- This is a coarse "rooms created this tick" observability signal, not
  -- fine-grained per-ladder reporting.
  return rooms_created;
end;
$function$;

-- pg_cron's scheduler executes this job as the postgres superuser, which is
-- unaffected by these revokes. Direct execution belongs only to service_role.
revoke all privileges on function private.run_matchmaking()
  from public, anon, authenticated;
grant execute on function private.run_matchmaking() to service_role;

create or replace function private.create_matchmade_room(
  p_ladder_id text,
  p_profile_id text,
  p_num_players int,
  p_user_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  room_code text;
  created_room public.rooms%rowtype;
  insert_attempt integer;
begin
  for insert_attempt in 1..5 loop
    room_code := private.gen_room_code();

    begin
      -- Matchmade rooms are system-created, so there is no single human owner
      -- or host client to privilege as the room owner.
      insert into public.rooms (
        code,
        owner_id,
        visibility,
        ladder_id,
        profile_id,
        num_players,
        match_target,
        is_ranked,
        allow_spectators,
        allow_bot_fill
      )
      values (
        room_code,
        null,
        'matchmade',
        p_ladder_id,
        p_profile_id,
        p_num_players,
        -- V1 ladders have no configurable match-target column. The fixed
        -- default can be replaced by a future ladder-level value.
        3000,
        true,
        false,
        -- A ranked no-show must never silently become a bot win. Although
        -- 0003's record_match_result also unranks any match with a bot seat,
        -- this prevents the host from offering bot fill in the first place.
        false
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

  -- PostgreSQL array position 1 maps to zero-indexed seat 0. run_matchmaking
  -- has already arranged this array in final engine seat order.
  insert into public.room_seats (
    room_id,
    seat,
    user_id,
    is_bot,
    reserved_until,
    joined_at,
    left_at
  )
  select
    created_room.id,
    user_position.array_index - 1,
    p_user_ids[user_position.array_index],
    false,
    pg_catalog.now() + interval '90 seconds',
    null,
    null
  from pg_catalog.generate_subscripts(
    p_user_ids,
    1
  ) as user_position(array_index);

  -- 0002's authorize_room_join checks an existing room_seats.user_id before
  -- considering any open seat. Pre-seeding the matched users therefore grants
  -- entry by room code without another matchmaking-specific authorization path.
  return created_room.id;
end;
$function$;

-- This helper is reachable only from run_matchmaking, whose security-definer
-- owner is service-role-equivalent for this internal write path, following
-- private.gen_room_code's service-role-only precedent.
revoke all privileges on function private.create_matchmade_room(
  text,
  text,
  int,
  uuid[]
) from public, anon, authenticated;
grant execute on function private.create_matchmade_room(
  text,
  text,
  int,
  uuid[]
) to service_role;

create or replace function private.reap_matchmaking()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update public.matchmaking_queue
  set status = 'expired'
  where status = 'waiting'
    and expires_at < pg_catalog.now();

  -- V1 deliberately abandons a whole stuck room. A fully correct reaper would
  -- compare room_seats.joined_at for every reserved player, release or requeue
  -- only no-shows, and handle partial matches such as 3-of-4 joined. For now,
  -- every matched player simply re-queues. This accepts the rare cost that
  -- three ready players must wait again when a fourth is stuck; it is a
  -- documented, revisitable simplification rather than an oversight.
  with abandoned_rooms as (
    update public.rooms as stuck_room
    set
      status = 'abandoned',
      closed_at = pg_catalog.now()
    where stuck_room.status = 'open'
      and exists (
        select 1
        from public.matchmaking_queue as stuck_entry
        where stuck_entry.matched_room_id = stuck_room.id
          and stuck_entry.status = 'matched'
          and stuck_entry.matched_at
            < pg_catalog.now() - interval '5 minutes'
      )
    returning stuck_room.id
  )
  update public.matchmaking_queue as stuck_entry
  set status = 'expired'
  where stuck_entry.status = 'matched'
    and stuck_entry.matched_at
      < pg_catalog.now() - interval '5 minutes'
    and stuck_entry.matched_room_id in (
      select abandoned_room.id
      from abandoned_rooms as abandoned_room
    );

  -- matched_at is the relevant age for matched-then-reaped rows. Cancelled or
  -- waiting-expired rows have no matched_at, so coalesce falls back to their
  -- original enqueued_at.
  delete from public.matchmaking_queue
  where status in ('cancelled', 'expired', 'matched')
    and coalesce(matched_at, enqueued_at)
      < pg_catalog.now() - interval '1 hour';
end;
$function$;

revoke all privileges on function private.reap_matchmaking()
  from public, anon, authenticated;
grant execute on function private.reap_matchmaking() to service_role;

-- pg_cron 1.6+ accepts plain intervals for sub-minute schedules. If this
-- project's version rejects them, fall back to '* * * * *' and widen the
-- matching-window timing assumptions to one-minute ticks.
select cron.schedule(
  'matchmake',
  '10 seconds',
  $cron$
    select private.run_matchmaking();
  $cron$
);

select cron.schedule(
  'matchmake_reap',
  '*/1 * * * *',
  $cron$
    select private.reap_matchmaking();
  $cron$
);

alter table public.matchmaking_queue enable row level security;

revoke all privileges on table public.matchmaking_queue
  from public, anon, authenticated;
grant select, delete on table public.matchmaking_queue to authenticated;
grant all privileges on table public.matchmaking_queue to service_role;

-- All enqueuing goes through the security-definer RPC so a client can never
-- insert or update an arbitrary rating snapshot. Granting direct INSERT or
-- UPDATE would defeat that anti-fabrication guarantee.

drop policy if exists matchmaking_queue_select_own
  on public.matchmaking_queue;
create policy matchmaking_queue_select_own
on public.matchmaking_queue
for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists matchmaking_queue_delete_own
  on public.matchmaking_queue;
create policy matchmaking_queue_delete_own
on public.matchmaking_queue
for delete
to authenticated
using (user_id = (select auth.uid()));
