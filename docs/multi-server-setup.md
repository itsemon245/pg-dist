# Multi-Server Citus Cluster Setup

This guide covers deploying a Citus cluster across multiple physical servers, with the coordinator and workers running on separate machines. This setup is ideal for production environments requiring true physical separation and dedicated resources.

## Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Coordinator    │    │    Worker 1     │    │    Worker 2     │
│   Server A      │    │    Server B     │    │    Server C     │
│                 │    │                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │   citus-    │ │    │ │   citus-    │ │    │ │   citus-    │ │
│ │ coordinator │◄┼────┼►│   worker1   │ │    │ │   worker2   │ │
│ │             │ │    │ │             │ │    │ │             │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘    └─────────────────┘
      Port 5432            Port 5432            Port 5432
```

## Prerequisites

- Multiple servers with Docker and Docker Compose installed
- Network connectivity between all servers (ensure ports are accessible)
- SSH access to all servers
- Same PostgreSQL credentials across all nodes

## Step 1: Coordinator Server Setup

### On the Coordinator Server (Server A):

```bash
# Clone the repository
git clone <your-repo-url> pg-dist
cd pg-dist

# Generate coordinator-only configuration
./setup_citus_cluster.sh --with-coordinator --workers=0 --port=5432 --user=postgres --pass=your-secure-password

# Start the coordinator
docker compose up -d

# Verify coordinator is running
docker ps
docker logs citus-coordinator
```

This creates a coordinator without any local workers.

**Generated Configuration:**

- `.env` file with coordinator settings
- `docker-compose.yml` with only coordinator service
- Coordinator accessible on port 5432

## Step 2: Worker Server Setup

### On Each Worker Server (Server B, C, etc.):

```bash
# Clone the repository
git clone <your-repo-url> pg-dist
cd pg-dist

# For single worker per server (recommended)
./setup_citus_cluster.sh --workers=1 --port=5432 --user=postgres --pass=your-secure-password

# For multiple workers per server (if server has sufficient resources)
./setup_citus_cluster.sh --workers=2 --port=5432 --user=postgres --pass=your-secure-password

# Start worker(s)
docker compose up -d

# Verify workers are running
docker ps
docker logs citus-worker1
```

**Note:** Each worker server will have its own `docker-compose.yml` with only worker services. Workers will be accessible on ports 5433, 5434, etc. if multiple workers per server.

### Worker Configuration Examples(Will be auto-generated):

#### Single Worker Per Server:

```yaml
# Generated docker-compose.yml on worker server
version: "3.8"
networks:
  citus:
    driver: bridge
services:
  worker1:
    image: citusdata/citus:13.0.3
    container_name: citus-worker1
    ports:
      - "5432:5432" # Direct port mapping for external access
    # ... rest of configuration
```

#### Multiple Workers Per Server:

```yaml
# For servers with more resources
version: "3.8"
networks:
  citus:
    driver: bridge
services:
  worker1:
    image: citusdata/citus:13.0.3
    container_name: citus-worker1
    ports:
      - "5432:5432"
  worker2:
    image: citusdata/citus:13.0.3
    container_name: citus-worker2
    ports:
      - "5433:5432"
```

## Step 3: Register Workers with Coordinator

### From the Coordinator Server:

Once all servers are running, register each worker with the coordinator:

```bash
# Register worker on Server B (replace with actual IP/hostname)
./add_worker_to_coordinator.sh --host server-b.example.com --port 5432

# Register worker on Server C
./add_worker_to_coordinator.sh --host server-c.example.com --port 5432

# If multiple workers per server, register each port
./add_worker_to_coordinator.sh --host server-d.example.com --port 5432
./add_worker_to_coordinator.sh --host server-d.example.com --port 5433
```

### Verify Cluster Setup:

```bash
# Connect to coordinator
docker exec -it citus-coordinator psql -U postgres -d postgres

# Check registered workers
SELECT * FROM citus_get_active_worker_nodes();
```

Expected output:

```
   nodename        | nodeport
-------------------+----------
 server-b.example.com |     5432
 server-c.example.com |     5432
 server-d.example.com |     5432
 server-d.example.com |     5433
