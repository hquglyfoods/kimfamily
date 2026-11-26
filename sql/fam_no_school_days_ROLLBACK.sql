begin;
drop trigger if exists fam_check_weekend_ticket on public.fam_tickets;
drop trigger if exists fam_check_no_school_day on public.fam_no_school_days;
drop function if exists public.fam_check_weekend_ticket();
drop function if exists public.fam_is_shop_weekend(timestamptz);
drop function if exists public.fam_check_no_school_day();
drop index if exists public.fam_no_school_days_active_date_idx;
-- Dropping the table also removes its Realtime publication membership.
drop table if exists public.fam_no_school_days;
commit;
