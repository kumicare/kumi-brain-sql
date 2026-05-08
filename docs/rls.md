# Row Level Security Notes

This document will describe Supabase RLS policies for Kumi Brain.

## Roles

- `anon`: Read-only access to `kumi_core.kumi_family_member` for the first OpenClaw smoke test.
- `authenticated`: Read-only access to `kumi_core.kumi_family_member` for the first OpenClaw smoke test.
- `service_role`: Granted table access for backend/server-side use. It bypasses RLS and must not be exposed to clients or agents.

## Policies

### `kumi_core.kumi_family_member`

Policy: `kumi_family_member_read_all`

Allows `anon` and `authenticated` roles to select all rows. This is intentionally permissive for the first smoke test where the table contains non-sensitive demo data.

## Service Access

Do not put the Supabase service role key in OpenClaw. For this smoke test, use the project URL plus anon/publishable key through the Supabase Data API.
