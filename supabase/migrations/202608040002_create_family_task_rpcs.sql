-- Phase 1.1: least-privilege, named RPC contracts for Hermes.

begin;

drop function if exists kumi_core.list_family_members();

create or replace function kumi_core.rpc_error(
  p_code text,
  p_message text,
  p_latest jsonb default null
)
returns jsonb
language sql
immutable
security invoker
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'ok', false,
    'error', jsonb_build_object(
      'code', p_code,
      'message', p_message,
      'latest', p_latest
    )
  ));
$$;

create or replace function kumi_core.task_state(p_task kumi_core.family_task)
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog, kumi_core
as $$
  select jsonb_build_object(
    'id', p_task.id,
    'title', p_task.title,
    'status', p_task.status,
    'assignee_member_id', p_task.assignee_member_id,
    'creator_member_id', p_task.creator_member_id,
    'due_date', p_task.due_date,
    'completed_by_member_id', p_task.completed_by_member_id,
    'completed_at', p_task.completed_at,
    'version', p_task.version,
    'created_at', p_task.created_at,
    'updated_at', p_task.updated_at
  );
$$;

create or replace function kumi_core.task_audit_state(p_task kumi_core.family_task)
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog, kumi_core
as $$
  select jsonb_build_object(
    'status', p_task.status,
    'assignee_member_id', p_task.assignee_member_id,
    'due_date', p_task.due_date,
    'completed_by_member_id', p_task.completed_by_member_id,
    'completed_at', p_task.completed_at,
    'version', p_task.version
  );
$$;

create or replace function kumi_core.authorized_actor(
  p_provider text,
  p_provider_user_id text,
  p_chat_type text,
  p_chat_id text
)
returns kumi_core.actor_identity
language plpgsql
stable
security definer
set search_path = pg_catalog, kumi_core
as $$
declare
  v_actor kumi_core.actor_identity;
begin
  if auth.uid() is null or not exists (
    select 1
    from kumi_core.integration_identity as integration
    where integration.auth_user_id = auth.uid()
      and integration.active
  ) then
    return null;
  end if;

  select actor.*
  into v_actor
  from kumi_core.actor_identity as actor
  where actor.provider = p_provider
    and actor.provider_user_id = p_provider_user_id
    and actor.active;

  if not found then
    return null;
  end if;

  if p_chat_type not in ('private', 'group', 'room') then
    return null;
  end if;

  if p_chat_type <> 'private' and not exists (
    select 1
    from kumi_core.approved_conversation as conversation
    where conversation.household_id = v_actor.household_id
      and conversation.provider = p_provider
      and conversation.provider_chat_type = p_chat_type
      and conversation.provider_chat_id = p_chat_id
      and conversation.active
  ) then
    return null;
  end if;

  return v_actor;
end;
$$;

create or replace function kumi_core.replay_result(
  p_household_id uuid,
  p_operation_key text,
  p_payload_hash text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, kumi_core
as $$
declare
  v_event kumi_core.task_event;
  v_task kumi_core.family_task;
begin
  select event.* into v_event
  from kumi_core.task_event as event
  where event.household_id = p_household_id
    and event.operation_key = p_operation_key;

  if not found then
    return null;
  end if;

  if v_event.payload_hash <> p_payload_hash then
    return kumi_core.rpc_error(
      'replay_mismatch',
      'The operation key was already used with a different payload.'
    );
  end if;

  select task.* into v_task
  from kumi_core.family_task as task
  where task.household_id = v_event.household_id
    and task.id = v_event.task_id;

  return jsonb_build_object(
    'ok', true,
    'data', kumi_core.task_state(v_task) || v_event.after_state,
    'replayed', true
  );
end;
$$;

create or replace function kumi_core.list_family_members(
  p_provider text,
  p_provider_user_id text,
  p_chat_type text,
  p_chat_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, kumi_core
as $$
declare
  v_actor kumi_core.actor_identity;
  v_members jsonb;
begin
  v_actor := kumi_core.authorized_actor(p_provider, p_provider_user_id, p_chat_type, p_chat_id);
  if v_actor.id is null then
    return kumi_core.rpc_error('forbidden', 'The integration, actor, or conversation is not authorized.');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', member.id,
    'name', member.name,
    'member_type', member.member_type,
    'role', member.role
  ) order by member.name), '[]'::jsonb)
  into v_members
  from kumi_core.kumi_family_member as member
  where member.household_id = v_actor.household_id;

  return jsonb_build_object('ok', true, 'data', v_members);
end;
$$;

