-- Reader key tests. Run with: npx supabase@3.0.0 test db
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

truncate public.alerts, public.allocations, public.payments, public.dues, public.deposits,
  public.devices, public.vehicles, public.members, private.team, private.join_attempts cascade;

set local app.now = '2026-11-04 09:00+02';
select private.set_team_code('test-team-code');

insert into public.vehicles (id, driver_name, plate, phone, momo_usernames, amount, start_date)
values ('00000000-0000-0000-0000-0000000000b1', 'Emmanuel', 'RD 482 K', '0788100123', array['Xxx MUGABO'], 6000, '2026-11-01');

insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000c1');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is(public.join_team('test-team-code', 'Aline') ->> 'ok', 'true', 'Aline joins');

create temp table k as select public.enable_reader('M-Money') as reader_key;
grant select on k to anon, authenticated;
select is(length((select reader_key from k)), 48, 'enable_reader returns a 48-character key');
select ok((select is_reader from public.devices), 'the phone is now a Reader');
select isnt((select reader_key_hash from public.devices), (select reader_key from k), 'only a hash is stored');

-- The background job runs with the publishable key only.
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is(public.reader_ingest('wrong-key', 6000, '2026-11-04 08:00+02', 'Xxx MUGABO', '*********123', 'FT-1') ->> 'status',
  'bad_key', 'a wrong key is refused');
select is(public.reader_ingest((select reader_key from k), 6000, '2026-11-04 08:00+02', 'xxx  mugabo', '*********123', 'FT-1') ->> 'status',
  'inserted', 'the right key uploads a matched payment');
select is(public.reader_ingest((select reader_key from k), 6000, '2026-11-04 08:00+02', 'Xxx MUGABO', '*********123', 'FT-1') ->> 'status',
  'duplicate', 'the same FT Id is only counted once');
select is(public.reader_ingest((select reader_key from k), 4000, '2026-11-04 08:10+02', 'Somebody ELSE', '*********111', 'FT-2') ->> 'status',
  'unmatched', 'unknown senders are not stored');

select is(public.reader_sync((select reader_key from k), 2) -> 'usernames', '["Xxx MUGABO"]'::jsonb,
  'sync returns the usernames to look for');
select is((select count(*)::int from public.payments), 0, 'anon still sees no payments directly');
reset role;

select is((select held_by_member_id from public.payments where tx_id = 'FT-1'),
  (select id from public.members where name = 'Aline'), 'the money is held by the Reader''s member');
select is((select unreadable_count from public.devices), 2, 'sync records messages that could not be read');

-- A quiet Reader raises an alert; the next sync resolves it.
update public.devices set last_checked_at = now() - interval '7 hours';
set local app.now = '2026-11-04 16:00+02';
select private.tick();
select is((select count(*)::int from public.alerts where type = 'reader_silent' and resolved_at is null), 1, 'quiet Reader alerts');
select is(public.reader_sync((select reader_key from k)) ->> 'ok', 'true', 'sync works');
select is((select count(*)::int from public.alerts where type = 'reader_silent' and resolved_at is null), 0, 'sync resolves it');

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}';
select public.disable_reader();
select is(public.reader_ingest((select reader_key from k), 6000, '2026-11-04 08:00+02', 'Xxx MUGABO', '*********123', 'FT-3') ->> 'status',
  'bad_key', 'turning the Reader off revokes its key');

select is(public.ingest_momo_payment(6000, '2026-11-04 08:30+02', 'Xxx MUGABO', '*********123', 'FT-4') ->> 'status',
  'inserted', 'the in-app upload path still works');

select * from finish();
rollback;
