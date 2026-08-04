# OPL + OPM remaining backlog

Concise product backlog for **Open Perf Lab** and **Open Project Manager** after the family split.
Ports: API **8092** / **8096**, dashboards **8095** / **8098**. Co-deployed **`/hub-auth/`** (`issuer=opa-hub`);
product `/api/auth/login` is disabled. Auth-on list routes scope to **`default-org` / `default-project`** when
tenant headers are omitted (Open-Tenant-Go ≥ 0.2.2). See [interop.md](interop.md) and
[nas-deploy.md](nas-deploy.md).

**Status basis (2026-08-04).** Every **Done** bullet below was re-checked against `origin/main`
(OPL-API `51b4e87`, OPL-Dashboard `487e2da`, OPM-API `8cd0562`, OPM-Dashboard `6d43452`, ORA-API `5a706fb`) by
reading the cited file and line. Two caveats that changed several bullets in this revision:

- **Deployment verification is unavailable this pass.** Health and index routes answer, but the images report
  unversioned build ids (`opm-api-dev`, `perf-lab-dev`) and capability routes need an operator token this pass
  does not hold. Nothing here is claimed as verified on the deployed stack.
- **Local checkouts sit on unmerged branches.** Several of these repos are commonly checked out on a feature
  branch, so behaviour reproduced locally is not evidence of a merge. Work that exists only on a branch is
  listed under **On a branch, not merged**, never under **Done**.

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
- **Collection import** — `POST /api/perf/scenarios/import-postman` + Capture UI (`postman.go:15`)
- **Validate triage + auto-correlation** — `triage[]` + `correlation_suggestions[]`; Apply extract in Design (`jmeter.go:48`)
- **Restore archived + JTL import UI** — `POST .../unarchive` (`jmeter.go:63`), list `?archived=1`; Results JTL upload
- **PDF / HTML report + bench pack ZIP** — `report?format=html|pdf` (`lab_extras.go:1022-1033`), `GET .../bench-pack` (`load.go:478` → `report_export.go:330`)
- **Trends tab widgets** — latency band, error bars, best/worst/SLA KPIs; `GET .../scenarios/{id}/trends` (`jmeter.go:69` → `report_export.go:382`)
- **Terminal-run notifications** — webhook on terminal status (`OPL_RUN_WEBHOOK_URL`, `run_notify.go`); health `run_notify`; optional HMAC + status filter

### On a branch, not merged

- **Richer notify channels + notification history** — `feature/notify-channels-report-templates`
  (`OPL-API/run_notify.go`, `run_notify_history.go`; `OPL-Dashboard/src/components/NotifyChannels.jsx`).
  `origin/main` has webhook only
- **Saved report / trend templates** — same branch (`OPL-API/report_templates.go`;
  `OPL-Dashboard/src/components/ReportTemplateBar.jsx`). `origin/main` has fixed layouts only

### Not implemented

- **Dataset binding to the executed plan** — inline CSV is stored and written to `data.csv` beside the plan
  (`jmeter_engine.go:554-563`, `:586`), but no generator emits a CSV Data Set element (`CSVDataSet` occurs only
  in the import parser, `jmeter.go:110`), so generated plans run with `${var}` unbound and nothing warns.
  `variableNames` / `delimiter` / `recycle` are stored but never applied. Highest-impact OPL gap

### Next

- **Dataset binding + unbound-variable warning on dispatch** (see Not implemented)
- **Merge `feature/notify-channels-report-templates`** in both OPL repos
- **Baselines / federation peers** — dashboard skips `/api/performance/baselines` and `/api/federation/peers` (edge agent today; `opl-api` has no such route). Proxy/peer cleanly or drop dead UI affordances
- **Visual editor depth** — multi-select, search/replace across tree, disable nodes
- **Redeploy `opl-api:nas` + `opl-dashboard:nas`** once the above land (sync-nas-src before rebuild)

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

**OPM does not deliver code.** A job clones the repo and discards the clone unused (`job_runner.go:45-50`,
`_ = workDir`); the only git calls in the service are two `git clone` invocations (`workspace.go:57`, `:69`).
There is no `git add` / `commit` / `push`, no branch creation, and no pull-request call. "Implementation" flips
the next plan subtask to `completed` (`job_runner.go:321-341`) and may append to `IMPLEMENTATION_NOTES.md`
(`model_apply.go:111-135`). Read every OPM bullet below with that in mind.

### Done

