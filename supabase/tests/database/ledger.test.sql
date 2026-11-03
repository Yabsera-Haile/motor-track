-- Business-rule tests. Run with: npx supabase@3.0.0 test db
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- Start from an empty team (the local sample data comes back on rollback).
truncate public.alerts, public.allocations, public.payments, public.dues, public.deposits,
  public.devices, public.vehicles, public.members, private.team, private.join_attempts cascade;

-- Fixed clock: Saturday 31 Oct 2026, 10:00 in Kigali.
set local app.now = '2026-10-31 10:00+02';

insert into public.members (id, name) values
  ('00000000-0000-0000-0000-0000000000a1', 'Aline'),
  ('00000000-0000-0000-0000-0000000000a3', 'Grace');

-- ---------------------------------------------------------------- vehicles
insert into public.vehicles (id, driver_name, plate, phone, momo_usernames, amount, rest_weekdays, start_date)
values ('00000000-0000-0000-0000-0000000000b1', ' Patrick  Uwimana ', 'rd 907  f', '0782 412 390',
        array['Patrick  UWIMANA', 'patrick uwimana', 'Xxx UWIMANA', ' '], 6000, '{7,7}', '2026-10-26');

select is((select plate from public.vehicles where id = '00000000-0000-0000-0000-0000000000b1'),
  'RD 907 F', 'plate is upper-cased and spaces collapsed');
select is((select momo_usernames from public.vehicles where id = '00000000-0000-0000-0000-0000000000b1'),
  array['Patrick UWIMANA', 'Xxx UWIMANA'], 'usernames are trimmed and de-duplicated ignoring case');
select is((select rest_weekdays from public.vehicles where id = '00000000-0000-0000-0000-0000000000b1'),
  '{7}'::smallint[], 'rest weekdays de-duplicated');
select is((select count(*)::int from public.dues where vehicle_id = '00000000-0000-0000-0000-0000000000b1'),
  6, 'a past start date creates dues from Mon 26 to Sat 31 Oct');

