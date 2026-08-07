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

## Security Redis (stack `.env`)

Required when using `compose.nas.yaml`. Each control plane gets a dedicated Redis; passwords must be distinct (≥16 bytes recommended).

| Variable | Type | Default | Scope | Description |
|----------|------|---------|-------|-------------|
| `REDIS_OPA_PASSWORD` | string | *(required)* | stack | Password for `redis-opa` — wired as `REDIS_URL` on `hub` |
| `REDIS_OAM_PASSWORD` | string | *(required)* | stack | Password for `redis-oam` — wired on `oam-api` |
| `REDIS_ORA_PASSWORD` | string | *(required)* | stack | Password for `redis-ora` — wired on `ora-api` |
| `REDIS_OSA_PASSWORD` | string | *(required)* | stack | Password for `redis-osa` — wired on `osa-api` |
| `REDIS_OPL_PASSWORD` | string | *(required)* | stack | Password for `redis-opl` — wired on `opl-api` |
| `REDIS_OPM_PASSWORD` | string | *(required)* | stack | Password for `redis-opm` — wired on `opm-api` |

`compose.all.yaml` (laptop smoke) supplies dev defaults when unset. Job runners and `opa_agent` never receive `REDIS_URL` — denylisted in Open-Job-Env-Go / ORA `job_env.go`.

Per-product cache tuning (after Open-Cache-Go wiring): `REDIS_URL`, `{PRODUCT}_SEC_L1_CACHE` (default 20000), `{PRODUCT}_SEC_KEY_PREFIX`.

## OAM environment (account plane)

| Variable | Type | Default | Scope | Description |
|----------|------|---------|-------|-------------|
| `LISTEN_ADDR` | string | `:8090` | oam-api | Listen address |
| `CLICKHOUSE_DB` | string | `oam` | oam-api | Product database |
| `OAM_SECRET_KEY` | string | falls back to `OPA_CONNECTOR_SECRET` | oam-api | AES-256-GCM key material for secrets at rest. **Must derive to the same bytes as the key ORA already uses**, because the migration copies ORA's ciphertext verbatim rather than re-encrypting it. Setting this to a *different* value is the one change that makes migrated credentials undecryptable — it fails closed and logs, it never returns garbage. Booting with no key is allowed (directory + model bindings still work) but every credential write is refused and `/api/health` reports `secret_key_present: false` |
| `OAM_RESOLVE_MAX_CANDIDATES` | int | `3` | oam-api | How many endpoints a single resolve returns, so a job can fall through to the next when one is down or over quota. This is an **exposure bound**, not a tuning knob: a job env holds one credential per candidate. Every one is a key that actor already resolves at that scope, so it widens exposure without escalating privilege — but a leaked job env leaks up to this many. Clamped to 1..10; setting `1` restores the pre-failover blast radius exactly. Read per request, so it can be tightened without a restart |
| `OPEN_SERVICE_JWT_SECRET` | string | empty | oam-api | **Required for credential resolution and ingest-key verify.** `POST /api/agents/resolve` and `POST /api/internal/ingest-keys/verify` refuse unauthenticated service JWTs. Distinct from `JWT_SECRET` on NAS |
| `PEER_ORA_URL` | string | empty | oam-api | Required for public connector mutations (BFF → ORA protocol / tokens). Unset → connector writes fail closed (`503 peer_unavailable`) |
| `OAM_DASHBOARD_URL` | string | smoke `http://127.0.0.1:8097` / NAS `http://192.168.100.101:18097` | ora-api | Preferred post-install / claim browser redirect base (`/connectors`). Distinct from `OPA_DASHBOARD_URL` (Check Run / job deep-links) |

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
Configure it in the OAM console's **Agents & Models** page —
`http://<host>:8097/agents` on the laptop stack, `:18097` on NAS — or via
`POST /api/models/bindings/set`. The variables above are read only when
`PEER_OAM_URL` is unset, and are kept solely so a deployment can roll back.

### Endpoints are registered, not enumerated

An organisation or user registers **many** AI endpoints — OpenAI-compatible and
Anthropic-compatible APIs (official or not), several Cursor accounts, Claude Code,
Qwen Code CLI (`cli_qwen_code`), or any other agent CLI — each with its own
credential, in a user-sortable priority order. Manage them on the console's
**AI Endpoints** page.

A job resolves the top `OAM_RESOLVE_MAX_CANDIDATES` of that order and walks them:
on a 429, an unreachable host or a bad key it advances to the next. Failover
happens **inside the job**, so a control-plane blip cannot fail a run that has
already started.

Priority is strict — always start at the top and descend only on failure. Nothing
is remembered between jobs, so an exhausted endpoint is retried first by every
later job and costs one fast 429 before the fall-through. Each resolve records its
offered order and skip count in `oam.audit_log`, so the pattern is visible on the
console's Audit page.

With **no** endpoints registered a deployment behaves exactly as it did before:
resolution synthesises one candidate from the binding's provider and that
provider's single fixed key.

The console's table has one row per agent a product has **published** to
`/api/agents/catalog`, and names the layer each effective model came from, so
"which model will this task run, and why" is answerable before running it. A
product that adds a job kind without publishing it silently inherits the product
default — the boot log lists the keys it registered, so check there first when an
agent is missing from the page.

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
| `OPA_INGEST_AUTH_REQUIRED` | bool | `0` | ingest | Require project ingest key on ND-JSON (auth envelope / field), OTLP/HTTP Bearer, RUM body/`?ingest_key=`, and `/v1` diagnostics |
| `OPA_INGEST_TOKEN` | string | empty | ingest | Optional shared lab bearer when OAM verify is unavailable (no tenant binding). Production collectors use per-project `OPA_INGEST_KEY` minted in OAM |
| `PEER_OAM_URL` | string | empty | ingest/auth | When set, edge verifies project keys via OAM `POST /api/internal/ingest-keys/verify` (needs `OPEN_SERVICE_JWT_SECRET`) |
| `OPA_OTLP_RECEIVER_ADDR` | string | empty | ingest | Optional dedicated OTLP/HTTP listen addr (e.g. `:4318`) for `/v1/traces`; admin mux already serves the same handler. OTLP/gRPC is not implemented |
| `OPA_PPROF` | bool | `0` | debug | Expose `/debug/pprof/` |
| `OPA_DEADMAN` | bool | `1` | ops | Log ingest silence |
| `OPA_DEADMAN_SILENCE_SECS` | int | `300` | ops | Silence threshold |
| `OPA_BUILD_VERSION` | string | `dev` | ops | `/api/version` |
| `OPA_WS_ALLOWED_ORIGINS` | string | empty | WS | Allowed WebSocket origins |

Regenerate hints from source:

```bash
# from OPA-Agent
./scripts/gen-config-reference.sh
```
