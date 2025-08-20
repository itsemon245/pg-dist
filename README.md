# PostgreSQL + Citus Distributed Database

A Docker-based setup for running PostgreSQL with Citus extension to create a distributed database cluster. This setup provides automated cluster provisioning, worker management, and easy scaling capabilities.

## What is Citus?

[Citus](https://www.citusdata.com/) is a PostgreSQL extension that transforms PostgreSQL into a distributed database. It enables you to:

- **Scale horizontally** across multiple machines
- **Distribute tables** across worker nodes automatically
- **Run distributed queries** transparently across the cluster
- **Maintain ACID properties** with distributed transactions
- **Scale to billions of rows** and hundreds of terabytes

### Key Concepts

- **Coordinator Node**: Routes queries and manages metadata
- **Worker Nodes**: Store distributed table data (shards)
- **Distributed Tables**: Tables split across multiple worker nodes based on a distribution key
- **Reference Tables**: Small tables replicated to all nodes (e.g., lookup tables, configurations)
- **Local Tables**: Regular PostgreSQL tables that exist only on the coordinator (not distributed)
- **Distribution Key/Shard Key**: The column used to determine how rows are distributed across workers
- **Shards**: Horizontal partitions of distributed tables stored on different worker nodes
- **Colocation**: Tables with the same distribution key are stored together on the same workers for efficient joins

## Setup Options

This repository supports two deployment scenarios:

1. **Single Machine Setup** (documented below) - All components on one machine using Docker Compose
2. **Multi-Server Setup** - Coordinator and workers on separate physical servers

📖 **[Multi-Server Deployment Guide](docs/multi-server-setup.md)** - For production environments requiring physical separation across multiple servers.

## Prerequisites

- Docker and Docker Compose
- Bash (for setup scripts)
- `psql` client (for database operations)

## Quick Start

> **Note:** This guide covers single-machine deployment. For multi-server production deployments, see the [Multi-Server Setup Guide](docs/multi-server-setup.md).

### 1. Generate Cluster Configuration

The setup script creates all necessary configuration files:

```bash
# Basic setup with coordinator + 2 workers
./setup_citus_cluster.sh --with-coordinator --workers=2

# Custom configuration
./setup_citus_cluster.sh --with-coordinator --workers=3 --port=5432 --user=myuser --pass=mypassword

# Non-interactive mode with auto-generated password
./setup_citus_cluster.sh --with-coordinator --workers=2 --no-prompt
```

**Script Options:**

- `--with-coordinator`: Include coordinator service (required for cluster)
- `--workers=N`: Number of worker nodes (1-N)
- `--port=5432`: Base port for coordinator (workers use port+1, port+2, etc.)
- `--user=postgres`: PostgreSQL username
- `--pass=password`: PostgreSQL password (auto-generated if not provided)
- `--no-prompt`: Skip interactive prompts
- `--force`: Overwrite existing files without confirmation

### 2. Start the Cluster

```bash
# Start all services in background
docker compose up -d

# View container status
docker ps

# Check coordinator logs
docker logs citus-coordinator

# Check worker logs
docker logs citus-worker1
```

### 3. Register Workers with Coordinator

After containers are healthy, register each worker:

```bash
# Register worker1
./add_worker_to_coordinator.sh --host citus-worker1 --port 5432

# Register worker2
./add_worker_to_coordinator.sh --host citus-worker2 --port 5432

# Register worker3 (if exists)
./add_worker_to_coordinator.sh --host citus-worker3 --port 5432
```

### 4. Verify Cluster Setup

```bash
# Connect to coordinator
docker exec -it citus-coordinator psql -U postgres -d postgres

# Check active workers
SELECT * FROM citus_get_active_worker_nodes();

# Check Citus version
SELECT citus_version();
```

## Documentation

### 📚 Core Concepts

- **[Citus Architecture & Concepts](docs/concepts.md)** - Understanding distributed databases, sharding, and distribution keys
- **[Terminology](docs/terminology.md)** - Glossary of distributed database and Citus terms
- **[Multi-Server Setup](docs/multi-server-setup.md)** - Production deployment across multiple servers

### 🛠️ Database Operations

- **[Database Operations](docs/database-operations.md)** - Creating distributed tables, query optimization, and performance patterns
- **[Configuration & Performance Tuning](docs/configuration.md)** - Memory settings, connection pooling, and optimization

### 📈 Scaling & Management

- **[Scaling Operations](docs/scaling.md)** - Adding workers, rebalancing data, and capacity planning
- **[Troubleshooting Guide](docs/troubleshooting.md)** - Common issues, health checks, and recovery procedures

### 🎯 Quick Reference

| Topic                   | Key Points                                       | Documentation                                      |
| ----------------------- | ------------------------------------------------ | -------------------------------------------------- |
| **Getting Started**     | Setup scripts, Docker deployment                 | ↑ Quick Start above                                |
| **Architecture**        | Coordinator/workers, sharding, distribution keys | [Concepts](docs/concepts.md)                       |
| **Terminology**         | Glossary of distributed database terms           | [Terminology](docs/terminology.md)                 |
| **Table Design**        | Distributed vs reference vs local tables         | [Database Operations](docs/database-operations.md) |
| **Query Performance**   | Single-worker vs scatter-gather patterns         | [Database Operations](docs/database-operations.md) |
| **Adding Workers**      | Scaling horizontally, rebalancing                | [Scaling](docs/scaling.md)                         |
| **Performance Tuning**  | Memory, connections, query optimization          | [Configuration](docs/configuration.md)             |
| **Multi-Server Deploy** | Production deployment across servers             | [Multi-Server Setup](docs/multi-server-setup.md)   |
| **Issues & Recovery**   | Common problems and solutions                    | [Troubleshooting](docs/troubleshooting.md)         |

## Repository Structure

```
pg-dist/
├── setup_citus_cluster.sh      # Main cluster setup script
├── add_worker_to_coordinator.sh # Worker registration script
├── templates/                  # Docker Compose templates
│   ├── coordinator.yml        # Coordinator service template
│   └── worker.yml             # Worker service template
├── config/                     # PostgreSQL configuration files
│   ├── coordinator.conf       # PostgreSQL config for coordinator
│   └── worker.conf            # PostgreSQL config for worker
├── initdb/                     # Database initialization scripts
├── docs/                       # Detailed documentation
│   ├── concepts.md            # Architecture and concepts
│   ├── terminology.md         # Glossary of terms
│   ├── database-operations.md # Tables, queries, performance
│   ├── scaling.md             # Adding workers and rebalancing
│   ├── configuration.md       # Performance tuning
│   └── troubleshooting.md     # Issues and solutions
├── docs/multi-server-setup.md       # Multi-server deployment guide
└── README.md                   # This file
```

**Important Files:**

- `.gitignore` - Excludes generated files (.env, docker-compose.yml)
- Generated files (.env, docker-compose.yml) are auto-created and excluded from version control

---

This setup provides a production-ready PostgreSQL + Citus cluster with automated provisioning, monitoring, and scaling capabilities. The distributed nature allows you to handle massive datasets while maintaining the familiar PostgreSQL interface and ACID guarantees.
