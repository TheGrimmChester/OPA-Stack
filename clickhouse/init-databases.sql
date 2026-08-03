-- Per-product ClickHouse databases (one server, four DBs).
-- Applied on ClickHouse first boot via docker-entrypoint-initdb.d.
CREATE DATABASE IF NOT EXISTS opa;
CREATE DATABASE IF NOT EXISTS ora;
CREATE DATABASE IF NOT EXISTS osa;
CREATE DATABASE IF NOT EXISTS opl;
