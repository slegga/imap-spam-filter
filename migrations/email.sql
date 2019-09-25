-- 1 up

create table variables (key text, value text);
create unique index key_idx on variables(key);
create table whitelist_email_address (email text);
create unique index email_idx on variables(email);
-- 1 down
drop table variables;
drop table whitelist_email_address;
