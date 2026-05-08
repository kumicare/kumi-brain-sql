-- Create the core Kumi Brain schema.

begin;

create schema if not exists kumi_core;

comment on schema kumi_core is 'Core schema for Kumi Brain application data.';

commit;
