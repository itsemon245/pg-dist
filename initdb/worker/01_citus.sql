-- Runs inside each worker container on first init
CREATE EXTENSION IF NOT EXISTS citus;
SELECT citus_version();
