# Open family — agent workspace map

This file is the **ownership map** for agents working across the Open-* sibling repos (typically under `~/Documents/repos/`). Detailed product/interop docs live in [`docs/products.md`](docs/products.md), [`docs/modules.md`](docs/modules.md), and [`docs/interop.md`](docs/interop.md). Prefer those for ports, auth modes, and contracts; use this file to decide **which repo owns a change**.

**Packaging / compose / NAS:** this repo (`OPA-Stack`).  
**Never deploy `*:smoke` to NAS** — production tags are `*:nas` only. See [`docs/nas-deploy.md`](docs/nas-deploy.md).

---

## Products (what each owns)

| Short | Full name | Repos | Owns (put new features here) | Does **not** own |
|-------|-----------|-------|------------------------------|------------------|
| **OAM** | Open Account Manager | `OAM-API`, `OAM-Dashboard` | Orgs & projects **directory** (+ per-product enablement), users/RBAC, **family login** (`iss=oam-api`), connector **storage + `/connectors` UI**, API keys (family), AI endpoint-backed secrets (`/endpoints`), per-agent model bindings | Product domain UIs (APM, review, AppSec, load, kanban) |
| **OPA** | Open Profiling Agent | `OPA-Hub`, `OPA-Agent`, `OPA-Dashboard`, ingest SDKs (`opa-node`, `opa-python`, `opa-rum-js`, `OPA-PHP-*`, `opa-collector`) | Observability only: edge ingest, hub registry/query, APM, RUM, metrics, alerts/SLOs, synthetics, Trace Explorer | Account plane, connectors CRUD, review, AppSec, load lab, PM boards |
| **ORA** | Open Review Agent | `ORA-API`, `ORA-Dashboard` | Repo Watch, GitHub App/PAT **protocol** (install/callback/clone/push/PR/webhooks), automated code review, review check-runs, coding agents for review; peers OSA for AppSec gates | Connector **management UI**, roadmap/ideation product, load tests, APM, family login issuer |
| **OSA** | Open Security Agent | `OSA-API`, `OSA-Dashboard` | AppSec findings (secrets/SAST/IaC), security runs, vulns/IAST, AppSec CI gates | Review product, PM, load, observability, connector storage |
| **OPL** | Open Perf Lab | `OPL-API`, `OPL-Dashboard` | Load scenarios/runs, HAR/JMX/Postman, Docker JMeter, optional OPA correlation deep-links | AppSec scanners, review, PM boards, account plane |
| **OPM** | Open Project Manager | `OPM-API`, `OPM-Dashboard` | Board registry keyed by OAM project id, kanban, roadmaps, ideation, task specs/plans, task-automation jobs, delivery orchestration (via ORA protocol) | Connector UI, GitHub App protocol, deep review product, AppSec/load/APM, credential storage |

Products are **optional peers**. Call another product over `PEER_*_URL`; do not copy its domain into yours. Empty peer URL → disable feature or `503 peer_unavailable`. **No compatibility shims** for moved APIs (plain 404; update callers in the same change).

---

## Shared modules (cross-cutting only)

Reusable code used by **two or more** products belongs in `Open-*` module repos — never copy-paste between products.

| Repo | Provides |
|------|----------|
| `Open-Auth-Go` | User JWT mint/validate, HTTP gate, standalone handlers, service JWT |
| `Open-Tenant-Go` | `X-Organization-ID` / `X-Project-ID` / `X-Project-IDs` helpers |
| `Open-ClickHouse-Go` | ClickHouse client, dial/config, migrate helpers |
| `Open-Job-Go` / `Open-Job-Env-Go` | Sandboxed job lifecycle, env scrub/denylist |
| `Open-Egress-Proxy` | Allowlisted egress proxy image |
| `Open-HTTP-Go` / `Open-Logger-Go` / `Open-Crypto-Go` / `Open-Cache-Go` | HTTP helpers, logging, `enc:v2`, cache |
| `Open-Client-Go` / `Open-Client-JS` | Typed peer/product HTTP clients |
| `Open-UI-JS` | Dashboard shell (layout, session, project switcher) |

