# Product interop

Products are **optional peers**. No hard dependency at boot. An empty peer URL disables the feature or returns `503` with `peer_unavailable`.

## User auth

| Mode | Mechanism | How to enable |
|------|-----------|---------------|
| **Standalone** | Each product issues JWTs with its own `JWT_SECRET` via local `/api/auth/login` | `AUTH_MODE=standalone`, or leave `PEER_OPA_URL` empty |
| **Co-deployed** | Shared `JWT_SECRET`; **OPA-Hub** issues user JWTs; ORA/OSA/OPL/OPM validate | `AUTH_MODE=codeployed`, or set `PEER_OPA_URL` to the hub |
| **CI** | Product tokens (not `JWT_SECRET`) | Pipeline secrets |

Headers: `Authorization: Bearer <user-jwt>`, **`X-Organization-ID`**, **`X-Project-ID`**.

### Tenant headers (required when auth is on)

Full curl matrix (no JWT → 401, wrong org → empty/403, co-deployed local login → 503): [security-tenant-scopes.md](security-tenant-scopes.md). Harness: `HOST=192.168.100.101 ./harness/security-tenant-matrix.sh`.

When `OPA_AUTH_REQUIRED=1` (NAS default on hub + ORA/OSA/OPL/OPM), Open-Tenant scopes ClickHouse list queries to the org/project in those headers. **Omit either header** (or send the picker marker `"all"`, which is stripped) and list endpoints scope to **`default-org` / `default-project`** — the same write tenant used for INSERT — not an empty array. They still return HTTP 200 (not `401`/`403`). Rows written under another tenant (e.g. `nas` / `infra`) stay invisible until you send those headers.

Always prefer sending both headers with the hub JWT. Canonical names (case-insensitive): `X-Organization-ID`, `X-Project-ID`. Query fallbacks `organization_id` / `project_id` work the same. The `"all"` picker marker is stripped under auth and does not widen scope to every tenant (Open-Tenant-Go ≥ 0.2.2 aligns missing/`all` with `WriteTenant` defaults).

Verified on NAS (`192.168.100.101`; use `127.0.0.1` when curling on the host) after Open-Tenant-Go 0.2.2:

| Product | Port | List path | Without headers | With `default-org` / `default-project` | With `nas` / `infra` |
|---------|------|-----------|-----------------|----------------------------------------|----------------------|
| OSA | `8093` | `GET /api/security/runs` | default-org rows | same | nas/infra rows |
| OSA | `8093` | `GET /api/security/secrets` | default-org findings | same | nas/infra findings |
| OPL | `8092` | `GET /api/perf/scenarios` | default-org scenarios | same | nas/infra scenarios |
| OPL | `8092` | `GET /api/perf/runs` | default-org runs | same | nas/infra runs |

Some ORA admin/SCM surfaces still return broader lists when headers are missing (honesty text may say tenant All). Prefer sending headers anyway so dashboards and scripts match the scoped tenant.

```bash
# On NAS host — or replace 127.0.0.1 with 192.168.100.101 from the LAN
TOKEN=$(curl -sf -X POST http://127.0.0.1:18080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' | jq -r .token)

# Default write tenant (no headers → default-org / default-project)
curl -sf "http://127.0.0.1:8092/api/perf/runs?limit=5" \
  -H "Authorization: Bearer $TOKEN" | jq '.runs | length'

# Explicit default tenant
curl -sf "http://127.0.0.1:8092/api/perf/scenarios" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Organization-ID: default-org" \
  -H "X-Project-ID: default-project" | jq '.scenarios | length'

# Other tenant
curl -sf "http://127.0.0.1:8092/api/perf/runs?limit=5" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Organization-ID: nas" \
  -H "X-Project-ID: infra" | jq '.runs | length'
```

