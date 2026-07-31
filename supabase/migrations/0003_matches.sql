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
      and enum_type.typname = 'match_status'
  )
  then
    create type public.match_status as enum (
      'in_progress',
      'completed',
      'abandoned'
    );
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_type as enum_type
    join pg_catalog.pg_namespace as type_namespace
      on type_namespace.oid = enum_type.typnamespace
    where type_namespace.nspname = 'public'
      and enum_type.typname = 'match_result'
  )
  then
    create type public.match_result as enum (
      'win',
      'loss',
      'draw'
    );
  end if;
end;
$do$;

create table if not exists public.matches (
  id uuid primary key,
  room_id uuid references public.rooms (id) on delete set null,
  room_code text,
  ladder_id text references public.ladders (id),
  profile_id text not null,
  num_players int not null,
  num_sides int not null,
  match_target int not null,
  seed bigint not null,
  is_ranked boolean not null default false,
  status public.match_status not null default 'in_progress',
  winner_side int
    check (winner_side is null or winner_side between 0 and 3),
  final_scores int[] not null default '{}',
  rounds_played int not null default 0,
  participant_ids uuid[] not null default '{}',
  host_instance text,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  recorded_at timestamptz
);

-- Unlike rooms, a match has no database-side UUID default. The trusted host
-- mints a UUIDv7 with the existing private.uuid_v7() pattern and includes it in
-- the payload, so this ID is also record_match_result()'s retry key.
comment on column public.matches.id is
  'Client-minted UUIDv7 supplied by the trusted game host. It is the record_match_result() idempotency key, so this column deliberately has no private.uuid_v7() default.';

-- Rooms are operational and eventually reaped, while match history is durable.
-- Keeping the human-facing code here preserves useful context after room_id is
-- set null by the room deletion.
comment on column public.matches.room_code is
  'Denormalised room code retained because operational room rows are eventually reaped while match history must survive.';

-- Plain text on purpose: the rules profiles live in the app's engine
-- (lib/engine/profiles.dart), not in a database table, so there is nothing
-- here to reference. The engine is the single source of rule truth.
comment on column public.matches.profile_id is
  'Engine rules-profile id (buraco, canasta, biriba, rummy) as accepted by loadProfile(). Unrelated to public.profiles.';

-- Membership is captured once so match visibility never needs to traverse
-- match_players. That keeps the parent policy cheap and prevents a future
-- parent/child RLS cycle.
comment on column public.matches.participant_ids is
  'Set of human player user IDs captured at insert time for direct, non-recursive match RLS and future my-matches queries.';

-- UUIDv7 values sort by creation time, so descending IDs provide recency
-- ordering within a ladder without repeating started_at in this index.
create index if not exists matches_ladder_id_id_idx
  on public.matches (ladder_id, id desc);

-- PostgreSQL does not automatically index foreign keys; this keeps room
-- deletion from scanning the durable match table.
create index if not exists matches_room_id_idx
  on public.matches (room_id);

-- This supports participant membership checks in RLS and the future
-- authenticated "my matches" query without normalising through match_players.
create index if not exists matches_participant_ids_idx
  on public.matches using gin (participant_ids);

-- Only unfinished matches participate in host-recovery scans.
create index if not exists matches_in_progress_started_at_idx
  on public.matches (started_at desc)
  where status = 'in_progress';

create table if not exists public.match_sides (
  match_id uuid references public.matches (id) on delete cascade,
  side int check (side between 0 and 3),
  score_final int not null,
  is_winner boolean not null default false,
  primary key (match_id, side)
);

-- The engine scores teams, not individuals. Per-player score attribution would
-- invent data in 2v2, so scores live here and match_players deliberately has no
-- score column.
comment on table public.match_sides is
  'Final scores belong to engine sides (teams). Per-player score attribution would be fabricated for 2v2, so match_players deliberately has no score column.';

