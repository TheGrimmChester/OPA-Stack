# OPL + OPM remaining backlog

Concise product backlog for **Open Perf Lab** and **Open Project Manager** after the family split. Verified against NAS `open-family` (2026-08-04): API ports **8092** / **8096**, dashboards **8095** / **8098**, co-deployed **`/hub-auth/`** (`issuer=opa-hub`), product `/api/auth/login` → **503**, tenant CORS allows `Authorization`, `X-Organization-ID`, `X-Project-ID`. Auth-on list routes scope to **`default-org` / `default-project`** when those headers are omitted (Open-Tenant-Go ≥ 0.2.2). See [interop.md](interop.md) and [nas-deploy.md](nas-deploy.md).

Near-term product PRs may close individual **Next** items; treat **Later** as the durable backlog.

---

## OPL — Open Perf Lab

Ports: API `8092`, dashboard `8095`. Control plane: `opl-api` + `opl-orchestrator`; UI: `opl-dashboard`.

### Done

- Product split: scenarios, runs, HAR/XHR/JMX import, Docker JMeter engine, k6 export
- Co-deployed hub login via dashboard `/hub-auth/`; standalone login disabled on the API
- ClickHouse DB `opl` with tenant-scoped `load_*` lists (headers or write-tenant defaults)
- Dashboard Perf Lab studio: Design, Users & data, Capture, JMX, Run & scale, Results, Compare, SLA tabs
- NAS health + seeded scenarios/runs under `default-org` / `default-project`
- Run lifecycle: undispatched → `created`, failed dispatch → `failed`, `POST .../runs/{id}/cancel`; gate JSON includes `pass`
- Results KPIs prefer `summary_json` (JMeter aggregates); sample table uses `step_name`
- OPA Trace Explorer deep-links default to same-host `:8088` (`?load_run_id=`)

### Next

- **Baselines / federation peers** — dashboard skips `/api/performance/baselines` and `/api/federation/peers` (edge agent today; `opl-api` 404). Proxy/peer cleanly or drop dead UI affordances
- **Scenario delete/archive** — API+UI still upsert-only
- **Runner live status** — container inspect / orchestrator visibility beyond run status + samples
- **Instrumented target honesty** — document when apps are not OPA-instrumented (example.com never yields traces)

### Later

- **JMeter Visual test case editor** — OctoPerf’s flagship design gap; see [opl-octoperf-parity.md](opl-octoperf-parity.md) (aspirational visual editing with JMeter semantics; form+import today is not enough)
- Multi-peer fan-out beyond local samples (not a commercial multi-region load grid)
- Kubernetes (or non-Docker) runner backends (`PerfContainerRunner` extension point)
- Scheduled / CI-triggered suites and multi-scenario campaigns
- Optional `opl-gateway` peel; keep Node/host JMeter fallbacks lab-only

---

## OPM — Open Project Manager

Ports: API `8096`, dashboard `8098`. Control plane: `opm-api` + `opm-orchestrator`; UI: `opm-dashboard` (web only).

### Done

- GitHub-linked projects only (no local folder registry); hub orgs + ORA connectors/repos
- Co-deployed `/hub-auth/`; `PEER_OPA_URL` / `PEER_ORA_URL`; `git` in `opm-api:nas` for ephemeral clones
- Board + tasks CRUD/move; roadmap / ideation / changelog read APIs; jobs list + enqueue
- `run-planning` can complete on NAS after clone-credentials + runtime git fixes
- Filesystem project state under `OPM_DATA_DIR` (board/tasks/jobs)

### Next

- **Edit surfaces** — roadmap / ideation / changelog are API `PUT`-capable but the dashboard is largely read-only; ship save flows operators actually use
- **Task depth** — plan / progress / detail views (`/tasks/{specId}/plan`, `/progress`); bind job enqueue to a `specId`
- **Job operations UX** — cancel (`POST .../jobs/{runId}/cancel`), live status, and actionable failure text (clone, egress, runner)
- **Non-planning actions** — `run-implementation`, `run-review`, `run-qa-fix`, roadmap/ideation/changelog generators still stub-lean; harden beyond `run-planning`

### Later

- GitHub Issues / Projects sync (two-way), multi-repo portfolio views
- Durable job/history store (ClickHouse or equivalent) instead of filesystem-only
- Deep-link to ORA for review — do not duplicate Repo Watch inside OPM
- Richer model-provider / runner orchestration (real container spawn maturity vs scheduler stub)

---

## Related

- [Products](products.md) — port table and ownership
- [Interop](interop.md) — hub-auth, tenant headers, OPM ↔ hub/ORA
- [NAS deploy](nas-deploy.md) — `*:nas` images and verify curls
- [OctoPerf → OPL parity](opl-octoperf-parity.md) — Done / Code-ready / Missing / Different-by-design + flagship JMeter Visual editor gap
- [OPM ↔ AutoCursor parity](opm-autocursor-parity.md) — Done / Missing / Different-by-design inventory + top gaps
- Product docs: [OPL-API](https://github.com/TheGrimmChester/OPL-API/tree/main/docs), [OPL-Dashboard](https://github.com/TheGrimmChester/OPL-Dashboard/tree/main/docs), [OPM-API](https://github.com/TheGrimmChester/OPM-API/tree/main/docs), [OPM-Dashboard](https://github.com/TheGrimmChester/OPM-Dashboard/tree/main/docs)
