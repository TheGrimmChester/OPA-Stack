-- Per-product ClickHouse databases (one server, five DBs).
-- Applied on ClickHouse first boot via docker-entrypoint-initdb.d.
CREATE DATABASE IF NOT EXISTS opa;
CREATE DATABASE IF NOT EXISTS ora;
CREATE DATABASE IF NOT EXISTS osa;
CREATE DATABASE IF NOT EXISTS opl;
-- oam holds the family's orgs, users, connectors, API keys, AI provider
-- credentials and per-agent model bindings. OPM is filesystem-backed and reads
-- this over HTTP; it has no database of its own.
CREATE DATABASE IF NOT EXISTS oam;
