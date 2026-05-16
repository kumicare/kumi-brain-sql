# Schema Notes

This document will describe the Kumi Brain database model.

## Tables

## Schemas

### `kumi_core`

Core schema for Kumi Brain application data.

## Tables

### `kumi_core.kumi_family_member`

Stores family members that Kumi Brain can answer questions about. Members can be people or pets.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | `uuid` | yes | Primary key, generated with `gen_random_uuid()`. |
| `name` | `text` | yes | Display name of the family member. |
| `member_type` | `smallint` | yes | Code: `0=human`, `1=pets`, `2=relative`. |
| `birthday` | `date` | no | Nullable because pets may not have known birthdays. |
| `gender` | `smallint` | no | Code: `0=male`, `1=female`. |
| `description` | `text` | no | Free-form notes for OpenClaw or app display. |
| `created_at` | `timestamptz` | yes | Defaults to `now()`. |
| `updated_at` | `timestamptz` | yes | Defaults to `now()`; automatic update behavior can be added later. |

## Relationships

None yet.

## Functions

### `kumi_core.list_family_members()`

Stable RPC function behind the first Kumi tool contract, `list_family_members`.

Returns family member summary fields ordered by `name`:

- `id`
- `name`
- `member_type`
- `birthday`
- `gender`
- `description`

See [tools.md](tools.md) for the agent-facing contract.

## Sensitive Data

To be defined.
