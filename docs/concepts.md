# Citus Concepts and Architecture

## What is Citus?

[Citus](https://www.citusdata.com/) is a PostgreSQL extension that transforms PostgreSQL into a distributed database. It enables you to:

- **Scale horizontally** across multiple machines
- **Distribute tables** across worker nodes automatically
- **Run distributed queries** transparently across the cluster
- **Maintain ACID properties** with distributed transactions
- **Scale to billions of rows** and hundreds of terabytes

## Key Concepts

- **Coordinator Node**: Routes queries and manages metadata
- **Worker Nodes**: Store distributed table data (shards)
- **Distributed Tables**: Tables split across multiple worker nodes based on a distribution key
- **Reference Tables**: Small tables replicated to all nodes (e.g., lookup tables, configurations)
- **Local Tables**: Regular PostgreSQL tables that exist only on the coordinator (not distributed)
- **Distribution Key/Shard Key**: The column used to determine how rows are distributed across workers
- **Shards**: Horizontal partitions of distributed tables stored on different worker nodes
- **Colocation**: Tables with the same distribution key are stored together on the same workers for efficient joins

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Coordinator Node                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐    │
│  │   Query Router  │  │  Metadata Store │  │ Transaction Mgr │    │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘    │
└─────────────────────────┬───────────────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          │               │               │
    ┌─────▼─────┐   ┌─────▼─────┐   ┌─────▼─────┐
    │  Worker 1 │   │  Worker 2 │   │  Worker N │
    │           │   │           │   │           │
    │ Shard 1_1 │   │ Shard 2_1 │   │ Shard N_1 │
    │ Shard 1_2 │   │ Shard 2_2 │   │ Shard N_2 │
    │    ...    │   │    ...    │   │    ...    │
    └───────────┘   └───────────┘   └───────────┘
```

## Table Distribution Strategies

### When to Distribute a Table

- Large tables (millions+ rows)
- High write/read volume tables
- Tables that benefit from parallel processing

### When to Use Reference Tables

- Small, relatively static lookup tables (< 100K rows)
- Configuration tables, countries, categories, etc.
- Tables frequently joined with distributed tables

### When to Keep Local (Regular Tables)

- Small operational tables (settings, configurations)
- Tables only accessed from coordinator
- Temporary or staging tables

## Distribution Key Selection

The **distribution key (shard key)** is crucial for performance. Choose a column that:

1. **High Cardinality**: Many distinct values to distribute data evenly
2. **Query Filtering**: Frequently used in WHERE clauses
3. **Join Key**: Used for joins with other distributed tables
4. **Immutable**: Values shouldn't change after insert

### Best Practices

- **Multi-tenant applications**: Use tenant_id or owner_id
- **Time-series data**: Use user_id or device_id, avoid timestamps
- **E-commerce**: Use customer_id, not order_id
- **Analytics**: Use user_id or session_id for event data

The distribution key choice impacts:

- Query performance (single-worker vs scatter-gather)
- Join efficiency (colocation enables local joins)
- Data distribution evenness
- Scalability and maintenance complexity
