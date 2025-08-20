# Scaling Operations

## Adding New Workers

### Single Machine Setup

1. **Update configuration** to add more workers:

```bash
# Regenerate with more workers
./setup_citus_cluster.sh --with-coordinator --workers=4 --force
```

2. **Restart cluster** with new configuration:

```bash
docker compose up -d
```

3. **Register new workers**:

```bash
./add_worker_to_coordinator.sh --host citus-worker4 --port 5432
```

### Multi-Server Setup

For adding new worker servers, see the [Multi-Server Setup Guide](../MULTI_SERVER_SETUP.md#scaling-operations).

## Rebalancing Data

When adding workers, rebalance existing data:

```sql
-- Start rebalancing (automatically triggered by add_worker script)
SELECT citus_rebalance_start();

-- Monitor rebalancing progress
SELECT * FROM citus_rebalance_status();

-- Manual rebalancing with custom strategy
SELECT citus_rebalance_start(
    rebalance_strategy := 'by_shard_count',
    drain_only := false
);
```

## Scaling Strategies

### Horizontal Scaling (Add More Workers)

**When to scale out:**

- CPU utilization consistently high across workers
- Memory pressure on worker nodes
- I/O bottlenecks on storage
- Need better fault tolerance

**Benefits:**

- Linear performance scaling
- Better fault tolerance
- More parallel processing capacity

### Vertical Scaling (Upgrade Worker Resources)

**When to scale up:**

- Single queries need more memory
- Complex aggregations hitting memory limits
- Storage I/O is the bottleneck

**Benefits:**

- Simpler than adding nodes
- Better for memory-intensive operations
- No data rebalancing required

## Removing Workers

### Graceful Worker Removal

```sql
-- 1. Drain worker (move shards to other workers)
SELECT citus_drain_node('citus-worker3', 5432);

-- 2. Monitor draining progress
SELECT * FROM citus_rebalance_status();

-- 3. Remove worker from cluster
SELECT citus_remove_node('citus-worker3', 5432);
```

### Emergency Worker Removal

```sql
-- Force remove unresponsive worker
SELECT citus_remove_node('citus-worker3', 5432, force => true);

-- Check for orphaned shards
SELECT * FROM citus_shard_placement WHERE nodename = 'citus-worker3';
```

## Scaling Considerations

### Distribution Key Impact

- **Good distribution keys** scale linearly with new workers
- **Poor distribution keys** may cause hotspots
- **Tenant-based keys** work well for multi-tenant applications

### Rebalancing Performance

```sql
-- Configure rebalancing for minimal impact
SELECT citus_rebalance_start(
    shard_transfer_mode := 'block_writes'  -- Options: 'auto', 'force_logical', 'block_writes'
);

-- Monitor rebalancing impact
SELECT * FROM citus_stat_activity() WHERE query LIKE '%rebalance%';
```

### Capacity Planning

**Memory Requirements:**

- Coordinator: 8-16GB for metadata and connection pooling
- Workers: 16GB+ per worker, scale with data size

**Storage Requirements:**

- Plan for 2-3x data size for rebalancing operations
- Use fast SSDs for better I/O performance

**Network Requirements:**

- High bandwidth between coordinator and workers
- Low latency for real-time applications

## Automated Scaling

### Monitoring-Based Scaling

```sql
-- Check worker resource utilization
SELECT
    nodename,
    pg_size_pretty(pg_database_size('postgres')) as db_size,
    (SELECT count(*) FROM citus_shards WHERE nodename = w.nodename) as shard_count
FROM citus_get_active_worker_nodes() w;

-- Monitor query performance trends
SELECT
    date_trunc('hour', query_start) as hour,
    avg(total_exec_time) as avg_query_time
FROM citus_stat_activity
WHERE query_start > now() - interval '24 hours'
GROUP BY hour
ORDER BY hour;
```

### Scaling Triggers

Set up alerts for:

- CPU utilization > 80% for sustained periods
- Memory utilization > 85%
- Query response times > acceptable thresholds
- Storage utilization > 80%

## Scaling Best Practices

1. **Plan ahead**: Scale before hitting resource limits
2. **Test rebalancing**: Practice on staging environments
3. **Monitor impact**: Watch for performance degradation during scaling
4. **Scale gradually**: Add workers incrementally, not all at once
5. **Consider peak times**: Schedule scaling operations during low-traffic periods
