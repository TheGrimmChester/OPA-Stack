# Product interop

Products are **optional peers**. No hard dependency at boot. An empty peer URL disables the feature or returns `503` with `peer_unavailable`.

## User auth

| Mode | Mechanism | How to enable |
|------|-----------|---------------|
| **Standalone** | Each product issues JWTs with its own `JWT_SECRET` via local `/api/auth/login` | `AUTH_MODE=standalone`, or leave `PEER_OPA_URL` empty |
| **Co-deployed** | Shared `JWT_SECRET`; **OPA-Hub** issues user JWTs; ORA/OSA/OPL/OPM validate | `AUTH_MODE=codeployed`, or set `PEER_OPA_URL` to the hub |
| **CI** | Product tokens (not `JWT_SECRET`) | Pipeline secrets |

Headers: `Authorization: Bearer <user-jwt>`, `X-Organization-ID`, `X-Project-ID`.

### Co-deployed browser login (`/hub-auth`)

ORA, OSA, OPL, and OPM dashboards proxy hub auth at same-origin **`/hub-auth/`** (nginx → `hub:8080`). Login pages POST to `/hub-auth/api/auth/login` so the browser never needs a cross-origin hub URL. Product-local `/api/auth/login` on those APIs returns **`503`** in co-deployed mode; status under `/hub-auth/api/auth/status` reports `issuer=opa-hub`.

OPA Dashboard talks to the hub URL directly (no `/hub-auth` bridge).

NAS verification (all four peer dashboards):

```bash
for port in 8089 8094 8095 8098; do
  curl -sf "http://127.0.0.1:$port/hub-auth/api/auth/status" | jq -r .issuer   # opa-hub
done
curl -sf -X POST http://127.0.0.1:8098/hub-auth/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' | jq -r .token
```

### Lab credentials

Smoke / lab default seed user: username **`admin`** / password **`admin`** (hub issuer, and each product’s local issuer in standalone). Override with `AUTH_ADMIN_USER` / `AUTH_ADMIN_PASSWORD`. Change immediately outside throwaway lab environments.

## ClickHouse databases

One ClickHouse server can host all products. Each service sets its own database:

| Product | `CLICKHOUSE_DB` |
|---------|-----------------|
| OPA hub | `opa` |
| ORA | `ora` |
| OSA | `osa` |
| OPL | `opl` |

`compose.all.yaml` creates all four databases on first boot (`clickhouse/init-databases.sql`). Solo profiles create the same init script so a shared server stays consistent. Prefer `CLICKHOUSE_DB`; `CLICKHOUSE_DATABASE` is an accepted alias.

### ORA connector backfill (legacy `opa.connectors`)

Co-deployed stacks split databases: hub writes `opa.*`, ORA writes `ora.*`. GitHub connector rows created before the product split may still live only in **`opa.connectors`**. On boot, `ora-api` rewrites new SQL to `ora.connectors`, then **backfills** missing legacy rows from hub `opa.connectors` into the product DB (via `QueryExact` on the hub database). Without this, peer `POST /api/peer/scm/clone-credentials` can return `404 connector not found` after restart even when connectors appear in the UI.

After upgrading `ora-api:nas`, recreate the container and confirm hydrate logs report legacy backfill counts. No manual SQL migration is required for normal operation.

## Service-to-service

Caller sets `PEER_{OPA|ORA|OSA|OPL|OPM}_URL` and mints a **service JWT** with `OPEN_SERVICE_JWT_SECRET`. Prefer a secret **distinct from** user `JWT_SECRET`. On NAS (`compose.nas.yaml`), `OPEN_SERVICE_JWT_SECRET` is required in `.env` and is not substituted from `JWT_SECRET`.

- Claims: `iss`, `aud`, `sub=service`, `scope`, short `exp`, optional `org_id`
- Callee rejects bad `aud` / unknown `iss` / missing scope

