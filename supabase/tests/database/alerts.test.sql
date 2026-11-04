-- Push registration, test push, message templates and Reader quiet hours.
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

set local app.now = '2026-11-04 10:00+02';
select private.set_team_code('test-team-code');

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000c1'),
  ('00000000-0000-0000-0000-0000000000c2'),
  ('00000000-0000-0000-0000-0000000000c3');

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is(public.join_team('test-team-code', 'Aline') ->> 'ok', 'true', 'Aline joins');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c2","role":"authenticated"}';
select is(public.join_team('test-team-code', 'Kevin') ->> 'ok', 'true', 'Kevin joins');

-- ---- register_push ----
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is(public.register_push('tok-A') ->> 'ok', 'true', 'a member registers a token');
select is((select fcm_token from public.devices where id = '00000000-0000-0000-0000-0000000000c1'), 'tok-A',
  'the token is saved on that phone');

-- Same install signs in again as someone else: the token moves.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c2","role":"authenticated"}';
select public.register_push('tok-A');
select is((select fcm_token from public.devices where id = '00000000-0000-0000-0000-0000000000c1'), null,
  'the older sign-in forgets a token that moved');
select is((select fcm_token from public.devices where id = '00000000-0000-0000-0000-0000000000c2'), 'tok-A',
  'the token now belongs to the newer sign-in');

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}';
select public.register_push('tok-B');

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}';
select is(public.register_push('tok-C') ->> 'error', 'not_a_member', 'a phone that has not joined cannot register');
select is(public.send_test_push() ->> 'error', 'not_a_member', 'nor send a test');

-- ---- send_test_push ----
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is(public.send_test_push(), '{"ok": true, "ready": false, "phones": 2}'::jsonb,
  'without the Vault secrets nothing is sent, but the phones are counted');
select is((select count(*)::int from net.http_request_queue), 0, 'no request is queued');

select vault.create_secret('http://push.invalid/functions/v1/push', 'push_function_url');
select vault.create_secret('test-push-secret', 'push_secret');
select is(public.send_test_push() ->> 'ready', 'true', 'with the secrets it is ready');
select is((select count(*)::int from net.http_request_queue
           where url = 'http://push.invalid/functions/v1/push'
             and headers ->> 'x-push-secret' = 'test-push-secret'
             and convert_from(body, 'utf8')::jsonb -> 'tokens' @> '["tok-A", "tok-B"]'
             and convert_from(body, 'utf8')::jsonb -> 'data' ->> 'type' = 'test'), 1,
  'one request goes to the push function with every token');

-- A new alert is pushed with its id, so tapping it can open it.
insert into public.alerts (type, title, body, dedupe_key) values ('overpayment', 'T', 'B', 'test:1');
select is((select count(*)::int from net.http_request_queue
           where convert_from(body, 'utf8')::jsonb -> 'data' ->> 'alert_id'
                 = (select id::text from public.alerts where dedupe_key = 'test:1')), 1,
  'inserting an alert queues its push');

-- ---- message templates ----
set local role authenticated;
select is((select count(*)::int from public.message_templates), 3, 'members read the three templates');
select is((select english from public.message_templates where kind = 'reminder') like 'Hello {name}%', true,
  'the reminder starts with the driver''s name');
update public.message_templates set kinyarwanda = 'Muraho {name}.' where kind = 'reminder';
reset role;
select is((select updated_by_member_id from public.message_templates where kind = 'reminder'),
  (select id from public.members where name = 'Aline'), 'an edit records who made it');

set local role authenticated;
select throws_ok($$ insert into public.message_templates (kind, english, kinyarwanda) values ('other', 'a', 'b') $$,
  '42501', null, 'members cannot add new kinds');
select throws_ok($$ update public.message_templates set english = ' ' where kind = 'amount' $$,
  '23514', null, 'a template cannot be empty');
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select is((select count(*)::int from public.message_templates), 0, 'the publishable key alone reads nothing');
reset role;

-- ---- Payment notifications ----
create temp view pushes as
  select convert_from(body, 'utf8')::jsonb as b from net.http_request_queue;
grant select on pushes to anon, authenticated;

