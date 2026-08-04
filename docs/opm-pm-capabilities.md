# OPM project manager capabilities

Implementation guide for **Open Project Manager** (`OPM-API` + `OPM-Dashboard`): what a self-hosted, Hub-linked project manager should ship for kanban, task automation, roadmap/ideation, and job orchestration — and where OPM stands today.

**Sources checked (2026-08-04):**

| Repo | Path / ref |
|------|------------|
| OPM-API | `/Users/nicolasmeloni/Documents/repos/OPM-API` |
| OPM-Dashboard | `/Users/nicolasmeloni/Documents/repos/OPM-Dashboard` |
| NAS | `192.168.100.101` — `opm-api:nas` `:8096`, `opm-dashboard:nas` `:8098` (no smoke tags) |

Companion product backlog: [opl-opm-backlog.md](opl-opm-backlog.md). Product boundaries vs ORA/Hub: [interop.md](interop.md).

---

## 1. Product shape (different-by-design)

| Dimension | OPM stance |
|-----------|------------|
| Delivery | Web dashboard + HTTP API + orchestrator/runners (not a desktop Electron app) |
| Project identity | **GitHub `owner/repo`** via Hub orgs + ORA connectors (not local folder paths) |
| Execution | Ephemeral tmp clone + Open-Job-Go `docker run` (today: **honest stub** for most actions) |
| Auth | Co-deployed Hub JWT + tenant headers |
| Review depth | Automated review column; **deep review owned by ORA** |
| Multi-tenancy | Org-scoped projects (`X-Organization-ID`) |