```

## Network Configuration

### Firewall Rules

Ensure these ports are accessible between servers:

```bash
# On each server, allow PostgreSQL port from coordinator
sudo ufw allow from <coordinator-ip> to any port 5432
sudo ufw allow from <coordinator-ip> to any port 5433  # if multiple workers

# On coordinator, allow connections from workers (for metadata sync)
sudo ufw allow from <worker-ip> to any port 5432
```

### DNS/Host Resolution

For reliable connectivity, configure DNS or hosts files:

```bash
# /etc/hosts on coordinator server
192.168.1.10    coordinator.internal
192.168.1.11    worker1.internal
192.168.1.12    worker2.internal

# /etc/hosts on worker servers
192.168.1.10    coordinator.internal
```

Then use hostnames in registration:

```bash
./add_worker_to_coordinator.sh --host worker1.internal --port 5432
./add_worker_to_coordinator.sh --host worker2.internal --port 5432
```

## Production Considerations

### 1. Resource Allocation

**Coordinator Server:**

- CPU: 4-8 cores (for query planning and routing)
- RAM: 8-16GB (metadata cache and connection pooling)
- Storage: Fast SSD for metadata and logs

**Worker Servers:**

- CPU: 8-16+ cores (parallel query execution)
- RAM: 16-64GB+ (data caching and sorting)
- Storage: Fast SSD with high IOPS for data storage

## Operational Commands

### Cluster Management

```bash
# Check cluster health from coordinator
docker exec -it citus-coordinator psql -U postgres -d postgres -c "SELECT * FROM citus_check_cluster_node_health();"

# Rebalance data after adding new workers
docker exec -it citus-coordinator psql -U postgres -d postgres -c "SELECT citus_rebalance_start();"

# Monitor rebalancing progress
docker exec -it citus-coordinator psql -U postgres -d postgres -c "SELECT * FROM citus_rebalance_status();"
```

### Worker Maintenance

```bash
# Drain worker before maintenance (moves shards to other workers)
docker exec -it citus-coordinator psql -U postgres -d postgres -c "SELECT citus_drain_node('worker1.internal', 5432);"

# Remove worker from cluster
docker exec -it citus-coordinator psql -U postgres -d postgres -c "SELECT citus_remove_node('worker1.internal', 5432);"

# Re-add worker after maintenance
./add_worker_to_coordinator.sh --host worker1.internal --port 5432
```

### Scaling Operations

#### Adding New Worker Server:

1. **Provision new server** with same setup
2. **Deploy worker** on new server:

   ```bash
   git clone <your-repo-url> pg-dist
   cd pg-dist
   ./setup_citus_cluster.sh --workers=1 --port=5432 --user=postgres --pass=your-secure-password
   docker compose up -d
   ```

3. **Register with coordinator**:

   ```bash
   # From coordinator server
   ./add_worker_to_coordinator.sh --host new-worker.internal --port 5432
   ```

4. **Rebalance data**:
   ```bash
   docker exec -it citus-coordinator psql -U postgres -d postgres -c "SELECT citus_rebalance_start();"
   ```

## Troubleshooting Multi-Server Setup

### Connection Issues

```sql
-- Test connectivity from coordinator to workers
SELECT * FROM citus_check_connection_health();

-- If connection fails, check:
-- 1. Network connectivity: ping worker-host
-- 2. Port accessibility: telnet worker-host 5432
-- 3. PostgreSQL service: docker logs citus-worker1
-- 4. Credentials: ensure same POSTGRES_USER/PASSWORD across nodes
```

### Data Distribution Issues

```sql
-- Check shard distribution across workers
SELECT
    nodename,
    nodeport,
    count(*) as shard_count
FROM citus_shards
GROUP BY nodename, nodeport
ORDER BY shard_count DESC;

-- Rebalance if distribution is uneven
SELECT citus_rebalance_start();
```

This multi-server setup provides true horizontal scaling with dedicated resources per node, better fault isolation, and the flexibility to scale individual components based on workload requirements.
