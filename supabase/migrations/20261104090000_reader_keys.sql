-- Reader phones upload payments with their own key, so the background job on
-- the phone never needs the app's login session (which expires and rotates).
-- The key is random, shown to the phone once, and stored here only as a hash.

alter table public.devices add column reader_key_hash text unique;

create function private.key_hash(p_key text) returns text
language sql immutable set search_path = '' as $$
  select encode(extensions.digest(coalesce(p_key, ''), 'sha256'), 'hex')
$$;

-- Username matching and the insert, shared by both upload paths.
create function private.ingest(
  p_member uuid, p_device uuid,
  p_amount integer, p_paid_at timestamptz, p_sender_name text, p_sender_phone text, p_tx_id text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  candidates uuid[];
  v public.vehicles;
  pid uuid;
begin
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
  values (v.id, p_amount, p_paid_at, 'momo', p_sender_name, p_sender_phone, btrim(p_tx_id), p_member, p_member)
  on conflict (tx_id) do nothing
  returning id into pid;

  update public.devices set last_checked_at = now() where id = p_device;
  return jsonb_build_object('status', case when pid is null then 'duplicate' else 'inserted' end,
                            'payment_id', pid, 'vehicle_id', v.id, 'plate', v.plate);
end $$;

-- Same behaviour as before, now through private.ingest.
create or replace function public.ingest_momo_payment(
  p_amount integer, p_paid_at timestamptz, p_sender_name text, p_sender_phone text, p_tx_id text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := private.current_member_id();
begin
  if me is null then
    return jsonb_build_object('status', 'not_a_member');
  end if;
  return private.ingest(me, auth.uid(), p_amount, p_paid_at, p_sender_name, p_sender_phone, p_tx_id);
end $$;

-- Turns this phone into a Reader and returns its key (only time it is shown).
create function public.enable_reader(p_sender text, p_template_id uuid default null) returns text
language plpgsql security definer set search_path = '' as $$
declare
  k text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  if not private.is_member() then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  update public.devices
  set is_reader = true, reader_sender = p_sender, template_id = p_template_id,
      reader_key_hash = private.key_hash(k), last_checked_at = now(), unreadable_count = 0
  where id = auth.uid();
  update public.alerts set resolved_at = now()
  where type = 'reader_silent' and device_id = auth.uid() and resolved_at is null;
  return k;
end $$;

create function public.disable_reader() returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.devices set is_reader = false, reader_key_hash = null where id = auth.uid();
  update public.alerts set resolved_at = now()
  where type = 'reader_silent' and device_id = auth.uid() and resolved_at is null;
end $$;

-- Background upload from a Reader phone, authenticated by its key.
create function public.reader_ingest(
  p_key text, p_amount integer, p_paid_at timestamptz, p_sender_name text, p_sender_phone text, p_tx_id text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  d public.devices;
begin
  select * into d from public.devices where reader_key_hash = private.key_hash(p_key) and is_reader;
  if not found then
    return jsonb_build_object('status', 'bad_key');
  end if;
  return private.ingest(d.member_id, d.id, p_amount, p_paid_at, p_sender_name, p_sender_phone, p_tx_id);
end $$;

-- Heartbeat after each inbox check. Returns the MoMo usernames to look for,
-- so the phone can ignore every other message without uploading it.
create function public.reader_sync(p_key text, p_unreadable integer default 0) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  d public.devices;
begin
  select * into d from public.devices where reader_key_hash = private.key_hash(p_key) and is_reader;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'bad_key');
  end if;
  update public.devices
  set last_checked_at = now(), unreadable_count = greatest(coalesce(p_unreadable, 0), 0)
  where id = d.id;
  update public.alerts set resolved_at = now()
  where type = 'reader_silent' and device_id = d.id and resolved_at is null;
  return jsonb_build_object('ok', true, 'usernames', coalesce(
    (select jsonb_agg(distinct u) from public.vehicles v, unnest(v.momo_usernames) u where v.deleted_at is null),
    '[]'::jsonb));
end $$;

revoke all on function private.key_hash(text) from public;
revoke all on function private.ingest(uuid, uuid, integer, timestamptz, text, text, text) from public;
revoke execute on function public.enable_reader(text, uuid) from public, anon;
revoke execute on function public.disable_reader() from public, anon;
revoke execute on function public.reader_ingest(text, integer, timestamptz, text, text, text) from public;
revoke execute on function public.reader_sync(text, integer) from public;
grant execute on function public.enable_reader(text, uuid) to authenticated;
grant execute on function public.disable_reader() to authenticated;
-- The background job only has the publishable key, so these run as anon.
grant execute on function public.reader_ingest(text, integer, timestamptz, text, text, text) to anon, authenticated;
grant execute on function public.reader_sync(text, integer) to anon, authenticated;
