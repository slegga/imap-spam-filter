-- 1 up
create table variables (key text, value text);
create table whitelist_email_address (email text);
CREATE UNIQUE INDEX key ON variables(key);
CREATE UNIQUE INDEX email ON whitelist_email_address(email);
-- 1 down
drop table variables;
drop table whitelist_email_address;
