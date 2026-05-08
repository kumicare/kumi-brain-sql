-- Expose family member data as a read-only Supabase Data API endpoint.
-- This is for the first OpenClaw smoke test.

begin;

grant usage on schema kumi_core to anon, authenticated, service_role;
grant select on table kumi_core.kumi_family_member to anon, authenticated, service_role;

alter table kumi_core.kumi_family_member enable row level security;

drop policy if exists kumi_family_member_read_all on kumi_core.kumi_family_member;

create policy kumi_family_member_read_all
on kumi_core.kumi_family_member
for select
to anon, authenticated
using (true);

commit;
