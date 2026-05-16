# Kumi Tool Contracts

Agent-facing tools use stable business names. Their implementation may change over time, but agents should not need to know whether a tool is currently backed by Supabase RPC, Supabase Edge Functions, or a future `kumi-api` service.

## `list_family_members`

Lists family member summaries known to Kumi Brain.

### Agent-facing contract

```json
{
  "name": "list_family_members",
  "description": "List family member summaries known to Kumi Brain.",
  "input": {}
}
```

### Output

Returns an array of family member summary objects ordered by `name`:

| Field | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` | Stable row identifier. |
| `name` | `text` | Display name. |
| `member_type` | `smallint` | Code: `0=human`, `1=pets`, `2=relative`. |
| `birthday` | `date \| null` | Calendar birthday when known. |
| `gender` | `smallint \| null` | Code: `0=male`, `1=female`. |
| `description` | `text \| null` | Short free-form summary. |

### Phase 1 implementation

Supabase RPC function:

```sql
kumi_core.list_family_members()
```

Example hosted API request:

```bash
curl -X POST \
  'https://uahzamhpbbzintsalqgg.supabase.co/rest/v1/rpc/list_family_members' \
  -H 'apikey: <anon-or-publishable-key>' \
  -H 'Authorization: Bearer <anon-or-user-jwt>' \
  -H 'Content-Profile: kumi_core'
```

Live verification on 2026-05-16 returned the current seed rows in `name` order.

### Replacement rule

Future implementations may move behind Supabase Edge Functions or a dedicated Spring Boot / `kumi-api` backend, but the agent-facing tool contract should remain `list_family_members`.

The implementation can change. The tool name and meaning should not.

### Current data note

The current repository seed data only contains demo records. That affects completeness of the data, not the stability of the tool contract.
