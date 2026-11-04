-- Changing the deadline or the "day missed" time re-judges today's alerts,
-- and a deleted vehicle's payments stop counting as held money.
-- Run with: npx supabase@3.0.0 test db
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- Truncating members cascades to message_templates (it references members): keep them.
create temp table saved_templates as select * from public.message_templates;
truncate public.alerts, public.allocations, public.payments, public.dues, public.deposits,
  public.devices, public.vehicles, public.members, private.team, private.join_attempts cascade;
insert into public.message_templates (kind, english, kinyarwanda)
  select kind, english, kinyarwanda from saved_templates;
delete from vault.secrets where name in ('push_function_url', 'push_secret');

select private.set_team_code('test-team-code');
insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000d1');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}';
select is(public.join_team('test-team-code', 'Aline') ->> 'ok', 'true', 'Aline joins');

update public.settings set deadline_time = '18:30', missed_alert_offset = '-01:00';

create temp view day_alerts as
  select a.type::text as type, a.title, d.due_date
  from public.alerts a join public.dues d on d.id = a.due_id;
grant select on day_alerts to authenticated;

-- A bike since Tue 3 Nov that never pays.
set local app.now = '2026-11-03 10:00+02';
insert into public.vehicles (id, driver_name, plate, momo_usernames, amount, start_date)
values ('00000000-0000-0000-0000-0000000000e1', 'Patrick', 'RD 907 F', array['Xxx UWIMANA'], 6000, '2026-11-03');

set local app.now = '2026-11-03 18:35+02';
select private.tick();
select is((select count(*)::int from day_alerts where type = 'unpaid_deadline' and due_date = '2026-11-03'), 1,
  'Tuesday: not paid by 18:30');

set local app.now = '2026-11-04 10:00+02';
select private.tick();
set local app.now = '2026-11-04 18:35+02';
select private.tick();
select is((select title from day_alerts where type = 'unpaid_deadline' and due_date = '2026-11-04'),
  'Not paid by 18:30', 'Wednesday: not paid by 18:30');

-- ---- The deadline moves later: today is not late yet ----
set local app.now = '2026-11-04 19:00+02';
set local role authenticated;
update public.settings set deadline_time = '23:50';
reset role;
select is((select count(*)::int from day_alerts where type = 'unpaid_deadline' and due_date = '2026-11-04'), 0,
  'a member moving the deadline later clears today''s late alert');
select is((select count(*)::int from day_alerts where type = 'unpaid_deadline' and due_date = '2026-11-03'), 1,
  'earlier days keep theirs');

select private.tick();
select is((select count(*)::int from day_alerts where type = 'unpaid_deadline' and due_date = '2026-11-04'), 0,
  'nothing before the new deadline');

set local app.now = '2026-11-04 23:51+02';
select private.tick();
select is((select title from day_alerts where type = 'unpaid_deadline' and due_date = '2026-11-04'),
  'Not paid by 23:50', 'it comes again at the new deadline');

-- ---- The deadline moves earlier, to a time already passed: still late ----
set local app.now = '2026-11-04 23:55+02';
update public.settings set deadline_time = '21:00';
select private.tick();
select is((select count(*)::int from day_alerts where type = 'unpaid_deadline' and due_date = '2026-11-04'), 1,
  'an earlier deadline keeps the alert, without a second one');

update public.settings set overpay_alerts = false;
select is((select count(*)::int from day_alerts where type = 'unpaid_deadline'), 2,
  'other settings leave the alerts alone');

-- ---- "Day missed" moves later ----
select is((select count(*)::int from day_alerts where type = 'missed_day' and due_date = '2026-11-04'), 1,
  'Wednesday missed at 23:00, the same day');
update public.settings set missed_alert_offset = '07:00';
select is((select count(*)::int from day_alerts where type = 'missed_day' and due_date = '2026-11-04'), 0,
  'moving "day missed" to 07:00 the next morning clears it until then');
select is((select count(*)::int from day_alerts where type = 'missed_day' and due_date = '2026-11-03'), 1,
  'Tuesday''s stays: 07:00 Wednesday has passed');

set local app.now = '2026-11-05 07:05+02';
select private.tick();
select is((select count(*)::int from day_alerts where type = 'missed_day' and due_date = '2026-11-04'), 1,
  'it comes again at 07:00');

-- ---- Deleted vehicles ----
insert into public.payments (vehicle_id, amount, paid_at, source, held_by_member_id)
values ('00000000-0000-0000-0000-0000000000e1', 6000, '2026-11-05 07:00+02', 'cash',
        (select id from public.members where name = 'Aline'));
select is((select held from public.v_member_balances where name = 'Aline'), 6000, 'cash Aline took counts as held');

update public.vehicles set deleted_at = private.now(), is_active = false
where id = '00000000-0000-0000-0000-0000000000e1';
select is((select held from public.v_member_balances where name = 'Aline'), 0,
  'once the vehicle is deleted, its payments no longer count');

select * from finish();
rollback;
