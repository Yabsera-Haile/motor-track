-- Motor Track: initial schema.
--
-- All business rules live here so every phone sees the same numbers:
--   * dues: one row per vehicle per period (daily / weekly / monthly), rest days included
--   * payments are applied to dues oldest-first (recompute_vehicle)
--   * a 5-minute cron tick creates dues and raises alerts
--   * alerts are pushed to every phone through the `push` Edge Function
--
-- Dates and times are Africa/Kigali. private.now() can be overridden with
-- `set app.now = '...'` so tests can run at a fixed moment.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

create schema if not exists private;
grant usage on schema private to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Time and formatting helpers
-- ---------------------------------------------------------------------------

create function private.now() returns timestamptz
language sql stable as $$
  select coalesce(nullif(current_setting('app.now', true), '')::timestamptz, now())
$$;

create function private.tz() returns text
language sql immutable as $$ select 'Africa/Kigali' $$;

create function private.local_date(ts timestamptz) returns date
language sql stable as $$ select (ts at time zone private.tz())::date $$;

create function private.today() returns date
language sql stable as $$ select private.local_date(private.now()) $$;

-- A local wall-clock moment in Kigali as a timestamptz.
create function private.at_local(d date, t time) returns timestamptz
language sql stable as $$ select (d + t) at time zone private.tz() $$;

-- The first instant after the given day ends.
create function private.day_end(d date) returns timestamptz
language sql stable as $$ select private.at_local(d + 1, time '00:00') $$;

-- MoMo usernames are compared ignoring case and repeated spaces.
create function private.norm_name(n text) returns text
language sql immutable as $$ select upper(regexp_replace(btrim(coalesce(n, '')), '\s+', ' ', 'g')) $$;

create function private.rwf(n bigint) returns text
language sql stable as $$ select to_char(n, 'FM999,999,999,990') $$;

create function private.short_date(d date) returns text
language sql stable as $$ select to_char(d, 'Dy FMDD Mon') $$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create type public.frequency as enum ('daily', 'weekly', 'monthly');
create type public.payment_source as enum ('momo', 'cash', 'other');
create type public.alert_type as enum (
  'unpaid_deadline', 'short_deadline', 'missed_day', 'overpayment', 'reader_silent'
);

create table public.settings (
  id boolean primary key default true check (id),
  deadline_time time not null default '20:00',
  -- When the "day missed" alert fires, relative to the end of the due day:
  -- -1 hour = 23:00 same day, 0 = midnight, 7 hours = 07:00 next day.
  missed_alert_offset interval not null default '7 hours'
    check (missed_alert_offset between interval '-12 hours' and interval '12 hours'),
  overpay_alerts boolean not null default true,
  reader_silence_hours integer not null default 6 check (reader_silence_hours between 1 and 72),
  updated_at timestamptz not null default now()
);
insert into public.settings default values;

-- The team code is hashed and kept out of the API entirely.
create table private.team (
  id boolean primary key default true check (id),
  code_hash text not null
);

create table private.join_attempts (
  uid uuid,
  ok boolean not null,
  at timestamptz not null default now()
);
create index on private.join_attempts (uid, at);

create table public.members (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 60),
  momo_number text,
  created_at timestamptz not null default now()
);
create unique index members_name_key on public.members (lower(btrim(name)));

