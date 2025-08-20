# Database Operations

## Connecting to the Cluster

```bash
# Connect to coordinator (main entry point)
docker exec -it citus-coordinator psql -U postgres -d postgres

# Connect from host machine (check .env for port)
psql -h localhost -p 6432 -U postgres -d postgres

# Connect to specific worker (for debugging)
docker exec -it citus-worker1 psql -U postgres -d postgres
```

## Creating Distributed Tables

### Multi-Tenant Application Example with `owner_id`

```sql
-- 1. Create the anchor table (users) - distribute by primary key
CREATE TABLE users (
    id bigserial PRIMARY KEY,
    email text UNIQUE,
    created_at timestamp DEFAULT now()
);

-- Distribute users table by id (tenant isolation)
SELECT create_distributed_table('users', 'id');

-- 2. Create related tables with same distribution key for colocation
CREATE TABLE events (
    id bigserial PRIMARY KEY,
    owner_id bigint NOT NULL,  -- Same distribution key as users
    event_type text,
    properties jsonb,
    created_at timestamp DEFAULT now()
);

-- Colocate with users table for efficient joins
SELECT create_distributed_table('events', 'owner_id', colocate_with => 'users');

-- 3. Another colocated table
CREATE TABLE user_sessions (
    id bigserial PRIMARY KEY,
    owner_id bigint NOT NULL,  -- Same distribution key
    session_token text,
    expires_at timestamp
);

SELECT create_distributed_table('user_sessions', 'owner_id', colocate_with => 'users');

-- 4. Reference table for lookups (replicated to all workers)
CREATE TABLE event_types (
    id bigserial PRIMARY KEY,
    name text UNIQUE,
    description text
);

SELECT create_reference_table('event_types');

-- Create indexes (include distribution key for optimal performance)
CREATE INDEX events_owner_created_idx ON events(owner_id, created_at);
CREATE INDEX events_owner_type_idx ON events(owner_id, event_type);
CREATE INDEX users_id_email_idx ON users(id, email);
```

### Why This Design Works

1. **Tenant Isolation**: All data for `owner_id = 123` lives on the same worker nodes
2. **Efficient Joins**: Users ↔ events ↔ sessions joins happen locally on workers
3. **Scalable Filtering**: Queries with `WHERE owner_id = X` only hit relevant workers
4. **Load Distribution**: Data spreads across workers based on number of tenants

## Creating Reference Tables

Reference tables are replicated to all workers (good for lookup tables):

```sql
-- Create reference table (replicated to all nodes)
CREATE TABLE countries (
    code char(2) PRIMARY KEY,
    name text NOT NULL
);

SELECT create_reference_table('countries');

-- Insert reference data
INSERT INTO countries VALUES ('US', 'United States'), ('CA', 'Canada');
```

## Query Performance and Best Practices

### Efficient Queries (Single Worker Execution)

**✅ GOOD: Include distribution key in WHERE clause**

```sql
-- Hits only workers containing owner_id = 123 (fast)
SELECT * FROM events
WHERE owner_id = 123 AND created_at > now() - interval '1 day';

-- Efficient join (colocated tables on same workers)
SELECT u.email, count(*) as event_count
FROM users u
JOIN events e ON u.id = e.owner_id
WHERE u.owner_id = 123;

-- Insert routed to specific worker
INSERT INTO events (owner_id, event_type, properties)
VALUES (123, 'login', '{"ip": "192.168.1.1"}');
```

### Scatter-Gather Queries (Multi-Worker Execution)

**✅ GOOD: When scatter-gather is efficient**

```sql
-- Aggregations across all data (parallelized)
SELECT event_type, count(*)
FROM events
WHERE created_at > now() - interval '1 day'
GROUP BY event_type;

-- Global statistics (parallel execution)
SELECT
    date_trunc('hour', created_at) as hour,
    avg(response_time_ms) as avg_response_time
FROM api_requests
WHERE created_at > now() - interval '24 hours'
GROUP BY hour
ORDER BY hour;

-- Reference table joins (reference tables available on all workers)
SELECT et.name, count(*)
FROM events e
JOIN event_types et ON e.event_type = et.name
GROUP BY et.name;
```

**❌ AVOID: Expensive scatter-gather patterns**

```sql
-- BAD: Filtering without distribution key + complex joins
SELECT u.email, e.event_type
FROM events e
JOIN users u ON e.owner_id = u.id
WHERE e.event_type = 'rare_event'  -- No owner_id filter
AND u.email LIKE '%@company.com';

-- BAD: Cross-shard joins without colocation
SELECT o1.*, o2.*
FROM orders o1
JOIN orders o2 ON o1.product_id = o2.product_id
WHERE o1.owner_id != o2.owner_id;  -- Different shards

-- BAD: Large result set without limits
SELECT * FROM events
WHERE created_at > '2020-01-01';  -- Returns millions of rows
```

### Query Optimization Guidelines

**🎯 Always Include Distribution Key When Possible**

```sql
-- Instead of this (scatter-gather):
SELECT * FROM events WHERE owner_id = 123;

-- Do this (single worker):
SELECT * FROM events WHERE owner_id = 123;
```

**🎯 Use Colocation for Related Tables**

```sql
-- Tables distributed by same key enable local joins
SELECT
    u.email,
    count(e.*) as event_count,
    count(s.*) as session_count
FROM users u
LEFT JOIN events e ON u.id = e.owner_id
LEFT JOIN user_sessions s ON u.id = s.owner_id
WHERE u.id = 123  -- Single worker execution
GROUP BY u.email;
```

**🎯 Optimize Aggregations with Partial Results**

```sql
-- Citus automatically parallelizes aggregations
SELECT
    owner_id,
    count(*) as total_events,
    count(DISTINCT event_type) as event_type_variety,
    avg(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) as purchase_rate
FROM events
WHERE created_at > now() - interval '30 days'
GROUP BY owner_id
HAVING count(*) > 1000;
```

## When to Use Each Query Pattern

| Query Type                 | Use When                                  | Performance | Example                       |
| -------------------------- | ----------------------------------------- | ----------- | ----------------------------- |
| **Single Worker**          | Filtering by distribution key             | ⚡ Fastest  | `WHERE owner_id = 123`        |
| **Colocated Joins**        | Joining tables with same distribution key | ⚡ Fast     | `users ⟕ events ON owner_id`  |
| **Reference Joins**        | Joining with lookup tables                | 🔥 Good     | `events ⟕ event_types`        |
| **Parallel Aggregations**  | Global statistics, reporting              | 🔥 Good     | `SELECT count(*) FROM events` |
| **Cross-Shard Operations** | Rare, when absolutely necessary           | 🐌 Slow     | Avoid when possible           |

## Query Performance Monitoring

```sql
-- View query execution across workers
SELECT query, calls, total_time, mean_time
FROM citus_stat_statements
WHERE query NOT LIKE '%citus_%'
ORDER BY total_time DESC LIMIT 10;

-- Check if query hits single worker vs scatter-gather
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM events WHERE owner_id = 123;
-- Look for "Custom Scan (Citus Adaptive)" vs "Custom Scan (Citus Router)"
```

## Monitoring and Management

```sql
-- View shard distribution
SELECT * FROM citus_shards;

-- View shard placement across workers
SELECT * FROM citus_shard_placement;

-- Monitor rebalancing progress
SELECT * FROM citus_rebalance_status();

-- Get cluster statistics
SELECT * FROM citus_stat_activity();
```
