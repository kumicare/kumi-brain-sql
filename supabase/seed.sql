-- Development seed data for local Supabase and smoke testing.
-- Do not put sensitive production data in this file.

insert into kumi_core.kumi_family_member (
  id,
  household_id,
  role,
  name,
  birthday,
  member_type,
  gender,
  description
)
values
  (
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000100',
    'member',
    'kumi',
    null,
    1,
    0,
    '貓貓酷咪老大'
  ),
  (
    '00000000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8000-000000000100',
    'member',
    'bally',
    date '2021-01-27',
    1,
    0,
    '西格瑪男'
  ),
  (
    '00000000-0000-4000-8000-000000000003',
    '00000000-0000-4000-8000-000000000100',
    'member',
    'pica',
    date '2021-01-27',
    1,
    1,
    '酪梨身材'
  )
on conflict (id) do update
set
  name = excluded.name,
  household_id = excluded.household_id,
  role = excluded.role,
  birthday = excluded.birthday,
  member_type = excluded.member_type,
  gender = excluded.gender,
  description = excluded.description,
  updated_at = now();
