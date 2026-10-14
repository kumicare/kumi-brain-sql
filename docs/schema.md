# Phase 1.1 Schema

All durable family task data lives in `kumi_core` and is scoped by
`household_id`.

## Tables

- `household`: the authorization and ownership boundary.
- `kumi_family_member`: existing member table, migrated in place with
  `household_id` and `role` (`member|admin`). Existing IDs are preserved.
- `integration_identity`: allowlisted Supabase Auth UIDs permitted to invoke
  Kumi RPCs.
- `actor_identity`: maps verified LINE user IDs to household members.
- `approved_conversation`: allowlists LINE group/room IDs. Private chats are
  authorized by actor identity; groups require both actor and conversation.
- `family_task`: immutable title plus open/completed status, creator, optional
  assignee/due date, completion actor/time, and optimistic `version`.
- `task_event`: append-only mutation audit and idempotency record. It stores
  structural state only and never duplicates task titles or private notes.

## Household integrity

Household-scoped relationships use composite `(household_id, id)` foreign
keys. A task, actor, or event cannot reference a member or task belonging to a
different household even if RPC validation has a defect.

## State transitions

Beta supports create, assign/reassign under authorization, claim an unassigned
task, and complete. Delete, archive, reopen, generic updates, recurrence, and
free-text notes are intentionally absent.
