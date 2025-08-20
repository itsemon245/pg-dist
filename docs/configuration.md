# Configuration and Performance Tuning

## Environment Variables

The `.env` file contains cluster configuration:

```bash
# Database credentials
POSTGRES_USER=postgres
POSTGRES_PASSWORD=auto-generated-password
POSTGRES_DB=postgres

# Network configuration
COORD_PORT=6432
COORD_CONTAINER=citus-coordinator

# Cluster topology
WORKERS=2
WITH_COORDINATOR=1
```

## Citus Configuration

Key settings in `initdb/coordinator/01_citus.sql`:

```sql
-- Number of shards per distributed table (higher = more parallelism)
ALTER SYSTEM SET citus.shard_count = 64;

-- Replication factor (copies of each shard)
ALTER SYSTEM SET citus.shard_replication_factor = 2;

-- Enable connection pooling
ALTER SYSTEM SET citus.max_worker_nodes_tracked = 100;
```

## Performance Tuning

### Coordinator Settings

Add to coordinator init script:

```sql
-- Memory settings
ALTER SYSTEM SET shared_preload_libraries = 'citus';
ALTER SYSTEM SET max_connections = 200;
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';

-- Parallel query settings
ALTER SYSTEM SET max_parallel_workers = 8;
ALTER SYSTEM SET max_parallel_workers_per_gather = 4;

-- Connection and networking
ALTER SYSTEM SET max_worker_processes = 32;
ALTER SYSTEM SET max_prepared_transactions = 200;

-- Logging for monitoring
ALTER SYSTEM SET log_min_duration_statement = 1000;  -- Log slow queries
ALTER SYSTEM SET log_statement = 'ddl';  -- Log DDL statements
```

### Worker Settings

Add to worker init script:

```sql
-- Worker-specific memory settings
ALTER SYSTEM SET shared_buffers = '512MB';  -- Higher on workers
ALTER SYSTEM SET effective_cache_size = '2GB';
ALTER SYSTEM SET work_mem = '64MB';  -- For sorting/hashing operations

-- I/O settings
ALTER SYSTEM SET random_page_cost = 1.1;  -- Assume SSD storage
ALTER SYSTEM SET checkpoint_segments = 32;
ALTER SYSTEM SET wal_buffers = '16MB';

-- Parallel processing
ALTER SYSTEM SET max_parallel_workers = 16;
ALTER SYSTEM SET max_parallel_workers_per_gather = 8;
```

## Shard Configuration

### Optimal Shard Count

```sql
-- Calculate optimal shard count
-- Rule of thumb: 2-4 shards per worker core
-- For 4 workers with 8 cores each: 64-128 shards

-- Set shard count globally
ALTER SYSTEM SET citus.shard_count = 128;

-- Or per table
SELECT create_distributed_table('large_table', 'distribution_key', shard_count => 256);
```

### Shard Replication

```sql
-- For high availability (2+ copies of each shard)
ALTER SYSTEM SET citus.shard_replication_factor = 2;

-- For maximum performance (single copy)
ALTER SYSTEM SET citus.shard_replication_factor = 1;
```

## Connection Management

### Connection Pooling

```sql
-- Enable connection pooling between coordinator and workers
ALTER SYSTEM SET citus.max_adaptive_executor_pool_size = 16;

-- Connection limits
ALTER SYSTEM SET citus.executor_slow_start_interval = 10;
ALTER SYSTEM SET citus.max_worker_nodes_tracked = 100;
```

### External Connection Pooling

For high-traffic applications, use pgBouncer:

```yaml
# docker-compose.yml addition
pgbouncer:
  image: pgbouncer/pgbouncer:latest
  environment:
    DATABASES_HOST: citus-coordinator
    DATABASES_PORT: 5432
    DATABASES_USER: postgres
    DATABASES_PASSWORD: ${POSTGRES_PASSWORD}
    DATABASES_DBNAME: postgres
    POOL_MODE: transaction
    MAX_CLIENT_CONN: 1000
    DEFAULT_POOL_SIZE: 25
  ports:
    - "6543:5432"
```

## Query Performance Configuration

### Execution Planning

