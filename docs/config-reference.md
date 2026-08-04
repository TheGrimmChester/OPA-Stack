# Configuration reference

> Generated / curated for Wave 16. Defaults are one-box friendly.

## Agent environment

| Variable | Type | Default | Scope | Description |
|----------|------|---------|-------|-------------|
| `CLICKHOUSE_URL` | string | `http://localhost:8123` | process | ClickHouse HTTP endpoint |
| `TRANSPORT_TCP` | string | empty | process | ND-JSON TCP listen addr (e.g. `:9090`) |
| `SOCKET_PATH` | string | empty | process | Unix socket path |
| `JWT_SECRET` | string | ephemeral | process | ≥32 bytes when `OPA_AUTH_REQUIRED=1` (user JWTs) |
| `OPEN_SERVICE_JWT_SECRET` | string | empty | process | Service JWT mint/validate; **must be distinct from** `JWT_SECRET` on NAS (required; no compose fallback) |
| `AUTH_MODE` | string | auto | process | `standalone` \| `codeployed`; empty auto-resolves from `PEER_OPA_URL` |
| `AUTH_ADMIN_USER` | string | `admin` | process | Lab seed username for local / hub issuer |
| `AUTH_ADMIN_PASSWORD` | string | `admin` | process | Lab seed password (change outside throwaway lab) |
| `OPA_AUTH_REQUIRED` | bool | `0` | process | Enforce JWT on data/admin APIs |
| `OPA_REDACT` | bool | `0` | process | PII redaction |
| `OPA_LEADER_ELECTION` | bool | `1` | process | Single-writer background jobs |
| `OPA_REPLICAS` | int | `1` | topology | Advertised replica count |
| `OPA_INGEST_SHARDS` | int | `1` | ingest | Trace-id shard count |
| `OPA_INGEST_SHARD_INDEX` | int | `0` | ingest | This process shard index |
| `OPA_ADMISSION_PER_SEC` | int | `0` | ingest | Admission cap (`0` = off) |
| `OPA_LOAD_SHED_HEAP_MB` | int | `0` | ingest | Shed when heap ≥ N MiB |
| `OPA_TLS_CERT_FILE` | path | empty | API | TLS cert for admin API |
| `OPA_TLS_KEY_FILE` | path | empty | API | TLS key |
| `OPA_TLS_CLIENT_AUTH` | bool | `0` | API | Require client certs |
| `OPA_INGEST_AUTH_REQUIRED` | bool | `0` | ingest | Require ingest token |
| `OPA_INGEST_TOKEN` | string | empty | ingest | Shared ingest bearer token |
| `OPA_PPROF` | bool | `0` | debug | Expose `/debug/pprof/` |
| `OPA_DEADMAN` | bool | `1` | ops | Log ingest silence |
| `OPA_DEADMAN_SILENCE_SECS` | int | `300` | ops | Silence threshold |
| `OPA_BUILD_VERSION` | string | `dev` | ops | `/api/version` |
| `OPA_OTLP_GRPC` | bool | `0` | ingest | Enable OTLP/gRPC `:4317` |
| `OPA_WS_ALLOWED_ORIGINS` | string | empty | WS | Allowed WebSocket origins |

Regenerate hints from source:

```bash
# from OPA-Agent
./scripts/gen-config-reference.sh
```
