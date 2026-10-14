-- Phase 1.1: secure household task domain.
-- Preserve the existing family-member rows while removing the demo anonymous path.

begin;

alter default privileges in schema kumi_core revoke execute on functions from public;

create table kumi_core.household (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 100),
  created_at timestamptz not null default now()
);

comment on table kumi_core.household is 'Security and ownership boundary for Kumi family data.';

insert into kumi_core.household (id, name)
values ('00000000-0000-4000-8000-000000000100', 'Kumi Family')
on conflict (id) do nothing;

alter table kumi_core.kumi_family_member
  add column household_id uuid,
  add column role text;

update kumi_core.kumi_family_member
set
  household_id = '00000000-0000-4000-8000-000000000100',
  role = 'member'
where household_id is null or role is null;

alter table kumi_core.kumi_family_member
  add constraint kumi_family_member_household_fk
    foreign key (household_id) references kumi_core.household (id),
  add constraint kumi_family_member_role_check
    check (role in ('member', 'admin')),
  add constraint kumi_family_member_household_id_unique
    unique (household_id, id),
  alter column household_id set not null,
  alter column role set not null,
  alter column role set default 'member';

create table kumi_core.integration_identity (
  auth_user_id uuid primary key,
  label text not null check (char_length(btrim(label)) between 1 and 100),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table kumi_core.actor_identity (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  member_id uuid not null,
  provider text not null check (provider in ('line')),
  provider_user_id text not null check (char_length(btrim(provider_user_id)) between 1 and 255),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint actor_identity_household_fk
    foreign key (household_id) references kumi_core.household (id),
  constraint actor_identity_member_fk
    foreign key (household_id, member_id)
    references kumi_core.kumi_family_member (household_id, id),
  constraint actor_identity_provider_user_unique
    unique (provider, provider_user_id),
  constraint actor_identity_household_id_unique
    unique (household_id, id)
);

create table kumi_core.approved_conversation (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  provider text not null check (provider in ('line')),
  provider_chat_type text not null check (provider_chat_type in ('group', 'room')),
  provider_chat_id text not null check (char_length(btrim(provider_chat_id)) between 1 and 255),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint approved_conversation_household_fk
    foreign key (household_id) references kumi_core.household (id),
  constraint approved_conversation_provider_chat_unique
    unique (provider, provider_chat_type, provider_chat_id),
  constraint approved_conversation_household_id_unique
    unique (household_id, id)
);

create table kumi_core.family_task (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  title text not null check (char_length(btrim(title)) between 1 and 200),
  status text not null default 'open' check (status in ('open', 'completed')),
  assignee_member_id uuid,
  creator_member_id uuid not null,
  due_date date,
  completed_by_member_id uuid,
  completed_at timestamptz,
  version integer not null default 1 check (version >= 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint family_task_household_fk
    foreign key (household_id) references kumi_core.household (id),
  constraint family_task_assignee_fk
    foreign key (household_id, assignee_member_id)
    references kumi_core.kumi_family_member (household_id, id),
  constraint family_task_creator_fk
    foreign key (household_id, creator_member_id)
    references kumi_core.kumi_family_member (household_id, id),
  constraint family_task_completed_by_fk
    foreign key (household_id, completed_by_member_id)
    references kumi_core.kumi_family_member (household_id, id),
  constraint family_task_completion_consistent_check check (
    (status = 'open' and completed_by_member_id is null and completed_at is null)
    or
    (status = 'completed' and completed_by_member_id is not null and completed_at is not null)
  ),
  constraint family_task_household_id_unique unique (household_id, id)
);

create table kumi_core.task_event (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  task_id uuid not null,
  actor_member_id uuid not null,
  action text not null check (action in ('created', 'assigned', 'claimed', 'completed')),
  operation_key text not null check (char_length(operation_key) between 16 and 255),
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  before_state jsonb,
  after_state jsonb not null,
  created_at timestamptz not null default now(),
  constraint task_event_household_fk
    foreign key (household_id) references kumi_core.household (id),
  constraint task_event_task_fk
    foreign key (household_id, task_id)
    references kumi_core.family_task (household_id, id),
  constraint task_event_actor_fk
    foreign key (household_id, actor_member_id)
    references kumi_core.kumi_family_member (household_id, id),
  constraint task_event_operation_key_unique unique (operation_key)
);

create index family_task_open_household_due_idx
  on kumi_core.family_task (household_id, due_date nulls last, created_at)
  where status = 'open';

create index family_task_open_assignee_due_idx
  on kumi_core.family_task (household_id, assignee_member_id, due_date nulls last, created_at)
  where status = 'open';

alter table kumi_core.household enable row level security;
alter table kumi_core.integration_identity enable row level security;
alter table kumi_core.actor_identity enable row level security;
alter table kumi_core.approved_conversation enable row level security;
alter table kumi_core.family_task enable row level security;
alter table kumi_core.task_event enable row level security;

drop policy if exists kumi_family_member_read_all on kumi_core.kumi_family_member;

revoke all on table kumi_core.kumi_family_member from anon, authenticated;
revoke all on table kumi_core.household from anon, authenticated;
revoke all on table kumi_core.integration_identity from anon, authenticated;
revoke all on table kumi_core.actor_identity from anon, authenticated;
revoke all on table kumi_core.approved_conversation from anon, authenticated;
revoke all on table kumi_core.family_task from anon, authenticated;
revoke all on table kumi_core.task_event from anon, authenticated;

revoke usage on schema kumi_core from anon;
grant usage on schema kumi_core to authenticated;

comment on table kumi_core.integration_identity is 'Allowlisted Supabase Auth users permitted to invoke Kumi RPCs.';
comment on table kumi_core.actor_identity is 'Maps a verified channel user to a household member.';
comment on table kumi_core.approved_conversation is 'Allowlisted non-private conversations for one household.';
comment on table kumi_core.family_task is 'Household-owned shared tasks for the Phase 1 family loop.';
comment on table kumi_core.task_event is 'Append-only structural audit and idempotency record; excludes task free text.';

commit;