create table public.sms_templates (
  id uuid primary key default gen_random_uuid(),
  sender text not null,
  -- Literal text with {amount} {name} {phone} {datetime} {txid} {skip} placeholders.
  pattern text not null,
  sample text not null,
  created_by_member_id uuid references public.members (id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.devices (
  id uuid primary key references auth.users (id) on delete cascade,
  member_id uuid not null references public.members (id) on delete cascade,
  platform text,
  fcm_token text,
  is_reader boolean not null default false,
  reader_sender text,
  template_id uuid references public.sms_templates (id) on delete set null,
  last_checked_at timestamptz,
  unreadable_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.devices (member_id);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  driver_name text not null check (length(btrim(driver_name)) between 1 and 80),
  plate text not null check (length(btrim(plate)) between 2 and 20),
  phone text not null default '',
  momo_usernames text[] not null default '{}',
  amount integer not null check (amount > 0),
  frequency public.frequency not null default 'daily',
  -- Weekly / monthly only: the first due date; later ones repeat from it.
  first_due_date date,
  -- ISO weekdays, 1 = Monday ... 7 = Sunday. Daily only.
  rest_weekdays smallint[] not null default '{}'
    check (rest_weekdays <@ '{1,2,3,4,5,6,7}'::smallint[]),
  start_date date not null default private.today(),
  is_active boolean not null default true,
  deleted_at timestamptz,
  -- Last day the dues generator has covered. Internal.
  dues_through date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (frequency = 'daily' or first_due_date is not null)
);
create unique index vehicles_plate_key on public.vehicles (upper(replace(plate, ' ', '')))
  where deleted_at is null;

create table public.dues (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  kind text not null check (kind in ('due', 'rest')),
  period_start date not null,
  period_end date not null,
  due_date date not null,
  amount_due integer not null check (amount_due >= 0),
  amount_paid integer not null default 0 check (amount_paid >= 0),
  fully_paid_at timestamptz,
  created_at timestamptz not null default private.now(),
  unique (vehicle_id, due_date)
);
create index on public.dues (due_date);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles (id) on delete restrict,
  amount integer not null check (amount > 0),
  paid_at timestamptz not null default private.now(),
  source public.payment_source not null,
  sender_name text,
  sender_phone text,
  tx_id text unique,
  held_by_member_id uuid references public.members (id) on delete set null,
  recorded_by_member_id uuid references public.members (id) on delete set null,
  note text,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);
create index on public.payments (vehicle_id, paid_at);
create index on public.payments (paid_at);

-- Written only by recompute_vehicle(): how much of each payment went to each due.
create table public.allocations (
  payment_id uuid not null references public.payments (id) on delete cascade,
  due_id uuid not null references public.dues (id) on delete cascade,
  amount integer not null check (amount > 0),
  primary key (payment_id, due_id)
);
create index on public.allocations (due_id);

create table public.deposits (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members (id) on delete restrict,
  amount integer not null check (amount > 0),
  fee integer not null default 0 check (fee >= 0),
  deposited_on date not null default private.today(),
  reference text,
  note text,
  recorded_by_member_id uuid references public.members (id) on delete set null,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);
create index on public.deposits (member_id);

create table public.alerts (
  id uuid primary key default gen_random_uuid(),
  type public.alert_type not null,
  vehicle_id uuid references public.vehicles (id) on delete cascade,
  due_id uuid references public.dues (id) on delete cascade,
  payment_id uuid references public.payments (id) on delete cascade,
  device_id uuid references public.devices (id) on delete cascade,
  title text not null,
  body text not null,
  data jsonb not null default '{}',
  push boolean not null default true,
  dedupe_key text not null unique,
  created_at timestamptz not null default private.now(),
  resolved_at timestamptz
);
create index on public.alerts (created_at desc);

-- ---------------------------------------------------------------------------
-- Membership
-- ---------------------------------------------------------------------------

create function private.current_member_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select member_id from public.devices where id = auth.uid()
$$;

create function private.is_member() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.devices where id = auth.uid())
$$;

