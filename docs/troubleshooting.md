# Troubleshooting Guide

## Common Issues

### 1. Workers Not Registering

**Symptoms:**

- `citus_get_active_worker_nodes()` shows no workers
- Queries fail with "no healthy connections" errors

**Diagnosis:**

```sql
-- Check worker connectivity from coordinator
SELECT * FROM citus_check_connection_health();
```

**Solutions:**

- Verify worker containers are running: `docker ps`
- Check network connectivity between containers
- Ensure workers have started successfully: `docker logs citus-worker1`
- Verify PostgreSQL is accepting connections on workers

### 2. Containers Not Starting

**Symptoms:**

- Containers exit immediately or fail to start
- Services show as "unhealthy" in `docker ps`

**Diagnosis:**

```bash
# Check container logs
docker logs citus-coordinator
docker logs citus-worker1

# Verify network connectivity
docker network ls
docker network inspect pg-dist_citus

# Check resource usage
docker stats
```

**Solutions:**

- Check for port conflicts: `netstat -tulpn | grep :5432`
- Verify sufficient disk space: `df -h`
- Ensure .env file has correct credentials
- Check Docker daemon status: `systemctl status docker`

### 3. Permission Denied Errors

**Symptoms:**

- "permission denied" in container logs
- Init scripts failing to execute

**Diagnosis:**

```bash
# Check file permissions
ls -la initdb/coordinator/
ls -la initdb/worker/
```

**Solutions:**

```bash
# Ensure init scripts are readable
chmod +r initdb/coordinator/*.sql
chmod +r initdb/worker/*.sql

# Fix ownership if needed
sudo chown -R $USER:$USER initdb/
```

### 4. Slow Query Performance

**Symptoms:**

- Queries taking much longer than expected
- High CPU usage on coordinator
- Timeouts on large queries

**Diagnosis:**

```sql
-- Check for scatter-gather queries
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM events WHERE event_type = 'login';

-- View slow queries
SELECT query, calls, total_time, mean_time
FROM citus_stat_statements
WHERE mean_time > 1000  -- queries > 1 second
ORDER BY total_time DESC;

-- Check for missing distribution key in WHERE clauses
SELECT query FROM citus_stat_statements
WHERE query NOT LIKE '%distribution_key%'
AND calls > 100;
```

**Solutions:**

- Add distribution key to WHERE clauses
- Create appropriate indexes including distribution key
- Consider table colocation for joins
- Use LIMIT for large result sets

### 5. Connection Failures

**Symptoms:**

- "connection refused" errors
- Intermittent connection drops
- "too many connections" errors

**Diagnosis:**

```sql
-- Check current connections
SELECT count(*) FROM pg_stat_activity;
SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname;

-- Check connection limits
SHOW max_connections;
```

**Solutions:**

```sql
-- Increase connection limits
ALTER SYSTEM SET max_connections = 200;
SELECT pg_reload_conf();

-- Implement connection pooling
-- Use pgBouncer or application-level pooling
```

## Health Checks

### Cluster Health Verification

```sql
-- Verify cluster health
SELECT * FROM citus_get_active_worker_nodes();

-- Check distributed table health
SELECT * FROM citus_check_cluster_node_health();

-- Monitor query distribution
SELECT query, calls, total_time
FROM citus_stat_statements
ORDER BY total_time DESC LIMIT 10;
```

### System Resource Monitoring

```sql
-- Active connections
SELECT * FROM citus_stat_activity();

-- Lock monitoring
SELECT * FROM citus_lock_waits;

-- Shard statistics
SELECT
    nodename,
    nodeport,
    count(*) as shard_count,
    sum(size) as total_size
FROM citus_shards
GROUP BY nodename, nodeport;
```

### Container Health Checks

```bash
# Check all container statuses
docker compose ps

# View container resource usage
docker stats --no-stream

# Check container logs for errors
docker logs citus-coordinator --tail 50
docker logs citus-worker1 --tail 50

# Test database connectivity
docker exec citus-coordinator pg_isready -U postgres
```

## Database Administration Commands

### Table Management

```sql
-- View distributed tables
SELECT * FROM citus_tables;

-- View table sizes across cluster
SELECT
    table_name,
    pg_size_pretty(citus_table_size(table_name::regclass)) as distributed_size
FROM citus_tables;

-- Vacuum distributed tables
SELECT run_command_on_workers('VACUUM ANALYZE events;');

-- Update statistics
SELECT run_command_on_workers('ANALYZE;');
```

