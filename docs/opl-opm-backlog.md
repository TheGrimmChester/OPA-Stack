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
- **Lab ops API on NAS `opl-api:nas`** (Hub JWT): `GET /api/perf/load-policies` → **200** (not 404); soft-archive / duplicate / validate; `GET .../runs/{id}/steps|report|runners`; `POST .../import-jtl`
- **JMeter visual test case editor** — VU tree (HTTP / Txn / If / While / Loop / ForEach / Fragment+Link) + DnD reorder/nest; JMX round-trip for controllers; archive/duplicate/validate/runners/steps/report in Dashboard
- **Custom load curve + scheduler UX** — point-curve editor → `schedule.curve` / load-policies custom; Run & scale schedule panel (`enabled` / `every_minutes` / `daily_at`); scenario multi-run history (≤25) + sparklines
- **Postman import** — `POST /api/perf/scenarios/import-postman` + Capture UI
- **Validate triage + auto-correlation** — `triage[]` + `correlation_suggestions[]`; Apply extract in Design
- **Restore archived + JTL import UI** — `POST .../unarchive`, list `?archived=1`; Results JTL upload
- **Terminal-run notifications** — webhook on terminal status (`OPL_RUN_WEBHOOK_URL`); health `run_notify`; optional HMAC + status filter

### Next

- **Redeploy `opl-api:nas` + `opl-dashboard:nas`** — ship ForEach/fragments/Postman/triage/restore/notify from this pass (sync-nas-src before rebuild)
- **Baselines / federation peers** — dashboard skips `/api/performance/baselines` and `/api/federation/peers` (edge agent today; `opl-api` 404). Proxy/peer cleanly or drop dead UI affordances
- Arrivals-accurate curve / PDF bench pack / full trend widgets (see [opl-lab-capabilities.md](opl-lab-capabilities.md))
- **Visual editor depth** — multi-select, search/replace across tree, disable nodes
- **Trend chart builder** — multi-run history table exists; spark/trend charts still open

### Later

- Full visual editor fidelity (fragments, processors beyond extract/assert, arrivals-accurate injectors)
- Multi-peer fan-out beyond local samples (not a commercial multi-region load grid)
- Kubernetes (or non-Docker) runner backends (`PerfContainerRunner` extension point)
- Distributed campaign scheduler (beyond in-process tick) and multi-scenario campaigns
- Optional `opl-gateway` peel; keep Node/host JMeter fallbacks lab-only

---

## OPM — Open Project Manager

Ports: API `8096`, dashboard `8098`. Control plane: `opm-api` + `opm-orchestrator`; UI: `opm-dashboard` (web only).

### Done

- GitHub-linked projects only (no local folder registry); hub orgs + ORA connectors/repos
- Co-deployed `/hub-auth/`; `PEER_OPA_URL` / `PEER_ORA_URL`; `git` in `opm-api:nas` for ephemeral clones
- Board + tasks CRUD/move/**DnD** + task action menu; require-review + approve-for-coding; task detail (plan/progress/spec/logs)
- Roadmap / ideation create + inline edit/delete; changelog generate + save
- Builtin job executor writes real artifacts for planning / implementation / review / QA / changelog; **container spawn** of `opm-runner-task:nas` when `spawnReady` (`execution: "container"`, builtin fallback)
- Stuck/recover (`mark-stuck`, `recover-subtask`); pause/resume (`pause-task`, `resume-task`); **skip-to-phase** (`targetPhase`)
- Roadmap/ideation agents (`run-roadmap-discovery`, `run-roadmap-features`, `run-ideation`) write real artifacts (builtin helpers)
- Jobs list + enqueue + cancel with operator `message`; filesystem project state under `OPM_DATA_DIR`
- Orchestrator spawn probe (`/api/spawn-probe`) — `spawnReady: true` when docker CLI + daemon + runner image work
- NAS verify: `GET :8096/api/health` → **200** `{ status: ok, service: opm-api, auth_mode: codeployed }`; `:8098/` → **200**

### Next

- ~~**Model-backed agents in runner**~~ — shipped: OpenAI-compatible `OPM_MODEL_*` in runner; fallback + builtin when key missing

### Later

- GitHub Issues / Projects sync (two-way), multi-repo portfolio views
- Durable job/history store (ClickHouse or equivalent) instead of filesystem-only
- Deep-link to ORA for review — do not duplicate Repo Watch inside OPM
- Insights / context / live terminals; pre-merge quality gates

---

## Related

- [Products](products.md) — port table and ownership
- [Interop](interop.md) — hub-auth, tenant headers, OPM ↔ hub/ORA
- [NAS deploy](nas-deploy.md) — `*:nas` images and verify curls
- [OPL load lab capabilities](opl-lab-capabilities.md) — Done / Code-ready / Missing / Different-by-design + flagship JMeter Visual editor gap
- [OPM project manager capabilities](opm-pm-capabilities.md) — Done / Missing / Different-by-design inventory + top gaps
- Product docs: [OPL-API](https://github.com/TheGrimmChester/OPL-API/tree/main/docs), [OPL-Dashboard](https://github.com/TheGrimmChester/OPL-Dashboard/tree/main/docs), [OPM-API](https://github.com/TheGrimmChester/OPM-API/tree/main/docs), [OPM-Dashboard](https://github.com/TheGrimmChester/OPM-Dashboard/tree/main/docs)