```sql
-- Enable adaptive executor for better performance
ALTER SYSTEM SET citus.task_executor_type = 'adaptive';

-- Query optimization
ALTER SYSTEM SET citus.enable_router_execution = on;
ALTER SYSTEM SET citus.enable_repartition_joins = on;

-- Subquery pushdown
ALTER SYSTEM SET citus.subquery_pushdown = on;
ALTER SYSTEM SET citus.enable_cte_inlining = on;
```

### Statistics and Planning

```sql
-- Auto-analyze settings
ALTER SYSTEM SET track_counts = on;
ALTER SYSTEM SET autovacuum = on;
ALTER SYSTEM SET autovacuum_analyze_scale_factor = 0.1;

-- Statistics collection
ALTER SYSTEM SET track_activities = on;
ALTER SYSTEM SET track_io_timing = on;
ALTER SYSTEM SET log_executor_stats = on;
```

## Monitoring Configuration

### Enable Statistics

```sql
-- Enable Citus statistics extension
CREATE EXTENSION IF NOT EXISTS citus_stat_statements;

-- Configure statement tracking
ALTER SYSTEM SET citus.stat_statements_track = 'all';
ALTER SYSTEM SET citus.stat_statements_max = 10000;

-- Query duration logging
ALTER SYSTEM SET log_min_duration_statement = 5000;  -- 5 seconds
```

### Metrics Collection

```yaml
# Add to docker-compose.yml for Prometheus monitoring
postgres_exporter:
  image: prometheuscommunity/postgres-exporter
  environment:
    DATA_SOURCE_NAME: "postgresql://postgres:${POSTGRES_PASSWORD}@citus-coordinator:5432/postgres?sslmode=disable"
    PG_EXPORTER_EXTEND_QUERY_PATH: "/etc/postgres_exporter/queries.yaml"
  ports:
    - "9187:9187"
  volumes:
    - ./monitoring/queries.yaml:/etc/postgres_exporter/queries.yaml:ro
```

## Security Configuration

### SSL/TLS Settings

```sql
-- Enable SSL
ALTER SYSTEM SET ssl = on;
ALTER SYSTEM SET ssl_cert_file = '/path/to/server.crt';
ALTER SYSTEM SET ssl_key_file = '/path/to/server.key';
ALTER SYSTEM SET ssl_ca_file = '/path/to/ca.crt';

-- Force SSL connections
ALTER SYSTEM SET ssl_require = on;
```

### Authentication

```sql
-- Configure pg_hba.conf for secure access
-- Example entries:
-- hostssl all postgres coordinator.internal cert
-- hostssl all postgres worker1.internal cert
-- hostssl all app_user 0.0.0.0/0 md5
```

## Resource Management

### Memory Configuration

Calculate memory settings based on available RAM:

```sql
-- For coordinator (8GB RAM):
ALTER SYSTEM SET shared_buffers = '2GB';
ALTER SYSTEM SET effective_cache_size = '6GB';
ALTER SYSTEM SET work_mem = '32MB';
ALTER SYSTEM SET maintenance_work_mem = '512MB';

-- For workers (16GB RAM):
ALTER SYSTEM SET shared_buffers = '4GB';
ALTER SYSTEM SET effective_cache_size = '12GB';
ALTER SYSTEM SET work_mem = '64MB';
ALTER SYSTEM SET maintenance_work_mem = '1GB';
```

### Disk I/O Configuration

```sql
-- For SSD storage
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET seq_page_cost = 1.0;

-- Checkpoint configuration
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET checkpoint_timeout = '15min';
ALTER SYSTEM SET max_wal_size = '4GB';
ALTER SYSTEM SET min_wal_size = '1GB';
```

## Configuration Validation

### Check Current Settings

```sql
-- View current Citus settings
SELECT name, setting, source
FROM pg_settings
WHERE name LIKE 'citus%'
ORDER BY name;

-- Check shard distribution
SELECT
    schemaname,
    tablename,
    pg_size_pretty(citus_table_size(schemaname||'.'||tablename)) as size,
    citus_shard_count(schemaname||'.'||tablename) as shards
FROM citus_tables;

-- Verify worker connectivity
SELECT * FROM citus_check_connection_health();
```

### Performance Benchmarking

```sql
-- Test query performance
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM distributed_table WHERE distribution_key = 'test';

-- Check parallel execution
SET citus.explain_distributed_queries = on;
EXPLAIN (ANALYZE) SELECT * FROM large_table LIMIT 1000;
```
