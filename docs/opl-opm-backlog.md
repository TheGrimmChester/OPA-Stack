# OPL + OPM remaining backlog

Concise product backlog for **Open Perf Lab** and **Open Project Manager** after the family split.
Ports: API **8092** / **8096**, dashboards **8095** / **8098**. Co-deployed **`/hub-auth/`** (`issuer=opa-hub`);
product `/api/auth/login` is disabled. Auth-on list routes scope to **`default-org` / `default-project`** when
tenant headers are omitted (Open-Tenant-Go ≥ 0.2.2). See [interop.md](interop.md) and
[nas-deploy.md](nas-deploy.md).

**Status basis (re-verified 2026-08-04, late pass).** Every **Done** bullet below was checked against
`origin/main` (OPL-API `3cff6ee`, OPL-Dashboard `cd91121`, OPM-API `5c9dd43`, OPM-Dashboard `4d5e8a2`,
ORA-API `325df77`) by reading the cited file and line. Three caveats:

- **Deployment verification is unavailable this pass.** Health and index routes answer, but the images report
  unversioned build ids (`opm-api-dev`, `perf-lab-dev`) and capability routes need an operator token this pass
  does not hold. Nothing here is claimed as verified on the deployed stack — several capabilities below are
  merged in code and **not yet deployed**.
- **Judge `origin/main`, not the checkout.** These repos are frequently checked out on a feature branch based on
  an older `main`, so behaviour reproduced locally is not evidence of a merge, and an absent symbol in the
  working tree is not evidence of an absent feature.
- **Search output here is unreliable.** A command hook rewrites `git diff`, `grep`, and `rg` output, so an empty
  result can be a tool artifact. Negatives below were taken with `rtk proxy` and a positive control that fired
  in the same command, or by reading the whole file from the `origin/main` blob.

**Correction (2026-08-04).** An earlier revision of this file listed skip-to-phase, the roadmap/ideation
generators, GitHub Issue sync, notification channels, report/trend templates, and CSV dataset binding as absent
or branch-only. All six have since merged to `origin/main` and are recorded as **Done** below. The wording was
correct for the `main` of a few hours earlier and became wrong as those PRs landed during the review; it is
corrected here rather than deleted.

Near-term product PRs may close individual **Next** items; treat **Later** as the durable backlog.

---

## OPL — Open Perf Lab

Ports: API `8092`, dashboard `8095`. UI: `opl-dashboard`.

**Control plane is `opl-api` alone.** `opl-orchestrator` is a health endpoint, not a scheduler:
`OPL-API/opl_orchestrator.go` registers only `/api/health` (`:14`) and has no dispatch, queue, or reaper logic —
run dispatch and the schedule tick both live in `opl-api` (`main.go:30` → `lab_extras.go:283`;
`jmeter_engine.go` starts the containers). Treat the service name as aspirational.

### Done

