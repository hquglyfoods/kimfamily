begin;

create table public.fam_no_school_days (
  id uuid primary key default gen_random_uuid(),
  day_date date not null,
  status text not null check (status in ('pending', 'approved', 'denied')),
  requested_by uuid references public.fam_users(id),
  approved_by uuid references public.fam_users(id),
  approved_at timestamptz,
  denied_by uuid references public.fam_users(id),
  note text,
  created_at timestamptz default now()
);

create unique index fam_no_school_days_active_date_idx
  on public.fam_no_school_days (day_date)
  where status in ('pending', 'approved');

alter table public.fam_no_school_days enable row level security;
create policy fam_no_school_days_open on public.fam_no_school_days
  for all using (true) with check (true);
grant all on table public.fam_no_school_days to anon, authenticated, public;

create function public.fam_check_no_school_day()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    if new.day_date is distinct from old.day_date
       or new.requested_by is distinct from old.requested_by
       or (old.status <> 'pending' and new.status is distinct from old.status) then
      raise exception 'no_school_invalid_transition';
    end if;
  end if;

  if new.status = 'approved' then
    if new.denied_by is not null or not exists (
      select 1 from public.fam_users
      where id = new.approved_by and role in ('dad', 'mom', 'gran')
    ) then
      raise exception 'no_school_parent_required';
    end if;
    if tg_op = 'INSERT' then
      new.approved_at := now();
    elsif old.status = 'pending' then
      new.approved_at := now();
    else
      new.approved_at := old.approved_at;
    end if;
  elsif new.status = 'denied' then
    if new.approved_by is not null or not exists (
      select 1 from public.fam_users
      where id = new.denied_by and role in ('dad', 'mom', 'gran')
    ) then
      raise exception 'no_school_parent_required';
    end if;
    new.approved_at := null;
  elsif new.approved_by is not null or new.denied_by is not null or new.approved_at is not null then
    raise exception 'no_school_invalid_transition';
  end if;
  return new;
end;
$$;

create trigger fam_check_no_school_day
  before insert or update on public.fam_no_school_days
  for each row execute function public.fam_check_no_school_day();

create function public.fam_is_shop_weekend(ts timestamptz default now())
returns boolean language sql stable set search_path = '' as $$
  select extract(dow from ny.local_time) in (0, 6)
    or (extract(dow from ny.local_time) = 5 and ny.local_time::time >= time '18:00')
    or exists (
      select 1 from public.fam_no_school_days
      where day_date = ny.local_time::date and status = 'approved'
    )
  from (select ts at time zone 'America/New_York' as local_time) ny;
$$;

create function public.fam_check_weekend_ticket()
returns trigger language plpgsql set search_path = '' as $$
declare
  item_minutes integer;
  child_settings jsonb;
  purchased timestamptz := coalesce(new.purchased_at, now());
  ny_date date := (purchased at time zone 'America/New_York')::date;
  used_minutes bigint;
begin
  if new.paid_gold is true then
    return new;
  end if;

  select coalesce(timer_minutes, 60) into item_minutes
    from public.fam_store_items where id = new.item_id and weekend_only;
  if not found then
    return new;
  end if;

  select settings into child_settings from public.fam_users where id = new.child_id;
  if (child_settings->>'weekday_ok') is distinct from 'true'
     and not public.fam_is_shop_weekend(purchased) then
    raise exception 'no_school_or_weekend_required';
  end if;

  -- Serialize purchases for this child and date before reading the daily total.
  perform pg_advisory_xact_lock(hashtext(new.child_id::text), ny_date - date '2000-01-01');
  select coalesce(sum(coalesce(i.timer_minutes, 60)), 0) into used_minutes
    from public.fam_tickets t join public.fam_store_items i on i.id = t.item_id
    where t.child_id = new.child_id and i.weekend_only and t.paid_gold is not true
      and t.purchased_at >= (ny_date::timestamp at time zone 'America/New_York')
      and t.purchased_at < ((ny_date + 1)::timestamp at time zone 'America/New_York');

  if used_minutes + item_minutes > coalesce((child_settings->>'daily_cap_min')::integer, 120) then
    raise exception 'weekend_cap_exceeded';
  end if;
  new.purchased_at := purchased;
  return new;
end;
$$;

create trigger fam_check_weekend_ticket
  before insert on public.fam_tickets
  for each row execute function public.fam_check_weekend_ticket();

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime' and not puballtables) then
    alter publication supabase_realtime add table public.fam_no_school_days;
  end if;
end;
$$;

commit;