Domain APIs and ingest SDKs stay product-scoped (not modules).

---

## Peer vs own (decision rules)

| Need | Correct pattern |
|------|-----------------|
| List/manage connectors | **OAM** UI + storage only (`/connectors`). Products may **proxy list** for runtime; **no dashboard connector pickers** for scoping work |
| Scope SCM work (watch/scan/link) | **Family project switcher** — OAM directory `connector_ids` (+ `external_key`). **All projects** → aggregate across enabled projects' connectors (`X-Project-IDs`) |
| Sign in (family / NAS) | **OAM** issues JWT; dashboards use `/oam-auth/`; product `/api/auth/login` → **503** when co-deployed |
| Clone / push / open PR | **ORA** peer (`scm:pr` / clone helpers); OPM/others apply domain logic only |
| AppSec scan on a PR | **OSA** runs scanners; ORA may fan-out SCM events / evaluate gates via peer |
| Load test | **OPL** only |
| Kanban / roadmap / ideation | **OPM** only (ORA may keep GitHub Issues/milestones **protocol** for OPM) |
| Traces / metrics / alerts | **OPA** hub (+ edge ingest); dashboard talks to **hub**, not edge, in production |
| AI model + API key for a job | Resolve/lease from **OAM**; do not store keys in product env as the steady state |
| Shared job sandbox / egress | Prefer **Open-Job-*** / **Open-Egress-Proxy**; thin product wiring only |

---

## Smoke / NAS ports (quick)

| Service | Laptop smoke | Notes |
|---------|--------------|-------|
| OPA hub / dashboard | `8080` / `8088` | NAS hub often `18080` |
| ORA / OSA / OPL / OPM APIs | `8091` / `8093` / `8092` / `8096` | |
| ORA / OSA / OPL / OPM dashboards | `8089` / `8094` / `8095` / `8098` | |
| OAM API / dashboard | `8090` / `8097` | NAS API often `18090` |

Full NAS layout: [`docs/nas-deploy.md`](docs/nas-deploy.md).

---

## Ownership audit — features in the wrong product

Refreshed **2026-08-07** (post connector-picker removal + prior migrations). Prefer migrate/delete over new work on misplaced surfaces.

### Fixed since prior audit

| Was in | Feature | Resolution |
|--------|---------|------------|
| **OPA-Dashboard** | Users & roles / API keys pages | Removed; Account deep-links to OAM |
| **OPA-Dashboard** | Vite `/api` → edge agent | Default proxy → **hub** |
| **OPA-Agent** | Identity CRUD as family SoT | **503** when `PEER_OAM_URL` / `OPA_HUB_URL` set |
| **ORA** | Roadmap product (generate/publish/runs + nav) | Removed; OPM owns roadmap/ideation |
| **ORA-Dashboard** | AI provider credential management UI | Deep-link to OAM **`/endpoints`** (not `/credentials`) |
| **ORA** | AppSec scanner leftovers / local `job_env` | Cleaned; `Open-Job-Env-Go` wrapper |
| **OPM-API** | In-product `run-review` / `run-qa-fix` | Retired; deep review stays on ORA |
| **OPM-API** | Legacy `OPM_MODEL*` / `CURSOR_API_KEY` credential plane | Removed as steady-state; OAM lease/resolve only under auth |
| **OPM-API** | `POST /api/projects` inventing a new UUID | **EnsureProject** keyed by OAM directory id |
| **OPM** | Org discovery via Hub as primary | **`/api/oam/organizations`** |
| **OPL-API** | Leftover `gitleaks.toml` | Deleted |
| **ORA / OSA / OPM dashboards** | Connector **pickers** for scoping Watch/Runs/Projects | **Removed** — project switcher + OAM `connector_ids` (All projects aggregates) |

### Still open — high