- Product split: scenarios, runs, HAR/XHR/JMX import, Docker JMeter engine, k6 export
- Co-deployed hub login via dashboard `/hub-auth/`; standalone login disabled on the API
- ClickHouse DB `opl` with tenant-scoped `load_*` lists (headers or write-tenant defaults)
- Dashboard Perf Lab studio: Design, Users & data, Capture, JMX, Run & scale, Results, Compare, SLA tabs
- Run lifecycle: undispatched → `created`, failed dispatch → `failed`, `POST .../runs/{id}/cancel`; gate JSON includes `pass`
- Results KPIs prefer `summary_json` (JMeter aggregates); sample table uses `step_name`
- OPA Trace Explorer deep-links default to same-host `:8088` (`?load_run_id=`)
- **Lab ops API** — `GET /api/perf/load-policies`; soft-archive / duplicate / validate (`jmeter.go:48-67`); `GET .../runs/{id}/steps|report|runners` (`load.go:470-485`); `POST .../import-jtl` (`jmeter.go:23`). Routes exist in source; the previous "→ 200 on NAS with Hub JWT" result is withdrawn as unverifiable this pass
- **JMeter visual test case editor** — VU tree (HTTP / Txn / If / While / Loop / ForEach / Fragment+Link) + DnD reorder/nest; JMX round-trip for controllers; archive/duplicate/validate/runners/steps/report in Dashboard
- **Custom load curve + scheduler UX** — point-curve editor → `schedule.curve` / load-policies custom; Run & scale schedule panel (`enabled` / `every_minutes` / `daily_at`); scenario multi-run history (≤25) + sparklines
- **Arrivals-accurate load curve** — `curve_mode=arrivals` rate points → open-model ThreadGroup segments (one journey per arrival); honesty vs concurrent VU mode
- **Postman import** — `POST /api/perf/scenarios/import-postman` + Capture UI
- **Validate triage + auto-correlation** — `triage[]` + `correlation_suggestions[]`; Apply extract in Design
- **Restore archived + JTL import UI** — `POST .../unarchive`, list `?archived=1`; Results JTL upload
- **PDF / HTML report + bench pack ZIP** — `report?format=html|pdf`, `GET .../bench-pack`
- **Trends tab widgets** — latency band, error bars, best/worst/SLA KPIs; `GET .../scenarios/{id}/trends`
- **Terminal-run notifications** — webhook on terminal status (`OPL_RUN_WEBHOOK_URL`); health `run_notify`; optional HMAC + status filter
- **Notification channels** — one terminal-run event delivered to webhook + chat incoming-webhook (`OPL_RUN_CHAT_WEBHOOK_URL`) + SMTP email (`OPL_RUN_EMAIL_TO` + shared `OPA_SMTP_*`); `OPL_RUN_NOTIFY_CHANNELS` restricts the set; health `run_notify.channels[]` reports each channel with a redacted target
- **Notification history** — `opl.run_notifications` + `GET /api/perf/notifications` (and per run); `sent` / `failed` / `logged` / `skipped` with a plain reason; `POST /api/perf/notifications/test`; Notification channels + history panels in the dashboard
- **Report / trend templates** — `opl.report_templates` + `/api/perf/report-templates` CRUD (org/project scoped); `?template=<id>` on `report`, `bench-pack` and `trends`; picker + editor on Results and Trends

- **CSV dataset binding** — the generated plan now carries a CSV Data Set element matching the written
  `data.csv`, so `${var}` resolves at run time (`jmeter_datasets.go:47`, `:66`, `:317`; `syncJMXCSVDataSet` at
  `:378` back-fills stored and imported plans; generators take the dataset at `jmeter_engine.go:32`, `:71`,
  `:110`; dispatch wires it at `:547`, `:559`, `:589`). Honours `variableNames`, `delimiter`, `recycle`,
  `stop_thread`, `share_mode`, `quoted`, `ignore_first_line`, `encoding`; parse problems come back as
  `warnings` (`jmeter_datasets.go:94-166`, surfaced `:298`) and dispatch reports `dataset_injected`
  (`jmeter_engine.go:718`)

### Next

- **Redeploy `opl-api:nas` + `opl-dashboard:nas`** after each OPL pass (sync-nas-src before rebuild)
- **Baselines / federation peers** — dashboard skips `/api/performance/baselines` and `/api/federation/peers` (edge agent today; `opl-api` 404). Proxy/peer cleanly or drop dead UI affordances
- **Visual editor depth** — multi-select, search/replace across tree, disable nodes
- Issue-tracker notification adapters over the same terminal-run event; multi-scenario trend dashboards; branded PDF theming


### Later

- Full visual editor fidelity (processors beyond extract/assert; module-reference path)
- Multi-peer fan-out beyond local samples (not a multi-region load grid)
- Kubernetes (or non-container) runner backends (`PerfContainerRunner` extension point)
- Distributed campaign scheduler (beyond in-process tick) and multi-scenario campaigns
- Optional `opl-gateway` peel; keep host-JMeter fallbacks lab-only

---

## OPM — Open Project Manager

Ports: API `8096`, dashboard `8098`. UI: `opm-dashboard` (web only).

