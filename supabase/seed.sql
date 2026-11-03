-- Local development data only (runs on `supabase db reset`, never on the real project).
-- Mirrors the design canvas: three bikes since 1 Oct 2026 and a fourth, switched off.

select private.set_team_code('local-dev-code');

insert into public.members (id, name, momo_number) values
  ('10000000-0000-0000-0000-000000000001', 'Aline', '0788551102'),
  ('10000000-0000-0000-0000-000000000002', 'Kevin', '0789330664'),
  ('10000000-0000-0000-0000-000000000003', 'Grace', null);

insert into public.vehicles (id, driver_name, plate, phone, momo_usernames, amount, rest_weekdays, start_date, is_active) values
  ('20000000-0000-0000-0000-000000000001', 'Emmanuel Mugabo', 'RD 482 K', '0788100123', array['Xxx MUGABO'], 6000, '{}', '2026-10-01', true),
  ('20000000-0000-0000-0000-000000000002', 'Eric Mugisha', 'RE 115 C', '0789640118', array['Eric MUGISHA'], 6000, '{7}', '2026-10-01', true),
  ('20000000-0000-0000-0000-000000000003', 'Patrick Uwimana', 'RD 907 F', '0782412390', array['Patrick UWIMANA', 'Xxx UWIMANA'], 6000, '{7}', '2026-10-01', true),
  ('20000000-0000-0000-0000-000000000004', 'Jean Claude Niyonsaba', 'RF 230 A', '0785337021', array['Jean Claude NIYONSABA'], 6000, '{7}', '2026-11-03', false);

do $$
declare
  aline constant uuid := '10000000-0000-0000-0000-000000000001';
  kevin constant uuid := '10000000-0000-0000-0000-000000000002';
  grace constant uuid := '10000000-0000-0000-0000-000000000003';
  emmanuel constant uuid := '20000000-0000-0000-0000-000000000001';
  eric constant uuid := '20000000-0000-0000-0000-000000000002';
  patrick constant uuid := '20000000-0000-0000-0000-000000000003';
  d date;
  sunday boolean;
  amt integer;
  n integer := 0;
begin
  for d in select g::date from generate_series(date '2026-10-01', least(private.today(), date '2026-11-03'), interval '1 day') g loop
    sunday := extract(isodow from d) = 7;

    -- Emmanuel: every day; paid two days at once on Sun 1 Nov.
    amt := case d when '2026-11-01' then 12000 when '2026-11-02' then 0 else 6000 end;
    if amt > 0 then
      n := n + 1;
      insert into public.payments (vehicle_id, amount, paid_at, source, sender_name, tx_id, held_by_member_id, recorded_by_member_id)
      values (emmanuel, amt, private.at_local(d, case d when '2026-11-03' then time '07:42' else time '18:20' end),
              'momo', 'Xxx MUGABO', 'SEED' || n, aline, aline);
    end if;

    -- Eric: rest on Sundays, a few late days, short on 28 Oct.
    if not sunday then
      amt := case d when '2026-10-07' then 0 when '2026-10-08' then 12000 when '2026-10-20' then 0
                    when '2026-10-22' then 12000 when '2026-10-28' then 3000 when '2026-10-29' then 9000
                    when '2026-11-02' then 4000 when '2026-11-03' then 3000 else 6000 end;
      if amt > 0 then
        n := n + 1;
        insert into public.payments (vehicle_id, amount, paid_at, source, sender_name, tx_id, held_by_member_id, recorded_by_member_id)
        values (eric, amt, private.at_local(d, time '15:00'), 'momo', 'Eric MUGISHA', 'SEED' || n, aline, aline);
      end if;
      if d = '2026-11-02' then
        n := n + 1;
        insert into public.payments (vehicle_id, amount, paid_at, source, sender_name, tx_id, held_by_member_id, recorded_by_member_id)
        values (eric, 2000, private.at_local(d, time '21:14'), 'momo', 'Eric MUGISHA', 'SEED' || n, aline, aline);
      end if;
    end if;

    -- Patrick: rest on Sundays, missed days caught up later, one cash day.
    if not sunday then
      amt := case d when '2026-10-14' then 0 when '2026-10-15' then 12000 when '2026-10-21' then 0
                    when '2026-10-23' then 12000 when '2026-10-30' then 0 when '2026-10-31' then 0
                    when '2026-11-02' then 12000 when '2026-11-03' then 0 else 6000 end;
      if amt > 0 and d = '2026-10-28' then
        insert into public.payments (vehicle_id, amount, paid_at, source, held_by_member_id, recorded_by_member_id)
        values (patrick, amt, private.at_local(d, time '12:10'), 'cash', grace, grace);
      elsif amt > 0 then
        n := n + 1;
        insert into public.payments (vehicle_id, amount, paid_at, source, sender_name, tx_id, held_by_member_id, recorded_by_member_id)
        values (patrick, amt, private.at_local(d, case d when '2026-11-02' then time '18:44' else time '19:05' end),
                'momo', 'Patrick UWIMANA', 'SEED' || n, kevin, kevin);
      end if;
    end if;
  end loop;
end $$;

insert into public.deposits (member_id, amount, fee, deposited_on, reference) values
  ('10000000-0000-0000-0000-000000000001', 100000, 500, '2026-10-10', 'SLIP-1010'),
  ('10000000-0000-0000-0000-000000000002', 60000, 500, '2026-10-15', 'SLIP-1015'),
  ('10000000-0000-0000-0000-000000000001', 100000, 500, '2026-10-20', 'SLIP-1020'),
  ('10000000-0000-0000-0000-000000000002', 60000, 500, '2026-10-30', 'SLIP-1030'),
  ('10000000-0000-0000-0000-000000000001', 100000, 500, '2026-10-31', 'SLIP-1031');
