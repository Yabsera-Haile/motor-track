-- Alerts milestone: push registration, a test push, message templates for
-- drivers, and no "Reader offline" alerts at night.

-- ---------------------------------------------------------------------------
-- Messages to drivers (edited in Settings, shared by the team)
-- ---------------------------------------------------------------------------

-- Placeholders: {name} {plate} {amount} {received} {expected} {date}
create table public.message_templates (
  kind text primary key check (kind in ('reminder', 'amount', 'missed')),
  english text not null check (length(btrim(english)) between 1 and 600),
  kinyarwanda text not null check (length(btrim(kinyarwanda)) between 1 and 600),
  updated_by_member_id uuid references public.members (id) on delete set null,
  updated_at timestamptz not null default now()
);

insert into public.message_templates (kind, english, kinyarwanda) values
  ('reminder',
   'Hello {name}, a reminder that today''s payment of {amount} RWF for motorcycle {plate} has not been received yet. Please send it today. Thank you.',
   'Muraho {name}, turabibutsa ko amafaranga y''uyu munsi angana na {amount} RWF ya moto {plate} ataratugeraho. Mwayohereza uyu munsi. Murakoze.'),
  ('amount',
   'Hello {name}, today we received {received} RWF for motorcycle {plate}, but the agreed amount is {expected} RWF. Could you tell us why the amount is different? Thank you.',
   'Muraho {name}, uyu munsi twakiriye {received} RWF ya moto {plate}, ariko amafaranga twumvikanye ni {expected} RWF. Mwatubwira impamvu amafaranga atandukanye? Murakoze.'),
  ('missed',
   'Hello {name}, we did not receive the payment of {amount} RWF for motorcycle {plate} for {date}. Please send it as soon as possible. Thank you.',
   'Muraho {name}, ntitwakiriye amafaranga {amount} RWF ya moto {plate} yo ku itariki {date}. Turabasaba kuyohereza vuba bishoboka. Murakoze.');

create function private.message_templates_before() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.updated_at := now();
  new.updated_by_member_id := private.current_member_id();
  return new;
end $$;

create trigger message_templates_before before update on public.message_templates
for each row execute function private.message_templates_before();

alter table public.message_templates enable row level security;
create policy "team reads message templates" on public.message_templates
  for select to authenticated using ((select private.is_member()));
create policy "team edits message templates" on public.message_templates
  for update to authenticated using ((select private.is_member())) with check ((select private.is_member()));

alter publication supabase_realtime add table public.message_templates;

-- ---------------------------------------------------------------------------
-- Push registration
-- ---------------------------------------------------------------------------

-- Saves this phone's Firebase token. A token belongs to one install, so an
-- older sign-in that still has it (after "I've joined before") forgets it.
create function public.register_push(p_token text, p_platform text default 'android') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  t text := nullif(btrim(coalesce(p_token, '')), '');
begin
  if not private.is_member() then
    return jsonb_build_object('ok', false, 'error', 'not_a_member');
  end if;
  if t is not null then
    update public.devices set fcm_token = null where fcm_token = t and id <> auth.uid();
  end if;
  -- Only write when something changed: every write wakes the other phones.
  update public.devices set fcm_token = t, platform = p_platform
  where id = auth.uid() and (fcm_token is distinct from t or platform is distinct from p_platform);
  return jsonb_build_object('ok', true);
end $$;

-- "Send a test notification" in Settings: one push to every phone.
create function public.send_test_push() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := private.current_member_id();
  who text;
  phones integer;
  ready boolean;
begin
  if me is null then
    return jsonb_build_object('ok', false, 'error', 'not_a_member');
  end if;
  select name into who from public.members where id = me;
  select count(distinct fcm_token)::int into phones from public.devices where fcm_token is not null;
  select count(*) = 2 into ready from vault.secrets where name in ('push_function_url', 'push_secret');
  if ready and phones > 0 then
    perform private.send_push('Test notification',
      who || ' sent a test. Payment alerts will show on this phone like this.',
      jsonb_build_object('type', 'test'));
  end if;
  return jsonb_build_object('ok', true, 'ready', ready, 'phones', phones);
end $$;

revoke execute on function public.register_push(text, text) from public, anon;
revoke execute on function public.send_test_push() from public, anon;
grant execute on function public.register_push(text, text) to authenticated;
grant execute on function public.send_test_push() to authenticated;

-- ---------------------------------------------------------------------------
-- The tick: same as before, but "Reader offline" only alerts 07:00 to 21:00.
-- A phone left on a table overnight can sleep for hours; nobody should be
-- woken for that. If it is still quiet at 07:00, the alert comes then.
-- ---------------------------------------------------------------------------

create or replace function private.tick() returns void
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

  -- 4. Readers that went quiet, in the daytime only. Resolved by reader_sync().
  if (n at time zone private.tz())::time between time '07:00' and time '21:00' then
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
  end if;
end $$;