-- Run once from the SQL editor: select private.set_team_code('your code');
create function private.set_team_code(p_code text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if length(coalesce(p_code, '')) < 8 then
    raise exception 'The team code must be at least 8 characters';
  end if;
  insert into private.team (code_hash) values (extensions.crypt(p_code, extensions.gen_salt('bf')))
  on conflict (id) do update set code_hash = excluded.code_hash;
end $$;

-- Returns an error code, or null when the code is right. Records failures
-- (without raising, so the record survives) and locks out after 10 in an hour.
create function private.team_code_error(p_code text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  h text;
  failures integer;
begin
  if auth.uid() is null then
    return 'sign_in_required';
  end if;
  select count(*) into failures from private.join_attempts
  where uid = auth.uid() and not ok and at > now() - interval '1 hour';
  if failures >= 10 then
    return 'too_many_attempts';
  end if;
  select code_hash into h from private.team;
  if h is null then
    return 'team_code_not_set';
  end if;
  if extensions.crypt(coalesce(p_code, ''), h) <> h then
    insert into private.join_attempts (uid, ok) values (auth.uid(), false);
    return 'wrong_team_code';
  end if;
  insert into private.join_attempts (uid, ok) values (auth.uid(), true);
  return null;
end $$;

-- Names already on the team, for "I've joined before".
create function public.team_members(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  err text := private.team_code_error(p_code);
begin
  if err is not null then
    return jsonb_build_object('ok', false, 'error', err);
  end if;
  return jsonb_build_object('ok', true, 'members', coalesce(
    (select jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name) from public.members), '[]'));
end $$;

-- Links this phone (its anonymous auth user) to a new or existing member.
create function public.join_team(p_code text, p_name text default null, p_member_id uuid default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  err text := private.team_code_error(p_code);
  m public.members;
begin
  if err is not null then
    return jsonb_build_object('ok', false, 'error', err);
  end if;
  if p_member_id is not null then
    select * into m from public.members where id = p_member_id;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'member_not_found');
    end if;
  else
    if coalesce(btrim(p_name), '') = '' then
      return jsonb_build_object('ok', false, 'error', 'name_required');
    end if;
    if exists (select 1 from public.members where lower(btrim(name)) = lower(btrim(p_name))) then
      return jsonb_build_object('ok', false, 'error', 'name_taken');
    end if;
    insert into public.members (name) values (btrim(p_name)) returning * into m;
  end if;
  insert into public.devices (id, member_id) values (auth.uid(), m.id)
  on conflict (id) do update set member_id = excluded.member_id, updated_at = now();
  return jsonb_build_object('ok', true, 'member', to_jsonb(m));
end $$;

-- ---------------------------------------------------------------------------
-- Dues and oldest-debt-first allocation
-- ---------------------------------------------------------------------------

create function private.nth_due(freq public.frequency, first date, k integer) returns date
language sql immutable as $$
  select case freq
    when 'weekly' then first + 7 * k
    else (first + make_interval(months => k))::date
  end
$$;

-- Creates the dues a vehicle should have up to today. Returns how many it made.
create function private.ensure_dues(p_vehicle uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v public.vehicles;
  t date := private.today();
  from_d date;
  d date;
  k integer;
  dd date;
  ps date;
  is_rest boolean;
  rc integer;
  made integer := 0;
begin
  select * into v from public.vehicles where id = p_vehicle for update;
  if not found or v.deleted_at is not null or not v.is_active then
    return 0;
  end if;
  from_d := greatest(v.start_date, coalesce(v.dues_through + 1, v.start_date));
  if from_d > t then
    return 0;
  end if;

  if v.frequency = 'daily' then
    for d in select g::date from generate_series(from_d, t, interval '1 day') g loop
      is_rest := extract(isodow from d)::smallint = any (v.rest_weekdays);
      insert into public.dues (vehicle_id, kind, period_start, period_end, due_date, amount_due)
      values (v.id, case when is_rest then 'rest' else 'due' end, d, d, d,
              case when is_rest then 0 else v.amount end)
      on conflict (vehicle_id, due_date) do nothing;
      get diagnostics rc = row_count;
      made := made + rc;
    end loop;
  else
    -- A weekly / monthly due is created when its period starts, so the
    -- card can show "this week: 0 of 42,000" before the due date.
    k := 0;
    loop
      dd := private.nth_due(v.frequency, v.first_due_date, k);
      ps := case when v.frequency = 'weekly' then dd - 6
                 else private.nth_due(v.frequency, v.first_due_date, k - 1) + 1 end;
      exit when ps > t or k > 5000;
      if dd >= from_d and dd >= v.start_date then
        insert into public.dues (vehicle_id, kind, period_start, period_end, due_date, amount_due)
        values (v.id, 'due', greatest(ps, v.start_date), dd, dd, v.amount)
        on conflict (vehicle_id, due_date) do nothing;
        get diagnostics rc = row_count;
        made := made + rc;
      end if;
      k := k + 1;
    end loop;
  end if;

  update public.vehicles set dues_through = t where id = v.id;
  return made;
end $$;

-- Rebuilds a vehicle's allocations from scratch: payments in time order fill
-- the oldest due that isn't fully paid. Money left over is credit and fills
-- future dues as they are created.
create function private.recompute_vehicle(p_vehicle uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  p record;
  d record;
  remaining integer;
  take integer;
begin
  perform private.ensure_dues(p_vehicle);
  perform 1 from public.vehicles where id = p_vehicle for update;

  delete from public.allocations a using public.dues du
  where a.due_id = du.id and du.vehicle_id = p_vehicle;
  update public.dues set amount_paid = 0, fully_paid_at = null
  where vehicle_id = p_vehicle and (amount_paid <> 0 or fully_paid_at is not null);

  for p in
    select id, amount, paid_at from public.payments
    where vehicle_id = p_vehicle and deleted_at is null
    order by paid_at, created_at, id
  loop
    remaining := p.amount;
    for d in
      select id, amount_due, amount_paid from public.dues
      where vehicle_id = p_vehicle and amount_paid < amount_due
      order by due_date, id
    loop
      exit when remaining = 0;
      take := least(remaining, d.amount_due - d.amount_paid);
      update public.dues
      set amount_paid = amount_paid + take,
          fully_paid_at = case when amount_paid + take >= amount_due then p.paid_at end
      where id = d.id;
      insert into public.allocations (payment_id, due_id, amount) values (p.id, d.id, take);
      remaining := remaining - take;
    end loop;
  end loop;

  -- Deadline and missed-day alerts resolve once their due is paid in full.
  update public.alerts a set resolved_at = du.fully_paid_at
  from public.dues du
  where a.due_id = du.id and du.vehicle_id = p_vehicle
    and a.type in ('unpaid_deadline', 'short_deadline', 'missed_day')
    and du.fully_paid_at is not null and a.resolved_at is null;
  update public.alerts a set resolved_at = null
  from public.dues du
  where a.due_id = du.id and du.vehicle_id = p_vehicle
    and a.type in ('unpaid_deadline', 'short_deadline', 'missed_day')
    and du.fully_paid_at is null and a.resolved_at is not null;
end $$;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

create function private.vehicles_before() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.plate := upper(regexp_replace(btrim(new.plate), '\s+', ' ', 'g'));
  new.driver_name := regexp_replace(btrim(new.driver_name), '\s+', ' ', 'g');
  new.phone := btrim(coalesce(new.phone, ''));
  -- Keep each username once (ignoring case), in the order entered.
  new.momo_usernames := coalesce(
    (select array_agg(n order by ord)
     from (select distinct on (private.norm_name(u)) regexp_replace(btrim(u), '\s+', ' ', 'g') as n, ord
           from unnest(new.momo_usernames) with ordinality as x(u, ord)
           where btrim(u) <> ''
           order by private.norm_name(u), ord) s),
    '{}');
  new.rest_weekdays := coalesce((select array_agg(distinct x order by x) from unnest(new.rest_weekdays) x), '{}');
  if new.frequency <> 'daily' then
    new.rest_weekdays := '{}';
  end if;
  new.updated_at := now();
  return new;
end $$;

create trigger vehicles_before before insert or update on public.vehicles
for each row execute function private.vehicles_before();

create function private.vehicles_after() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  t date := private.today();
  was_on boolean;
  is_on boolean;
begin
  if tg_op = 'INSERT' then
    perform private.recompute_vehicle(new.id);
    return null;
  end if;

  was_on := old.is_active and old.deleted_at is null;
  is_on := new.is_active and new.deleted_at is null;

  if was_on <> is_on then
    if is_on then
      -- Switched back on: expect payments from today, not for the days it was off.
      update public.vehicles set dues_through = t - 1 where id = new.id;
    else
      delete from public.dues where vehicle_id = new.id and due_date >= t;
    end if;
    perform private.recompute_vehicle(new.id);
  elsif (new.amount, new.frequency, new.first_due_date, new.rest_weekdays, new.start_date)
        is distinct from
        (old.amount, old.frequency, old.first_due_date, old.rest_weekdays, old.start_date) then
    -- Schedule changes apply from today. Past dues stay as they were.
    delete from public.dues where vehicle_id = new.id and (due_date >= t or due_date < new.start_date);
    update public.vehicles
    set dues_through = case when new.start_date < old.start_date then new.start_date - 1
                            else least(coalesce(dues_through, t - 1), t - 1) end
    where id = new.id;
    perform private.recompute_vehicle(new.id);
  end if;
  return null;
end $$;

create trigger vehicles_after after insert or update on public.vehicles
for each row execute function private.vehicles_after();

create function private.payments_before() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.recorded_by_member_id := coalesce(new.recorded_by_member_id, private.current_member_id());
  new.held_by_member_id := coalesce(new.held_by_member_id, new.recorded_by_member_id);
  return new;
end $$;

create trigger payments_before before insert on public.payments
for each row execute function private.payments_before();

create function private.payments_after() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  left_over integer;
  v public.vehicles;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform private.recompute_vehicle(old.vehicle_id);
  end if;
  if tg_op = 'INSERT' or (tg_op = 'UPDATE' and new.vehicle_id <> old.vehicle_id) then
    perform private.recompute_vehicle(new.vehicle_id);
  end if;

  -- Overpayment: money left after every due so far is paid. Old payments
  -- (e.g. a Reader catching up on past SMS) don't alert.
  if tg_op = 'INSERT' and new.deleted_at is null
     and new.paid_at > private.now() - interval '2 days'
     and (select overpay_alerts from public.settings) then
    select new.amount - coalesce(sum(a.amount), 0) into left_over
    from public.allocations a where a.payment_id = new.id;
    if left_over > 0 then
      select * into v from public.vehicles where id = new.vehicle_id;
      insert into public.alerts (type, vehicle_id, payment_id, title, body, data, dedupe_key)
      values ('overpayment', v.id, new.id, 'Overpayment',
              v.plate || ' · ' || v.driver_name || ' sent ' || private.rwf(new.amount)
                || ' RWF. ' || private.rwf(left_over) || ' kept as credit.',
              jsonb_build_object('plate', v.plate, 'driver', v.driver_name, 'phone', v.phone,
                                 'sent', new.amount, 'credit', left_over, 'expected', v.amount),
              'overpayment:' || new.id)
      on conflict (dedupe_key) do nothing;
    end if;
  end if;
  return null;
end $$;

create trigger payments_after after insert or update or delete on public.payments
for each row execute function private.payments_after();

create function private.set_recorded_by() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.recorded_by_member_id := coalesce(new.recorded_by_member_id, private.current_member_id());
  return new;
end $$;

create trigger deposits_before before insert on public.deposits
for each row execute function private.set_recorded_by();

create function private.touch() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger devices_touch before update on public.devices
for each row execute function private.touch();
create trigger settings_touch before update on public.settings
for each row execute function private.touch();

-- ---------------------------------------------------------------------------
-- Push notifications
-- ---------------------------------------------------------------------------

-- Sends one notification to every registered phone through the `push` Edge
-- Function. Does nothing until the Vault secrets `push_function_url` and
-- `push_secret` exist, so local development and tests never call out.
create function private.send_push(p_title text, p_body text, p_data jsonb default '{}') returns void
language plpgsql security definer set search_path = '' as $$
declare
  fn_url text;
  secret text;
  tokens jsonb;
begin
  select decrypted_secret into fn_url from vault.decrypted_secrets where name = 'push_function_url';
  select decrypted_secret into secret from vault.decrypted_secrets where name = 'push_secret';
  if fn_url is null or secret is null then
    return;
  end if;
  select jsonb_agg(distinct fcm_token) into tokens from public.devices where fcm_token is not null;
  if tokens is null then
    return;
  end if;
  perform net.http_post(
    url := fn_url,
    body := jsonb_build_object('title', p_title, 'body', p_body, 'data', p_data, 'tokens', tokens),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', secret)
  );
exception when others then
  raise warning 'send_push failed: %', sqlerrm;
end $$;

create function private.alerts_push() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.push then
    perform private.send_push(new.title, new.body,
      jsonb_build_object('alert_id', new.id, 'type', new.type, 'vehicle_id', new.vehicle_id));
  end if;
  return null;
end $$;

create trigger alerts_push after insert on public.alerts
for each row execute function private.alerts_push();

-- ---------------------------------------------------------------------------
-- The tick: every 5 minutes
-- ---------------------------------------------------------------------------

create function private.tick() returns void
language plpgsql security definer set search_path = '' as $$
declare
  s public.settings;
  t date := private.today();
  n timestamptz := private.now();
  r record;
  period text;
  missed_lines text[] := '{}'::text[];
  missed_day date;
  rc integer;
begin
  select * into s from public.settings;

  -- 1. Dues for today (and any days the tick missed while the project slept).
  for r in select id from public.vehicles where is_active and deleted_at is null and coalesce(dues_through, start_date - 1) < t loop
    perform private.recompute_vehicle(r.id);
  end loop;

  -- 2. Deadline check (default 20:00) on the due date.
  for r in
    select d.*, v.plate, v.driver_name, v.phone, v.frequency,
           coalesce((select sum(p.amount) from public.payments p
                     where p.vehicle_id = d.vehicle_id and p.deleted_at is null
                       and private.local_date(p.paid_at) between d.period_start and d.period_end), 0) as sent
    from public.dues d join public.vehicles v on v.id = d.vehicle_id
    where d.kind = 'due' and d.due_date = t and d.amount_paid < d.amount_due
      and n >= private.at_local(t, s.deadline_time)
      and d.created_at < private.at_local(t, s.deadline_time)
      and v.is_active and v.deleted_at is null
  loop
    period := case r.frequency when 'daily' then 'today' when 'weekly' then 'this week' else 'this month' end;
    insert into public.alerts (type, vehicle_id, due_id, title, body, data, dedupe_key)
    values (
      case when r.amount_paid = 0 then 'unpaid_deadline' else 'short_deadline' end::public.alert_type,
      r.vehicle_id, r.id,
      case when r.amount_paid = 0 then 'Not paid by ' else 'Short by ' end || to_char(s.deadline_time, 'HH24:MI'),
      r.plate || ' · ' || r.driver_name || ': ' || private.rwf(r.amount_paid) || ' of '
        || private.rwf(r.amount_due) || ' RWF ' || period || '.'
        || case when r.sent > r.amount_paid
                then ' The ' || private.rwf(r.sent) || ' sent ' || period || ' paid older days first.'
                else '' end,
      jsonb_build_object('plate', r.plate, 'driver', r.driver_name, 'phone', r.phone,
                         'due_date', r.due_date, 'expected', r.amount_due, 'received', r.amount_paid, 'sent', r.sent),
      'deadline:' || r.id)
    on conflict (dedupe_key) do nothing;
  end loop;

  -- 3. Day missed (default 07:00 next day). One row per bike, one summary push.
  --    Dues created after their deadline (a vehicle added at night, or with a
  --    past start date) never alert.
  for r in
    select d.*, v.plate, v.driver_name, v.phone
    from public.dues d join public.vehicles v on v.id = d.vehicle_id
    where d.kind = 'due' and d.due_date between t - 3 and t and d.amount_paid < d.amount_due
      and n >= private.day_end(d.due_date) + s.missed_alert_offset
      and d.created_at < private.at_local(d.due_date, s.deadline_time)
      and v.deleted_at is null
    order by d.due_date, v.plate
  loop
    insert into public.alerts (type, vehicle_id, due_id, title, body, data, push, dedupe_key)
    values ('missed_day', r.vehicle_id, r.id, 'Day missed',
            r.plate || ' · ' || r.driver_name || ' paid ' || private.rwf(r.amount_paid) || ' of '
              || private.rwf(r.amount_due) || ' RWF for ' || private.short_date(r.due_date) || '.',
            jsonb_build_object('plate', r.plate, 'driver', r.driver_name, 'phone', r.phone,
                               'due_date', r.due_date, 'expected', r.amount_due, 'received', r.amount_paid),
            false, 'missed:' || r.id)
    on conflict (dedupe_key) do nothing;
    get diagnostics rc = row_count;
    if rc > 0 then
      missed_lines := missed_lines || (r.plate || ' (' || private.rwf(r.amount_paid) || ')');
      missed_day := r.due_date;
    end if;
  end loop;
  if cardinality(missed_lines) > 0 then
    perform private.send_push(
      cardinality(missed_lines) || case when cardinality(missed_lines) = 1 then ' bike' else ' bikes' end
        || ' didn''t pay in full for ' || private.short_date(missed_day),
      array_to_string(missed_lines, ', '),
      jsonb_build_object('type', 'missed_day'));
  end if;

  -- 4. Readers that went quiet. Resolved by reader_heartbeat().
  for r in
    select dv.id, dv.last_checked_at, m.name
    from public.devices dv join public.members m on m.id = dv.member_id
    where dv.is_reader and dv.last_checked_at is not null
      and dv.last_checked_at < n - make_interval(hours => s.reader_silence_hours)
  loop
    insert into public.alerts (type, device_id, title, body, data, dedupe_key)
    values ('reader_silent', r.id, 'Reader offline',
            r.name || '''s phone hasn''t checked SMS for ' || s.reader_silence_hours
              || ' hours. Payments to ' || r.name || '''s MoMo may be missing.',
            jsonb_build_object('member', r.name, 'last_checked_at', r.last_checked_at),
            'silent:' || r.id || ':' || r.last_checked_at)
    on conflict (dedupe_key) do nothing;
  end loop;
end $$;

select cron.schedule('motor-track-tick', '*/5 * * * *', 'select private.tick()');

-- ---------------------------------------------------------------------------
-- Reader RPCs
-- ---------------------------------------------------------------------------

-- Called by a Reader phone for each matched M-Money SMS. The server repeats
-- the username match so every phone follows the same rule.
create function public.ingest_momo_payment(
  p_amount integer, p_paid_at timestamptz, p_sender_name text, p_sender_phone text, p_tx_id text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := private.current_member_id();
  candidates uuid[];
  v public.vehicles;
  pid uuid;
begin
  if me is null then
    return jsonb_build_object('status', 'not_a_member');
  end if;
  if coalesce(p_amount, 0) <= 0 or coalesce(btrim(p_tx_id), '') = '' or p_paid_at is null then
    return jsonb_build_object('status', 'invalid');
  end if;

  select array_agg(id) into candidates from public.vehicles
  where deleted_at is null
    and private.norm_name(p_sender_name) = any (array(select private.norm_name(u) from unnest(momo_usernames) u));
  if candidates is null then
    return jsonb_build_object('status', 'unmatched');
  end if;
  if cardinality(candidates) > 1 then
    select array_agg(id) into candidates from public.vehicles
    where id = any (candidates)
      and right(regexp_replace(phone, '\D', '', 'g'), 3) = right(regexp_replace(coalesce(p_sender_phone, ''), '\D', '', 'g'), 3);
    if candidates is null or cardinality(candidates) <> 1 then
      return jsonb_build_object('status', 'ambiguous');
    end if;
  end if;

  select * into v from public.vehicles where id = candidates[1];
  if private.local_date(p_paid_at) < v.start_date then
    return jsonb_build_object('status', 'before_start', 'vehicle_id', v.id);
  end if;

  insert into public.payments (vehicle_id, amount, paid_at, source, sender_name, sender_phone, tx_id,
                               held_by_member_id, recorded_by_member_id)
  values (v.id, p_amount, p_paid_at, 'momo', p_sender_name, p_sender_phone, btrim(p_tx_id), me, me)
  on conflict (tx_id) do nothing
  returning id into pid;

  update public.devices set last_checked_at = now() where id = auth.uid();
  return jsonb_build_object('status', case when pid is null then 'duplicate' else 'inserted' end,
                            'payment_id', pid, 'vehicle_id', v.id);
end $$;

-- Called by a Reader phone after each inbox scan.
create function public.reader_heartbeat(p_unreadable integer default 0) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.devices
  set last_checked_at = now(), unreadable_count = greatest(coalesce(p_unreadable, 0), 0)
  where id = auth.uid();
  update public.alerts set resolved_at = now()
  where type = 'reader_silent' and device_id = auth.uid() and resolved_at is null;
end $$;

-- ---------------------------------------------------------------------------
-- Views for the app (they run with the caller's permissions)
-- ---------------------------------------------------------------------------

create view public.v_dues with (security_invoker = true) as
select
  d.*,
  case
    when d.kind = 'rest' then 'rest'
    when d.amount_paid >= d.amount_due and d.fully_paid_at < private.day_end(d.due_date) then 'on_time'
    when d.amount_paid >= d.amount_due then 'late'
    when private.now() < private.day_end(d.due_date) then
      case when d.amount_paid > 0 then 'partial_open' else 'open' end
    when d.amount_paid > 0 then 'partial'
    else 'unpaid'
  end as status,
  coalesce(s.sent, 0)::integer as sent_in_period
from public.dues d
left join lateral (
  select sum(p.amount) as sent from public.payments p
  where p.vehicle_id = d.vehicle_id and p.deleted_at is null
    and private.local_date(p.paid_at) between d.period_start and d.period_end
) s on true;

create view public.v_vehicle_today with (security_invoker = true) as
select
  v.id as vehicle_id,
  cur.id as current_due_id,
  cur.kind as current_kind,
  cur.due_date as current_due_date,
  coalesce(cur.amount_due, 0) as current_due,
  coalesce(cur.amount_paid, 0) as current_paid,
  coalesce(sent.amount, 0)::integer as sent_today,
  coalesce(od.overdue, 0)::integer as overdue,
  od.oldest_unpaid,
  greatest(0, coalesce(pt.total, 0) - coalesce(dt.paid, 0))::integer as credit,
  pt.last_paid_at
from public.vehicles v
left join lateral (
  select d.* from public.dues d
  where d.vehicle_id = v.id and d.period_start <= private.today() and d.period_end >= private.today()
  order by d.due_date limit 1
) cur on true
left join lateral (
  select sum(p.amount) as amount from public.payments p
  where p.vehicle_id = v.id and p.deleted_at is null and private.local_date(p.paid_at) = private.today()
) sent on true
left join lateral (
  select sum(d.amount_due - d.amount_paid) as overdue,
         min(d.due_date) filter (where d.amount_paid < d.amount_due) as oldest_unpaid
  from public.dues d
  where d.vehicle_id = v.id and d.kind = 'due' and d.due_date < private.today()
) od on true
left join lateral (
  select sum(p.amount) as total, max(p.paid_at) as last_paid_at from public.payments p
  where p.vehicle_id = v.id and p.deleted_at is null
) pt on true
left join lateral (
  select sum(d.amount_paid) as paid from public.dues d where d.vehicle_id = v.id
) dt on true;

create view public.v_member_balances with (security_invoker = true) as
select
  m.id as member_id,
  m.name,
  m.momo_number,
  coalesce(r.received, 0)::integer as received,
  coalesce(dp.deposited, 0)::integer as deposited,
  coalesce(dp.fees, 0)::integer as fees,
  (coalesce(r.received, 0) - coalesce(dp.deposited, 0) - coalesce(dp.fees, 0))::integer as held
from public.members m
left join lateral (
  select sum(p.amount) as received from public.payments p
  where p.held_by_member_id = m.id and p.deleted_at is null
) r on true
left join lateral (
  select sum(x.amount) as deposited, sum(x.fee) as fees from public.deposits x
  where x.member_id = m.id and x.deleted_at is null
) dp on true;

-- ---------------------------------------------------------------------------
-- Row-level security: only phones that joined with the team code get in.
-- ---------------------------------------------------------------------------

alter table public.settings enable row level security;
alter table public.members enable row level security;
alter table public.sms_templates enable row level security;
alter table public.devices enable row level security;
alter table public.vehicles enable row level security;
alter table public.dues enable row level security;
alter table public.payments enable row level security;
alter table public.allocations enable row level security;
alter table public.deposits enable row level security;
alter table public.alerts enable row level security;

create policy "team reads settings" on public.settings for select to authenticated using ((select private.is_member()));
create policy "team updates settings" on public.settings for update to authenticated using ((select private.is_member()));

create policy "team reads members" on public.members for select to authenticated using ((select private.is_member()));
create policy "team updates members" on public.members for update to authenticated using ((select private.is_member()));

create policy "team reads templates" on public.sms_templates for select to authenticated using ((select private.is_member()));
create policy "team adds templates" on public.sms_templates for insert to authenticated with check ((select private.is_member()));

create policy "team reads devices" on public.devices for select to authenticated using ((select private.is_member()));
create policy "phone updates itself" on public.devices for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "team reads vehicles" on public.vehicles for select to authenticated using ((select private.is_member()));
create policy "team adds vehicles" on public.vehicles for insert to authenticated with check ((select private.is_member()));
create policy "team updates vehicles" on public.vehicles for update to authenticated using ((select private.is_member()));

create policy "team reads dues" on public.dues for select to authenticated using ((select private.is_member()));
create policy "team reads allocations" on public.allocations for select to authenticated using ((select private.is_member()));

create policy "team reads payments" on public.payments for select to authenticated using ((select private.is_member()));
-- MoMo payments only arrive through ingest_momo_payment().
create policy "team records manual payments" on public.payments for insert to authenticated
  with check ((select private.is_member()) and source <> 'momo');
create policy "team edits payments" on public.payments for update to authenticated using ((select private.is_member()));

create policy "team reads deposits" on public.deposits for select to authenticated using ((select private.is_member()));
create policy "team records deposits" on public.deposits for insert to authenticated with check ((select private.is_member()));
create policy "team edits deposits" on public.deposits for update to authenticated using ((select private.is_member()));

create policy "team reads alerts" on public.alerts for select to authenticated using ((select private.is_member()));

-- ---------------------------------------------------------------------------
-- Function permissions
-- ---------------------------------------------------------------------------

revoke all on all functions in schema private from public;
grant execute on function
  private.now(), private.tz(), private.local_date(timestamptz), private.today(),
  private.at_local(date, time), private.day_end(date), private.norm_name(text),
  private.is_member(), private.current_member_id()
to authenticated, service_role;

revoke execute on function public.team_members(text) from public, anon;
revoke execute on function public.join_team(text, text, uuid) from public, anon;
revoke execute on function public.ingest_momo_payment(integer, timestamptz, text, text, text) from public, anon;
revoke execute on function public.reader_heartbeat(integer) from public, anon;
grant execute on function public.team_members(text) to authenticated;
grant execute on function public.join_team(text, text, uuid) to authenticated;
grant execute on function public.ingest_momo_payment(integer, timestamptz, text, text, text) to authenticated;
grant execute on function public.reader_heartbeat(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Live updates and the default M-Money template
-- ---------------------------------------------------------------------------

alter publication supabase_realtime add table
  public.vehicles, public.dues, public.payments, public.deposits, public.alerts,
  public.members, public.devices, public.settings;

insert into public.sms_templates (sender, pattern, sample) values (
  'M-Money',
  'You have received {amount} RWF from {name} ({phone}) at {datetime} . Balance:{skip} RWF. FT Id: {txid}.',
  'You have received 6000 RWF from Xxx MUGABO (*********123) at 2026-11-02 19:57:24 . Balance:25000 RWF. FT Id: 30012345678.'
);
