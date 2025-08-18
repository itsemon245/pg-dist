-- Runs inside the coordinator container on first init
CREATE EXTENSION IF NOT EXISTS citus;
SELECT citus_set_coordinator_host('coordinator', 5432);
SELECT citus_version();

-- Determines how the number of splits for a distributed table (64 is decent)
ALTER SYSTEM SET citus.shard_count = 64;
-- Determines that each shard has 2 copies in different workers (more means more data redundancy)
ALTER SYSTEM SET citus.shard_replication_factor = 2;