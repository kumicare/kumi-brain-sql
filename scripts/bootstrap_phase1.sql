-- Operator-only bootstrap after migrations are applied.
-- Run with psql -v values; never commit real LINE IDs or auth credentials.
-- Required variables:
--   integration_auth_uid, louis_line_user_id, jacee_line_user_id, sibling_group_id

\if :{?integration_auth_uid}
\else
  \error integration_auth_uid is required
\endif
\if :{?louis_line_user_id}
\else
  \error louis_line_user_id is required
\endif
\if :{?jacee_line_user_id}
\else
  \error jacee_line_user_id is required
\endif
\if :{?sibling_group_id}
\else
  \error sibling_group_id is required
\endif

begin;

insert into kumi_core.kumi_family_member (
  id, household_id, role, name, member_type
) values
  ('00000000-0000-4000-8000-000000000011', '00000000-0000-4000-8000-000000000100', 'admin', 'Louis', 0),
  ('00000000-0000-4000-8000-000000000012', '00000000-0000-4000-8000-000000000100', 'member', 'Jacee', 0)
on conflict (id) do update set
  household_id = excluded.household_id,
  role = excluded.role,
  name = excluded.name,
  member_type = excluded.member_type,
  updated_at = now();

insert into kumi_core.integration_identity (auth_user_id, label, active)
values (:'integration_auth_uid'::uuid, 'Hermes VPS integration', true)
on conflict (auth_user_id) do update set
  label = excluded.label,
  active = true,
  updated_at = now();

insert into kumi_core.actor_identity (
  household_id, member_id, provider, provider_user_id, active
) values
  ('00000000-0000-4000-8000-000000000100', '00000000-0000-4000-8000-000000000011', 'line', :'louis_line_user_id', true),
  ('00000000-0000-4000-8000-000000000100', '00000000-0000-4000-8000-000000000012', 'line', :'jacee_line_user_id', true)
on conflict (provider, provider_user_id) do update set
  household_id = excluded.household_id,
  member_id = excluded.member_id,
  active = true,
  updated_at = now();

insert into kumi_core.approved_conversation (
  household_id, provider, provider_chat_type, provider_chat_id, active
) values (
  '00000000-0000-4000-8000-000000000100', 'line', 'group', :'sibling_group_id', true
)
on conflict (provider, provider_chat_type, provider_chat_id) do update set
  household_id = excluded.household_id,
  active = true,
  updated_at = now();

commit;
