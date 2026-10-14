# Phase 1.1 Authorization and RLS

Anonymous access is removed before real family data is inserted.

## Credential boundary

Hermes signs in as one dedicated Supabase Auth user using the project
publishable key. Every RPC requires its `auth.uid()` to be active in
`kumi_core.integration_identity`. The Hermes plugin never receives a
service-role credential.

## Grants

- `anon`: no `kumi_core` schema usage, table access, or RPC execution.
- `authenticated`: schema usage and execute only on the six named public RPCs.
- Tables: RLS enabled, with no direct client policies. `authenticated` has no
  direct table privileges.
- Helper functions: execution revoked from `public`, `anon`, and
  `authenticated`.
- Public RPCs: `SECURITY DEFINER`, fixed `search_path`, explicit integration,
  actor, household, and conversation checks.

## Domain authorization

- List: any active household actor; groups must be explicitly approved.
- Create: any active household actor.
- Assign unassigned: creator or admin.
- Reassign assigned: admin only.
- Claim unassigned: any active household actor for themselves.
- Complete: assignee, creator when unassigned, or admin.
- Delete/archive: unavailable.

Every mutation is transactional and appends one structural audit event.
Operation-key replay is checked before version/state checks.