| Found in | Feature | Should live in | Notes |
|----------|---------|----------------|-------|
| **OAM-API** | `api_keys` schema without full management API/UI | **OAM** (complete it) | Gap historically pushed UI onto OPA |

### Still open — medium

| Found in | Feature | Should live in | Notes |
|----------|---------|----------------|-------|
| **ORA-API, OPM-API** | Duplicated egress-proxy spawn/allowlist orchestration | **Open-Egress-Proxy** (+ thin wiring) | |
| **ORA/OSA/OPL** | Tenant validation still reading legacy `opa.organizations` / `opa.projects` when OAM unset | **OAM** directory | Short-circuit when `PEER_OAM_URL` set (done); standalone path remains |
| **ORA-Dashboard** | Security scanner prefs in Watch Agents UI | **OSA** policy UX | ORA may keep gate wiring only |
| Stale docs/strings | Occasional “Hub issues tokens” / `iss=opa-hub` | **OAM** (`iss=oam-api`) | Code mostly proxies correctly |

### Still open — low / noise

| Found in | Feature | Action |
|----------|---------|--------|
| **ORA/OSA/OPL** | Copied `clickhouse.go` (incl. unused RUM helpers) | Prefer Open-ClickHouse-Go |
| **ORA** | Direct CH reads of OSA finding tables for review ledger | Prefer OSA peer API over long term |
| **OPM** | Roadmap competitor agent historically lifted from ORA | Keep as OPM roadmap input; drop ORA-era framing |

### Intentional peer patterns (not violations)

- **OAM `/connectors`** is the only connector **management** console; product dashboards may deep-link “Manage in Account Manager”
- Background jobs/APIs resolve SCM via OAM project `connector_ids` / `external_key` (and peer ORA protocol) — **not** via a second UI picker
- OAM connector BFF → ORA for GitHub protocol
- ORA → OSA for security scans / gate evaluation
- Hub `/api/auth/login` → OAM when `PEER_OAM_URL` set; peer product login → 503
- OPM clone/push/PR/issue sync via ORA `scm:*`
- OAM project list proxies (`GET /api/oam/projects`) on product APIs
- OPL optional deep-link into OPA Trace Explorer

---

## Agent working rules

1. **Pick the owner repo first** using the tables above. If a change spans products, prefer peer API + thin proxy over duplicating domain logic.
2. **Do not add** new Users/API-keys/Connectors/AI-Endpoints/Roadmap product surfaces outside their owner — deep-link or proxy instead. **Do not reintroduce connector pickers** on product dashboards for scoping work.
3. **Extract shared infra** into `Open-*` modules when a second product needs the same code.
4. **Update callers in the same PR** when moving an API; no redirect shims.
5. **NAS:** rebuild/recreate matching `*:nas` images after product-facing UI/API fixes meant to be verified on `192.168.100.101` (see workspace deploy rule).
6. **Naming:** describe capabilities in plain language in PRs/commits; do not name work after internal phases or filename-style buckets.
7. **Never keep legacy:** when a replacement owns a domain, remove the old UI/path in the same change — do not leave parallel consoles or break-glass pages. **OAM:** AI provider secrets are managed only under **AI Endpoints** (`/endpoints`); do not reintroduce `/credentials`.

---

## Related docs

- [`docs/products.md`](docs/products.md) — product catalog & ports
- [`docs/modules.md`](docs/modules.md) — shared modules
- [`docs/interop.md`](docs/interop.md) — auth, peers, SCM checker platform, tenancy
- [`docs/security-tenant-scopes.md`](docs/security-tenant-scopes.md) — curl matrix
- [`docs/nas-deploy.md`](docs/nas-deploy.md) — production compose
- [`docs/opl-opm-backlog.md`](docs/opl-opm-backlog.md) · [`docs/opm-pm-capabilities.md`](docs/opm-pm-capabilities.md) · [`docs/opl-lab-capabilities.md`](docs/opl-lab-capabilities.md)