set local app.now = '2026-11-04 10:00+02';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}';
insert into public.vehicles (id, driver_name, plate, phone, momo_usernames, amount, start_date)
values ('00000000-0000-0000-0000-0000000000b1', 'Patrick', 'RD 907 F', '0782412390', array['Xxx UWIMANA'], 6000, '2026-11-04');

delete from net.http_request_queue;
insert into public.payments (vehicle_id, amount, paid_at, source)
values ('00000000-0000-0000-0000-0000000000b1', 2000, '2026-11-04 09:30+02', 'cash');
select is((select b ->> 'title' from pushes), 'Cash payment', 'a cash payment notifies');
select is((select b ->> 'body' from pushes), 'Aline recorded 2,000 RWF cash from RD 907 F · Patrick. Still owes 4,000 RWF.',
  'it says who recorded it and what is still owed');
select is((select b -> 'tokens' from pushes), '["tok-A"]'::jsonb, 'but not to the phone that recorded it');
select is((select b -> 'data' ->> 'vehicle_id' from pushes), '00000000-0000-0000-0000-0000000000b1',
  'tapping it can open the bike');

delete from net.http_request_queue;
select public.ingest_momo_payment(4000, '2026-11-04 09:45+02', 'Xxx UWIMANA', '*********390', 'FT-P1');
select is((select b ->> 'title' from pushes), 'Payment received', 'a MoMo payment notifies');
select is((select b ->> 'body' from pushes), 'RD 907 F · Patrick sent 4,000 RWF. All paid up.', 'paid up for today');
select is((select b -> 'tokens' from pushes), '["tok-A", "tok-B"]'::jsonb, 'MoMo payments go to every phone');

delete from net.http_request_queue;
select public.ingest_momo_payment(6000, '2026-11-04 09:50+02', 'Xxx UWIMANA', '*********390', 'FT-P2');
select is((select count(*)::int from pushes), 1, 'money left over: one notification, not two');
select is((select b ->> 'title' from pushes), 'Overpayment', 'and it is the overpayment alert');

update public.settings set overpay_alerts = false;
delete from net.http_request_queue;
select public.ingest_momo_payment(1000, '2026-11-04 09:55+02', 'Xxx UWIMANA', '*********390', 'FT-P3');
select is((select b ->> 'body' from pushes), 'RD 907 F · Patrick sent 1,000 RWF. All paid up, 7,000 RWF credit.',
  'with overpayment alerts off, the payment notification mentions the credit');

update public.settings set payment_push = false;
delete from net.http_request_queue;
select public.ingest_momo_payment(1000, '2026-11-04 10:00+02', 'Xxx UWIMANA', '*********390', 'FT-P4');
select is((select count(*)::int from pushes), 0, 'payment notifications can be turned off');

update public.settings set payment_push = true, overpay_alerts = true;
delete from net.http_request_queue;
set local app.now = '2026-11-07 10:00+02';
select public.ingest_momo_payment(6000, '2026-11-04 18:00+02', 'Xxx UWIMANA', '*********390', 'FT-P5');
select is((select count(*)::int from pushes), 0, 'an old SMS found later (catch-up) stays quiet');

-- ---- Reader quiet hours ----
update public.devices set is_reader = true, last_checked_at = '2026-11-04 12:00+02'
where id = '00000000-0000-0000-0000-0000000000c1';

set local app.now = '2026-11-04 22:30+02';
select private.tick();
select is((select count(*)::int from public.alerts where type = 'reader_silent'), 0,
  'no Reader offline alert at night');

set local app.now = '2026-11-05 06:55+02';
select private.tick();
select is((select count(*)::int from public.alerts where type = 'reader_silent'), 0, 'still none before 07:00');

set local app.now = '2026-11-05 07:05+02';
select private.tick();
select is((select count(*)::int from public.alerts where type = 'reader_silent'), 1,
  'still quiet in the morning: the alert comes at 07:00');

set local app.now = '2026-11-05 15:00+02';
select private.tick();
select is((select count(*)::int from public.alerts where type = 'reader_silent'), 1, 'and only once');

select * from finish();
rollback;
