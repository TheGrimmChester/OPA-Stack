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
| Execution | Ephemeral tmp clone + **container spawn** of `opm-runner-task:nas` when `spawnReady`, then shared artifact helpers; **builtin** in-process fallback (`OPM_FORCE_BUILTIN` / spawn failure) |
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

External issue/PR lists (GitHub and other SCM/issue hosts) prefer **link-out or ORA** rather than in-app clones unless later sync is justified.

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
| `/board` | Board | CRUD + **DnD** + task action menu; require-review; Plan/Build/Approve/Pause/Recover; task detail drawer |
| `/roadmap` | Roadmap | Create / edit / delete phases and features |
| `/ideation` | Ideation | Create / edit / delete; promote to task |
| `/changelog` | Changelog | Read + generate job + edit/save (`PUT`) |
| `/jobs` | Jobs | Enqueue + cancel; `specId`; shows `execution`/`message` |
| `/login` | Login | Hub-auth co-deployed |

Side rail: Projects, Board, Roadmap, Ideation, Changelog, Jobs.

### 3.2 API routes (`OPM-API`)

| Area | Endpoints |
|------|-----------|
| Health | `GET /api/health`, `GET /api/peer/health` |
| Hub / GitHub | `GET /api/hub/status`, `/api/hub/organizations`, `/api/github/connectors`, `…/repos` |
| GitHub PM | `GET …/github/milestones`, `POST …/milestones/assign`, `GET …/github/projects`, `POST …/projects/bind`, `POST …/projects/sync-item`, `POST …/github/sync-task/{specId}` |
| GitHub Issues | `POST …/github/issues/link`, `…/issues/unlink`, `…/issues/push`, `…/issues/pull` |
| Projects | `GET|POST /api/projects`, `GET|DELETE /api/projects/{id}`, `POST …/init` |
| Board | `GET|PUT …/board` |
| Tasks | `GET|POST …/tasks`, `GET|PATCH|DELETE …/tasks/{specId}`, `POST …/move`, `POST …/approve`, `GET …/plan|progress|spec|logs|actions` |
| Roadmap / ideation / changelog | `GET|PUT …/roadmap`, `GET|PUT …/ideation`, `GET|PUT …/changelog` |
| Status / jobs | `GET …/status`, `GET|POST …/jobs`, `GET …/jobs/{runId}`, `POST …/jobs/{runId}/cancel` |

### 3.3 Job actions (dashboard + store)

Enqueued from UI: `run-planning`, `run-implementation`, `run-review`, `run-qa-fix`, `run-followup-planning`, `recover-subtask`, `mark-stuck`, `pause-task`, `resume-task`, `run-roadmap-discovery`, `run-roadmap-features`, `run-ideation`, `generate-changelog`.

Store also maps `run-followup-planning` → planning state.

**Execution today:** when spawnReady (docker CLI + daemon + `opm-runner-task:nas`), jobs `docker run` one hardened ephemeral runner (`execution: "container"`), then shared helpers write `spec.md` / plan / progress / review + QA / changelog. Builtin in-process path (`execution: "builtin"`) remains the fallback (`OPM_FORCE_BUILTIN=1` or spawn failure). Orchestrator `/api/spawn-probe` reports `spawnReady: true` when docker works. Default runner tag env `OPM_RUNNER_TAG` (prefer `nas` on NAS — never smoke).

### 3.4 Data layout (`OPM_DATA_DIR`)

Server-side project artifacts (not a local desktop clone):

```text
projects/<id>/board.json, status.json, changelog.md
  specs/<specId>/{task.json,spec.md,implementation_plan.json,progress.json,logs/*.log,review_state.json}
  roadmap/roadmap.json, ideation/ideation.json, runs/<runId>.json
```

### 3.5 NAS verify (2026-08-04)

| Check | Result |
|-------|--------|
| `http://192.168.100.101:8096/api/health` | **200** `{ status: ok, service: opm-api, auth_mode: codeployed }` (re-checked same day) |
| `http://192.168.100.101:8098/` | **200** dashboard HTML |
| `GET /api/projects` (Hub JWT + `X-Organization-ID`) | **200** — GitHub-linked projects listed |
| Builtin E2E | plan → approve → impl loop → review → changelog **PASS** (`execution=builtin` or `container` when spawnReady; `*:nas` only) |
| Container spawn | `/api/spawn-probe` → `spawnReady: true` when docker CLI + daemon + `opm-runner-task:nas`; jobs set `execution: "container"` after successful `docker run` |
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
| Drag-and-drop board | **Done** | HTML5 DnD + action menu |
| Require review before coding | **Done** | Create checkbox + gate after planning |
| Approve-for-coding action | **Done** | `POST …/approve` + board/detail UI |
| Task detail (overview/subtasks/logs/files) | **Done** (partial) | Drawer: overview / plan / spec / logs; files thin |
| Plan + progress read APIs | **Done** | Consumed by board + detail |
| Spec artifacts (`spec.md`, plan JSON) | **Done** | Builtin planning writes them |
| Generate title | **Missing** | No job/API |
| Valid column transition rules | **Missing** | Enforce allowed moves |

### 4.3 Automation jobs

