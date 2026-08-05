# Configuration reference

> Generated / curated for Wave 16. Defaults are one-box friendly.

## Stack environment (production compose)

Read from the stack `.env` beside `compose.nas.yaml`. Template:
[`compose.nas.env.example`](../compose.nas.env.example).

| Variable | Type | Default | Scope | Description |
|----------|------|---------|-------|-------------|
| `COMPOSE_FILE` | string | none | compose | Set to `compose.nas.yaml` so a plain `docker compose` resolves to the single stack file. Keeps the directory free of a duplicate `docker-compose.yaml`, whose merge repeats every list-valued service key |
| `COMPOSE_PROJECT_NAME` | string | `open-family` | compose | Project name; also builds the JMeter volume and network names passed to `opl-api` |
| `OPA_DOCKER_GID` | int | `999` | collector | GID owning `/var/run/docker.sock`, added to the collector (which runs as uid/gid `65534`) so it can read container stats. Check with `getent group docker` |

## OAM environment (account plane)

| Variable | Type | Default | Scope | Description |
|----------|------|---------|-------|-------------|
| `LISTEN_ADDR` | string | `:8090` | oam-api | Listen address |
| `CLICKHOUSE_DB` | string | `oam` | oam-api | Product database |
| `OAM_SECRET_KEY` | string | falls back to `OPA_CONNECTOR_SECRET` | oam-api | AES-256-GCM key material for secrets at rest. **Must derive to the same bytes as the key ORA already uses**, because the migration copies ORA's ciphertext verbatim rather than re-encrypting it. Setting this to a *different* value is the one change that makes migrated credentials undecryptable — it fails closed and logs, it never returns garbage. Booting with no key is allowed (directory + model bindings still work) but every credential write is refused and `/api/health` reports `secret_key_present: false` |
| `OPEN_SERVICE_JWT_SECRET` | string | empty | oam-api | **Required for credential resolution.** `POST /api/agents/resolve` refuses to serve without it, regardless of `OPA_AUTH_REQUIRED`: it is the only route returning a plaintext key, and a peer that cannot be authenticated must not receive one |

Consumers set `PEER_OAM_URL`. With it unset, a product uses its pre-OAM
environment path unchanged — that is the rollback switch, and it needs no code
change.

### Model selection is no longer environment-driven

`OPM_MODEL`, `OPM_MODEL_PLANNING`, `OPM_MODEL_CODING`, `OPM_MODEL_REVIEW`,
`OPM_MODEL_IDEATION`, `OPM_MODEL_ROADMAP_DISCOVERY`,
`OPM_MODEL_ROADMAP_FEATURES`, `OPM_MODEL_PROVIDER` and `OPM_MODEL_BASE_URL` are
**legacy**. They applied to the whole deployment, so no organization, project or
user could choose their own model.

Model choice now lives in OAM as a per-agent binding, resolved per job for the
acting user (`task override → user → org → product default → family default`).
Configure it in the OAM console's **Agents & Models** page, or via
`POST /api/models/bindings/set`. The variables above are read only when
`PEER_OAM_URL` is unset, and are kept solely so a deployment can roll back.

`OPM_MODEL_API_KEY` / `CURSOR_API_KEY` remain readable as an explicit
admin-scope development fallback, default off. They are never a tenant fallback:
a job whose org has no credential fails closed with `credential_unavailable`
rather than borrowing the deployment's key.

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