Product docs: [OSA api](https://github.com/TheGrimmChester/OSA-API/blob/main/docs/api.md), [OPL interop](https://github.com/TheGrimmChester/OPL-API/blob/main/docs/interop.md), [ORA interop](https://github.com/TheGrimmChester/ORA-API/blob/main/docs/interop.md), [OPM security](https://github.com/TheGrimmChester/OPM-API/blob/main/docs/security.md).

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
| OAM | `oam` |

`compose.all.yaml` creates all four databases on first boot (`clickhouse/init-databases.sql`). Solo profiles create the same init script so a shared server stays consistent. Prefer `CLICKHOUSE_DB`; `CLICKHOUSE_DATABASE` is an accepted alias.

### Legacy hub `opa.*` product tables

Before per-product databases (`ora` / `osa` / `opl`), some product APIs wrote SCM, AppSec, and perf rows into the shared hub database (`opa.*`). SQL in those APIs still uses the legacy `opa.<table>` qualifier; the ClickHouse client rewrites it to the product DB (`ora.*`, `osa.*`, `opl.*`) at query time.

**Hub-only tables** (never rewritten): `opa.organizations`, `opa.projects`, `opa.api_keys`, `opa.federation_peers`, `opa.callgraph_agg`. Use `QueryExact` / `hubTable()` for these.

**Product tables with boot backfill** (when `CLICKHOUSE_DB` ≠ `opa` and hub row count exceeds product):

| Product | Tables | Boot backfill |
|---------|--------|---------------|
| ORA | `connectors`, `watched_repos`, `scm_jobs`, `scm_review_stacks`, `scm_webhooks`, `review_contexts`, `scm_secrets`, `ai_reviews`, `agent_prefs` | Row-level for `connectors`; bulk `INSERT SELECT` for the rest |
| OSA | `security_runs`, `secret_findings`, `sast_findings`, `iac_findings`, `vuln_findings`, `iast_findings`, `service_dependencies` | Bulk `INSERT SELECT` on startup |
| OPL | `load_scenarios`, `load_runs`, `load_run_samples` | Uses explicit `chTable()` — no rewrite; no backfill needed when empty |

After upgrading ORA/OSA images on a NAS that still has legacy hub rows, restart the API once and confirm product DB counts match hub (or exceed hub when dual-written). OPL already qualifies tables explicitly and does not rely on rewrite.

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
| `creds:resolve` | Resolve a job's model + API key (any product → OAM). The only scope that yields a plaintext credential |
| `catalog:write` | Publish a product's agent/task catalog (any product → OAM) |
| `orgs:read` / `users:read` | Read the OAM directory (hub, products → OAM) |
| `scm:pm` | Milestones + Projects v2 list/bind/sync (OPM → ORA peer `/api/peer/scm/milestones/*`, `/api/peer/scm/projects/*`) |

## OPM + Hub + GitHub

OPM projects are **GitHub repositories** only (no local folder registry).

| Concern | Owner |
|---------|-------|
| Organizations / projects / users / RBAC | **OAM** (`PEER_OAM_URL`) |
| Connectors, API keys, AI provider credentials, per-agent model bindings | **OAM** (`PEER_OAM_URL`) |
| User JWTs / org directory | **OPA-Hub** (`PEER_OPA_URL`) — reads the OAM directory when `PEER_OAM_URL` is set |
| GitHub App / PAT *protocol* work (install-url, callback, clone creds, PR/issue writes) | **ORA** (`PEER_ORA_URL`), using OAM-stored credentials |
| Kanban / roadmap / task jobs | **OPM** |
| Code review / Repo Watch | **ORA** (deep-link; do not duplicate) |

### Per-job credentials and models (OAM)

A job resolves the model **and** the API key it runs with from OAM, in one call,
scoped to the user who enqueued it:

```
POST /api/agents/resolve   (service JWT, scope creds:resolve)
  { organization_id, project_id, user_id, product, agent_key, override? }
→ { provider, model, base_url, api_key, key_scope, model_source, agent_key_known }
```

Model resolution: `task override → user → org → product default → family default`.
The family default is `cli_cursor` / `auto`, which is what every product runs
today, so adopting OAM changes no behaviour until someone sets an override.
Credential resolution: `user → org → fail closed` — never an admin key, never a
process environment variable. A job whose org has no credential fails with
`credential_unavailable` rather than borrowing a deployment-wide key.

Model and key come back **together** on purpose: two separate calls can disagree
(an org's key paired with a user's model, or a rotation landing between the
lookups) and a job must never run that combination.

**Agent keys belong to the product.** OAM normalises formatting and nothing else —
it does not translate a job action into an agent key, because that is not a string
transform: in OPM, `run-implementation` is the **coding** phase and both
`run-planning` and `run-followup-planning` are **planning**. Each product owns its
mapping and publishes its keys via `POST /api/agents/catalog/publish` on boot; a
key that was never published resolves against a default and reports
`agent_key_known: false`.

**OPM adoption:** with `PEER_OAM_URL` set, `OPM_MODEL*` and `CURSOR_API_KEY` no
longer participate. Unset it and OPM falls back to that environment path exactly
as before — including its per-phase `OPM_MODEL_<PHASE>` overrides.

NAS/open-family already sets `PEER_OPA_URL` and `PEER_ORA_URL` on `opm-api` and `osa-api`. Redeploy `opm-api:nas`, `osa-api:nas`, `osa-dashboard:nas`, `opa-hub:nas`, and `ora-api:nas` after upgrading images.

### OSA security-runs list cap

`GET /api/security/runs` on `osa-api` applies a **server-side `limit` clamp of 200** (default `50`). Requests like `?limit=500` still return at most 200 rows; there is no offset/cursor pagination and no `total` in the JSON. This is intentional — not a ClickHouse or rewrite bug. The dashboard requests `limit=50` for the “Past runs” panel.

Verify on NAS (hub JWT + tenant headers; row counts are per org/project, not global). Omit the tenant headers and this returns `0` even when ClickHouse has rows — see [Tenant headers](#tenant-headers-required-when-auth-is-on).

```bash
TOKEN=$(curl -sf -X POST http://127.0.0.1:18080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' | jq -r .token)
# ClickHouse total (all tenants): curl -sf 'http://127.0.0.1:8123/?query=SELECT%20count()%20FROM%20osa.security_runs'
curl -sf "http://127.0.0.1:8093/api/security/runs?limit=500" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Organization-ID: default-org" \
  -H "X-Project-ID: default-project" | jq '.runs | length'   # max 200
```

See [OSA-API api.md](https://github.com/TheGrimmChester/OSA-API/blob/main/docs/api.md) for param details.

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
CLICKHOUSE_DB=             # opa | ora | osa | opl | oam per service
OAM_SECRET_KEY=            # oam-api only; must match ORA's OPA_CONNECTOR_SECRET
PEER_OPA_URL=
PEER_OAM_URL=              # account plane; unset = pre-OAM env behaviour
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
