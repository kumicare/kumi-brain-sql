-- Expose the first stable Kumi tool contract through Supabase RPC.

begin;

create or replace function kumi_core.list_family_members()
returns table (
  id uuid,
  name text,
  member_type smallint,
  birthday date,
  gender smallint,
  description text
)
language sql
stable
security invoker
set search_path = kumi_core, public
as $$
  select
    family_member.id,
    family_member.name,
    family_member.member_type,
    family_member.birthday,
    family_member.gender,
    family_member.description
  from kumi_core.kumi_family_member as family_member
  order by family_member.name asc;
$$;

comment on function kumi_core.list_family_members() is
  'Stable Kumi tool contract for listing family member summaries.';

grant execute on function kumi_core.list_family_members() to anon, authenticated, service_role;

commit;
