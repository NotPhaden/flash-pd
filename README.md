# FLASH Management System – Member/Profile & Operations Update

## Included updates

- Member profile: real CNP fallback from RP account, call sign and badge details, profile avatar and cover/background uploads.
- Departments: Conducere headcount is calculated from rank level 8 (Subcomisar) and above; multiple department memberships are supported through `officer_departments`.
- Notifications: bell indicator, in-app toast and alert sound; polling fallback refreshes notifications even if Realtime publication is not enabled.
- Leave requests: only `Concediu` and `Învoire ședință`; own submissions and leadership approval/rejection.
- Actions: participants are listed, participation cannot be withdrawn, creator can cancel their own open action.
- Profile weekly activity is calculated from actual attendance hours.
- Audit journal is shown only to Subcomisar+ and command roles.
- Sanctions: insert RLS for Subcomisar+ and delete only for `super_admin` / `commander`.
- Radio codes and processing templates: rank-based write policies.
- Equipment and vehicles: real CRUD lists using the existing `equipment` and `vehicles` tables, linked to members in the personnel register.
- Removed public-facing Supabase connection/settings text from the interface.

## Supabase migration order

Only run `schema.sql` for a new/empty project. For an existing project, do not rerun the fresh schema.

For an existing FLASH installation, apply any earlier migrations that have not yet been applied, in this order:

1. `rp_accounts_migration.sql`
2. `flash_corrective_migration.sql`
3. `flash_functional_fixes.sql`
4. `sas_dcco_units_migration.sql`
5. `flash_profile_actions_migration.sql`
6. `flash_member_profile_inventory_fix.sql`

The two previously supplied migrations `flash_corrective_migration.sql` and `flash_profile_actions_migration.sql` have been corrected to avoid the malformed `DO $$` terminators that caused SQL syntax errors. Do not rerun migrations already applied unless you have a database backup and understand their effects.

## Notes

- `flash_member_profile_inventory_fix.sql` creates the multiple-department relation, storage bucket/policies, rank-based RLS, profile appearance RPC, and audit triggers.
- Profile uploads use the Supabase Storage bucket named `avatars` and a user-specific folder.
- The interface no longer exposes database-provider configuration details. Keep environment variables and keys in deployment configuration; never put a `service_role` key in browser code.
- `tsc --noEmit` passes. A production Next.js build could not complete in this environment because the Linux SWC binary was unavailable and network access to the package registry failed.
- Supabase migrations have not been run against the live project from this workspace.
