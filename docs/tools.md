# Kumi Tool and RPC Contracts

Agent-facing names are stable even if the backend later moves behind an API.

| Tool / RPC | Domain input | Result |
| --- | --- | --- |
| `list_family_members` | none | active household member IDs, names, types, roles |
| `create_family_task` | title, optional exact assignee, optional ISO due date | created task |
| `list_family_tasks` | optional scope/status/limit | ordered task list |
| `assign_family_task` | task UUID, exact assignee, expected version | updated task or conflict |
| `claim_family_task` | task UUID, expected version | updated task or conflict |
| `complete_family_task` | task UUID, expected version | completed task or conflict |

Hermes adds provider, verified user/chat context, operation key, and payload
hash outside model arguments. RPCs return one JSON envelope:

```json
{"ok": true, "data": {}}
```

or:

```json
{"ok": false, "error": {"code": "conflict", "message": "...", "latest": {}}}
```

Stable expected codes are `forbidden`, `not_found`, `invalid_input`,
`conflict`, and `replay_mismatch`. Transport/unexpected failures are redacted
and mapped to `upstream_unavailable` by the plugin.

List defaults are `mine` in private chat and `household` in an approved group,
status `open`, due date ascending with nulls last, then creation time, maximum
50 rows.
