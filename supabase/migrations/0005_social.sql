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
      and enum_type.typname = 'friend_request_status'
  )
  then
    create type public.friend_request_status as enum (
      'pending',
      'accepted',
      'declined',
      'cancelled'
    );
  end if;
end;
$do$;

create table if not exists public.friend_requests (
  id bigint generated always as identity primary key,
  requester_id uuid not null
    references public.profiles (id) on delete cascade,
  addressee_id uuid not null
    references public.profiles (id) on delete cascade,
  status public.friend_request_status not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint friend_requests_not_self_check
    check (requester_id <> addressee_id)
);

-- This enforces one live ask per pair-direction. Once a request is declined or
-- cancelled, the partial index no longer covers it, so a new ask is possible.
create unique index if not exists friend_requests_pending_pair_unique
  on public.friend_requests (requester_id, addressee_id)
  where status = 'pending';

-- These are the two query directions: requests sent to me and requests I sent.
-- Their leading columns also cover both profile foreign keys for cascades.
create index if not exists friend_requests_addressee_status_idx
  on public.friend_requests (addressee_id, status);

create index if not exists friend_requests_requester_status_idx
  on public.friend_requests (requester_id, status);

create table if not exists public.friendships (
  user_low uuid not null
    references public.profiles (id) on delete cascade,
  user_high uuid not null
    references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_low, user_high),
  constraint friendships_canonical_order_check
    check (user_low < user_high)
);

-- The primary key already covers lookups and cascades by user_low as its
-- leading column. user_high needs its own index for the other direction.
create index if not exists friendships_user_high_idx
  on public.friendships (user_high);

-- One canonical row gives friendship creation and deletion a single write
-- path. Two mirrored rows could drift out of sync; enforcing user_low <
-- user_high makes that inconsistent state structurally impossible.
comment on table public.friendships is
  'One canonical row per friendship, ordered by user_low < user_high, avoids mirrored rows that could drift out of sync.';

create table if not exists public.blocks (
  blocker_id uuid not null
    references public.profiles (id) on delete cascade,
  blocked_id uuid not null
    references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_not_self_check
    check (blocker_id <> blocked_id)
);

-- The primary key covers blocker-side lookups and cascades. PostgreSQL does
-- not index the blocked-side foreign key automatically.
create index if not exists blocks_blocked_id_idx
  on public.blocks (blocked_id);

alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.blocks enable row level security;

revoke all privileges on table
  public.friend_requests,
  public.friendships,
  public.blocks
from public, anon, authenticated;
grant select on table
  public.friend_requests,
  public.friendships,
  public.blocks
to authenticated;
grant all privileges on table
  public.friend_requests,
  public.friendships,
  public.blocks
to service_role;

-- Social writes are deliberately RPC-only. Direct reads expose only requests
-- involving the caller, friendships involving the caller, and blocks created
-- by the caller.
drop policy if exists friend_requests_select_involved
  on public.friend_requests;
create policy friend_requests_select_involved
on public.friend_requests
for select
to authenticated
using (
  requester_id = (select auth.uid())
  or addressee_id = (select auth.uid())
);

drop policy if exists friendships_select_involved
  on public.friendships;
create policy friendships_select_involved
on public.friendships
for select
to authenticated
using (
  user_low = (select auth.uid())
  or user_high = (select auth.uid())
);

drop policy if exists blocks_select_own
  on public.blocks;
create policy blocks_select_own
on public.blocks
for select
to authenticated
using (blocker_id = (select auth.uid()));

create or replace view public.friends
with (security_invoker = true)
as
select
  friendship.user_low as user_id,
  friendship.user_high as friend_id
from public.friendships as friendship
union all
select
  friendship.user_high as user_id,
  friendship.user_low as friend_id
from public.friendships as friendship;

-- Views otherwise use their owner's privileges and bypass underlying RLS for
-- every caller. security_invoker = true is what makes this convenience view
-- respect the querying user's own friendship-row visibility.
comment on view public.friends is
  'Two-way friendship projection. security_invoker is required so callers retain the underlying friendships RLS visibility.';