create table if not exists public.match_players (
  match_id uuid,
  seat int check (seat between 0 and 3),
  side int,
  user_id uuid references public.profiles (id) on delete set null,
  is_bot boolean not null default false,
  bot_level text,
  display_name text not null,
  result public.match_result,
  disconnects int not null default 0,
  replaced_by_bot boolean not null default false,
  rating_before int,
  rating_after int,
  rating_delta int,
  primary key (match_id, seat),
  constraint match_players_match_id_fkey
    foreign key (match_id)
    references public.matches (id)
    on delete cascade,
  constraint match_players_match_side_fkey
    foreign key (match_id, side)
    references public.match_sides (match_id, side)
    on delete cascade,
  constraint match_players_bot_has_no_user
    check (not is_bot or user_id is null)
);

-- The primary key's (match_id, seat) order already covers the bare match_id
-- foreign key. This separate order covers the composite side foreign key.
create index if not exists match_players_match_id_side_idx
  on public.match_players (match_id, side);

-- UUIDv7 match IDs are time-ordered, so this one index yields a player's
-- matches most-recent-first without carrying another timestamp.
create index if not exists match_players_user_id_match_id_idx
  on public.match_players (user_id, match_id desc)
  where user_id is not null;

create table if not exists public.match_rounds (
  match_id uuid references public.matches (id) on delete cascade,
  round_index int,
  reason text not null,
  went_out_side int,
  sheet jsonb not null,
  match_scores_after int[] not null,
  ended_at timestamptz not null default now(),
  primary key (match_id, round_index)
);

-- Keeping the engine's view model verbatim lets the existing Flutter widget
-- render historical sheets directly, avoiding a second representation that
-- would drift as scoring rules evolve.
comment on column public.match_rounds.sheet is
  'Verbatim RoundResultView.toJson() output from the Flutter engine, retained so the existing round-sheet widget can render history without a parallel schema.';

create table if not exists public.ratings (
  user_id uuid references public.profiles (id) on delete cascade,
  ladder_id text references public.ladders (id),
  rating int not null default 1200,
  peak_rating int not null default 1200,
  games int not null default 0,
  wins int not null default 0,
  losses int not null default 0,
  draws int not null default 0,
  streak int not null default 0,
  last_played_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, ladder_id)
);

-- This order serves the leaderboard and also covers the ladder foreign key.
create index if not exists ratings_ladder_rating_wins_idx
  on public.ratings (ladder_id, rating desc, wins desc);

create table if not exists public.rating_history (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  ladder_id text not null references public.ladders (id),
  match_id uuid references public.matches (id) on delete set null,
  rating_before int not null,
  rating_after int not null,
  rating_delta int not null,
  created_at timestamptz not null default now()
);

create index if not exists rating_history_user_created_at_idx
  on public.rating_history (user_id, created_at desc);

create index if not exists rating_history_match_id_idx
  on public.rating_history (match_id);

-- The two requested history indexes cover profile and match deletion. This
-- additional narrow index prevents a ladder deletion from scanning history.
create index if not exists rating_history_ladder_id_idx
  on public.rating_history (ladder_id);

-- K depends only on the player's pre-match state. Keeping this pure makes the
-- threshold behavior straightforward to review and safe to reuse in the
-- atomic rating transaction below.
create or replace function private.elo_k(p_games int, p_rating int)
returns int
language sql
immutable
security definer
set search_path = ''
as $function$
  select case
    when p_games < 30 then 40
    when p_rating >= 2400 then 10
    else 20
  end;
$function$;

revoke all privileges on function private.elo_k(int, int)
  from public, anon, authenticated;
grant execute on function private.elo_k(int, int) to service_role;

