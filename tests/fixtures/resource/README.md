# Resource Metric Source — Research & Decision

## Summary

**Selected sources: cAdvisor (per-container) + node_exporter (host-level)**

cAdvisor and node_exporter are not deployed in a standard ethereum-package enclave but can be
run as additional Docker containers on the same Kurtosis enclave network. This document records
the research, deployment pattern, and findings from a live ethereum-package enclave.

## Deployment Pattern

Spin up ethereum-package normally, then attach cAdvisor and node_exporter to the enclave network:

```bash
# Find the enclave network
docker network ls | grep <enclave-name>

# Run cAdvisor with kurtosis_service_name label whitelisted
docker run -d \
  --name cadvisor \
  --network kt-<enclave-name> \
  --volume /var/run/docker.sock:/var/run/docker.sock:ro \
  --volume /sys:/sys:ro \
  --volume /var/lib/docker/:/var/lib/docker:ro \
  gcr.io/cadvisor/cadvisor:latest \
  --docker_only=true \
  --store_container_labels=true \
  --whitelisted_container_labels=kurtosis_service_name \
  --housekeeping_interval=15s

# Run node_exporter
docker run -d \
  --name node-exporter \
  --network kt-<enclave-name> \
  --pid host \
  prom/node-exporter:latest
```

Then add scrape jobs to the Prometheus config and hot-reload:

```yaml
- job_name: "cadvisor"
  metrics_path: "/metrics"
  scrape_interval: 15s
  static_configs:
    - targets: ['cadvisor:8080']

- job_name: "node-exporter"
  metrics_path: "/metrics"
  scrape_interval: 15s
  static_configs:
    - targets: ['node-exporter:9100']
```

```bash
curl -X POST http://<prometheus-addr>/-/reload
```

## Label Schema

### cAdvisor (per-container)

On Linux hosts, cAdvisor exposes `kurtosis_service_name` as a Prometheus label when launched
with `--whitelisted_container_labels=kurtosis_service_name`. This label contains the
ethereum-package service name (e.g. `el-1-geth-lighthouse`, `cl-1-lighthouse-geth`) and is
how container metrics are matched back to Ethereum services.

Confirmed Docker label on ethereum-package containers:kurtosis_service_name: "el-1-geth-lighthouse"

kurtosis_service_uuid: "73a1fe6c750f492ebe54ac741dc5d3b1"

com.kurtosistech.custom.ethereum-package.client: "geth"

com.kurtosistech.custom.ethereum-package.client-type: "execution"### node_exporter (host-level)

node_exporter exposes host-level metrics with no per-container breakdown. Used for overall
host health panels: CPU load average, memory pressure, disk capacity, network throughput.

## Mac/Docker Desktop Limitation

cAdvisor on Docker Desktop for Mac can only see the root cgroup (`id="/"`) and cannot
enumerate individual containers. This is because Docker Desktop runs inside a Linux VM
and cAdvisor cannot access the VM's cgroup hierarchy from inside a container.

**Per-container metrics from cAdvisor work correctly on Linux hosts**, which is the
intended production environment for ethereum-package devnets.

Fixtures in this directory were collected on a Mac — they show node_exporter working
fully and cAdvisor working at host level only. On Linux, cAdvisor will additionally
expose per-container metrics with `kurtosis_service_name` labels.

## Metrics Confirmed Working

| Source | Metric | Coverage |
|---|---|---|
| cAdvisor | `container_cpu_usage_seconds_total` | Per-container on Linux, host-only on Mac |
| cAdvisor | `container_memory_working_set_bytes` | Per-container on Linux, host-only on Mac |
| cAdvisor | `container_fs_usage_bytes` | Per-container on Linux, host-only on Mac |
| cAdvisor | `container_network_receive_bytes_total` | Per-container on Linux, host-only on Mac |
| node_exporter | `node_cpu_seconds_total` | Host-level, 80 series confirmed |
| node_exporter | `node_memory_MemAvailable_bytes` | Host-level, confirmed |
| node_exporter | `node_filesystem_avail_bytes` | Host-level, confirmed |
| node_exporter | `node_network_receive_bytes_total` | Host-level, confirmed |

## Fixture Files

| File | Source | Contents |
|---|---|---|
| `cadvisor-cpu.json` | cAdvisor | `container_cpu_usage_seconds_total` |
| `cadvisor-memory.json` | cAdvisor | `container_memory_working_set_bytes` |
| `cadvisor-disk.json` | cAdvisor | `container_fs_usage_bytes` |
| `cadvisor-network.json` | cAdvisor | `container_network_receive_bytes_total` |
| `node-cpu.json` | node_exporter | `node_cpu_seconds_total` |
| `node-memory.json` | node_exporter | `node_memory_MemAvailable_bytes` |
| `node-disk.json` | node_exporter | `node_filesystem_avail_bytes` |
| `node-network.json` | node_exporter | `node_network_receive_bytes_total` |
| `prometheus-config-with-exporters.yml` | — | Full Prometheus scrape config including cAdvisor and node_exporter jobs |
