-- Version 0.6.0
-- 1. Changing the deadline (or the "day missed" time) re-judges today: alerts
--    that would not have fired yet under the new time are removed, so they
--    fire again, with their Message driver option, at the new time. Moving
--    the time earlier keeps an alert that has already fired.
-- 2. Deleting a vehicle is for mistakes: its payments no longer count as
--    money a member holds. (Reports leave deleted vehicles out too.)

create function private.settings_after() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.deadline_time is distinct from old.deadline_time then
    delete from public.alerts a
    using public.dues d
    where a.due_id = d.id
      and a.type in ('unpaid_deadline', 'short_deadline')
      and d.due_date = private.today()
      and private.now() < private.at_local(d.due_date, new.deadline_time);
  end if;

  if new.missed_alert_offset is distinct from old.missed_alert_offset then
    delete from public.alerts a
    using public.dues d
    where a.due_id = d.id
      and a.type = 'missed_day'
      and private.now() < private.day_end(d.due_date) + new.missed_alert_offset;
  end if;

  return null;
end $$;

create trigger settings_after after update on public.settings
  for each row execute function private.settings_after();

create or replace view public.v_member_balances with (security_invoker = true) as
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
  select sum(p.amount) as received
  from public.payments p join public.vehicles v on v.id = p.vehicle_id
  where p.held_by_member_id = m.id and p.deleted_at is null and v.deleted_at is null
) r on true
left join lateral (
  select sum(x.amount) as deposited, sum(x.fee) as fees from public.deposits x
  where x.member_id = m.id and x.deleted_at is null
) dp on true;