-- Hand-traced ELO checks for post-migration verification:
--
-- 1. Ranked 1v1, both players at 1200 with fewer than 30 games, side 0 wins.
--    E(side 0) = E(side 1) = 0.5 and K = 40, so the side-0 player
--    receives round(40 * (1 - 0.5)) = +20 and the side-1 player receives
--    round(40 * (0 - 0.5)) = -20.
--
-- 2. Ranked 2v2, side 0 averages 1300 and side 1 averages 1100, every
--    player with fewer than 30 games, side 0 wins. E(side 0) =
--    1 / (1 + 10 ^ ((1100 - 1300) / 400)) ~= 0.75975 and E(side 1)
--    ~= 0.24025. Every side-0 player receives
--    round(40 * (1 - 0.75975)) = round(9.61) = +10; every side-1
--    player receives round(40 * (0 - 0.24025)) = round(-9.61) = -10.
create or replace function public.record_match_result(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  recorded_match_id uuid := (p ->> 'match_id')::uuid;
  match_ladder_id text := p ->> 'ladder_id';
  match_winner_side int := (p ->> 'winner_side')::int;
  effective_is_ranked boolean :=
    coalesce((p ->> 'is_ranked')::boolean, false);
  human_participant_ids uuid[];
  rated boolean := false;
  deltas jsonb := '{}'::jsonb;
  rated_player record;
  player_delta int;
  player_rating_after int;
begin
  -- The host-generated UUIDv7 is the idempotency key. A retry after a lost
  -- response must return before touching any child or rating row.
  if exists (
    select 1
    from public.matches as existing_match
    where existing_match.id = recorded_match_id
  )
  then
    return pg_catalog.jsonb_build_object(
      'ok', true,
      'duplicate', true
    );
  end if;

  select array(
    select distinct (payload_player.player ->> 'user_id')::uuid
    from pg_catalog.jsonb_array_elements(
      coalesce(p -> 'players', '[]'::jsonb)
    ) as payload_player(player)
    where coalesce(
      (payload_player.player ->> 'is_bot')::boolean,
      false
    ) is false
      and payload_player.player ->> 'user_id' is not null
    order by (payload_player.player ->> 'user_id')::uuid
  )
  into human_participant_ids;

  insert into public.matches (
    id,
    room_id,
    room_code,
    ladder_id,
    profile_id,
    num_players,
    num_sides,
    match_target,
    seed,
    is_ranked,
    status,
    winner_side,
    final_scores,
    rounds_played,
    participant_ids,
    host_instance,
    started_at,
    ended_at,
    recorded_at
  )
  values (
    recorded_match_id,
    (p ->> 'room_id')::uuid,
    p ->> 'room_code',
    match_ladder_id,
    p ->> 'profile',
    (p ->> 'num_players')::int,
    (p ->> 'num_sides')::int,
    (p ->> 'match_target')::int,
    (p ->> 'seed')::bigint,
    effective_is_ranked,
    'completed'::public.match_status,
    match_winner_side,
    array(
      select final_score.score_value::int
      from pg_catalog.jsonb_array_elements_text(
        coalesce(p -> 'final_scores', '[]'::jsonb)
      ) as final_score(score_value)
    ),
    pg_catalog.jsonb_array_length(
      coalesce(p -> 'rounds', '[]'::jsonb)
    ),
    human_participant_ids,
    p ->> 'host_instance',
    (p ->> 'started_at')::timestamptz,
    (p ->> 'ended_at')::timestamptz,
    pg_catalog.now()
  );

  insert into public.match_sides (
    match_id,
    side,
    score_final,
    is_winner
  )
  select
    recorded_match_id,
    payload_side.side,
    payload_side.score_final,
    match_winner_side is not null
      and payload_side.side = match_winner_side
  from pg_catalog.jsonb_to_recordset(
    coalesce(p -> 'sides', '[]'::jsonb)
  ) as payload_side(
    side int,
    score_final int
  );

  insert into public.match_players (
    match_id,
    seat,
    side,
    user_id,
    is_bot,
    bot_level,
    display_name,
    result,
    disconnects,
    replaced_by_bot
  )
  select
    recorded_match_id,
    payload_player.seat,
    payload_player.side,
    payload_player.user_id,
    coalesce(payload_player.is_bot, false),
    payload_player.bot_level,
    payload_player.display_name,
    case
      when match_winner_side is null then 'draw'::public.match_result
      when payload_player.side = match_winner_side
        then 'win'::public.match_result
      else 'loss'::public.match_result
    end,
    coalesce(payload_player.disconnects, 0),
    coalesce(payload_player.replaced_by_bot, false)
  from pg_catalog.jsonb_to_recordset(
    coalesce(p -> 'players', '[]'::jsonb)
  ) as payload_player(
    seat int,
    side int,
    user_id uuid,
    is_bot boolean,
    bot_level text,
    display_name text,
    disconnects int,
    replaced_by_bot boolean
  );

  insert into public.match_rounds (
    match_id,
    round_index,
    reason,
    went_out_side,
    sheet,
    match_scores_after
  )
  select
    recorded_match_id,
    payload_round.round_index,
    payload_round.reason,
    payload_round.went_out_side,
    payload_round.sheet,
    array(
      select round_score.score_value::int
      from pg_catalog.jsonb_array_elements_text(
        coalesce(
          payload_round.match_scores_after,
          '[]'::jsonb
        )
      ) as round_score(score_value)
    )
  from pg_catalog.jsonb_to_recordset(
    coalesce(p -> 'rounds', '[]'::jsonb)
  ) as payload_round(
    round_index int,
    reason text,
    went_out_side int,
    sheet jsonb,
    match_scores_after jsonb
  );

  -- A bot-occupied seat changes the competitive conditions, so the match may
  -- be recorded but must never affect the human rating pool.
  if exists (
    select 1
    from public.match_players as match_player
    where match_player.match_id = recorded_match_id
      and match_player.is_bot
  )
  then
    effective_is_ranked := false;
  end if;

  -- Every side needs at least one human result to define a side rating and to
  -- prevent an empty team from manufacturing rating movement.
  if exists (
    select 1
    from public.match_sides as match_side
    where match_side.match_id = recorded_match_id
      and not exists (
        select 1
        from public.match_players as match_player
        where match_player.match_id = match_side.match_id
          and match_player.side = match_side.side
          and not match_player.is_bot
      )
  )
  then
    effective_is_ranked := false;
  end if;

  -- Guests are intentionally outside the durable competitive identity pool,
  -- even though they remain valid participants in recorded casual matches.
  if exists (
    select 1
    from public.match_players as match_player
    join public.profiles as profile
      on profile.id = match_player.user_id
    where match_player.match_id = recorded_match_id
      and not match_player.is_bot
      and profile.is_guest
  )
  then
    effective_is_ranked := false;
  end if;

  -- A human seat without an account has no durable rating key. Recording it is
  -- valid for casual history, but attempting an upsert would fabricate or lose
  -- identity, so it cannot be rated.
  if exists (
    select 1
    from public.match_players as match_player
    where match_player.match_id = recorded_match_id
      and not match_player.is_bot
      and match_player.user_id is null
  )
  then
    effective_is_ranked := false;
  end if;

  -- This v1 ELO model compares one team average against exactly one opposing
  -- team average. Other side counts remain recordable and can gain a separate
  -- multiplayer rating model later without silently reusing pairwise math.
  if (p ->> 'num_sides')::int <> 2
    or (
      select pg_catalog.count(*)
      from public.match_sides as match_side
      where match_side.match_id = recorded_match_id
    ) <> 2
  then
    effective_is_ranked := false;
  end if;

  -- Persist the guarded value rather than the host's assertion so later reads
  -- never describe an ineligible match as ranked.
  update public.matches
  set is_ranked = effective_is_ranked
  where id = recorded_match_id;

  if effective_is_ranked and match_ladder_id is not null then
    rated := true;

    -- Seed missing rows atomically before taking locks. This gives every
    -- participant a concrete 1200/0-games row and makes subsequent expectation,
    -- history, and upsert values agree even when two matches finish together.
    insert into public.ratings (
      user_id,
      ladder_id
    )
    select
      match_player.user_id,
      match_ladder_id
    from public.match_players as match_player
    where match_player.match_id = recorded_match_id
      and not match_player.is_bot
      and match_player.user_id is not null
    order by match_player.user_id
    on conflict (user_id, ladder_id) do nothing;

    -- A stable lock order prevents two simultaneous team results from
    -- deadlocking while preserving each match's before/after audit trail.
    perform current_rating.user_id
    from public.ratings as current_rating
    join public.match_players as match_player
      on match_player.user_id = current_rating.user_id
    where match_player.match_id = recorded_match_id
      and not match_player.is_bot
      and current_rating.ladder_id = match_ladder_id
    order by current_rating.user_id
    for update of current_rating;

    -- Expectation is computed once per side from the average of its current
    -- human ratings. K remains individual, so provisional players move faster
    -- without pretending that teammates necessarily share experience.
    --
    -- replaced_by_bot deliberately does not branch the formula in v1. A human
    -- who left keeps the loss if their side lost and the win if their side won;
    -- the team may have built its result before or around takeover. The field
    -- is retained as an explicit, revisitable policy knob, while bona fide bot
    -- seats are excluded above because they have no rating at all.
    for rated_player in
      with player_ratings as (
        select
          match_player.seat,
          match_player.side,
          match_player.user_id,
          match_player.result as player_result,
          current_rating.rating as rating_before,
          current_rating.peak_rating as peak_before,
          current_rating.games as games_before,
          current_rating.wins as wins_before,
          current_rating.losses as losses_before,
          current_rating.draws as draws_before,
          current_rating.streak as streak_before
        from public.match_players as match_player
        join public.ratings as current_rating
          on current_rating.user_id = match_player.user_id
          and current_rating.ladder_id = match_ladder_id
        where match_player.match_id = recorded_match_id
          and not match_player.is_bot
          and match_player.user_id is not null
      ),
      side_ratings as (
        select
          player_rating.side,
          pg_catalog.avg(
            player_rating.rating_before::numeric
          ) as side_rating
        from player_ratings as player_rating
        group by player_rating.side
      )
      select
        player_rating.*,
        case
          when match_winner_side is null then 0.5::numeric
          when player_rating.side = match_winner_side then 1::numeric
          else 0::numeric
        end as actual_score,
        1::numeric / (
          1::numeric
          + pg_catalog.power(
            10::numeric,
            (
              opposing_side.side_rating
              - player_side.side_rating
            ) / 400::numeric
          )
        ) as expected_score
      from player_ratings as player_rating
      join side_ratings as player_side
        on player_side.side = player_rating.side
      join side_ratings as opposing_side
        on opposing_side.side <> player_rating.side
      order by player_rating.user_id
    loop
      player_delta := pg_catalog.round(
        private.elo_k(
          rated_player.games_before,
          rated_player.rating_before
        )::numeric
        * (
          rated_player.actual_score
          - rated_player.expected_score
        )
      )::int;

      insert into public.ratings as current_rating (
        user_id,
        ladder_id,
        rating,
        peak_rating,
        games,
        wins,
        losses,
        draws,
        streak,
        last_played_at,
        updated_at
      )
      values (
        rated_player.user_id,
        match_ladder_id,
        rated_player.rating_before + player_delta,
        greatest(
          rated_player.peak_before,
          rated_player.rating_before + player_delta
        ),
        rated_player.games_before + 1,
        rated_player.wins_before
          + case
              when rated_player.player_result =
                'win'::public.match_result
                then 1
              else 0
            end,
        rated_player.losses_before
          + case
              when rated_player.player_result =
                'loss'::public.match_result
                then 1
              else 0
            end,
        rated_player.draws_before
          + case
              when rated_player.player_result =
                'draw'::public.match_result
                then 1
              else 0
            end,
        case
          when rated_player.player_result = 'win'::public.match_result
            then greatest(rated_player.streak_before, 0) + 1
          when rated_player.player_result = 'loss'::public.match_result
            then least(rated_player.streak_before, 0) - 1
          else 0
        end,
        pg_catalog.now(),
        pg_catalog.now()
      )
      on conflict (user_id, ladder_id)
      do update
      set
        rating = current_rating.rating + player_delta,
        peak_rating = greatest(
          current_rating.peak_rating,
          current_rating.rating + player_delta
        ),
        games = current_rating.games + 1,
        wins = current_rating.wins
          + case
              when rated_player.player_result =
                'win'::public.match_result
                then 1
              else 0
            end,
        losses = current_rating.losses
          + case
              when rated_player.player_result =
                'loss'::public.match_result
                then 1
              else 0
            end,
        draws = current_rating.draws
          + case
              when rated_player.player_result =
                'draw'::public.match_result
                then 1
              else 0
            end,
        streak = case
          when rated_player.player_result = 'win'::public.match_result
            then greatest(current_rating.streak, 0) + 1
          when rated_player.player_result = 'loss'::public.match_result
            then least(current_rating.streak, 0) - 1
          else 0
        end,
        last_played_at = pg_catalog.now(),
        updated_at = pg_catalog.now()
      returning rating
      into player_rating_after;

      insert into public.rating_history (
        user_id,
        ladder_id,
        match_id,
        rating_before,
        rating_after,
        rating_delta
      )
      values (
        rated_player.user_id,
        match_ladder_id,
        recorded_match_id,
        rated_player.rating_before,
        player_rating_after,
        player_delta
      );

      update public.match_players as rated_match_player
      set
        rating_before = rated_player.rating_before,
        rating_after = player_rating_after,
        rating_delta = player_delta
      where rated_match_player.match_id = recorded_match_id
        and rated_match_player.seat = rated_player.seat;

      deltas := deltas || pg_catalog.jsonb_build_object(
        rated_player.user_id::text,
        player_delta
      );
    end loop;
  end if;

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'rated', rated,
    'deltas', deltas
  );