Do **not** chase Electron, local-folder registry, or duplicating ORA Repo Watch inside OPM. Those are explicit non-goals ([OPM-API backlog](https://github.com/TheGrimmChester/OPM-API/blob/main/docs/backlog.md)).

---

## 2. Target project manager surface

Capabilities a mature OPM should cover (UI + jobs + storage).

### 2.1 UI views (target)

| View | Purpose |
|------|---------|
| Projects | Multi-project registry; link GitHub repos |
| Board (kanban) | Six-column board + task create/edit/remove, DnD, run actions |
| Task detail | Overview / subtasks / plan / progress / logs / files |
| Jobs | Enqueue / cancel / live status for automation actions |
| Roadmap | Discovery + features generation and editing |
| Ideation | Typed idea lists; promote to tasks |
| Changelog | Generate / view / save changelog |
| Context | Project index / context |
| Agent tools | Agent utilities / MCP-ish tooling surface |
| Terminals / live runs | Live agent / runner visibility |
| Settings | Theme, providers, profiles (where Hub does not already own them) |
| Onboarding | Welcome / first-run wizard |

External issue/PR lists (GitHub/GitLab/Linear) prefer **link-out or ORA** rather than in-app clones unless later sync is justified.

### 2.2 Kanban columns (OPM)

`backlog` → `queue` → `in_progress` → `review` → `human_review` → `done`  
(`review` is the automated review-runner column.)

### 2.3 Automation job actions (target)

| Action | Role |
|--------|------|
| `init` / project init | Seed project storage |
| Create task / generate title | Spec/task creation helpers |
| `run-planning` | Multi-phase planning → `spec.md` + `implementation_plan.json` |
| `run-implementation` | One subtask per call; retry / stuck / recover |
| `recover-subtask` | Unstick failed subtask |
| `run-review` | QA review → fix request on fail |
| `run-qa-fix` | Fix from failed review |
| `run-followup-planning` | Extend plan with follow-up phases |
| `approve-for-coding` | Human Review → Queue |
| `pause-task` / `resume-task` / `skip-to-phase` | Interruptible pipeline checkpoints |
| `run-roadmap-discovery` / `run-roadmap-features` | Roadmap agents |
| `run-ideation` (typed) | Ideation agents |
| `generate-changelog` | Changelog from done tasks |
| Insights ask | Insights chat |
| Refresh project index | Rebuild project index |

### 2.4 Ideation types

`code_improvements`, `security`, `performance`, `documentation`, `ui_ux`, `code_quality` (underscored in store; hyphenated variants in some CLIs).

### 2.5 Parallelism & workspaces

- Ephemeral job clone under `OPM_JOB_TMP` (not durable per-task worktrees)
- Container runner slots / orchestrator reaper (target)
- Multi-spec + multi-subtask coordination when real runners land

### 2.6 Provider model

Pluggable providers; per-phase model overrides; prompt packs (`CURSOR.md` or equivalent) prepended inside runners.

---

## 3. OPM inventory (today)

### 3.1 Dashboard routes (`OPM-Dashboard` `src/App.jsx`)

| Route | Page | Notes |
|-------|------|-------|
| `/` | Projects | Link GitHub repos via Hub orgs + ORA connectors |
| `/board` | Board | CRUD tasks, button move (no DnD); task detail maturity varies by release |
| `/roadmap` | Roadmap | Create phase/feature; edit/delete improving |
| `/ideation` | Ideation | Create ideas; promote to task |
| `/changelog` | Changelog | Read / generate+save depending on release |
| `/jobs` | Jobs | Enqueue + cancel; action picker + optional `specId` |
| `/login` | Login | Hub-auth co-deployed |

Side rail: Projects, Board, Roadmap, Ideation, Changelog, Jobs.

### 3.2 API routes (`OPM-API`)

| Area | Endpoints |
|------|-----------|
| Health | `GET /api/health`, `GET /api/peer/health` |
| Hub / GitHub | `GET /api/hub/status`, `/api/hub/organizations`, `/api/github/connectors`, `…/repos` |
| Projects | `GET|POST /api/projects`, `GET|DELETE /api/projects/{id}`, `POST …/init` |
| Board | `GET|PUT …/board` |
| Tasks | `GET|POST …/tasks`, `GET|PATCH|DELETE …/tasks/{specId}`, `POST …/move`, `GET …/plan`, `GET …/progress` |
| Roadmap / ideation / changelog | `GET|PUT …/roadmap`, `GET|PUT …/ideation`, `GET …/changelog` |
| Status / jobs | `GET …/status`, `GET|POST …/jobs`, `GET …/jobs/{runId}`, `POST …/jobs/{runId}/cancel` |

### 3.3 Job actions (dashboard + store)

Enqueued from UI: `run-planning`, `run-implementation`, `run-review`, `run-qa-fix`, `run-roadmap-discovery`, `run-roadmap-features`, `run-ideation`, `generate-changelog`.

Store also maps `run-followup-planning` → planning state.

**Execution today:** `stubRunJob` prepares ephemeral workspace + Open-Job-Go argv, sets `execution: "stub"`, completes with **no container exec / no model output** for most paths (`run-planning` may complete on NAS after clone-credentials + runtime git fixes). Default runner tag env `OPM_RUNNER_TAG` (prefer `nas` on NAS — never smoke).

### 3.4 Data layout (`OPM_DATA_DIR`)

Server-side project artifacts (not a local desktop clone):

```text
projects/<id>/board.json, status.json, changelog.md
  specs/<specId>/{task.json,spec.md,implementation_plan.json,progress.json}
  roadmap/roadmap.json, ideation/ideation.json, runs/<runId>.json
```

### 3.5 NAS verify (2026-08-04)

| Check | Result |
|-------|--------|
| `http://192.168.100.101:8096/api/health` | **200** `{ status: ok, service: opm-api, auth_mode: codeployed }` |
| `http://192.168.100.101:8098/` | **200** dashboard HTML |
| Host `:8099` | TrueNAS/nginx UI redirect — **not** `opm-orchestrator` public health (orchestrator is compose-internal; see [nas-deploy.md](nas-deploy.md)) |

---

## 4. Capability matrix

Legend: **Done** = OPM has usable equivalent · **Missing** = gap for implementers · **Different-by-design** = intentional OPM/family choice

### 4.1 Platform & projects

| Capability | Status | Notes |
|------------|--------|-------|
| Multi-project registry | **Done** | GitHub-linked via Hub + ORA |
| Local folder / Electron app | **Different-by-design** | Web-only; API rejects path create |
| Hub auth + tenant headers | **Done** | Co-deployed `/hub-auth/` |
| Project via ORA connectors | **Done** | Family-native path |
| Onboarding / welcome wizard | **Missing** | Thin first-run UX |
| Settings (theme, providers, profiles) | **Missing** / partial | OPM inherits Hub; no per-phase model UI |

### 4.2 Board & tasks

| Capability | Status | Notes |
|------------|--------|-------|
| Six-column kanban | **Done** | `review` column for automated review |
| Create / edit / delete / move tasks | **Done** | Dashboard CRUD + move |
| Drag-and-drop board | **Missing** | Button moves only |
| Require review before coding | **Done** (API field) | Surfacing + approve flow may still be thin |
| Approve-for-coding action | **Missing** / partial | Prefer first-class API/job/UI |
| Task detail (overview/subtasks/logs/files) | **Missing** / partial | Highest UX gap when absent |
| Plan + progress read APIs | **Done** (API) | Dashboard must consume them |
| Spec artifacts (`spec.md`, plan JSON) | **Done** (store shape) | Populated only when runners actually write them |
| Generate title | **Missing** | No job/API |
| Valid column transition rules | **Missing** | Enforce allowed moves |

### 4.3 Automation jobs

| Capability | Status | Notes |
|------------|--------|-------|
| Job list / enqueue / cancel | **Done** | Honest stub status fields |
| Optional `specId` on enqueue | **Done** | Jobs page picker |
| Real runner container + model output | **Missing** | Critical path |
| Orchestrator spawn/reaper loop | **Missing** | Health stub only in binary |
| `run-planning` (multi-phase) | **Missing** (real) / partial on NAS | Action exists; often stub |
| `run-implementation` + subtask loop | **Missing** (real) | |
| Retry / stuck / recover-subtask | **Missing** | |
| `run-review` / `run-qa-fix` loop | **Missing** (real) | |
| `run-followup-planning` | **Missing** (UI + enqueue) | Mapped in store; not always in Jobs `ACTIONS` |
| Pause / resume / skip-to-phase | **Missing** | |
| Parallel multi-spec / runner slots | **Missing** | Container runtime model |
| Autonomous multi-spec build workflow | **Missing** | Orchestrator workflow later |
| Provider / model selection | **Missing** | Runner image env only |

### 4.4 Roadmap / ideation / changelog

| Capability | Status | Notes |
|------------|--------|-------|
| Roadmap GET/PUT + create phase/feature UI | **Done** (partial) | Edit/delete inline still thin in places |
| Roadmap discovery/features **agents** | **Missing** (real jobs) | Actions stub |
| Ideation CRUD + promote to task | **Done** (partial) | Edit/delete incomplete in places |
| Ideation type agents | **Missing** (real jobs) | Types aligned |
| Changelog read | **Done** | |
| Changelog generate UX | **Missing** / partial | Job action exists; wire save UX |

### 4.5 Insights, context, agent tools

| Capability | Status | Notes |
|------------|--------|-------|
| Insights chat | **Missing** | |
| Project index / Context page | **Missing** | |
| Agent Tools page | **Missing** | |
| Agent terminals live view | **Missing** | Jobs list is coarse substitute |
| Long-term memory store | **Missing** | Optional later |

### 4.6 Workspaces, merge, PRs

| Capability | Status | Notes |
|------------|--------|-------|
| Durable per-task worktrees | **Different-by-design** | OPM: ephemeral job clone under `OPM_JOB_TMP` |
| Review / Merge / Discard UI | **Missing** / **Different-by-design** | Prefer PR + ORA review deep-link |
| Create/open PR from task | **Missing** | ORA/GitHub App path preferred |
| Task diff in UI | **Missing** | |

### 4.7 External issue sync

| Capability | Status | Notes |
|------------|--------|-------|
| In-app GitHub Issues/PRs views | **Different-by-design** | Link out / ORA; optional later sync |
| GitLab / Linear import | **Different-by-design** | Later backlog |
| GitHub Issues two-way sync | **Missing** (Later) | Listed in [opl-opm-backlog.md](opl-opm-backlog.md) |

### 4.8 Cross-cutting

| Capability | Status | Notes |
|------------|--------|-------|
| i18n | **Missing** | |
| App auto-update | **Different-by-design** | Container image deploys |
| Prompt packs in runners | **Missing** | Needed for runner quality |
| Pre-merge quality gates (tests/lint) | **Missing** | Valuable for OPM runners |
| Analytics (cycle time, pass rates) | **Missing** | Later |
| Durable job history (ClickHouse) | **Missing** | Later; FS runs today |

---

## 5. Suggested implementation order (for coding agents)

1. **Real job execution** — orchestrator spawn of `opm-runner-task:nas`, stream status, persist plan/spec/progress artifacts (unblocks almost everything else).
2. **Task detail** — consume `…/plan` + `…/progress` + logs; actions wired to jobs with `specId`.
3. **Approve-for-coding** — API action or first-class move + UI gate when `requireReviewBeforeCoding`.
4. **Implementation + review/QA loops** — subtask iteration, recover, follow-up planning.
5. **Roadmap/ideation/changelog generators** — turn stub actions into real agent runs; changelog write UX.
6. **Board DnD + richer edit** — roadmap/ideation inline edit/delete.
7. **ORA deep-links** — PR/review instead of in-app merge/discard for durable worktrees.
8. **Insights / context** — only after core automation works.

---

## 6. Top 10 missing features (by user impact)

Ranked for an operator using OPM on NAS today:

1. **Real runner execution (not stub)** — jobs must produce specs, plans, and code changes; without this the product is a board CRUD shell.
2. **Task detail with plan / progress / logs** — primary “what is this task doing?” surface; API already half-ready.
3. **Working `run-implementation` loop** — subtask-by-subtask build with stuck/recover; core delivery value.
4. **Working `run-review` + `run-qa-fix`** — closes the quality loop before human_review / done.
5. **Working `run-planning` end-to-end** — multi-phase writing `spec.md` + `implementation_plan.json` into `OPM_DATA_DIR`.
6. **Approve-for-coding + require-review UX** — human gate after planning.
7. **Changelog generate + save UX** — operators expect release notes from done work; job action exists unused.
8. **Roadmap / ideation agent runs** — discovery/features/typed ideation that fill the boards users already edit by hand.
9. **Board drag-and-drop + task action menu** — daily kanban friction.
10. **Follow-up planning + pause/resume** — keeps long-running automation usable without restarting from scratch.

Honorable mentions: Insights chat, live terminals, create-PR helpers (prefer ORA), provider/model settings, parallel job slots.

---

## 7. Naming cheatsheet

| Concept | OPM |
|---------|-----|
| Automated review column | `review` |
| Review job action | `run-review` |
| Spec storage | `$OPM_DATA_DIR/projects/<id>/specs/…` |
| Enqueue automation | `POST …/jobs` `{ action, specId }` |
| Merge path | Ephemeral clone + GitHub PR / ORA |
| Ideation type key | `code_improvements` (underscored) |

---

## 8. Out of scope

- Replicating Electron or local-folder projects
- Shipping smoke runner tags to NAS (`*:smoke`)
- Embedding full ORA Repo Watch / check-runs inside OPM
- Bit-for-bit third-party prompt pack cloning without runner design

When in doubt: **OPM owns kanban + task automation orchestration; ORA owns SCM credentials and deep code review; Hub owns identity.**
