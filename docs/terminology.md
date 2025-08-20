# Terminology

This glossary defines key terms used in distributed databases and Citus specifically.

## Core Citus Architecture

### **Citus**

A PostgreSQL extension that transforms PostgreSQL into a distributed database system. Enables horizontal scaling across multiple machines while maintaining ACID properties and SQL compatibility.

### **Coordinator Node**

The main PostgreSQL instance that:

- Routes queries to appropriate worker nodes
- Stores metadata about distributed tables and shards
- Manages distributed transactions
- Serves as the entry point for applications

### **Worker Node**

PostgreSQL instances that:

- Store actual table data (shards)
- Execute queries on their local data
- Report results back to the coordinator
- Can be added/removed to scale the cluster

### **Cluster**

The complete distributed database system consisting of one coordinator and multiple worker nodes working together.

## Data Distribution

### **Distributed Table**

A table whose data is split (sharded) across multiple worker nodes based on a distribution key. Applications query it as if it were a single table, but Citus distributes operations across workers.

### **Distribution Key (Shard Key)**

The column used to determine which worker node stores each row. Citus hashes this value to decide shard placement. Critical for performance - queries filtering by this key only hit relevant workers.

### **Anchor Table**

The main table in a group of related distributed tables, typically chosen first when designing the schema. Other tables are colocated with the anchor table using the same distribution key.

### **Shard**

A horizontal partition of a distributed table stored on a single worker node. Each shard contains a subset of the table's rows based on the distribution key hash.

### **Shard Count**

The total number of shards a distributed table is split into. Higher shard count allows better parallelism but increases overhead. Typically 2-4 shards per worker CPU core.

### **Shard Replication Factor**

The number of copies of each shard maintained across different workers. Higher replication provides fault tolerance but increases storage and write overhead.

### **Colocation**

Storing related tables with the same distribution key on the same worker nodes. Enables efficient local joins without cross-worker communication.

## Table Types

### **Reference Table**

A small table replicated in full to every worker node. Used for lookup tables, configuration data, or frequently joined small tables. Enables local joins with distributed tables.

### **Local Table**

A regular PostgreSQL table that exists only on the coordinator node. Not distributed. Used for metadata, small operational tables, or coordinator-specific data.

### **Colocated Tables**

Multiple distributed tables that use the same distribution key and are stored together on the same workers. Enables efficient joins and maintains related data locality.

## Query Execution Patterns

### **Single-Worker Query**

A query that can be executed entirely on one worker node because:

- It filters by a specific distribution key value
- All required data exists on that worker
- Most efficient execution pattern

### **Scatter-Gather**

A query execution pattern where:

- **Scatter**: Coordinator sends query fragments to multiple workers
- **Gather**: Coordinator collects and combines results from all workers
- Used for cross-shard aggregations, analytics, and queries without distribution key filters

### **Fan-Out**

The process of sending a query or operation to multiple worker nodes simultaneously. Part of the scatter-gather pattern.

### **Router Query**

A query that can be routed to a single worker node based on distribution key filtering. The most efficient query type in Citus.

### **Multi-Shard Query**

A query that requires data from multiple shards/workers. Requires scatter-gather execution and is generally slower than single-shard queries.

## Data Management

### **Rebalancing**

The process of redistributing shards across workers to achieve better balance after adding/removing workers or when data distribution becomes skewed.

### **Shard Placement**

The mapping of which shards are stored on which worker nodes. Managed automatically by Citus but can be viewed and manually adjusted.

### **Drain Node**

The process of moving all shards away from a worker node before maintenance or removal. Ensures no data loss when taking a worker offline.

### **Shard Move**

Moving a shard from one worker to another, typically during rebalancing or maintenance operations.

## Performance Concepts

### **Distribution Key Cardinality**

The number of distinct values in the distribution key column. Higher cardinality generally provides better data distribution across workers.

### **Hotspot**

A situation where one worker receives disproportionately more queries or data than others, creating a performance bottleneck. Usually caused by poor distribution key choice.

### **Cross-Shard Join**

A join operation that requires data from multiple workers. Generally expensive as it requires network communication between workers.

### **Local Join**

A join operation between colocated tables that can be executed entirely on worker nodes without cross-worker communication. Much more efficient than cross-shard joins.

### **Parallel Execution**

The ability to execute parts of a query simultaneously across multiple workers, improving performance for large operations.

## Operational Terms

### **Node Registration**

The process of adding a new worker node to the cluster by informing the coordinator about the worker's existence and connectivity details.

### **Health Check**

Monitoring the status and connectivity of worker nodes to ensure the cluster is operating correctly.

### **Metadata**

Information stored on the coordinator about distributed tables, shard locations, worker nodes, and cluster configuration.

### **Connection Pooling**

Managing database connections efficiently between the coordinator and workers to handle high-concurrency workloads.

## Multi-Tenancy Terms

### **Tenant**

An individual customer, organization, or isolated group in a multi-tenant application. Each tenant's data is typically isolated using the distribution key.

### **Tenant Isolation**

Ensuring that data for each tenant is stored together and queries are automatically scoped to the correct tenant's data.

### **Multi-Tenant Distribution**

Using tenant ID (like `owner_id`) as the distribution key to achieve tenant isolation and efficient single-tenant queries.

## Scaling Terms

### **Horizontal Scaling (Scale Out)**

Adding more worker nodes to increase capacity and performance. Citus's primary scaling method.

### **Vertical Scaling (Scale Up)**

Increasing resources (CPU, RAM, storage) on existing nodes rather than adding new nodes.

### **Elastic Scaling**

The ability to add or remove worker nodes dynamically based on workload demands without downtime.

### **Capacity Planning**

Determining the appropriate number and size of worker nodes needed for expected workloads and growth.


Understanding these terms helps in designing efficient distributed database schemas and writing performant queries in Citus.