end;
$function$;

revoke all privileges on function public.record_match_result(jsonb)
  from public, anon, authenticated;
grant execute on function public.record_match_result(jsonb) to service_role;

-- Materialized views cannot carry RLS policies. Keeping this one in private
-- prevents direct PostgREST exposure; authenticated reads cross only the two
-- bounded security-definer functions below. WITH DATA is required because the
-- first concurrent refresh needs an already-populated materialized view.
create materialized view if not exists private.leaderboard_mv as
select
  pg_catalog.row_number() over (
    partition by rating.ladder_id
    order by
      rating.rating desc,
      rating.wins desc,
      rating.user_id
  ) as rank,
  rating.ladder_id,
  rating.user_id,
  rating.rating,
  rating.games,
  rating.wins,
  rating.losses,
  rating.draws,
  profile.username,
  profile.display_name,
  profile.avatar_url
from public.ratings as rating
join public.profiles as profile
  on profile.id = rating.user_id
where rating.games >= 10
  and not profile.is_guest
with data;

comment on materialized view private.leaderboard_mv is
  'Private because materialized views cannot carry RLS; bounded security-definer readers are the only authenticated access path.';

-- REFRESH MATERIALIZED VIEW CONCURRENTLY requires at least one unique index.
-- Rank is unique within each ladder, so this is the refresh-enabling index.
create unique index if not exists leaderboard_mv_ladder_rank_unique
  on private.leaderboard_mv (ladder_id, rank);

