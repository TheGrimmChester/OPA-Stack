# Product interop

Products are **optional peers**. No hard dependency at boot. An empty peer URL disables the feature or returns `503` with `peer_unavailable`.

## User auth

| Mode | Mechanism | How to enable |
|------|-----------|---------------|
| **Standalone** | Each product issues JWTs with its own `JWT_SECRET` via local `/api/auth/login` | `AUTH_MODE=standalone`, or leave `PEER_OPA_URL` empty |
| **Co-deployed** | Shared `JWT_SECRET`; **OAM** issues user JWTs (`iss=oam-api`) when `PEER_OAM_URL` is set; hub validates and proxies login; ORA/OSA/OPL/OPM validate | `AUTH_MODE=codeployed`, set `PEER_OPA_URL` and `PEER_OAM_URL` |
| **CI** | Product tokens (not `JWT_SECRET`) | Pipeline secrets |

Headers: `Authorization: Bearer <user-jwt>`, **`X-Organization-ID`**, **`X-Project-ID`** (single), and optionally list-only **`X-Project-IDs`**.

### Tenant headers (required when auth is on)

Full curl matrix (no JWT → 401, wrong org → empty/403, co-deployed local login → 503): [security-tenant-scopes.md](security-tenant-scopes.md). Harness: `HOST=192.168.100.101 ./harness/security-tenant-matrix.sh`.

When `OPA_AUTH_REQUIRED=1` (NAS default on hub + ORA/OSA/OPL/OPM), Open-Tenant scopes ClickHouse list queries to the org/project in those headers. **Omit either header** (or send the picker marker `"all"` on **`X-Project-ID`**, which is stripped): there is **no** silent collapse to `default-org` / `default-project`.

| Caller | No-header / empty-org list behavior |
|--------|-------------------------------------|
| **Personal** | Owner-only empty org (`user_id`) — never invent `default-org` |
| **Organization member** | JWT `org_id` pinned — foreign org → **403** |
| **Platform admin (own session)** | Directory (users/orgs) OK; tenant product data → **empty / 400** unless a concrete org is sent or the admin **impersonates** a user |
| **Admin impersonating** | Same tenancy as the target user (`impersonator` claim) |

Rows written under another tenant (e.g. `nas` / `infra`) stay invisible until you send those headers (or impersonate a user in that tenant). Explicit `X-Organization-ID: default-org` still selects that org id when it exists as a real tenant — it is never the empty-header destination.

Always prefer sending org + project headers with the OAM-issued JWT. Canonical names (case-insensitive): `X-Organization-ID`, `X-Project-ID`. Query fallbacks `organization_id` / `project_id` work the same. The `"all"` picker marker on **`X-Project-ID`** is stripped under auth and does **not** widen scope to every tenant. That meaning is unchanged — dashboards must **not** send `X-Project-ID: all` to mean “every enabled project.”

