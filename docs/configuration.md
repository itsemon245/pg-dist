# Configuration and Performance Tuning

## PostgreSQL Configuration Files

The setup includes optimized PostgreSQL configuration files for different node types:

### Coordinator Configuration (`config/coordinator.conf`)

Optimized for query planning, metadata management, and connection routing:

- **Memory**: Moderate settings (256MB shared_buffers, 1GB effective_cache_size)
- **Connections**: Higher max_connections (200) for client requests
- **Logging**: Verbose logging for DDL and slow queries (>1s)
- **Parallel Processing**: Moderate parallelism (8 workers, 4 per gather)

### Worker Configuration (`config/worker.conf`)

Optimized for data processing and heavy workloads:

- **Memory**: Higher settings (512MB shared_buffers, 2GB effective_cache_size)
- **Connections**: Fewer connections (100) as they're mostly from coordinator
- **Logging**: Less verbose, only very slow queries (>5s)
- **Parallel Processing**: Higher parallelism (16 workers, 8 per gather)
- **I/O**: Optimized for bulk operations and SSD storage

### Customizing Configuration

To modify PostgreSQL settings:

1. **Edit the configuration files**:

   ```bash
   # Edit coordinator settings
   nano config/coordinator.conf

   # Edit worker settings
   nano config/worker.conf
   ```

2. **Restart containers to apply changes**:

   ```bash
   # Restart all containers to pick up new config
   docker compose restart

   # Or force recreate containers
   docker compose up -d --force-recreate
   ```

3. **Or apply runtime changes** (some settings require restart):
   ```sql
   -- Connect to coordinator
   ALTER SYSTEM SET work_mem = '64MB';
   SELECT pg_reload_conf();
   ```

## Environment Variables

The `.env` file contains cluster configuration:

```bash
# Database credentials
POSTGRES_USER=postgres
POSTGRES_PASSWORD=auto-generated-password
POSTGRES_DB=postgres

# Network configuration
COORD_PORT=5432
COORD_CONTAINER=citus-coordinator

# Cluster topology
WORKERS=2
WITH_COORDINATOR=1
```

## Citus Configuration(runs only once when the container is first created)

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
