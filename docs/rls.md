# Row Level Security Notes

This document describes the current Supabase RLS posture for Kumi Brain.

## Roles

- `anon`: Read-only access to `kumi_core.kumi_family_member` while the dataset contains non-sensitive demo records only.
- `authenticated`: Read-only access to `kumi_core.kumi_family_member` while the dataset contains non-sensitive demo records only.
- `service_role`: Granted table access for backend/server-side use. It bypasses RLS and must not be exposed to clients or agents.

## Policies

### `kumi_core.kumi_family_member`

Policy: `kumi_family_member_read_all`

Allows `anon` and `authenticated` roles to select all rows. This is intentionally permissive only while the table contains non-sensitive demo data.

Before real family data is added, replace this policy with family-scoped access and remove any anonymous read path.

## Tool RPCs

### `kumi_core.list_family_members()`

The first stable Kumi tool contract is exposed as a `security invoker` RPC function. It inherits the caller's row access rather than bypassing RLS.

## Service Access

Do not put the Supabase service role key in OpenClaw. While only demo data exists, use the project URL plus anon/publishable key through the Supabase Data API. Before real family data is added, move the tool call behind authenticated access or a controlled backend boundary.