revoke all privileges on table public.friends
  from public, anon, authenticated;
grant select on table public.friends to authenticated;
grant all privileges on table public.friends to service_role;

create or replace function private.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.friendships as friendship
    where friendship.user_low = least(a, b)
      and friendship.user_high = greatest(a, b)
  );
$function$;

-- As with 0002's private.is_room_seat_holder, a policy that calls a
-- private-schema helper needs authenticated to hold EXECUTE on that specific
-- function even though authenticated has no USAGE grant on the private schema.
revoke all privileges on function private.are_friends(uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.are_friends(uuid, uuid) to authenticated;

create table if not exists public.user_presence (
  user_id uuid primary key
    references public.profiles (id) on delete cascade,
  status text not null default 'online'
    constraint user_presence_status_check
      check (status in ('online', 'in_lobby', 'in_game', 'away')),
  room_id uuid references public.rooms (id) on delete set null,
  last_seen_at timestamptz not null default now()
);

-- The reaper uses this range scan to remove old housekeeping rows.
create index if not exists user_presence_last_seen_at_idx
  on public.user_presence (last_seen_at desc);

-- PostgreSQL does not automatically index foreign keys; room deletion should
-- not have to scan every presence row before setting matching room IDs null.
create index if not exists user_presence_room_id_idx
  on public.user_presence (room_id);

-- This is deliberately a plain table rather than Supabase Realtime Presence.
-- "Which friends are online?" needs one SQL query joined to friendships;
-- Realtime Presence is an ephemeral in-memory channel construct and cannot
-- provide that joined answer. There is no offline status: last_seen_at older
-- than 90 seconds means offline. Clients should heartbeat about every 30
-- seconds, so three missed heartbeats make a user stale.
comment on table public.user_presence is
  'Queryable friend presence. Rows older than 90 seconds are offline; clients should heartbeat roughly every 30 seconds.';

alter table public.user_presence enable row level security;

revoke all privileges on table public.user_presence
  from public, anon, authenticated;
grant select, insert, update on table public.user_presence to authenticated;
grant all privileges on table public.user_presence to service_role;

-- There is deliberately no client DELETE grant. Stale rows age out of every
-- read after 90 seconds and the presence_reap cron caps long-term table growth.
drop policy if exists user_presence_select_self_or_friend
  on public.user_presence;
create policy user_presence_select_self_or_friend
on public.user_presence
for select
to authenticated
using (
  user_id = (select auth.uid())
  or (select private.are_friends((select auth.uid()), user_id))
);

drop policy if exists user_presence_insert_own
  on public.user_presence;
create policy user_presence_insert_own
on public.user_presence
for insert
to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists user_presence_update_own
  on public.user_presence;
create policy user_presence_update_own
on public.user_presence
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create or replace function public.accept_friend_request(
  p_request_id bigint
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  requester uuid := (select auth.uid());
  pending_request public.friend_requests%rowtype;
begin
  select friend_request.*
  into pending_request
  from public.friend_requests as friend_request
  where friend_request.id = p_request_id
    and friend_request.addressee_id = requester
    and friend_request.status = 'pending'
  for update;

  if not found then
    raise exception using
      errcode = '42501',
      message =
        'Pending friend request not found or caller is not its addressee.';
  end if;

  update public.friend_requests
  set
    status = 'accepted',
    responded_at = pg_catalog.now()
  where id = pending_request.id;

  insert into public.friendships (user_low, user_high)
  values (
    least(pending_request.requester_id, pending_request.addressee_id),
    greatest(pending_request.requester_id, pending_request.addressee_id)
  )
  on conflict do nothing;
end;
$function$;

revoke all privileges on function public.accept_friend_request(bigint)
  from public, anon, authenticated;
grant execute on function public.accept_friend_request(bigint)
  to authenticated;

create or replace function public.decline_friend_request(
  p_request_id bigint
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  requester uuid := (select auth.uid());
  pending_request public.friend_requests%rowtype;
begin
  select friend_request.*
  into pending_request
  from public.friend_requests as friend_request
  where friend_request.id = p_request_id
    and friend_request.addressee_id = requester
    and friend_request.status = 'pending'
  for update;

  if not found then
    raise exception using
      errcode = '42501',
      message =
        'Pending friend request not found or caller is not its addressee.';
  end if;

  update public.friend_requests
  set
    status = 'declined',
    responded_at = pg_catalog.now()
  where id = pending_request.id;
end;
$function$;

revoke all privileges on function public.decline_friend_request(bigint)
  from public, anon, authenticated;
grant execute on function public.decline_friend_request(bigint)
  to authenticated;

create or replace function public.cancel_friend_request(
  p_request_id bigint
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  requester uuid := (select auth.uid());
  pending_request public.friend_requests%rowtype;
begin
  select friend_request.*
  into pending_request
  from public.friend_requests as friend_request
  where friend_request.id = p_request_id
    and friend_request.requester_id = requester
    and friend_request.status = 'pending'
  for update;

  if not found then
    raise exception using
      errcode = '42501',
      message =
        'Pending friend request not found or caller is not its requester.';
  end if;

  update public.friend_requests
  set
    status = 'cancelled',
    responded_at = pg_catalog.now()
  where id = pending_request.id;
end;
$function$;

revoke all privileges on function public.cancel_friend_request(bigint)
  from public, anon, authenticated;
grant execute on function public.cancel_friend_request(bigint)
  to authenticated;

create or replace function public.request_friend(p_addressee uuid)
returns public.friend_requests
language plpgsql
security definer
set search_path = ''
as $function$
declare
  requesting_user_id uuid := (select auth.uid());
  requested_friendship public.friend_requests%rowtype;
begin
  if requesting_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required to request a friend.';
  end if;

  if p_addressee = requesting_user_id then
    raise exception
      'A user cannot send a friend request to themselves.';
  end if;

  if exists (
    select 1
    from public.blocks as user_block
    where (
      user_block.blocker_id = requesting_user_id
      and user_block.blocked_id = p_addressee
    )
    or (
      user_block.blocker_id = p_addressee
      and user_block.blocked_id = requesting_user_id
    )
  )
  then
    raise exception
      'A friend request cannot be sent while either user blocks the other.';
  end if;

  if private.are_friends(requesting_user_id, p_addressee) then
    raise exception
      'These users are already friends.';
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
      message = 'Create an account to add friends.';
  end if;

  if coalesce(
    (
      select profile.is_guest
      from public.profiles as profile
      where profile.id = requesting_user_id
    ),
    true
  )
  then
    raise exception using
      errcode = '42501',
      message = 'Create an account to add friends.';
  end if;

  select mirror_request.*
  into requested_friendship
  from public.friend_requests as mirror_request
  where mirror_request.requester_id = p_addressee
    and mirror_request.addressee_id = requesting_user_id
    and mirror_request.status = 'pending'
  for update;

  if found then
    -- Two people asking each other at roughly the same time means yes.
    -- Converting the mirror ask into acceptance is a small kindness instead
    -- of leaving both users stuck with parallel pending requests.
    update public.friend_requests
    set
      status = 'accepted',
      responded_at = pg_catalog.now()
    where id = requested_friendship.id
    returning *
    into requested_friendship;

    insert into public.friendships (user_low, user_high)
    values (
      least(
        requested_friendship.requester_id,
        requested_friendship.addressee_id
      ),
      greatest(
        requested_friendship.requester_id,
        requested_friendship.addressee_id
      )
    )
    on conflict do nothing;

    return requested_friendship;
  end if;

  -- The partial unique index is the anti-duplicate mechanism. A genuine
  -- same-direction duplicate should raise unique_violation; the mirror case
  -- above is the only conflicting direction that receives special treatment.
  insert into public.friend_requests (requester_id, addressee_id)
  values (requesting_user_id, p_addressee)
  returning *
  into requested_friendship;

  return requested_friendship;
end;
$function$;

revoke all privileges on function public.request_friend(uuid)
  from public, anon, authenticated;
grant execute on function public.request_friend(uuid) to authenticated;

create or replace function public.block_user(p_blocked uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  blocker uuid := (select auth.uid());
begin
  insert into public.blocks (blocker_id, blocked_id)
  values (blocker, p_blocked)
  on conflict do nothing;

  delete from public.friendships
  where user_low = least(blocker, p_blocked)
    and user_high = greatest(blocker, p_blocked);

  update public.friend_requests
  set
    status = 'cancelled',
    responded_at = pg_catalog.now()
  where status = 'pending'
    and (
      (
        requester_id = blocker
        and addressee_id = p_blocked
      )
      or (
        requester_id = p_blocked
        and addressee_id = blocker
      )
    );
end;
$function$;

revoke all privileges on function public.block_user(uuid)
  from public, anon, authenticated;
grant execute on function public.block_user(uuid) to authenticated;

create or replace function public.unblock_user(p_blocked uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  delete from public.blocks
  where blocker_id = (select auth.uid())
    and blocked_id = p_blocked;
end;
$function$;

revoke all privileges on function public.unblock_user(uuid)
  from public, anon, authenticated;
grant execute on function public.unblock_user(uuid) to authenticated;

-- Polling this RPC every roughly 10-30 seconds is a better fit at this
-- project's scale than N per-friend Realtime subscriptions per client.
-- Postgres Changes and Presence channels do not naturally produce one joined,
-- computed answer across many friends the way a single RPC call does.
create or replace function public.friends_online()
returns table (
  friend_id uuid,
  display_name text,
  username text,
  status text,
  room_id uuid,
  last_seen_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    friendship.friend_id,
    profile.display_name,
    profile.username,
    friend_presence.status,
    friend_presence.room_id,
    friend_presence.last_seen_at
  from public.friends as friendship
  join public.user_presence as friend_presence
    on friend_presence.user_id = friendship.friend_id
  join public.profiles as profile
    on profile.id = friendship.friend_id
  where friendship.user_id = (select auth.uid())
    and friend_presence.last_seen_at
      > pg_catalog.now() - interval '90 seconds';
$function$;

revoke all privileges on function public.friends_online()
  from public, anon, authenticated;
grant execute on function public.friends_online() to authenticated;

create table if not exists public.room_invites (
  id bigint generated always as identity primary key,
  room_id uuid not null
    references public.rooms (id) on delete cascade,
  inviter_id uuid not null
    references public.profiles (id) on delete cascade,
  invitee_id uuid not null
    references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '10 minutes',
  accepted_at timestamptz
);

create index if not exists room_invites_invitee_expires_at_idx
  on public.room_invites (invitee_id, expires_at desc);

-- PostgreSQL does not automatically index foreign keys. The invitee index
-- above covers that direction; these cover room and inviter cascades/lookups.
create index if not exists room_invites_room_id_idx
  on public.room_invites (room_id);

create index if not exists room_invites_inviter_id_idx
  on public.room_invites (inviter_id);

-- Postgres Changes applies the table's RLS SELECT policy to subscribers, so
-- only the inviter and invitee can receive an invite-row change.
do $do$
begin
  if not exists (
    select 1
    from pg_catalog.pg_publication_tables as publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'room_invites'
  )
  then
    alter publication supabase_realtime
      add table public.room_invites;
  end if;
end;
$do$;

alter table public.room_invites enable row level security;

revoke all privileges on table public.room_invites
  from public, anon, authenticated;
grant select on table public.room_invites to authenticated;
grant all privileges on table public.room_invites to service_role;

-- There are no direct client writes. invite_to_room is the only insert path
-- and runs as a controlled security-definer RPC.
drop policy if exists room_invites_select_involved
  on public.room_invites;
create policy room_invites_select_involved
on public.room_invites
for select
to authenticated
using (
  invitee_id = (select auth.uid())
  or inviter_id = (select auth.uid())
);

create or replace function public.invite_to_room(
  p_room_code text,
  p_invitee uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  inviter uuid := (select auth.uid());
  invited_room public.rooms%rowtype;
begin
  select candidate_room.*
  into invited_room
  from public.rooms as candidate_room
  where pg_catalog.upper(p_room_code) = pg_catalog.upper(candidate_room.code)
    and candidate_room.status in ('open', 'in_progress');

  if not found then
    raise exception
      'The requested room does not exist or is no longer joinable.';
  end if;

  if not exists (
    select 1
    from public.room_seats as room_seat
    where room_seat.room_id = invited_room.id
      and room_seat.user_id = inviter
  )
  then
    raise exception using
      errcode = '42501',
      message = 'Only a current room seat holder may invite a friend.';
  end if;

  if not private.are_friends(inviter, p_invitee) then
    raise exception
      'Only friends may be invited to a room.';
  end if;

  if exists (
    select 1
    from public.blocks as user_block
    where (
      user_block.blocker_id = inviter
      and user_block.blocked_id = p_invitee
    )
    or (
      user_block.blocker_id = p_invitee
      and user_block.blocked_id = inviter
    )
  )
  then
    raise exception
      'A room invite cannot be sent while either user blocks the other.';
  end if;

  insert into public.room_invites (room_id, inviter_id, invitee_id)
  values (invited_room.id, inviter, p_invitee);

  -- Do not reserve or assign a seat at invite time. Occupying a seat for
  -- someone who may never accept would block every other prospective joiner;
  -- accept_room_invite performs the short reservation only on acceptance.
end;
$function$;

revoke all privileges on function public.invite_to_room(text, uuid)
  from public, anon, authenticated;
grant execute on function public.invite_to_room(text, uuid)
  to authenticated;

create or replace function public.accept_room_invite(
  p_invite_id bigint
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  invitee uuid := (select auth.uid());
  locked_invite public.room_invites%rowtype;
  locked_room public.rooms%rowtype;
  reserved_seat integer;
begin
  select room_invite.*
  into locked_invite
  from public.room_invites as room_invite
  where room_invite.id = p_invite_id
  for update;

  if not found then
    raise exception
      'The requested room invite does not exist.';
  end if;

  if locked_invite.invitee_id is distinct from invitee
    or pg_catalog.now() >= locked_invite.expires_at
    or locked_invite.accepted_at is not null
  then
    raise exception using
      errcode = '42501',
      message =
        'Room invite is expired, already accepted, or belongs to another user.';
  end if;

  select candidate_room.*
  into locked_room
  from public.rooms as candidate_room
  where candidate_room.id = locked_invite.room_id
  for update;

  if not found
    or locked_room.status not in ('open', 'in_progress')
  then
    raise exception
      'The invited room is no longer joinable.';
  end if;

  select room_seat.seat
  into reserved_seat
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

  if not found then
    raise exception
      'room is full';
  end if;

  update public.room_seats
  set
    user_id = (select auth.uid()),
    reserved_until = pg_catalog.now() + interval '90 seconds'
  where room_id = locked_room.id
    and seat = reserved_seat;

  -- This reuses 0004's create_matchmade_room reservation-as-authorization
  -- seam. 0002's authorize_room_join treats an existing room_seats.user_id
  -- match as an admission ticket, so a short 90-second user_id reservation
  -- grants entry without a separate invite-specific authorization path.
  update public.room_invites
  set accepted_at = pg_catalog.now()
  where id = locked_invite.id;

  return locked_room.code;
end;
$function$;

revoke all privileges on function public.accept_room_invite(bigint)
  from public, anon, authenticated;
grant execute on function public.accept_room_invite(bigint)
  to authenticated;

-- The 90-second freshness rule already makes stale rows harmless for every
-- read path, including friends_online and RLS-protected presence reads. This
-- reaper exists only to cap table growth over time, not for correctness.
select cron.schedule(
  'presence_reap',
  '*/10 * * * *',
  $cron$
    delete from public.user_presence where last_seen_at < pg_catalog.now() - interval '1 day';
  $cron$
);
