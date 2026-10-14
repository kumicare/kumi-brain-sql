begin;

create extension if not exists pgtap with schema extensions;
select plan(24);

select ok(
  exists (select 1 from kumi_core.kumi_family_member where id = '00000000-0000-4000-8000-000000000001'),
  'existing family member IDs survive the household migration'
);

insert into kumi_core.kumi_family_member (
  id, household_id, role, name, member_type
) values
  ('00000000-0000-4000-8000-000000000011', '00000000-0000-4000-8000-000000000100', 'admin', 'Louis', 0),
  ('00000000-0000-4000-8000-000000000012', '00000000-0000-4000-8000-000000000100', 'member', 'Jacee', 0);

insert into kumi_core.integration_identity (auth_user_id, label)
values ('00000000-0000-4000-8000-000000000900', 'local test integration');

insert into kumi_core.actor_identity (
  id, household_id, member_id, provider, provider_user_id
) values
  ('00000000-0000-4000-8000-000000000021', '00000000-0000-4000-8000-000000000100', '00000000-0000-4000-8000-000000000011', 'line', 'U-louis'),
  ('00000000-0000-4000-8000-000000000022', '00000000-0000-4000-8000-000000000100', '00000000-0000-4000-8000-000000000012', 'line', 'U-jacee');

insert into kumi_core.approved_conversation (
  household_id, provider, provider_chat_type, provider_chat_id
) values (
  '00000000-0000-4000-8000-000000000100', 'line', 'group', 'C-siblings'
);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000900', true);

select is(
  (kumi_core.list_family_members('line', 'U-louis', 'private', 'U-louis')->>'ok')::boolean,
  true,
  'an allowlisted integration and actor can list members in private chat'
);

select is(
  kumi_core.list_family_members('line', 'U-unknown', 'private', 'U-unknown')->'error'->>'code',
  'forbidden',
  'an unknown actor is denied'
);

select is(
  kumi_core.list_family_members('line', 'U-louis', 'group', 'C-unapproved')->'error'->>'code',
  'forbidden',
  'an unapproved group is denied'
);

select is(
  (kumi_core.list_family_members('line', 'U-louis', 'group', 'C-siblings')->>'ok')::boolean,
  true,
  'an approved group is authorized'
);

select is(
  (kumi_core.create_family_task(
    'line', 'U-louis', 'private', 'U-louis',
    'test:create:0001', repeat('a', 64), '申請長照交通',
    '00000000-0000-4000-8000-000000000012', date '2026-08-09'
  )->>'ok')::boolean,
  true,
  'admin creates an assigned task'
);

select is((select count(*) from kumi_core.family_task where title = '申請長照交通'), 1::bigint, 'create writes one task');
select is((select count(*) from kumi_core.task_event where operation_key = 'test:create:0001'), 1::bigint, 'create writes one audit event');

select is(
  (kumi_core.create_family_task(
    'line', 'U-louis', 'private', 'U-louis',
    'test:create:0001', repeat('a', 64), '申請長照交通',
    '00000000-0000-4000-8000-000000000012', date '2026-08-09'
  )->>'replayed')::boolean,
  true,
  'exact replay returns the stored operation result'
);

select is((select count(*) from kumi_core.family_task where title = '申請長照交通'), 1::bigint, 'exact replay does not duplicate the task');

select is(
  kumi_core.create_family_task(
    'line', 'U-louis', 'private', 'U-louis',
    'test:create:0001', repeat('b', 64), '不同內容', null, null
  )->'error'->>'code',
  'replay_mismatch',
  'same operation key with another payload is rejected'
);

select is(
  jsonb_array_length(kumi_core.list_family_tasks('line', 'U-jacee', 'private', 'U-jacee')->'data'),
  1,
  'private default lists tasks assigned to the actor'
);

select is(
  jsonb_array_length(kumi_core.list_family_tasks('line', 'U-louis', 'group', 'C-siblings')->'data'),
  1,
  'group default lists household tasks'
);

select is(
  (kumi_core.create_family_task(
    'line', 'U-louis', 'private', 'U-louis',
    'test:create:0002', repeat('c', 64), '領慢性處方箋', null, null
  )->>'ok')::boolean,
  true,
  'creator can create an unassigned task'
);

select is(
  (kumi_core.claim_family_task(
    'line', 'U-jacee', 'private', 'U-jacee',
    'test:claim:00001', repeat('d', 64),
    (select id from kumi_core.family_task where title = '領慢性處方箋'), 1
  )->>'ok')::boolean,
  true,
  'a household member can atomically claim an unassigned task'
);

select is(
  kumi_core.claim_family_task(
    'line', 'U-louis', 'private', 'U-louis',
    'test:claim:00002', repeat('e', 64),
    (select id from kumi_core.family_task where title = '領慢性處方箋'), 1
  )->'error'->>'code',
  'conflict',
  'a stale simultaneous claim loses with conflict'
);

select is(
  (kumi_core.complete_family_task(
    'line', 'U-jacee', 'private', 'U-jacee',
    'test:complete:0001', repeat('f', 64),
    (select id from kumi_core.family_task where title = '領慢性處方箋'), 2
  )->>'ok')::boolean,
  true,
  'assignee can complete their task'
);

select is(
  (select status from kumi_core.family_task where title = '領慢性處方箋'),
  'completed',
  'completion persists the state transition'
);

select ok(
  not exists (
    select 1 from kumi_core.task_event
    where before_state ? 'title' or after_state ? 'title'
  ),
  'audit state does not copy task titles'
);

select ok(
  not has_table_privilege('anon', 'kumi_core.family_task', 'select'),
  'anonymous callers have no task table access'
);

select ok(
  not has_function_privilege(
    'anon',
    'kumi_core.create_family_task(text,text,text,text,text,text,text,uuid,date)',
    'execute'
  ),
  'anonymous callers cannot execute mutation RPCs'
);

select ok(
  has_function_privilege(
    'authenticated',
    'kumi_core.list_family_tasks(text,text,text,text,text,text,integer)',
    'execute'
  ),
  'authenticated callers may execute named task RPCs'
);

insert into kumi_core.household (id, name)
values ('00000000-0000-4000-8000-000000000101', 'Other Household');

select throws_ok(
  $$insert into kumi_core.family_task (
      household_id, title, creator_member_id
    ) values (
      '00000000-0000-4000-8000-000000000101',
      'Cross household violation',
      '00000000-0000-4000-8000-000000000011'
    )$$,
  '23503',
  null,
  'composite foreign keys reject cross-household member references'
);

select is(
  kumi_core.assign_family_task(
    'line', 'U-jacee', 'private', 'U-jacee',
    'test:assign:denied', repeat('1', 64),
    (select id from kumi_core.family_task where title = '申請長照交通'),
    '00000000-0000-4000-8000-000000000011', 1
  )->'error'->>'code',
  'forbidden',
  'a non-admin cannot reassign an assigned task'
);

select * from finish();
rollback;
