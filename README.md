# kumi-brain-sql

Kumi Brain's Supabase/PostgreSQL schema repository.

Phase 1.1 source of truth for household identity, shared tasks, audit/idempotency,
least-privilege grants, and named RPC contracts used by Hermes.

## Start Here

- [docs/schema.md](docs/schema.md) - application schema notes
- [docs/rls.md](docs/rls.md) - current row-level security posture
- [docs/tools.md](docs/tools.md) - stable agent-facing tool contracts

## Local verification

```bash
supabase start -x realtime,storage-api,imgproxy,mailpit,studio,edge-runtime,logflare,vector,supavisor,postgres-meta
supabase db reset --local
supabase test db
```

The database tests cover existing-member preservation, actor/conversation
authorization, anonymous denial, household isolation, idempotent replay,
replay mismatch, optimistic conflicts, assignment, claim, completion, and
audit-data minimization.

## Production workflow

1. Resume and back up the linked project.
2. Compare `supabase migration list --linked` with local history.
3. Run `supabase db push --linked --dry-run`.
4. Apply with `supabase db push --linked`.
5. Create a dedicated Supabase Auth integration user.
6. Run `scripts/bootstrap_phase1.sql` with psql variables for the auth UID and
   current LINE allowlist IDs. Never place those values in migrations or Git.

## Care event domain

`supabase/migrations/20261001143143_create_care_event_notification_domain.sql`
adds the private `care` schema for sibling `kumi-center`: idempotent sensor events,
transactional LINE notification outbox, and payload-free rejection fingerprints.
The runtime role can select/insert events and select/insert/update notifications
and rejection summaries; it cannot delete, alter schema or read family-domain data.
Its login password is provisioned separately and must never enter migrations.
The schema is not exposed through PostgREST; all tables also have main-home RLS.