**Control plane is `opm-api` alone.** `opm-orchestrator` serves `/api/health` and `/api/spawn-probe` and
describes itself as a "job scheduler stub" in its own startup log (`OPM-API/main.go:114`). It schedules
nothing; `opm-api` spawns runner containers in-process (`job_runner.go:60-91`). Treat the service name as
aspirational.

**Code delivery is shipped in OPM-API.** Implementation records a change set; `POST …/tasks/{specId}/deliver`
(and auto-deliver after review PASS) applies it, commits on `opm/<specId>`, pushes via ORA `scm:pr`, and opens
a PR. Builtin-only runs still produce no source changes. Models/keys resolve from **OAM** when `PEER_OAM_URL`
is set; `OPM_MODEL_*` is legacy rollback only.

### Done

- GitHub-linked projects only (no local folder registry); hub orgs + ORA connector list / repos; credentials stored in OAM
- Co-deployed `/hub-auth/`; `PEER_OPA_URL` / `PEER_ORA_URL` / `PEER_OAM_URL`; `git` in `opm-api:nas` for ephemeral clones
- Board + tasks CRUD/move/**DnD** + task action menu; require-review + approve-for-coding; task detail (plan/progress/spec/logs)
- Roadmap / ideation manual create + inline edit/delete; changelog generate + save
- Job executor writes artifacts for planning / implementation / review / QA / changelog; **container spawn** of `opm-runner-task` when `spawnReady`
- Per-job model + API key from OAM (`creds:resolve`) when `PEER_OAM_URL` set; legacy `OPM_MODEL_API_KEY` when unset
- Stuck/recover; pause/resume; **skip-to-phase**
- Repo-aware / model-backed roadmap discovery/features and ideation (builtin template fallback when no model)
- Jobs list + enqueue + cancel; filesystem project state under `OPM_DATA_DIR`
- Orchestrator spawn probe (`/api/spawn-probe`)
- **GitHub Milestones + Projects v2 bind** — ORA peer `scm:pm`
- **Task ↔ GitHub Issue two-way sync** — ORA peer `scm:pm`
- **Code delivery** — apply change set, branch, push, open/merge PR via ORA `scm:pr`; auto-deliver after review PASS

### Not implemented

- **Orchestrator dispatch + container reaping** — stub only (`main.go:114`); `opm-api` owns spawn
- **PR state tracking** — `prState` is a snapshot at open time; no webhook/poll
- **ORA review deep-link** — task `run-review` is an OPM agent phase, not Repo Watch
- **Live-stack delivery verification** — covered by stub-ORA tests; exercise against a real GitHub App on NAS still outstanding

### Next

- Live-stack verify delivery + OAM resolve on NAS after `*:nas` rebuild
- Poll or webhook PR state via ORA
- Deep-link to ORA for Repo Watch / check-runs (do not duplicate inside OPM)
- **Deploy**: rebuild/redeploy when stack images lag `main`

### Later

- Issue sync follow-ups: candidate-issue picker; issue comments ↔ task discussion; webhook-driven refresh; multi-assignee mirroring
- Multi-repo portfolio views
- Durable job/history store (ClickHouse or equivalent) instead of filesystem-only
- Insights / context / live terminals; pre-merge quality gates (OSA/OPL)

---

## Related

- [Products](products.md) — port table and ownership
- [Interop](interop.md) — hub-auth, tenant headers, OPM ↔ hub/OAM/ORA
- [NAS deploy](nas-deploy.md) — `*:nas` images and verify curls
- [OPL load lab capabilities](opl-lab-capabilities.md) — Done / On a branch, not merged / Missing / Different-by-design + flagship visual editor gap
- [OPM project manager capabilities](opm-pm-capabilities.md) — Done / On a branch, not merged / Not implemented / Different-by-design inventory + top gaps
- Product docs: [OPL-API](https://github.com/TheGrimmChester/OPL-API/tree/main/docs), [OPL-Dashboard](https://github.com/TheGrimmChester/OPL-Dashboard/tree/main/docs), [OPM-API](https://github.com/TheGrimmChester/OPM-API/tree/main/docs), [OPM-Dashboard](https://github.com/TheGrimmChester/OPM-Dashboard/tree/main/docs)
