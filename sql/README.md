# Family No School Day

**Nothing has been applied to production.**

After John approves the release, apply [fam_no_school_days.sql](fam_no_school_days.sql) first. It requires the existing `fam_users`, `fam_store_items`, and `fam_tickets` tables. The migration adds the new table to the existing `supabase_realtime` publication when that publication exists. Then update `fam_site.content` from [app/index.html](../app/index.html).

To roll back after a release, restore the previous client content first, then run [fam_no_school_days_ROLLBACK.sql](fam_no_school_days_ROLLBACK.sql). The rollback deletes the request history.

The approval trigger validates the roles of the profile IDs stored in `approved_by` and `denied_by`. Profile login uses the existing anonymous Data API session, so the database cannot verify that the caller owns the supplied parent profile ID. The UI restricts approvals and denials to parent profiles.
