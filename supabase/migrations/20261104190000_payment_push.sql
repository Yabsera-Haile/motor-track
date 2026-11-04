-- A notification on every phone when a driver pays, so a Motor Track
-- "Payment received" stands out from the other SMS on the MoMo phone.

alter table public.settings add column payment_push boolean not null default true;

-- send_push gains "everyone except this phone" (for cash: the phone that
-- recorded it already knows).
drop function private.send_push(text, text, jsonb);

create function private.send_push(
  p_title text, p_body text, p_data jsonb default '{}', p_except_device uuid default null
) returns void
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
  select jsonb_agg(distinct fcm_token) into tokens from public.devices
  where fcm_token is not null and id is distinct from p_except_device;
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

revoke all on function private.send_push(text, text, jsonb, uuid) from public;

create or replace function private.payments_after() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  left_over integer;
  owed integer;
  credit integer;
  v public.vehicles;
  s public.settings;
  who text;
  status text;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform private.recompute_vehicle(old.vehicle_id);
  end if;
  if tg_op = 'INSERT' or (tg_op = 'UPDATE' and new.vehicle_id <> old.vehicle_id) then
    perform private.recompute_vehicle(new.vehicle_id);
  end if;

  -- Only new money: a Reader catching up on old SMS stays quiet.
  if tg_op <> 'INSERT' or new.deleted_at is not null or new.paid_at <= private.now() - interval '2 days' then
    return null;
  end if;

  select * into s from public.settings;
  select * into v from public.vehicles where id = new.vehicle_id;
  select new.amount - coalesce(sum(a.amount), 0) into left_over
  from public.allocations a where a.payment_id = new.id;

  -- Overpayment: money left after every due so far is paid. Its alert is the
  -- one notification for this payment.
  if left_over > 0 and s.overpay_alerts then
    insert into public.alerts (type, vehicle_id, payment_id, title, body, data, dedupe_key)
    values ('overpayment', v.id, new.id, 'Overpayment',
            v.plate || ' · ' || v.driver_name || ' sent ' || private.rwf(new.amount)
              || ' RWF. ' || private.rwf(left_over) || ' kept as credit.',
            jsonb_build_object('plate', v.plate, 'driver', v.driver_name, 'phone', v.phone,
                               'sent', new.amount, 'credit', left_over, 'expected', v.amount),
            'overpayment:' || new.id)
    on conflict (dedupe_key) do nothing;
    return null;
  end if;

  if not s.payment_push then
    return null;
  end if;

  -- What is still unpaid up to and including the current period.
  select coalesce(sum(d.amount_due - d.amount_paid), 0)::integer into owed
  from public.dues d
  where d.vehicle_id = v.id and d.kind = 'due' and d.period_start <= private.today();
  -- The bike's whole credit (all payments minus what dues used), not just this payment's part.
  select greatest(0,
           coalesce((select sum(p.amount) from public.payments p where p.vehicle_id = v.id and p.deleted_at is null), 0)
           - coalesce((select sum(d.amount_paid) from public.dues d where d.vehicle_id = v.id), 0))::integer
  into credit;
  status := case
    when owed > 0 then 'Still owes ' || private.rwf(owed) || ' RWF.'
    when credit > 0 then 'All paid up, ' || private.rwf(credit) || ' RWF credit.'
    else 'All paid up.'
  end;

  if new.source = 'momo' then
    perform private.send_push('Payment received',
      v.plate || ' · ' || v.driver_name || ' sent ' || private.rwf(new.amount) || ' RWF. ' || status,
      jsonb_build_object('type', 'payment', 'vehicle_id', v.id, 'payment_id', new.id));
  else
    select name into who from public.members where id = coalesce(new.recorded_by_member_id, new.held_by_member_id);
    perform private.send_push(
      case when new.source = 'cash' then 'Cash payment' else 'Payment recorded' end,
      coalesce(who, 'Someone') || ' recorded ' || private.rwf(new.amount) || ' RWF'
        || case when new.source = 'cash' then ' cash' else '' end
        || ' from ' || v.plate || ' · ' || v.driver_name || '. ' || status,
      jsonb_build_object('type', 'payment', 'vehicle_id', v.id, 'payment_id', new.id),
      auth.uid());
  end if;
  return null;
end $$;