-- --------------------------------------------- oldest debt first, partials
insert into public.payments (vehicle_id, amount, paid_at, source, held_by_member_id) values
  ('00000000-0000-0000-0000-0000000000b1', 6000, '2026-10-26 18:00+02', 'cash', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-0000000000b1', 6000, '2026-10-27 18:00+02', 'cash', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-0000000000b1', 12000, '2026-10-29 18:00+02', 'cash', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-0000000000b1', 3000, '2026-10-30 18:00+02', 'cash', '00000000-0000-0000-0000-0000000000a1');

select results_eq(
  $$ select due_date::text, status from public.v_dues
     where vehicle_id = '00000000-0000-0000-0000-0000000000b1' order by due_date $$,
  $$ values ('2026-10-26', 'on_time'), ('2026-10-27', 'on_time'), ('2026-10-28', 'late'),
            ('2026-10-29', 'on_time'), ('2026-10-30', 'partial'), ('2026-10-31', 'open') $$,
  'the 12,000 on the 29th pays the missed 28th first, then the 29th');

select results_eq(
  $$ select current_due, current_paid, sent_today, overdue, oldest_unpaid::text, credit
     from public.v_vehicle_today where vehicle_id = '00000000-0000-0000-0000-0000000000b1' $$,
  $$ values (6000, 0, 0, 3000, '2026-10-30', 0) $$,
  'home card numbers on Saturday morning');

select is((select sent_in_period from public.v_dues
           where vehicle_id = '00000000-0000-0000-0000-0000000000b1' and due_date = '2026-10-28'),
  0, 'nothing was sent on the 28th (counts as a missed day)');

-- ------------------------------------------- next days, rest day, alerts
set local app.now = '2026-11-02 10:00+02';
select private.tick();

select is((select kind from public.dues
           where vehicle_id = '00000000-0000-0000-0000-0000000000b1' and due_date = '2026-11-01'),
  'rest', 'Sunday is a rest day');
select is((select count(*)::int from public.alerts where type = 'missed_day'),
  1, 'one missed-day alert: Sat 31 Oct (the 30th was back-filled, so it stays quiet)');
select matches((select body from public.alerts where type = 'missed_day'),
  'RD 907 F · Patrick Uwimana paid 0 of 6,000 RWF for Sat 31 Oct\.', 'missed-day wording');

insert into public.payments (vehicle_id, amount, paid_at, source) values
  ('00000000-0000-0000-0000-0000000000b1', 15000, '2026-11-02 09:00+02', 'cash');
select results_eq(
  $$ select due_date::text, status from public.v_dues
     where vehicle_id = '00000000-0000-0000-0000-0000000000b1' and due_date >= '2026-10-30' order by due_date $$,
  $$ values ('2026-10-30', 'late'), ('2026-10-31', 'late'), ('2026-11-01', 'rest'), ('2026-11-02', 'on_time') $$,
  '15,000 clears the 30th, the 31st and today');
select isnt((select resolved_at from public.alerts where type = 'missed_day'), null,
  'the missed-day alert is resolved once the day is paid');

insert into public.payments (vehicle_id, amount, paid_at, source) values
  ('00000000-0000-0000-0000-0000000000b1', 6000, '2026-11-02 09:30+02', 'cash');
select is((select credit from public.v_vehicle_today where vehicle_id = '00000000-0000-0000-0000-0000000000b1'),
  6000, 'paying ahead becomes credit');
select matches((select body from public.alerts where type = 'overpayment'),
  'sent 6,000 RWF\. 6,000 kept as credit\.', 'overpayment alert');

set local app.now = '2026-11-03 08:00+02';
select private.tick();
select is((select status from public.v_dues
           where vehicle_id = '00000000-0000-0000-0000-0000000000b1' and due_date = '2026-11-03'),
  'on_time', 'credit pays the next day automatically');
select is((select credit from public.v_vehicle_today where vehicle_id = '00000000-0000-0000-0000-0000000000b1'),
  0, 'credit is used up');

-- --------------------------------------------------------- deadline alerts
insert into public.vehicles (id, driver_name, plate, phone, momo_usernames, amount, rest_weekdays)
values ('00000000-0000-0000-0000-0000000000b2', 'Eric Mugisha', 'RE 115 C', '0789640118',
        array['Eric MUGISHA', 'Xxx UWIMANA'], 6000, '{7}');
insert into public.payments (vehicle_id, amount, paid_at, source) values
  ('00000000-0000-0000-0000-0000000000b2', 4000, '2026-11-03 12:00+02', 'cash');

set local app.now = '2026-11-03 19:59+02';
select private.tick();
select is((select count(*)::int from public.alerts where type in ('short_deadline', 'unpaid_deadline')),
  0, 'no deadline alert before 20:00');

set local app.now = '2026-11-03 20:05+02';
select private.tick();
select private.tick();
select is((select count(*)::int from public.alerts where type = 'short_deadline'),
  1, 'one short alert at 20:00, even if the tick runs twice');
select is((select body from public.alerts where type = 'short_deadline'),
  'RE 115 C · Eric Mugisha: 4,000 of 6,000 RWF today.', 'short alert wording');

insert into public.vehicles (id, driver_name, plate, amount)
values ('00000000-0000-0000-0000-0000000000b5', 'Late Addition', 'RL 001 A', 6000);
select private.tick();
select is((select count(*)::int from public.alerts where vehicle_id = '00000000-0000-0000-0000-0000000000b5'),
  0, 'a bike registered after 20:00 gets no alert that night');

insert into public.payments (vehicle_id, amount, paid_at, source) values
  ('00000000-0000-0000-0000-0000000000b2', 2000, '2026-11-03 21:14+02', 'cash');
select is((select resolved_at from public.alerts where type = 'short_deadline'),
  '2026-11-03 21:14+02'::timestamptz, 'short alert resolves when paid in full');

set local app.now = '2026-11-04 07:05+02';
select private.tick();
select is((select count(*)::int from public.alerts where type = 'missed_day'),
  1, 'paid late in the evening, so no missed-day alert next morning');
select is((select count(*)::int from public.alerts where vehicle_id = '00000000-0000-0000-0000-0000000000b5'),
  0, 'the bike registered at night gets no missed-day alert either');
delete from public.vehicles where id = '00000000-0000-0000-0000-0000000000b5';

-- ------------------------------------------------- deactivate / reactivate
update public.vehicles set is_active = false where id = '00000000-0000-0000-0000-0000000000b2';
select is((select count(*)::int from public.dues
           where vehicle_id = '00000000-0000-0000-0000-0000000000b2' and due_date = '2026-11-04'),
  0, 'switching off removes today''s due');
update public.vehicles set is_active = true where id = '00000000-0000-0000-0000-0000000000b2';
select is((select count(*)::int from public.dues
           where vehicle_id = '00000000-0000-0000-0000-0000000000b2' and due_date = '2026-11-04'),
  1, 'switching back on expects today again');

update public.vehicles set amount = 7000 where id = '00000000-0000-0000-0000-0000000000b2';
select results_eq(
  $$ select due_date::text, amount_due from public.dues
     where vehicle_id = '00000000-0000-0000-0000-0000000000b2' order by due_date $$,
  $$ values ('2026-11-03', 6000), ('2026-11-04', 7000) $$,
  'a new amount applies from today, the past stays');

-- ---------------------------------------------------- weekly and monthly
insert into public.vehicles (id, driver_name, plate, amount, frequency, first_due_date, start_date)
values ('00000000-0000-0000-0000-0000000000b3', 'Weekly Driver', 'RW 001 A', 42000, 'weekly', '2026-11-07', '2026-11-02');
select results_eq(
  $$ select period_start::text, due_date::text, amount_due from public.dues
     where vehicle_id = '00000000-0000-0000-0000-0000000000b3' $$,
  $$ values ('2026-11-02', '2026-11-07', 42000) $$,
  'weekly: this week''s due exists from the start of the week');

insert into public.vehicles (id, driver_name, plate, amount, frequency, first_due_date, start_date)
values ('00000000-0000-0000-0000-0000000000b4', 'Monthly Driver', 'RM 001 A', 150000, 'monthly', '2026-01-31', '2026-01-01');
select is((select array_agg(due_date::text order by due_date) from public.dues
           where vehicle_id = '00000000-0000-0000-0000-0000000000b4' and due_date < '2026-05-01'),
  array['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30'], 'monthly: the 31st becomes the last day of short months');
select is((select current_due_date::text from public.v_vehicle_today where vehicle_id = '00000000-0000-0000-0000-0000000000b4'),
  '2026-11-30', 'monthly: the current period ends 30 Nov');

-- ------------------------------------------------ team code and joining
insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000c1');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}';

select is(public.join_team('anything', 'Kevin') ->> 'error', 'team_code_not_set', 'no code set yet');
select private.set_team_code('test-team-code');
select is(public.join_team('wrong-code', 'Kevin') ->> 'error', 'wrong_team_code', 'wrong code is refused');
select is(public.join_team('test-team-code', 'aline') ->> 'error', 'name_taken', 'names are unique, ignoring case');
select is(public.join_team('test-team-code', 'Kevin') ->> 'ok', 'true', 'right code joins');
select is(private.current_member_id(), (select id from public.members where name = 'Kevin'), 'this phone is now Kevin');
select is(jsonb_array_length(public.team_members('test-team-code') -> 'members'), 3, 'team list for returning members');

-- ---------------------------------------------------------- Reader ingest
select is(public.ingest_momo_payment(6000, '2026-11-04 06:00+02', 'patrick   UWIMANA', '*********390', 'FT-1') ->> 'status',
  'inserted', 'username matches ignoring case and spaces');
select is(public.ingest_momo_payment(6000, '2026-11-04 06:00+02', 'Patrick UWIMANA', '*********390', 'FT-1') ->> 'status',
  'duplicate', 'the same FT Id is only counted once');
select is(public.ingest_momo_payment(5000, '2026-11-04 06:10+02', 'Somebody ELSE', '*********111', 'FT-2') ->> 'status',
  'unmatched', 'unknown senders are not stored');
select is(public.ingest_momo_payment(6000, '2026-11-04 06:20+02', 'Xxx UWIMANA', '*********390', 'FT-3') ->> 'status',
  'inserted', 'a shared username is settled by the last 3 phone digits');
select is(public.ingest_momo_payment(6000, '2026-11-04 06:30+02', 'Xxx UWIMANA', '*********999', 'FT-4') ->> 'status',
  'ambiguous', 'still unclear means skipped');
select is(public.ingest_momo_payment(6000, '2026-11-01 06:30+02', 'Eric MUGISHA', '*********118', 'FT-5') ->> 'status',
  'before_start', 'payments from before the start date are ignored');
select is((select count(*)::int from public.payments where tx_id like 'FT-%'), 2, 'two MoMo payments stored');
select is((select held_by_member_id from public.payments where tx_id = 'FT-1'),
  (select id from public.members where name = 'Kevin'), 'MoMo money is held by the Reader''s member');

-- ------------------------------------------------------------- balances
insert into public.deposits (member_id, amount, fee) values ((select id from public.members where name = 'Kevin'), 10000, 500);
select results_eq(
  $$ select received, deposited, fees, held from public.v_member_balances where name = 'Kevin' $$,
  $$ values (12000, 10000, 500, 1500) $$,
  'held = received - deposited - fees');

-- --------------------------------------------------------------- security
set local role authenticated;
select is((select count(*)::int from public.vehicles), 4, 'a member sees the vehicles');
select throws_ok(
  $$ insert into public.payments (vehicle_id, amount, source) values ('00000000-0000-0000-0000-0000000000b1', 6000, 'momo') $$,
  '42501', null, 'members cannot fake a MoMo payment');
select lives_ok(
  $$ insert into public.payments (vehicle_id, amount, source) values ('00000000-0000-0000-0000-0000000000b1', 6000, 'cash') $$,
  'members can record cash');
select is((select count(*)::int from public.payments
           where source = 'cash' and recorded_by_member_id = (select id from public.members where name = 'Kevin')),
  1, 'cash is recorded by the member who entered it');

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c9","role":"authenticated"}';
select is((select count(*)::int from public.vehicles), 0, 'a phone that has not joined sees nothing');
select is((select count(*)::int from public.payments), 0, 'and no payments');
reset role;

select * from finish();
rollback;