**List multi-select (`X-Project-IDs`):** for list/read endpoints only, clients may send `X-Project-IDs: id1,id2,…` (comma-separated, cap **32**). Open-Tenant-Go turns that into `project_id IN (…)`; Open-Auth-Go ACL-checks every id. Keep **`X-Project-ID` single-valued** for writes and for exactly-one selection. Writes ignore the multi header. UI “All projects” stamps `X-Project-IDs` with the **enabled + allowlisted** OAM directory ids for the current product (same cap) — see [Family project switcher](#family-project-switcher-oam-directory).

**OAM configuration pages** (`/endpoints`, `/agents`, `/connectors`): **All projects** is a valid write scope (org/user-global — API collapses empty project to `default-project`); a single selected project writes project-scoped overrides where the product supports them. Connectors are managed at org/user scope and do not require a concrete project in the switcher.

**Account types (immutable):** users are created as `personal` or `organization` in OAM and the type never changes. **Personal** accounts have empty JWT `org_id` (owner-only); org headers (`X-Organization-ID` other than `"all"`) are rejected (**403**). **Organization** accounts carry a fixed JWT `org_id`; a mismatched org header is rejected (**403**). **Platform admins** list users/orgs without impersonation; for tenant-scoped product work they impersonate or pick a concrete org — never silent `default-org`. Headers select project within the JWT org only — they do not switch organizations. See [security-tenant-scopes.md](security-tenant-scopes.md#account-types-jwt-bound-tenancy).

### Family project switcher (OAM directory)

Every Open dashboard’s project menu lists **OAM directory** projects (`oam.projects`) — the same registry as OAM Dashboard `/projects`. The switcher is **always shown** (including personal accounts). Open-UI-JS `ProjectScopeMenu` + `projectScopeHeaders` implement All + checkbox multi-select; selection state is `'all' | string[]`.

| Concern | Owner |
|---------|-------|
| Directory list + per-product enablement | **OAM** — `GET /api/projects?product=<code>`; `POST /api/projects/products/set` / `set-bulk` |
| Peer proxies | **ORA / OPA-Hub / OPM / OSA / OPL** — `GET /api/oam/projects?product=` forwards to OAM |
| Switcher UI | All six dashboards (Open-UI-JS ≥ 0.3.0) |
| Enablement UI | **OAM Dashboard `/projects` only** — checkbox matrix (OPA/OSA/ORA/OPL/OPM) + row/table select-all |
| OPM board registry | **OPM** — selecting a family project opens its board; `POST /api/projects/ensure` upserts a registry row keyed by the OAM directory id (GitHub fields from `external_key` / `connector_ids` when present). `POST /api/projects` (link) also fills omitted `connectorId`/`ownerRepo` from the directory (fail closed). Attach GitHub from the directory when clone/jobs need a binding (no connector picker). |

/** `disabled_products`:** denylist `Array(String)` on each directory project. Empty = all products enabled (backward compatible). Product code `P` is allowed when `NOT has(disabled_products, P)`. Codes: `opa`, `osa`, `ora`, `opl`, `opm`. OAM’s own management list is unfiltered. Filtered lists: `GET /api/projects?product=osa` (and peer `GET /api/oam/projects?product=osa`). Product job/scan entrypoints **fail closed** when that product is in `disabled_products` for the concrete `X-Project-ID` (skip when `PEER_OAM_URL` unset or project empty/`all`):

| Product | Checked entrypoints | Intentionally skipped |
|---------|---------------------|------------------------|
| OSA | `POST /api/security/runs` (+ batch) | — |
| OPL | `POST /api/perf/runs` | scenario upsert alone (run create is the job gate) |
| ORA | `POST /api/scm/ai-review`, `POST /api/scm/opa-review/stack` | — |
| OPM | `POST /api/projects` (link repo; directory id in header) | Nested board paths `/api/projects/{uuid}/…` (board UUID ≠ OAM directory id) |
| OPA-Hub | — | No job/scan enqueue that stamps a directory `X-Project-ID`; agent ingest unscoped by enablement |

Verified on NAS (`192.168.100.101`; use `127.0.0.1` when curling on the host) after removal of silent `default-org` fallback:

| Product | Port | List path | Without headers | With explicit `default-org` / `default-project` | With `nas` / `infra` |
|---------|------|-----------|-----------------|--------------------------------------------------|----------------------|
| OSA | `8093` | `GET /api/security/runs` | empty / 400 / JWT-pin (not default-org) | default-org rows only if that org is selected | nas/infra rows |
| OSA | `8093` | `GET /api/security/secrets` | empty / 400 / JWT-pin | default-org findings if selected | nas/infra findings |
| OPL | `8092` | `GET /api/perf/scenarios` | empty / 400 / JWT-pin | default-org scenarios if selected | nas/infra scenarios |
| OPL | `8092` | `GET /api/perf/runs` | empty / 400 / JWT-pin | default-org runs if selected | nas/infra runs |

Prefer sending concrete headers (or impersonating) so dashboards and scripts match the intended tenant. No-header responses must **not** match explicit `default-org` counts when that tenant has data.

```bash
# On NAS host — or replace 127.0.0.1 with 192.168.100.101 from the LAN
TOKEN=$(curl -sf -X POST http://127.0.0.1:18080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' | jq -r .token)

# No headers — must NOT silently equal default-org (empty / 400 / JWT-pin)
curl -s -o /tmp/runs-nohdr.json -w '%{http_code}\n' \
  "http://127.0.0.1:8092/api/perf/runs?limit=5" \
  -H "Authorization: Bearer $TOKEN"
jq '.runs | length' /tmp/runs-nohdr.json

# Explicit default tenant (only when intentionally selected)
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

### Co-deployed browser login (`/oam-auth` and `/hub-auth`)

When **`PEER_OAM_URL`** is set (family / NAS stacks), **OAM** is the sole JWT issuer (`iss=oam-api`). Durable users live in `oam.users`; login returns `account_type`, `org_id`, and `project_ids`.

ORA, OSA, OPL, and OPM dashboards expose same-origin nginx bridges:

| Path | Upstream | Use |
|------|----------|-----|
| **`/oam-auth/`** | `oam-api:8090` | **Preferred** — product login pages POST here |
| **`/hub-auth/`** | `hub:8080` | Legacy bridge; hub **proxies** login to OAM when `PEER_OAM_URL` is set |

Product-local `/api/auth/login` on peer APIs returns **`503`** in co-deployed mode. Status under `/oam-auth/api/auth/status` (or proxied `/hub-auth/api/auth/status`) reports `issuer=oam-api`.

OAM Dashboard talks to OAM directly. OPA Dashboard talks to the hub URL (no product bridge).

NAS verification (all four peer dashboards):

```bash
# Preferred: direct OAM bridge
for port in 8089 8094 8095 8098; do
  curl -sf "http://127.0.0.1:$port/oam-auth/api/auth/status" | jq -r .issuer   # oam-api
done
curl -sf -X POST http://127.0.0.1:8098/oam-auth/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' | jq '{token, issuer, account_type, org_id}'

# Hub bridge still works (transparent proxy to OAM)
curl -sf "http://127.0.0.1:8098/hub-auth/api/auth/status" | jq -r .issuer   # oam-api when PEER_OAM_URL set
```

Direct OAM API (NAS port `18090`, laptop smoke `8090`):

```bash
curl -sf -X POST http://127.0.0.1:18090/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' | jq '{issuer, account_type, org_id}'
```

### Lab credentials

Smoke / lab default seed user: username **`admin`** / password **`admin`** (`account_type=personal`, role admin; OAM issuer in co-deployed mode, local issuer in standalone). Override with `AUTH_ADMIN_USER` / `AUTH_ADMIN_PASSWORD`. Change immediately outside throwaway lab environments.

## ClickHouse databases

One ClickHouse server can host all products. Each service sets its own database:
| Product | `CLICKHOUSE_DB` |
|---------|-----------------|
| OPA hub | `opa` |
| ORA | `ora` |
| OSA | `osa` |
| OPL | `opl` |
| OAM | `oam` |

`compose.all.yaml` creates all **five** databases on first boot (`clickhouse/init-databases.sql`: `opa`, `ora`, `osa`, `opl`, `oam`). OPM has no ClickHouse DB (filesystem under `OPM_DATA_DIR`). Solo profiles create the same init script so a shared server stays consistent. Prefer `CLICKHOUSE_DB`; `CLICKHOUSE_DATABASE` is an accepted alias.

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

## Per-family security Redis

Each control-plane API gets **its own Redis** for security workloads (rate limits, dedup markers, encrypted cache blobs). Job runners and the edge agent **never** receive `REDIS_URL`.

| Service | Redis | Consumer | Typical keys |
|---------|-------|----------|--------------|
| `hub` | `redis-opa` | OPA hub | `opa:sec:*` — OAM directory stale cache |
| `oam-api` | `redis-oam` | OAM | `oam:sec:*` — login throttle counters |
| `ora-api` | `redis-ora` | ORA | `ora:sec:*` — webhook dedup, install-perm cache |
| `osa-api` | `redis-osa` | OSA | `osa:sec:*` — OSV CVE L2 cache |
| `opl-api` | `redis-opl` | OPL | `opl:sec:*` — dispatch idempotency |
| `opm-api` | `redis-opm` | OPM | `opm:sec:*` — peer SCM event dedup |

Compose wiring (`compose.nas.yaml` / `compose.all.yaml`):

- Six `redis-*` services on `open_internal` only — **no host ports**
- Per-instance `requirepass`, `maxmemory 256mb`, `FLUSHALL` / `CONFIG` / `DEBUG` renamed
- `appendonly yes` + named volumes for durable negative cache entries
- Each `*-api` / `hub` sets `REDIS_URL=redis://:${REDIS_*_PASSWORD}@redis-<product>:6379/0` and `depends_on` the matching Redis healthcheck

### Tenant encryption (`enc:v2`)

Sensitive cache values and ClickHouse credential columns use **Open-Crypto-Go** `enc:v2` wire format — never cleartext in Redis or backups:

| Scope | Key material | Used for |
|-------|--------------|----------|
| `org` | Org DEK (wrapped in OAM `org_encryption_keys`) | Org-scoped secrets |
| `user` | HKDF(master, org_id, user_id) | User secrets within an org |
| `personal` | HKDF(master, user_id) | Personal account secrets |
| `admin` | Master key | Platform admin secrets |
| `public` | Optional plaintext | Dedup markers, OSV negatives |

**Open-Cache-Go** stores only `enc:v2` blobs in L2 Redis; L1 memory holds plaintext inside the API process (same trust boundary as today's in-memory maps).

### Runner isolation

`REDIS_URL` is **denylisted** from job sandbox env via **Open-Job-Env-Go** (and Open-Job-Go `ScrubEnv`). Job containers run on sealed `opa-job-*` networks with no route to `redis-*`. Verify with `job_env_test.go` / runner network tests — a job box must not resolve `redis-osa` or reach ClickHouse.

NAS defaults (`compose.nas.yaml`): `OPA_JOB_SANDBOX=docker` on ora-api/osa-api; `OPM_RUNNER_NETWORK=internal+proxy` on opm-api (per-job sealed net + egress proxy). Break-glass: `OPA_JOB_SANDBOX=off`, `OPM_RUNNER_NETWORK=bridge`.

### Job tokens and credential leases

- **Job tokens** (`sub=job`): short-lived peer JWTs minted via OAM `POST /api/internal/job-tokens/mint`, revoked on job end. Validated like service JWTs (`aud`/`scope`) plus optional jti allowlist.
- **Credential leases**: OAM `POST /api/internal/job-credentials/lease` → one-shot `redeem` so plaintext model keys are not held longer than needed. OPM prefers lease→redeem and falls back to `/api/agents/resolve`.

### Adversarial-AI assumption

Treat the job agent as an attacker with shell access. Only pass **user/org-owned** data for the acting principal; never platform secrets, `REDIS_URL`, or cross-tenant material. See [ORA job isolation](../../ORA-API/docs/job-isolation.md) and [OPM security](../../OPM-API/docs/security.md).

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
| `connectors:write` | Upsert connector directory metadata (ORA → OAM `POST /api/internal/connectors/sync`); OAM BFF → ORA internal peer mutations |
| `scm:events` | Receive SCM checker fan-out envelope (ORA → OSA/OPL/OPM `POST /api/peer/scm/events`) |
| `scm:clone` | Short-lived clone credentials for ephemeral job workspaces (OPM → ORA) |
| `creds:resolve` | Resolve a job's model + API key (any product → OAM). The only scope that yields a plaintext credential |
| `catalog:write` | Publish a product's agent/task catalog (any product → OAM) |
| `orgs:read` / `users:read` | Read the OAM directory (hub, products → OAM) |
| `scm:pm` | Milestones + Projects v2 list/bind/sync (OPM → ORA peer `/api/peer/scm/milestones/*`, `/api/peer/scm/projects/*`) |

## SCM checker platform

Shared GitHub-driven automation for compatible Open family products. **ORA** is the only webhook entry point; products never receive raw GitHub webhooks directly.

See also: [ORA repo-watch](https://github.com/TheGrimmChester/ORA-API/blob/main/docs/repo-watch.md) (App vs repo-hook setup), [OAM connector sync](https://github.com/TheGrimmChester/OAM-API/blob/main/docs/api.md#connectors-directory).

### Rules (all compatible products)

1. **Single webhook entry** — ORA only. Repo hooks URL: `{ORA_PUBLIC_URL}/v1/scm/github/webhook/{connector_id}`; App webhooks: `{ORA_PUBLIC_URL}/v1/scm/github/webhook`.
2. **OAM tenancy required** — every connector and enabled watch has `organization_id` + `project_id`. No silent `default-org` fallback for SCM automation.
3. **Peer endpoint** — each compatible product exposes `POST /api/peer/scm/events` (service JWT scope **`scm:events`**, `aud=<product>-api`).
4. **Checker response** — list of `{id, check_run_name, should_run, reason, …}`; ORA creates GitHub status surfaces keyed `{product}:{checker_id}`.
5. **Works without App** — repo-webhook + PAT mode uses the **same** fan-out; products must not assume App installation APIs.
6. **Dashboards** — connector/repo setup lives in **OAM Dashboard**; each product dashboard shows its own checkers/findings.

Products opt in when `PEER_<PRODUCT>_URL` is set on ORA. Unconfigured peers are skipped (no error).

### Product compatibility matrix

| Product | SCM peer events | Planned checkers (this platform) | Ship status |
|---------|-----------------|----------------------------------|-------------|
| **OAM** | No (account plane) | Connector directory, org linkage | Sync API + UI |
| **ORA** | Native (hub) | `review`, optional `coding` | Refactor to checker model |
| **OSA** | Yes | `dependencies` (CVE lockfiles), later `secrets`/`sast`/`iac` | **`dependencies` full** |
| **OPL** | Yes | `perf-gate` when load assets change (JMX/HAR paths) | Stub `{checkers:[]}` + contract |
| **OPM** | Yes | `delivery` on PR merge / issue sync hooks | Stub `{checkers:[]}` + contract |
| **OPA** | No | Observability ingest — not PR checker compatible | Out of scope |

### Dual webhook ingress

| Mode | Credential | Webhook URL | Notes |
|------|------------|-------------|-------|
| **GitHub App** | App installation under OAM org | `{ORA_PUBLIC_URL}/v1/scm/github/webhook` | Check Runs when token allows; OAM-scoped install state |
| **Repository hooks** | PAT under OAM org (`admin:repo_hook` or fine-grained equivalent) | `{ORA_PUBLIC_URL}/v1/scm/github/webhook/{connector_id}` | Per-repo encrypted secret on `watched_repos`; events `pull_request`, `push` |

**GitHub App → Open tenant bind:** start install from **OAM Connectors**. OAM BFF peers to ORA, which mints a signed install `state` (`org`/`proj`/`user`). Organization Open sessions (any org member, viewer+) bind by org; personal Open sessions bind by `user_id` (empty org, `scope=user`) so a personal Open user can install the App on GitHub orgs they admin. Platform admin overview can list all connectors (`all_organizations=1`) but is not the gatekeeper for Connect / claim / edit — mutations follow the same ownership rules as members. Marketplace/orphan installs without valid state stay `pending_claim` (invisible to lists/peers) and redirect once to OAM `/connectors` with a one-time `claim_token`; the signed-in org member or personal user claims via OAM `POST /api/connectors/{id}/claim` `{ "claim_token": "…" }` into their JWT org or personal user scope. Peer resolve fail-closed: active + matching non-empty `org_id` for org connectors; personal user-scoped connectors authorize when the peer service/job JWT carries a matching `user_id` (never invent `default-org`). OSA AppSec peer checks that still require org equality for personal connectors remain a known sibling follow-up. Never map Open tenancy from GitHub `account_login` equality or silent `default-org`.

**Connector scoping (no product pickers):** SCM connectors are **not** chosen in ORA/OSA/OPM dashboards. The family project switcher selects one project or **All projects**; background UI and APIs use each selected project's OAM `connector_ids` (and `external_key` for owner/repo). **All projects** expands to the enabled directory ids (`X-Project-IDs`, cap 32) and unions those connectors. Prefer server-side resolve from the OAM directory when a write needs `connector_id` and the client omitted it; fail closed if the concrete project has no connector. **OAM `/connectors`** remains the only management UI (install, claim, PAT, edit, delete). List proxies (`GET /api/connectors`, `GET /api/github/connectors`) stay for runtime/status — not for a second scoping dropdown. See [security-tenant-scopes.md](security-tenant-scopes.md#github-connector-lists).

**List / status surfaces:** ORA `GET /api/connectors`, OPM/OSA `GET /api/github/connectors` (re-filter active/same-org), OAM `GET /api/connectors` (management directory, enriched via `PEER_ORA_URL`). Do not render pending/foreign rows.

Both routes share the same unified pipeline: verify → tenant resolve → build SCM envelope → parallel fan-out to configured peers → aggregate checker results → publish GitHub statuses.

### Watched-repo checks registry

`watched_repos.checks_json` names **product checkers**, not only legacy ORA strings:

```json
["ora:review", "osa:dependencies", "opl:perf-gate"]
```

Default for new watches (when peers configured): include all **compatible** checkers for that repo profile. ORA fan-out still calls every configured peer; each peer decides `should_run` from the envelope (`changed_paths`, event type, checks filter).

### Peer contract: `POST /api/peer/scm/events`

**Caller:** ORA (`iss=ora-api`, scope `scm:events`, `aud=osa-api|opl-api|opm-api`).

**Request envelope (representative fields):**

```json
{
  "id": "scmenv-…",
  "event_type": "pull_request.opened",
  "organization_id": "acme",
  "project_id": "proj-1",
  "connector_id": "conn-…",
  "repo_full_name": "acme/app",
  "ref": "feature/cve-fix",
  "default_branch": "main",
  "pr_number": 42,
  "commit_sha": "abc123",
  "scm_job_id": "job-…",
  "changed_paths": ["package-lock.json"],
  "checks": ["ora:review", "osa:dependencies"],
  "dispatch": true
}
```

**Response:**

```json
{
  "checkers": [
    {
      "id": "dependencies",
      "check_run_name": "OSA Dependencies",
      "should_run": true,
      "reason": "lockfile changed"
    }
  ]
}
```

Stub peers (OPL, OPM this ship) return `{ "checkers": [] }` until their checker bodies land. ORA publishes Check Run or commit-status fallback per returned checker (`{product}/{checker_id}` context).

### OAM connector directory + management BFF

Connector **metadata** (org, project, kind, `webhook_mode`) lives in OAM `connectors`; ORA keeps encrypted tokens and GitHub protocol. ORA dual-writes on create/update:

```
POST /api/internal/connectors/sync   (service JWT, scope connectors:write, aud=oam-api)
```

**OAM Dashboard** (`/connectors`, smoke `:8097` / NAS `:18097`) is the sole connector **management** UI (install App, PAT, claim, edit, delete, watched-repo registration). Public mutations go to `oam-api`, which peers to `PEER_ORA_URL` for protocol/token work. When `PEER_OAM_URL` is set, ORA refuses browser writes (`credentials_home_oam`) and redirects post-install / claim browsers via `OAM_DASHBOARD_URL` + `/connectors` (not OPA/ORA dashboard ports). Sibling products deep-link “Manage in Account Manager” to OAM and resolve connectors from the **project switcher** (OAM `connector_ids`) — they do **not** ship a second install/claim console or a scoping connector dropdown.

## OPM + Hub + GitHub

OPM projects are **GitHub repositories** only (no local folder registry).

**Two project layers:** OAM directory projects (`oam.projects`) are the family tenancy scope (`X-Project-ID` / list-only `X-Project-IDs`, credentials, bindings, dashboard switchers). They may be created manually or imported from GitHub discovery (`source=manual|github`), and GitHub-backed rows may carry `external_id` / `external_key` plus `connector_ids` (union of ORA connectors that can see the repo). Per-product access is stored as `disabled_products` and managed only on OAM `/projects` — see [Family project switcher](#family-project-switcher-oam-directory). OAM discovers candidates via `PEER_ORA_URL` (`GET /api/projects/discovered` → ORA connector repo lists); import does **not** create or sync an OPM board project. The OPM registry remains a separate GitHub-linked work surface with its own link flow (family switcher ≠ board UUID).

| Concern | Owner |
|---------|-------|
| Organizations / projects / users / RBAC / **login** | **OAM** (`PEER_OAM_URL`) — `POST /api/auth/login`, `iss=oam-api` |
| Connectors (**management UI + public write BFF**), API keys, AI endpoint-backed secrets (`/endpoints`), per-agent model bindings | **OAM** (`PEER_OAM_URL`; mutations need `PEER_ORA_URL` on `oam-api`) |
| Hub observability auth | **OPA-Hub** (`PEER_OPA_URL`) — validates OAM JWTs; proxies login to OAM when `PEER_OAM_URL` is set; org directory reads from OAM |
| GitHub App / PAT *protocol* work (install-url, callback, clone creds, PR/issue writes; peer-only writes when OAM is home) | **ORA** (`PEER_ORA_URL`), using OAM-stored credentials |
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
Endpoint kinds include `cli_qwen_code` (Qwen Code CLI) alongside `cli_cursor`,
`cli_claude_code`, and the HTTP providers — register a Qwen account on **AI
Endpoints** and set an explicit model on **Agents & Models** (`cli_qwen_code`
does not support `auto`).
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
| ORA → OSA/OPL/OPM | SCM checker fan-out (`POST /api/peer/scm/events`, scope `scm:events`) | Optional (per `PEER_*_URL`) |
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
REDIS_URL=                 # per-product dedicated redis-<product> (hub + *-api only)
REDIS_OPA_PASSWORD=        # stack .env — one password per redis-* instance
REDIS_OAM_PASSWORD=
REDIS_ORA_PASSWORD=
REDIS_OSA_PASSWORD=
REDIS_OPL_PASSWORD=
REDIS_OPM_PASSWORD=
OAM_SECRET_KEY=            # oam-api only; must match ORA's OPA_CONNECTOR_SECRET
PEER_OPA_URL=
PEER_OAM_URL=              # account plane; unset = pre-OAM env behaviour
PEER_ORA_URL=              # required on oam-api for connector mutation BFF
PEER_OSA_URL=
PEER_OPL_URL=
PEER_OPM_URL=
OAM_DASHBOARD_URL=         # ora-api post-install / claim redirect base → /connectors
OPA_DASHBOARD_URL=          # fallback redirect; Check Run / job deep-links
OPA_PUBLIC_URL=            # legacy alias; prefer ORA_PUBLIC_URL for ora-api webhooks
ORA_PUBLIC_URL=            # public base for ora-api (GitHub webhooks / review callbacks)
OSA_PUBLIC_URL=
OPL_PUBLIC_URL=
OPM_PUBLIC_URL=
```

On NAS (`open-family`), `ORA_PUBLIC_URL` / `OPA_PUBLIC_URL` currently share the legacy hostname `https://ai-orchestrator.clouded.fr`, which fronts **ora-api**. See [nas-deploy.md](nas-deploy.md).

## All-in-one compose

See [`compose.all.yaml`](../compose.all.yaml): one ClickHouse, databases `opa`/`ora`/`osa`/`opl`/`oam` (OPM uses filesystem only), shared `JWT_SECRET`, OAM-issued tokens when `PEER_OAM_URL` is set (`AUTH_MODE=codeployed`, `iss=oam-api`). Product dashboards use the `/oam-auth/` nginx bridge for browser login (`/hub-auth/` proxies through the hub to OAM). Lab seed user is `admin` / `admin` (`account_type=personal`).
