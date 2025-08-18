-- Runs inside the coordinator container on first init
CREATE EXTENSION IF NOT EXISTS citus;
SELECT citus_set_coordinator_host('coordinator', 5432);
-- Optional: set defaults cluster-wide later in a session or via ALTER SYSTEM
-- ALTER SYSTEM SET citus.shard_count = 64;
-- ALTER SYSTEM SET citus.shard_replication_factor = 1;
SELECT citus_version();