create index if not exists leaderboard_mv_user_id_idx
  on private.leaderboard_mv (user_id);

revoke all privileges on table private.leaderboard_mv
  from public, anon, authenticated;
grant select on table private.leaderboard_mv to service_role;

create or replace function public.leaderboard(
  p_ladder_id text,
  p_limit int default 50,
  p_offset int default 0
)
returns table (
  rank bigint,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  rating int,
  games int,
  wins int,
  losses int,
  draws int
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    leaderboard_row.rank,
    leaderboard_row.user_id,
    leaderboard_row.username,
    leaderboard_row.display_name,
    leaderboard_row.avatar_url,
    leaderboard_row.rating,
    leaderboard_row.games,
    leaderboard_row.wins,
    leaderboard_row.losses,
    leaderboard_row.draws
  from private.leaderboard_mv as leaderboard_row
  where leaderboard_row.ladder_id = p_ladder_id
  order by leaderboard_row.rank
  limit least(coalesce(p_limit, 50), 200)
  offset coalesce(p_offset, 0);
$function$;

revoke all privileges on function public.leaderboard(text, int, int)
  from public, anon, authenticated;
grant execute on function public.leaderboard(text, int, int)
  to authenticated;

-- Percentile is 1 - (rank - 1) / population: first place is exactly 1, and
-- lower ranks decrease toward zero while remaining higher for better rank.
create or replace function public.my_rank(p_ladder_id text)
returns table (
  rank bigint,
  rating int,
  games int,
  percentile numeric
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    leaderboard_row.rank,
    leaderboard_row.rating,
    leaderboard_row.games,
    1::numeric
      - (
          leaderboard_row.rank::numeric
          - 1::numeric
        )
        / nullif(ladder_population.total_count, 0)::numeric
      as percentile
  from private.leaderboard_mv as leaderboard_row
  cross join (
    select pg_catalog.count(*) as total_count
    from private.leaderboard_mv as counted_row
    where counted_row.ladder_id = p_ladder_id
  ) as ladder_population
  where leaderboard_row.ladder_id = p_ladder_id
    and leaderboard_row.user_id = (select auth.uid());
$function$;

revoke all privileges on function public.my_rank(text)
  from public, anon, authenticated;
grant execute on function public.my_rank(text) to authenticated;

-- Five-minute staleness is enough for a social leaderboard and avoids adding
-- refresh work to the latency-sensitive match-recording transaction.
select cron.schedule(
  'leaderboard_refresh',
  '*/5 * * * *',
  $cron$
    refresh materialized view concurrently private.leaderboard_mv;
  $cron$
);

alter table public.matches enable row level security;
alter table public.match_sides enable row level security;
alter table public.match_players enable row level security;
alter table public.match_rounds enable row level security;
alter table public.ratings enable row level security;
alter table public.rating_history enable row level security;

-- Authenticated clients receive read paths only, and RLS decides which rows
-- are visible. All mutation remains behind record_match_result or direct
-- service_role access.
revoke all privileges on table
  public.matches,
  public.match_sides,
  public.match_players,
  public.match_rounds,
  public.ratings,
  public.rating_history
from public, anon, authenticated;

grant select on table
  public.matches,
  public.match_sides,
  public.match_players,
  public.match_rounds,
  public.ratings,
  public.rating_history
to authenticated;

grant all privileges on table
  public.matches,
  public.match_sides,
  public.match_players,
  public.match_rounds,
  public.ratings,
  public.rating_history
to service_role;

-- Identity sequences have independent privileges from their owning tables.
revoke all privileges on sequence public.rating_history_id_seq
  from public, anon, authenticated;
grant all privileges on sequence public.rating_history_id_seq to service_role;

drop policy if exists matches_select_authenticated on public.matches;
create policy matches_select_authenticated
on public.matches
for select
to authenticated
using (
  status = 'completed'
  or (select auth.uid()) = any (participant_ids)
);

-- These child policies inspect public.matches only. The matches policy never
-- reads back from a child, and no child policy reads itself or a sibling, so
-- there is no cycle and no security-definer recursion breaker is needed.
drop policy if exists match_sides_select_authenticated
  on public.match_sides;
create policy match_sides_select_authenticated
on public.match_sides
for select
to authenticated
using (
  exists (
    select 1
    from public.matches as match
    where match.id = match_sides.match_id
      and (
        match.status = 'completed'
        or (select auth.uid()) = any (match.participant_ids)
      )
  )
);

drop policy if exists match_players_select_authenticated
  on public.match_players;
create policy match_players_select_authenticated
on public.match_players
for select
to authenticated
using (
  exists (
    select 1
    from public.matches as match
    where match.id = match_players.match_id
      and (
        match.status = 'completed'
        or (select auth.uid()) = any (match.participant_ids)
      )
  )
);

drop policy if exists match_rounds_select_authenticated
  on public.match_rounds;
create policy match_rounds_select_authenticated
on public.match_rounds
for select
to authenticated
using (
  exists (
    select 1
    from public.matches as match
    where match.id = match_rounds.match_id
      and (
        match.status = 'completed'
        or (select auth.uid()) = any (match.participant_ids)
      )
  )
);

-- Current ratings are leaderboard-adjacent facts rather than private history.
drop policy if exists ratings_select_authenticated on public.ratings;
create policy ratings_select_authenticated
on public.ratings
for select
to authenticated
using (true);

drop policy if exists rating_history_select_own
  on public.rating_history;
create policy rating_history_select_own
on public.rating_history
for select
to authenticated
using ((select auth.uid()) = user_id);

-- 0001 promised to retain stale guests once match history existed. Scheduling
-- the same name replaces the pg_cron 1.6 job definition, adding that promised
-- guard alongside the original legacy-upload protection without editing 0001.
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
      )
      and not exists (
        select 1
        from public.match_players mp
        where mp.user_id = u.id
      );
  $cron$
);