| Capability | Status | Notes |
|------------|--------|-------|
| Job list / enqueue / cancel | **Done** | `execution` + `message` fields |
| Optional `specId` on enqueue | **Done** | Jobs page + board/detail |
| Real runner container + model output | **Done** (when key set) | Runner calls model; persists into plan/progress/logs; fallback without key |
| Orchestrator spawn/reaper loop | **Partial** | Health + `/api/spawn-probe`; no reaper/spawn yet |
| `run-planning` (multi-phase) | **Done** (builtin) | Writes `spec.md` + plan; moves for require-review |
| `run-implementation` + subtask loop | **Done** (builtin) | One subtask per enqueue |
| Retry / stuck / recover-subtask | **Done** (builtin) | `mark-stuck`, `recover-subtask`; cancel marks stuck |
| `run-review` / `run-qa-fix` loop | **Done** (builtin) | PASS/FAIL + `QA_FIX_REQUEST.md` |
| `run-followup-planning` | **Done** | Jobs picker + detail action |
| Pause / resume / skip-to-phase | **Done** | `pause-task`, `resume-task`, `skip-to-phase` + `targetPhase` |
| Parallel multi-spec / runner slots | **Missing** | Container runtime model |
| Autonomous multi-spec build workflow | **Missing** | Orchestrator workflow later |
| Provider / model selection | **Partial** | Compose `OPM_MODEL_*` env (no dashboard UI yet) |

### 4.4 Roadmap / ideation / changelog

| Capability | Status | Notes |
|------------|--------|-------|
| Roadmap GET/PUT + create phase/feature UI | **Done** | Inline edit/delete shipped |
| Roadmap discovery/features **agents** | **Done** (builtin) | Writes vision/phases/features; model-backed runner follow-on |
| Ideation CRUD + promote to task | **Done** | Edit/delete + promote |
| Ideation type agents | **Done** (builtin) | Optional `ideationType`; all types when omitted |
| Changelog read | **Done** | |
| Changelog generate UX | **Done** | Generate job + edit/save |

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
| Non-GitHub issue import | **Different-by-design** | Later backlog |
| GitHub Milestones bind + sync | **Done** | List/assign via ORA `scm:pm`; roadmap phases + tasks |
| GitHub Projects v2 bind + item sync | **Done** (partial) | Bind project; draft items; Status on move best-effort; needs `organization_projects` |
| GitHub Issues two-way sync | **Done** | Task ↔ Issue link/unlink/push/pull via ORA `scm:pm`; needs only `issues: write`. Mapping below |
| Issue picker / candidate list | **Missing** (Later) | Attach is by number; no `GET …/issues` list endpoint yet |
| Issue comments ↔ task discussion | **Missing** (Later) | Not modelled in OPM |
| Webhook-driven issue refresh | **Missing** (Later) | Poll/refresh only today; a receiver would go through ORA like other SCM webhooks |

#### Task ↔ Issue field mapping

Authority is split per field. OPM owns what the board owns; GitHub owns the rest.

| Field | Direction | Notes |
|-------|-----------|-------|
| Task title → issue title | push | OPM authoritative |
| Task description → issue body | push | OPM authoritative |
| Board column → issue state | push | `done` → `closed`; all five other columns → `open` |
| Task milestone → issue milestone | push | Pushed when set; an unset task milestone does not clear the issue's |
| Issue state → board column | pull | `closed` → `done`; `open` on `done` → `in_progress` (reopened); `open` elsewhere → **no move** |
| Issue assignee → `githubIssueAssignee` | pull | Mirror only — OPM has no assignee model, so it is never pushed |
| Issue labels → `githubIssueLabels` | pull | Mirror only — OPM does not model task labels |
| Issue milestone → task milestone | pull | GitHub wins on refresh |
| Issue title → `githubIssueTitle` | pull | Mirrored without overwriting the task title unless `adoptTitle` is sent |

The reverse state mapping is deliberately partial: five columns map to `open`, so an open issue carries no column information and a refresh must not drag a task out of `human_review`. Only the `done`/reopen boundary is acted on.

Failures are never silent. Any push/pull failure is persisted on the task as `githubIssueSyncError`, appended to the `github-issue-sync` spec log, and returned with a machine-readable `status` — `missing_issues_permission` (403, listing the missing permissions), `issue_not_found` (404, link kept so it can be repaired), `no_issue_linked` / `not_linked_repo` (400), `upstream_error` (502). ORA pre-flights the App installation permission probe on writes, so a missing Issues grant is reported before GitHub is contacted. Title divergence is reported (`titleDiverged`) rather than resolved, so a refresh cannot discard a local edit.

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

1. ~~**Model-backed agents in runner**~~ — shipped (`OPM_MODEL_API_KEY` / base URL / model ids; honest fallback).
2. **Roadmap/ideation agents** — replace placeholder enqueue with real generators.
3. **Skip-to-phase** — finish interruptible pipeline controls (pause/resume done).
4. **ORA deep-links** — PR/review instead of in-app merge/discard.
5. **Insights / context** — after core automation matures.

---

## 6. Top remaining gaps (by user impact)

Ranked for an operator using OPM on NAS today:

1. ~~**Model-backed agents in runner**~~ — shipped (`OPM_MODEL_*` env; fallback without key).
2. **Live terminals / richer job logs UI** — Jobs list is coarse.
3. **Create-PR helpers via ORA** — prefer Hub/ORA over in-app merge.
4. **Provider / model settings** — runner image env only.
5. **Pre-merge quality gates** — tests/lint before done.
6. **Insights / context pages** — after automation matures.

Shipped this pass: task ↔ GitHub Issue two-way sync (link/unlink/push/pull via ORA `scm:pm`, explicit column↔state mapping, honest permission and missing-issue reporting); prior: roadmap/ideation agent generators + skip-to-phase; containerized task spawn; board DnD + stuck/recover + pause/resume. Health `:8096` and dashboard `:8098` on `*:nas`.

Honorable mentions: parallel job slots, durable ClickHouse job history, analytics.

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
