set client_min_messages = warning;
set timezone = 'UTC';

create role anon;
create role authenticated;
create table fam_users (id uuid primary key, role text, settings jsonb);
create table fam_store_items (id int primary key, weekend_only boolean, timer_minutes int);
create table fam_tickets (
  child_id uuid references fam_users, item_id int references fam_store_items,
  paid_gold boolean, purchased_at timestamptz default now()
);
create publication supabase_realtime;
\ir ../sql/fam_no_school_days.sql

create function pg_temp.check_case(label text, query text, expected_error text default null)
returns text language plpgsql as $$
declare
  result boolean;
  actual_error text;
begin
  begin
    if query like 'select %' then
      execute query into result;
    else
      execute query;
    end if;
  exception when others then
    actual_error := sqlerrm;
  end;
  if expected_error is distinct from actual_error or result is false then
    raise exception 'FAIL % (expected error %, got %, result %)', label, expected_error, actual_error, result;
  end if;
  return 'PASS ' || label;
end;
$$;

insert into fam_users values
  ('00000000-0000-0000-0000-000000000001','child',null),
  ('00000000-0000-0000-0000-000000000002','child',null),
  ('00000000-0000-0000-0000-000000000003','child','{"weekday_ok":true,"daily_cap_min":60}'),
  ('00000000-0000-0000-0000-000000000004','mom',null);
insert into fam_store_items values (1,true,null), (2,false,null);

select pg_temp.check_case('NY cutoff and weekends', $$select
  not fam_is_shop_weekend('2026-11-06 22:59Z') and fam_is_shop_weekend('2026-11-06 23:00Z')
  and fam_is_shop_weekend('2026-07-10 22:00Z') and fam_is_shop_weekend('2026-11-07 12:00Z')
  and fam_is_shop_weekend('2026-11-08 12:00Z')$$);
insert into fam_no_school_days(day_date,status,requested_by)
  values ('2026-11-05','pending','00000000-0000-0000-0000-000000000001');
select pg_temp.check_case('pending blocks sibling duplicate', $$insert into fam_no_school_days(day_date,status,requested_by)
  values ('2026-11-05','pending','00000000-0000-0000-0000-000000000002')$$,
  'duplicate key value violates unique constraint "fam_no_school_days_active_date_idx"');
select pg_temp.check_case('pending weekday still blocks ticket', $$insert into fam_tickets values
  ('00000000-0000-0000-0000-000000000001',1,false,'2026-11-06 01:00Z')$$,'no_school_or_weekend_required');
select pg_temp.check_case('gold bypasses weekday lock', $$insert into fam_tickets values
  ('00000000-0000-0000-0000-000000000001',1,true,'2026-11-06 01:00Z')$$);
select pg_temp.check_case('weekday exception allows ticket', $$insert into fam_tickets values
  ('00000000-0000-0000-0000-000000000003',1,false,'2026-11-04 18:00Z')$$);
select pg_temp.check_case('weekday exception still observes custom cap', $$insert into fam_tickets values
  ('00000000-0000-0000-0000-000000000003',1,false,'2026-11-04 19:00Z')$$,'weekend_cap_exceeded');
select pg_temp.check_case('child profile cannot approve', $$update fam_no_school_days
  set status='approved',approved_by='00000000-0000-0000-0000-000000000001'$$,'no_school_parent_required');
select pg_temp.check_case('child profile cannot deny', $$update fam_no_school_days
  set status='denied',denied_by='00000000-0000-0000-0000-000000000001'$$,'no_school_parent_required');
update fam_no_school_days set status='denied',denied_by='00000000-0000-0000-0000-000000000004';
select pg_temp.check_case('denied request allows a new one', $$insert into fam_no_school_days(day_date,status,requested_by)
  values ('2026-11-05','pending','00000000-0000-0000-0000-000000000002')$$);
update fam_no_school_days set status='approved',approved_by='00000000-0000-0000-0000-000000000004' where status='pending';
select pg_temp.check_case('approval lasts through New York midnight', $$select
  fam_is_shop_weekend('2026-11-06 04:59Z') and not fam_is_shop_weekend('2026-11-06 05:00Z')$$);
select pg_temp.check_case('approved date blocks another request', $$insert into fam_no_school_days(day_date,status)
  values ('2026-11-05','pending')$$,'duplicate key value violates unique constraint "fam_no_school_days_active_date_idx"');
select pg_temp.check_case('approved request cannot go back to pending', $$update fam_no_school_days
  set status='pending',approved_by=null,approved_at=null where status='approved'$$,'no_school_invalid_transition');
select pg_temp.check_case('one approval permits purchases for all three kids', $$insert into fam_tickets
  select id,1,false,'2026-11-06 01:00Z'::timestamptz from fam_users where role='child'$$);
select pg_temp.check_case('gold does not count against cap on approved day', $$insert into fam_tickets values
  ('00000000-0000-0000-0000-000000000001',1,false,'2026-11-05 18:00Z')$$);
select pg_temp.check_case('approved date still enforces cap across UTC midnight', $$insert into fam_tickets values
  ('00000000-0000-0000-0000-000000000001',1,false,'2026-11-06 02:00Z')$$,'weekend_cap_exceeded');
select pg_temp.check_case('new table is on Realtime publication', $$select exists (
  select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='fam_no_school_days')$$);
\ir ../sql/fam_no_school_days_ROLLBACK.sql
select pg_temp.check_case('rollback removes the table and ticket guard', $$select
  to_regclass('public.fam_no_school_days') is null and
  not exists(select 1 from pg_trigger where tgname='fam_check_weekend_ticket')$$);