create or replace function kumi_core.create_family_task(
  p_provider text,
  p_provider_user_id text,
  p_chat_type text,
  p_chat_id text,
  p_operation_key text,
  p_payload_hash text,
  p_title text,
  p_assignee_member_id uuid default null,
  p_due_date date default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, kumi_core
as $$
declare
  v_actor kumi_core.actor_identity;
  v_replay jsonb;
  v_task kumi_core.family_task;
begin
  v_actor := kumi_core.authorized_actor(p_provider, p_provider_user_id, p_chat_type, p_chat_id);
  if v_actor.id is null then
    return kumi_core.rpc_error('forbidden', 'The integration, actor, or conversation is not authorized.');
  end if;

  v_replay := kumi_core.replay_result(v_actor.household_id, p_operation_key, p_payload_hash);
  if v_replay is not null then
    return v_replay;
  end if;

  if char_length(btrim(coalesce(p_title, ''))) not between 1 and 200
    or p_operation_key is null
    or p_payload_hash !~ '^[0-9a-f]{64}$' then
    return kumi_core.rpc_error('invalid_input', 'Title or idempotency fields are invalid.');
  end if;

  if p_assignee_member_id is not null and not exists (
    select 1 from kumi_core.kumi_family_member as member
    where member.household_id = v_actor.household_id
      and member.id = p_assignee_member_id
  ) then
    return kumi_core.rpc_error('not_found', 'The assignee is not an active household member.');
  end if;

  insert into kumi_core.family_task (
    household_id, title, assignee_member_id, creator_member_id, due_date
  ) values (
    v_actor.household_id, btrim(p_title), p_assignee_member_id, v_actor.member_id, p_due_date
  ) returning * into v_task;

  insert into kumi_core.task_event (
    household_id, task_id, actor_member_id, action,
    operation_key, payload_hash, before_state, after_state
  ) values (
    v_task.household_id, v_task.id, v_actor.member_id, 'created',
    p_operation_key, p_payload_hash, null, kumi_core.task_audit_state(v_task)
  );

  return jsonb_build_object('ok', true, 'data', kumi_core.task_state(v_task), 'replayed', false);
exception
  when unique_violation then
    v_replay := kumi_core.replay_result(v_actor.household_id, p_operation_key, p_payload_hash);
    if v_replay is not null then
      return v_replay;
    end if;
    raise;
end;
$$;

create or replace function kumi_core.list_family_tasks(
  p_provider text,
  p_provider_user_id text,
  p_chat_type text,
  p_chat_id text,
  p_scope text default null,
  p_status text default 'open',
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, kumi_core
as $$
declare
  v_actor kumi_core.actor_identity;
  v_scope text;
  v_tasks jsonb;
begin
  v_actor := kumi_core.authorized_actor(p_provider, p_provider_user_id, p_chat_type, p_chat_id);
  if v_actor.id is null then
    return kumi_core.rpc_error('forbidden', 'The integration, actor, or conversation is not authorized.');
  end if;

  v_scope := coalesce(p_scope, case when p_chat_type = 'private' then 'mine' else 'household' end);
  if v_scope not in ('mine', 'household', 'unassigned')
    or p_status not in ('open', 'completed')
    or p_limit not between 1 and 50 then
    return kumi_core.rpc_error('invalid_input', 'Scope, status, or limit is invalid.');
  end if;

  select coalesce(jsonb_agg(task_json order by due_date nulls last, created_at), '[]'::jsonb)
  into v_tasks
  from (
    select kumi_core.task_state(task) as task_json, task.due_date, task.created_at
    from kumi_core.family_task as task
    where task.household_id = v_actor.household_id
      and task.status = p_status
      and (
        v_scope = 'household'
        or (v_scope = 'mine' and task.assignee_member_id = v_actor.member_id)
        or (v_scope = 'unassigned' and task.assignee_member_id is null)
      )
    order by task.due_date nulls last, task.created_at
    limit p_limit
  ) as selected_tasks;

  return jsonb_build_object('ok', true, 'data', v_tasks);
end;
$$;

create or replace function kumi_core.assign_family_task(
  p_provider text,
  p_provider_user_id text,
  p_chat_type text,
  p_chat_id text,
  p_operation_key text,
  p_payload_hash text,
  p_task_id uuid,
  p_assignee_member_id uuid,
  p_expected_version integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, kumi_core
as $$
declare
  v_actor kumi_core.actor_identity;
  v_replay jsonb;
  v_current kumi_core.family_task;
  v_updated kumi_core.family_task;
  v_is_admin boolean;
begin
  v_actor := kumi_core.authorized_actor(p_provider, p_provider_user_id, p_chat_type, p_chat_id);
  if v_actor.id is null then
    return kumi_core.rpc_error('forbidden', 'The integration, actor, or conversation is not authorized.');
  end if;

  v_replay := kumi_core.replay_result(v_actor.household_id, p_operation_key, p_payload_hash);
  if v_replay is not null then return v_replay; end if;

  select task.* into v_current
  from kumi_core.family_task as task
  where task.household_id = v_actor.household_id and task.id = p_task_id;
  if not found then return kumi_core.rpc_error('not_found', 'Task not found.'); end if;

  select member.role = 'admin' into v_is_admin
  from kumi_core.kumi_family_member as member
  where member.household_id = v_actor.household_id and member.id = v_actor.member_id;

  if not exists (
    select 1 from kumi_core.kumi_family_member as member
    where member.household_id = v_actor.household_id and member.id = p_assignee_member_id
  ) then
    return kumi_core.rpc_error('not_found', 'Assignee not found.');
  end if;

  if v_current.status <> 'open'
    or not (v_is_admin or (v_current.assignee_member_id is null and v_current.creator_member_id = v_actor.member_id)) then
    return kumi_core.rpc_error('forbidden', 'Actor cannot assign this task.');
  end if;

  update kumi_core.family_task as task
  set assignee_member_id = p_assignee_member_id, version = task.version + 1, updated_at = now()
  where task.household_id = v_actor.household_id
    and task.id = p_task_id
    and task.version = p_expected_version
    and task.status = 'open'
  returning * into v_updated;

  if not found then
    select task.* into v_current from kumi_core.family_task as task
    where task.household_id = v_actor.household_id and task.id = p_task_id;
    return kumi_core.rpc_error('conflict', 'Task changed before assignment.', kumi_core.task_state(v_current));
  end if;

  insert into kumi_core.task_event values (
    gen_random_uuid(), v_updated.household_id, v_updated.id, v_actor.member_id, 'assigned',
    p_operation_key, p_payload_hash, kumi_core.task_audit_state(v_current), kumi_core.task_audit_state(v_updated), now()
  );
  return jsonb_build_object('ok', true, 'data', kumi_core.task_state(v_updated), 'replayed', false);
exception when unique_violation then
  v_replay := kumi_core.replay_result(v_actor.household_id, p_operation_key, p_payload_hash);
  if v_replay is not null then return v_replay; end if;
  raise;
end;
$$;

create or replace function kumi_core.claim_family_task(
  p_provider text,
  p_provider_user_id text,
  p_chat_type text,
  p_chat_id text,
  p_operation_key text,
  p_payload_hash text,
  p_task_id uuid,
  p_expected_version integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, kumi_core
as $$
declare
  v_actor kumi_core.actor_identity;
  v_replay jsonb;
  v_current kumi_core.family_task;
  v_updated kumi_core.family_task;
begin
  v_actor := kumi_core.authorized_actor(p_provider, p_provider_user_id, p_chat_type, p_chat_id);
  if v_actor.id is null then return kumi_core.rpc_error('forbidden', 'The integration, actor, or conversation is not authorized.'); end if;
  v_replay := kumi_core.replay_result(v_actor.household_id, p_operation_key, p_payload_hash);
  if v_replay is not null then return v_replay; end if;

  select task.* into v_current from kumi_core.family_task as task
  where task.household_id = v_actor.household_id and task.id = p_task_id;
  if not found then return kumi_core.rpc_error('not_found', 'Task not found.'); end if;

  update kumi_core.family_task as task
  set assignee_member_id = v_actor.member_id, version = task.version + 1, updated_at = now()
  where task.household_id = v_actor.household_id
    and task.id = p_task_id
    and task.version = p_expected_version
    and task.status = 'open'
    and task.assignee_member_id is null
  returning * into v_updated;

  if not found then
    select task.* into v_current from kumi_core.family_task as task
    where task.household_id = v_actor.household_id and task.id = p_task_id;
    return kumi_core.rpc_error('conflict', 'Task is no longer claimable.', kumi_core.task_state(v_current));
  end if;
  insert into kumi_core.task_event values (
    gen_random_uuid(), v_updated.household_id, v_updated.id, v_actor.member_id, 'claimed',
    p_operation_key, p_payload_hash, kumi_core.task_audit_state(v_current), kumi_core.task_audit_state(v_updated), now()
  );
  return jsonb_build_object('ok', true, 'data', kumi_core.task_state(v_updated), 'replayed', false);
exception when unique_violation then
  v_replay := kumi_core.replay_result(v_actor.household_id, p_operation_key, p_payload_hash);
  if v_replay is not null then return v_replay; end if;
  raise;
end;
$$;

create or replace function kumi_core.complete_family_task(
  p_provider text,
  p_provider_user_id text,
  p_chat_type text,
  p_chat_id text,
  p_operation_key text,
  p_payload_hash text,
  p_task_id uuid,
  p_expected_version integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, kumi_core
as $$
declare
  v_actor kumi_core.actor_identity;
  v_replay jsonb;
  v_current kumi_core.family_task;
  v_updated kumi_core.family_task;
  v_is_admin boolean;
begin
  v_actor := kumi_core.authorized_actor(p_provider, p_provider_user_id, p_chat_type, p_chat_id);
  if v_actor.id is null then return kumi_core.rpc_error('forbidden', 'The integration, actor, or conversation is not authorized.'); end if;
  v_replay := kumi_core.replay_result(v_actor.household_id, p_operation_key, p_payload_hash);
  if v_replay is not null then return v_replay; end if;

  select task.* into v_current from kumi_core.family_task as task
  where task.household_id = v_actor.household_id and task.id = p_task_id;
  if not found then return kumi_core.rpc_error('not_found', 'Task not found.'); end if;
  select member.role = 'admin' into v_is_admin from kumi_core.kumi_family_member as member
  where member.household_id = v_actor.household_id and member.id = v_actor.member_id;

  if v_current.status <> 'open' or not (
    v_is_admin
    or v_current.assignee_member_id = v_actor.member_id
    or (v_current.assignee_member_id is null and v_current.creator_member_id = v_actor.member_id)
  ) then return kumi_core.rpc_error('forbidden', 'Actor cannot complete this task.'); end if;

  update kumi_core.family_task as task
  set status = 'completed', completed_by_member_id = v_actor.member_id,
      completed_at = now(), version = task.version + 1, updated_at = now()
  where task.household_id = v_actor.household_id and task.id = p_task_id
    and task.version = p_expected_version and task.status = 'open'
  returning * into v_updated;

  if not found then
    select task.* into v_current from kumi_core.family_task as task
    where task.household_id = v_actor.household_id and task.id = p_task_id;
    return kumi_core.rpc_error('conflict', 'Task changed before completion.', kumi_core.task_state(v_current));
  end if;
  insert into kumi_core.task_event values (
    gen_random_uuid(), v_updated.household_id, v_updated.id, v_actor.member_id, 'completed',
    p_operation_key, p_payload_hash, kumi_core.task_audit_state(v_current), kumi_core.task_audit_state(v_updated), now()
  );
  return jsonb_build_object('ok', true, 'data', kumi_core.task_state(v_updated), 'replayed', false);
exception when unique_violation then
  v_replay := kumi_core.replay_result(v_actor.household_id, p_operation_key, p_payload_hash);
  if v_replay is not null then return v_replay; end if;
  raise;
end;
$$;

revoke all on function kumi_core.rpc_error(text, text, jsonb) from public, anon, authenticated;
revoke all on function kumi_core.task_state(kumi_core.family_task) from public, anon, authenticated;
revoke all on function kumi_core.task_audit_state(kumi_core.family_task) from public, anon, authenticated;
revoke all on function kumi_core.authorized_actor(text, text, text, text) from public, anon, authenticated;
revoke all on function kumi_core.replay_result(uuid, text, text) from public, anon, authenticated;

revoke all on function kumi_core.list_family_members(text, text, text, text) from public, anon;
revoke all on function kumi_core.create_family_task(text, text, text, text, text, text, text, uuid, date) from public, anon;
revoke all on function kumi_core.list_family_tasks(text, text, text, text, text, text, integer) from public, anon;
revoke all on function kumi_core.assign_family_task(text, text, text, text, text, text, uuid, uuid, integer) from public, anon;
revoke all on function kumi_core.claim_family_task(text, text, text, text, text, text, uuid, integer) from public, anon;
revoke all on function kumi_core.complete_family_task(text, text, text, text, text, text, uuid, integer) from public, anon;

grant execute on function kumi_core.list_family_members(text, text, text, text) to authenticated;
grant execute on function kumi_core.create_family_task(text, text, text, text, text, text, text, uuid, date) to authenticated;
grant execute on function kumi_core.list_family_tasks(text, text, text, text, text, text, integer) to authenticated;
grant execute on function kumi_core.assign_family_task(text, text, text, text, text, text, uuid, uuid, integer) to authenticated;
grant execute on function kumi_core.claim_family_task(text, text, text, text, text, text, uuid, integer) to authenticated;
grant execute on function kumi_core.complete_family_task(text, text, text, text, text, text, uuid, integer) to authenticated;

comment on function kumi_core.list_family_members(text, text, text, text) is 'Authorized household-member list for stable Kumi tools.';
comment on function kumi_core.create_family_task(text, text, text, text, text, text, text, uuid, date) is 'Create one household task with audit and idempotency.';
comment on function kumi_core.list_family_tasks(text, text, text, text, text, text, integer) is 'List authorized household tasks with chat-aware defaults.';
comment on function kumi_core.assign_family_task(text, text, text, text, text, text, uuid, uuid, integer) is 'Assign or reassign a task under household authorization.';
comment on function kumi_core.claim_family_task(text, text, text, text, text, text, uuid, integer) is 'Atomically claim an unassigned task.';
comment on function kumi_core.complete_family_task(text, text, text, text, text, text, uuid, integer) is 'Complete a task under household authorization.';

commit;