| Scope | Meaning |
|-------|---------|
| `findings:read` | Read AppSec findings / run summaries |
| `runs:write` | Create/link security run from review |
| `traces:read` | Trace metadata for correlation |
| `ingest:load_run` | Load-run correlation |
| `health:read` | Peer probe |
| `connectors:read` | List ORA GitHub connectors / repos (OPM → ORA) |
| `scm:clone` | Short-lived clone credentials for ephemeral job workspaces (OPM → ORA) |

## OPM + Hub + GitHub

OPM projects are **GitHub repositories** only (no local folder registry).

| Concern | Owner |
|---------|-------|
| User JWTs / org directory | **OPA-Hub** (`PEER_OPA_URL`) |
| GitHub App / PAT connectors | **ORA** (`PEER_ORA_URL`; configure `OPA_GITHUB_APP_*` / PAT on `ora-api`) |
| Kanban / roadmap / task jobs | **OPM** |
| Code review / Repo Watch | **ORA** (deep-link; do not duplicate) |

NAS/open-family already sets `PEER_OPA_URL` and `PEER_ORA_URL` on `opm-api` and `osa-api`. Redeploy `opm-api:nas`, `osa-api:nas`, `osa-dashboard:nas`, `opa-hub:nas`, and `ora-api:nas` after upgrading images.

**Task job workspaces:** `opm-orchestrator` runs `run-planning` and other task jobs inside the **`opm-api:nas` runtime image**, which must include **`git`** for ORA-mediated clone credentials. If jobs fail with `git: executable file not found in $PATH`, rebuild `opm-api:nas` (runtime stage includes git) and recreate `opm-api` / `opm-orchestrator`. See [OPM-API github-setup](https://github.com/TheGrimmChester/OPM-API/blob/main/docs/github-setup.md).

## Allowed peer calls

| Caller → Callee | Purpose | Required? |
|-----------------|---------|-----------|
| OPL → OPA hub | `load_run_id` correlation | Optional |
| ORA → OSA | findings / `security_run_id` / gate status | Optional |
| OSA → OPA hub | runtime context deep links | Optional |
| ORA → OPA hub | dashboard deep links | Optional |
| ORA → OPM | Roadmap / task handoff (optional) | Optional |
| OPM → OPA hub | Org directory / identity co-deploy | Recommended in family stacks |
| OPM → ORA | List connectors/repos; clone credentials; review deep-link | Recommended for GitHub projects |
| Dashboard → foreign API | **Forbidden** — UI → own API only | — |

## Config sketch

```bash
JWT_SECRET=
AUTH_MODE=                 # standalone | codeployed (auto from PEER_OPA_URL when empty)
OPEN_SERVICE_JWT_SECRET=
CLICKHOUSE_URL=http://clickhouse:8123
CLICKHOUSE_DB=             # opa | ora | osa | opl per service
PEER_OPA_URL=
PEER_ORA_URL=
PEER_OSA_URL=
PEER_OPL_URL=
PEER_OPM_URL=
OPA_PUBLIC_URL=            # legacy alias; prefer ORA_PUBLIC_URL for ora-api webhooks
ORA_PUBLIC_URL=            # public base for ora-api (GitHub webhooks / review callbacks)
OSA_PUBLIC_URL=
OPL_PUBLIC_URL=
OPM_PUBLIC_URL=
```

On NAS (`open-family`), `ORA_PUBLIC_URL` / `OPA_PUBLIC_URL` currently share the legacy hostname `https://ai-orchestrator.clouded.fr`, which fronts **ora-api**. See [nas-deploy.md](nas-deploy.md).

## All-in-one compose

See [`compose.all.yaml`](../compose.all.yaml): one ClickHouse, databases `opa`/`ora`/`osa`/`opl`, shared `JWT_SECRET`, hub-issued tokens (`AUTH_MODE=codeployed`). Product dashboards use the `/hub-auth/` nginx bridge for browser login. Lab seed user is `admin` / `admin`.
