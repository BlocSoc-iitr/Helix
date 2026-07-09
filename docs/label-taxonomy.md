# Prometheus Label Taxonomy for ethereum-package Targets

This document maps every Prometheus label attached to scrape targets produced by
[ethpandaops/ethereum-package](https://github.com/ethpandaops/ethereum-package)
(ref: `main`, observed 2026-07-09).

Labels were verified against a live Kurtosis enclave (`helix-dev`) running the
configuration below and cross-checked against
`<prometheus-url>/targets` rendered in the Prometheus UI:

```yaml
participants:
  - el_type: geth
    cl_type: lighthouse
    count: 2
  - el_type: reth
    cl_type: teku
    count: 1
    vc_type: teku
additional_services:
  - prometheus
  - grafana
```

---

## Label Reference Table

| Label | Example values | Cardinality | Description |
|---|---|---|---|
| `service` | `el-1-geth-lighthouse`, `cl-2-reth-teku`, `vc-1-teku`, `remote-signer-1` | one per target | Unique name for the scrape target within the enclave. Pattern: `<role>-<index>-<el_name>-<cl_name>` for paired clients; `<role>-<index>-<client_name>` for standalone roles. |
| `job` | `el`, `cl`, `vc`, `remote-signer` | ~4 | Prometheus job label. Maps directly to client role. |
| `client_type` | `execution`, `beacon`, `validator`, `remote_signer` | 4 | High-level role of the client. Used for grouping and filtering in dashboards. |
| `client_name` | `geth`, `reth`, `lighthouse`, `teku`, `web3signer` | ~5–10 | Name of the specific client implementation. |
| `instance` | `10.0.1.2:9090`, `10.0.1.3:5054` | one per target | `<ip>:<metrics-port>` of the scrape endpoint inside the enclave network. |

---

## Observed Target Types

### 1. Execution Layer (`client_type="execution"`, `job="el"`)

Scraped from the EL client's metrics port (default `:9090` for geth, `:9091`
for additional instances, varies by client).

| Label | Value |
|---|---|
| `job` | `el` |
| `client_type` | `execution` |
| `client_name` | `geth` \| `reth` \| `nethermind` \| `besu` \| `erigon` |
| `service` | `el-<N>-<el_name>-<cl_name>` |

### 2. Consensus Layer (`client_type="beacon"`, `job="cl"`)

Scraped from the CL beacon node metrics port (default `:5054` for lighthouse,
`:8008` for teku).

| Label | Value |
|---|---|
| `job` | `cl` |
| `client_type` | `beacon` |
| `client_name` | `lighthouse` \| `teku` \| `prysm` \| `nimbus` \| `lodestar` |
| `service` | `cl-<N>-<el_name>-<cl_name>` |

### 3. Validator Client (`client_type="validator"`, `job="vc"`)

Appears when a participant specifies `vc_type`. Scraped from the VC metrics port
(default `:8009` for teku, `:5064` for lighthouse-vc).

| Label | Value |
|---|---|
| `job` | `vc` |
| `client_type` | `validator` |
| `client_name` | `teku` \| `lighthouse` \| `prysm` \| `nimbus` \| `lodestar` |
| `service` | `vc-<N>-<cl_name>` |

### 4. Remote Signer (`client_type="remote_signer"`, `job="remote-signer"`)

Appears when `remote_signer_type` is specified (e.g., web3signer). Scraped from
the signer metrics port (default `:9000`).

| Label | Value |
|---|---|
| `job` | `remote-signer` |
| `client_type` | `remote_signer` |
| `client_name` | `web3signer` |
| `service` | `remote-signer-<N>` |

---

## Fixture Coverage

The file `fixtures/targets.prom` exercises all four target types with realistic
label values drawn from the live enclave. One row deliberately has `up=0`
(the `el-2-reth-teku` execution target) to validate down-state panel logic
without requiring a live enclave.

---

## Source References

- ethereum-package source: <https://github.com/ethpandaops/ethereum-package>
- Kurtosis enclave run: `kurtosis run --enclave helix-dev github.com/ethpandaops/ethereum-package --args-file network_params.yaml`
- Prometheus scrape target discovery: `<prometheus-url>/targets` (observed directly, 2026-07-09)
- Package architecture overview: <https://github.com/ethpandaops/ethereum-package/blob/main/docs/architecture.md>
- Configuration reference: <https://github.com/ethpandaops/ethereum-package/blob/main/README.md>