- GitHub-linked projects only (no local folder registry); hub orgs + ORA connectors/repos (`store.go:134`, `github_handlers.go:16`)
- Co-deployed `/hub-auth/`; `PEER_OPA_URL` / `PEER_ORA_URL`; `git` in `opm-api:nas` for ephemeral clones
- Board + tasks CRUD/move/**DnD** + task action menu; require-review + approve-for-coding; task detail (plan/progress/spec/logs) — `handlers.go:113-136`, `:241-317`; DnD at `Board.jsx:415-448`
- Roadmap / ideation manual create + inline edit/delete; changelog generate + save (`handlers.go:117-121`)
- Job executor writes artifacts for planning / implementation / review / QA / changelog (`job_runner.go:128-152`); **container spawn** of `opm-runner-task` when `spawnReady` (`execution: "container"`, builtin fallback)
- Runner calls a chat-completions endpoint when `OPM_MODEL_API_KEY` is set (`cmd/opm-runner/main.go:69-100`); applied for planning, implementation, and review **only** (`model_apply.go:17-29`)
- Stuck/recover (`mark-stuck`, `recover-subtask`); pause/resume (`pause-task`, `resume-task`) — `job_runner.go:137-144`
- Jobs list + enqueue + cancel with operator `message`; filesystem project state under `OPM_DATA_DIR`
- Orchestrator spawn probe (`/api/spawn-probe`, `main.go:111`) — reports `spawnReady` from `docker info` / `docker image inspect` (`orchestrator_probe.go:47-55`)
- **GitHub Milestones bind + sync** — ORA peer `scm:pm`; list/assign (`github_pm.go:31`, `:46`); dashboard pickers on Roadmap + task detail
- **GitHub Projects v2 bind + draft item create + Status on move** (best-effort) — `github_pm.go:151-189`; ORA side `github_projects.go:274-292`

### On a branch, not merged

- **Roadmap/ideation generators and skip-to-phase** — `feature/agent-roadmap-ideation-skip` in OPM-API and
  OPM-Dashboard (open PR #18, never merged into `main`)
- **GitHub Issues two-way sync** — `feature/github-issue-sync` in OPM-API (`github_issue_sync.go`),
  OPM-Dashboard (`GitHubIssuePanel.jsx`), and ORA-API (`peer_scm_issues.go`)

### Not implemented

- **Roadmap / ideation generation** — entries can be created and edited manually; the three generation actions
  record an acknowledgement only. `job_runner.go:147-148` routes `run-roadmap-discovery`,
  `run-roadmap-features`, and `run-ideation` to `builtinMetaNote`, which appends one log line and returns
  `"builtin placeholder — agent prompts not wired yet"` (`job_runner.go:688-691`). The model path does not
  cover them either (`model_apply.go:27-29`), so a model key changes nothing here
- **Skip-to-phase** — `skipToPhase` / `skip-to-phase` / `targetPhase` match no source file on `origin/main` in
  either OPM repo; the only hits are `OPM-API/docs/backlog.md:26` and `OPM-Dashboard/docs/backlog.md:17`
- **Code delivery / pull requests from a task** — see the note above this list
- **Orchestrator dispatch + container reaping** — stub only (`main.go:114`)
- **Projects v2 draft-item title refresh** — `ORA-API/github_projects.go:294-302` returns `nil` without calling
  the API and its error is discarded at `ORA-API/peer_scm_pm.go:268`, so renaming a task never reaches the
  board and never reports a failure

### Next

- Merge PR #18 (`feature/agent-roadmap-ideation-skip`) or drop the claims that depend on it
- Give jobs a code-delivery path (branch + commit + pull request), or state plainly in the product that OPM
  orchestrates planning and tracking rather than producing changes
- Make the Projects v2 title-refresh no-op either work or report an error

### Later

- Multi-repo portfolio views
- Durable job/history store instead of filesystem-only
- Deep-link to ORA for review — do not duplicate Repo Watch inside OPM
- Insights / context / live terminals; pre-merge quality gates

---

## Related

- [Products](products.md) — port table and ownership
- [Interop](interop.md) — hub-auth, tenant headers, OPM ↔ hub/ORA
- [NAS deploy](nas-deploy.md) — `*:nas` images and verify curls
- [OPL load lab capabilities](opl-lab-capabilities.md) — Done / On a branch, not merged / Missing / Different-by-design + flagship visual editor gap
- [OPM project manager capabilities](opm-pm-capabilities.md) — Done / On a branch, not merged / Not implemented / Different-by-design inventory + top gaps
- Product docs: [OPL-API](https://github.com/TheGrimmChester/OPL-API/tree/main/docs), [OPL-Dashboard](https://github.com/TheGrimmChester/OPL-Dashboard/tree/main/docs), [OPM-API](https://github.com/TheGrimmChester/OPM-API/tree/main/docs), [OPM-Dashboard](https://github.com/TheGrimmChester/OPM-Dashboard/tree/main/docs)
