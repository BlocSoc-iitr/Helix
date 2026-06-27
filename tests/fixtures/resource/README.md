# Resource Metric Source — Research & Decision

## Summary

**Selected source: client self-reported process and system metrics.**

cAdvisor and node_exporter are not deployed in a standard ethereum-package enclave. The only available per-client resource metrics come from each client's own `/metrics` endpoint, already scraped by Prometheus with full client identity labels.

## What was tested

A single-node ethereum-package enclave was spun up with geth (EL), lighthouse (CL), and lighthouse (VC) using Kurtosis v1.20.0.

Queries run against Prometheus at the enclave's exposed port:

| Query | Result |
|---|---|
| `container_cpu_usage_seconds_total` | 0 results — cAdvisor not present |
| `container_memory_working_set_bytes` | 0 results — cAdvisor not present |
| `node_cpu_seconds_total` | 0 results — node_exporter not present |
| `process_cpu_seconds_total` | 2 results (lighthouse beacon + VC) |
| `process_resident_memory_bytes` | 2 results (lighthouse beacon + VC) |
| `system_cpu_procload` | 1 result (geth) |
| `system_memory_held` | 1 result (geth) |
| `system_disk_readbytes` | 1 result (geth) |
| `p2p_ingress` / `p2p_egress` | 1 result each (geth) |

## Label schema confirmed

All scraped targets carry these labels:

| Label | Values seen |
|---|---|
| `client_name` | `geth`, `lighthouse` |
| `client_type` | `execution`, `beacon`, `validator` |
| `service` | `el-1-geth-lighthouse`, `cl-1-lighthouse-geth`, `vc-1-geth-lighthouse` |
| `job` | same as `service` |
| `instance` | `<service>:<port>` |

## Metric source per client

| Client | CPU | Memory | Disk | Network |
|---|---|---|---|---|
| Geth (EL) | `system_cpu_procload` | `system_memory_held` | `system_disk_readbytes` / `system_disk_writebytes` | `p2p_ingress` / `p2p_egress` |
| Lighthouse beacon (CL) | `process_cpu_seconds_total` | `process_resident_memory_bytes` | not available | not available |
| Lighthouse VC | `process_cpu_seconds_total` | `process_resident_memory_bytes` | not available | not available |

## Gaps

- Disk and network metrics are only available for Geth via `system_*`. CL and VC clients do not expose equivalent metrics.
- No cross-client unified disk or network metric exists without cAdvisor.

## Fixture files

| File | Contents |
|---|---|
| `cpu.json` | `process_cpu_seconds_total` + `system_cpu_procload` |
| `memory.json` | `process_resident_memory_bytes` + `system_memory_held` |
| `disk.json` | `system_disk_readbytes` + `system_disk_writebytes` |
| `network.json` | `p2p_ingress` + `p2p_egress` |
| `targets.json` | Full `/api/v1/targets` output showing all scrape targets and labels |
