-- Private deterministic care domain. Runtime is scoped to this MVP's main home.
create schema care;
revoke all on schema care from public, anon, authenticated;
create role kumi_center_runtime nologin nosuperuser nocreatedb nocreaterole noinherit nobypassrls;
grant usage on schema care to kumi_center_runtime;
create table care.sensor_event (
 event_id uuid primary key,
 home_id text not null check (home_id='main'),
 device_id text not null check (device_id='front-door'),
 event_type text not null check (event_type in ('OPEN','CLOSED','LEFT_OPEN')),
 occurred_at timestamptz not null,
 received_at timestamptz not null default now(),
 source text not null check (source in ('XIAOMI_BLE','SYNTHETIC_MQTT_ACCEPTANCE')),
 sequence bigint not null check (sequence>0),
 rssi integer not null,
 topic text not null check (topic='care/v1/home/main/device/front-door/event'),
 payload jsonb not null check (jsonb_typeof(payload)='object')
);
create index sensor_event_device_time on care.sensor_event(home_id,device_id,occurred_at desc);
create table care.notification (
 event_id uuid primary key references care.sensor_event(event_id),
 home_id text not null check(home_id='main'),
 retry_key uuid not null unique,
 request_body text not null,
 status text not null default 'PENDING' check(status in ('PENDING','SENDING','ACCEPTED','FAILED','EXPIRED')),
 attempts integer not null default 0 check(attempts>=0),
 created_at timestamptz not null default now(),
 next_attempt_at timestamptz not null default now(),
 first_attempt_at timestamptz,
 lease_until timestamptz,
 lease_owner uuid,
 accepted_at timestamptz,
 last_result text
);
create index notification_pending on care.notification(next_attempt_at,created_at) where status='PENDING';
create index notification_lease on care.notification(lease_until) where status='SENDING';
create table care.rejected_event (
 fingerprint text primary key check(length(fingerprint)=64),
 home_id text not null check(home_id='main'),
 reason text not null,
 first_seen_at timestamptz not null default now(),
 last_seen_at timestamptz not null default now(),
 deliveries bigint not null default 1
);
alter table care.sensor_event enable row level security;
alter table care.notification enable row level security;
alter table care.rejected_event enable row level security;
create policy main_home on care.sensor_event to kumi_center_runtime using(home_id='main') with check(home_id='main');
create policy main_home on care.notification to kumi_center_runtime using(home_id='main') with check(home_id='main');
create policy main_home on care.rejected_event to kumi_center_runtime using(home_id='main') with check(home_id='main');
revoke all on all tables in schema care from public,anon,authenticated;
grant select,insert on care.sensor_event to kumi_center_runtime;
grant select,insert,update on care.notification,care.rejected_event to kumi_center_runtime;
comment on schema care is 'Private MQTT event and LINE notification domain; migrations owned by kumi-brain-sql';