### Shard Management

```sql
-- View shard distribution
SELECT
    table_name,
    shard_id,
    nodename,
    nodeport,
    pg_size_pretty(shard_size) as size
FROM citus_shards
ORDER BY table_name, shard_id;

-- Check for unbalanced shards
SELECT
    nodename,
    count(*) as shard_count,
    pg_size_pretty(sum(shard_size)) as total_size
FROM citus_shards
GROUP BY nodename
ORDER BY shard_count DESC;

-- Fix orphaned shards
SELECT citus_cleanup_orphaned_shards();
```

### Worker Management

```sql
-- Check worker status
SELECT
    nodename,
    nodeport,
    isactive,
    noderole
FROM pg_dist_node;

-- Activate/deactivate workers
SELECT citus_activate_node('worker-hostname', 5432);
SELECT citus_disable_node('worker-hostname', 5432);

-- Update worker metadata
SELECT citus_update_node('old-hostname', 5432, 'new-hostname', 5432);
```

## Recovery Procedures

### Worker Recovery

**When a worker fails:**

1. **Identify the issue:**

```bash
docker logs citus-worker1
docker exec citus-worker1 pg_isready -U postgres
```

2. **Restart the worker:**

```bash
docker compose restart citus-worker1
```

3. **Re-register if needed:**

```bash
./add_worker_to_coordinator.sh --host citus-worker1 --port 5432
```

4. **Rebalance if necessary:**

```sql
SELECT citus_rebalance_start();
```

### Coordinator Recovery

**When coordinator fails:**

1. **Restart coordinator:**

```bash
docker compose restart citus-coordinator
```

2. **Verify worker connections:**

```sql
SELECT * FROM citus_get_active_worker_nodes();
```

3. **Re-register workers if needed:**

```bash
./add_worker_to_coordinator.sh --host citus-worker1 --port 5432
```

### Data Recovery

**For data corruption or loss:**

1. **Stop all operations:**

```bash
docker compose stop
```

2. **Restore from backup:**

```bash
# Restore schema
psql -h localhost -p 6432 -U postgres < schema_backup.sql

# Restore data (per worker)
docker exec citus-worker1 psql -U postgres < worker1_backup.sql
```

3. **Restart cluster:**

```bash
docker compose up -d
```

4. **Verify data integrity:**

```sql
SELECT count(*) FROM distributed_table;
SELECT * FROM citus_check_cluster_node_health();
```

## Maintenance Procedures

### Routine Maintenance

```sql
-- Weekly maintenance script
DO $$
BEGIN
    -- Update statistics
    PERFORM run_command_on_workers('ANALYZE;');

    -- Vacuum tables(events is a table name)
    PERFORM run_command_on_workers('VACUUM (ANALYZE) events;');

    -- Clean up orphaned shards
    PERFORM citus_cleanup_orphaned_shards();

    -- Update worker node list
    PERFORM citus_update_node_health();
END $$;
```

### Performance Maintenance

```sql
-- Reindex distributed tables
SELECT run_command_on_workers('REINDEX TABLE events;');

-- Update table statistics
SELECT run_command_on_workers('VACUUM (ANALYZE, VERBOSE) events;');

-- Check for bloated tables
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) as index_size
FROM citus_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

## Monitoring and Alerting

### Key Metrics to Monitor

1. **Connection Health:** Worker connectivity status
2. **Query Performance:** Average query execution times
3. **Resource Usage:** CPU, memory, disk usage per node
4. **Shard Distribution:** Balance across workers
5. **Replication Health:** If using shard replication

### Sample Alerting Queries

```sql
-- Alert: Worker down
SELECT count(*) FROM citus_get_active_worker_nodes() < expected_worker_count;

-- Alert: High query response time
SELECT avg(total_time/calls) > 5000 FROM citus_stat_statements
WHERE calls > 10 AND query_start > now() - interval '5 minutes';

-- Alert: Unbalanced shard distribution
WITH shard_counts AS (
    SELECT nodename, count(*) as shards
    FROM citus_shards
    GROUP BY nodename
)
SELECT max(shards) - min(shards) > 10 FROM shard_counts;
```
