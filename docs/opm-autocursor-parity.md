# AutoCursor → OPM parity inventory

Implementation guide for closing the gap between **[AutoCursor](https://github.com/TheGrimmChester/AutoCursor)** (local-first Electron + Python CLI, Auto-Claude-style task automation) and **Open Project Manager** (`OPM-API` + `OPM-Dashboard`).

**Sources checked (2026-08-04):**

| Repo | Path / ref |
|------|------------|
| AutoCursor | `/Users/nicolasmeloni/Documents/repos/AutoCursor` (`main` @ origin) |
| OPM-API | `/Users/nicolasmeloni/Documents/repos/OPM-API` |
| OPM-Dashboard | `/Users/nicolasmeloni/Documents/repos/OPM-Dashboard` |
| NAS | `192.168.100.101` — `opm-api:nas` `:8096`, `opm-dashboard:nas` `:8098` (no smoke tags) |

Companion product backlog: [opl-opm-backlog.md](opl-opm-backlog.md). Product boundaries vs ORA/Hub: [interop.md](interop.md).

---

## 1. Product shape (different-by-design)

| Dimension | AutoCursor | OPM |
|-----------|------------|-----|
| Delivery | Desktop Electron app + local CLI; **no HTTP server** | Web dashboard + HTTP API + orchestrator/runners |
| Project identity | Local folder path; `.auto-cursor/` on disk | **GitHub `owner/repo`** via Hub orgs + ORA connectors |
| Execution | Spawn `python -m auto_cursor` / Cursor CLI in worktrees | Ephemeral tmp clone + Open-Job-Go `docker run` (today: **honest stub**) |
| Auth | Cursor CLI / API key / accounts in app settings | Co-deployed Hub JWT + tenant headers |
| Review depth | In-app AI review + worktree merge/discard/PR | Automated review column; **deep review owned by ORA** |
| Multi-tenancy | Multi-project tabs on one machine | Org-scoped projects (`X-Organization-ID`) |

Do **not** chase Electron, local-folder registry, or duplicating ORA Repo Watch inside OPM. Those are explicit non-goals ([OPM-API backlog](https://github.com/TheGrimmChester/OPM-API/blob/main/docs/backlog.md)).

---

## 2. AutoCursor inventory

### 2.1 UI views (sidebar)

From `src/App.tsx` / `Sidebar.tsx`:

| View id | Purpose |
|---------|---------|
| `kanban` | Six-column board + task create/edit/remove, DnD, run actions |
| `terminals` | Live agent terminal / queue slots |
| `insights` | Insights chat (`insights-ask`) |
| `roadmap` | Discovery + features generation and editing |
| `ideation` | Typed idea lists; promote to tasks |
| `changelog` | Generate / view changelog |
| `context` | Project index / context |
| `agent-tools` | Agent utilities / MCP-ish tooling surface |
| `worktrees` | Per-task worktrees; Review / Merge / Discard |
| `settings` | Theme, providers, profiles, accounts |
| `github-issues` / `github-prs` | GitHub issue & PR lists |
| `gitlab-issues` / `gitlab-merge-requests` | GitLab lists |
| `linear` | Linear import |

Plus: Welcome / onboarding, auth-failure & rate-limit modals, update banner, project tab bar, task creation wizard, **task detail modal** (tabs: overview / subtasks / logs / files).

### 2.2 Kanban columns

AutoCursor board statuses (Electron `file-api.js`): `backlog` → `queue` → `in_progress` → `ai_review` → `human_review` → `done` (UI labels often say Planning / AI Review).

### 2.3 CLI / job-like commands (`python -m auto_cursor`)

| Command | Role |
|---------|------|
| `init` | Init `.auto-cursor` |
| `create-task` | Create spec/task |
| `generate-title` | AI title from description |
| `run-planning` | 7-phase planning → `spec.md` + `implementation_plan.json` |
| `run-implementation` | One subtask per call; retry / stuck / recover |
| `recover-subtask` | Unstick failed subtask |
| `run-ai-review` | QA review → `QA_FIX_REQUEST.md` on fail |
| `run-qa-fix` | Fix from failed review |
| `run-followup-planning` | Extend plan with follow-up phases |
| `approve-for-coding` | Human Review → Queue |
| `pause-task` / `resume-task` / `skip-to-phase` | Interruptible pipeline checkpoints |
| `remove-task` | Delete task + dir |
| `run-roadmap-discovery` / `run-roadmap-features` | Roadmap agents |
| `run-ideation --type` | Ideation agents |
| `generate-changelog` | Changelog from done tasks |
| `insights-ask` | Insights chat |
| `refresh-project-index` | Rebuild project index |
| `profiles` / `set-profile` | Auth profiles |
| `github-issues` / `github-prs` / `gitlab-*` / `linear-issues` | SCM/issue list helpers |

Headless Auto-Claude-style: `run.py`, `spec_runner.py` (list, autonomous build, QA, merge instructions, multi-spec parallel).

### 2.4 Ideation types

`code-improvements`, `security`, `performance`, `documentation`, `ui-ux`, `code-quality` (hyphenated in CLI; file keys underscored).

### 2.5 Electron IPC surface (selected)

Board/tasks/plan/progress; run registry + cancel; settings/projects/accounts/profiles; roadmap/ideation/changelog; review state; logs by phase; worktree create/list/info; merge / discard / create-or-open PR; diff; agent tools; memory; MCP config; screenshot.

### 2.6 Parallelism & worktrees

- Per-spec worktrees under `.auto-cursor/worktrees/tasks/<spec_id>`
- Global agent terminal cap (`AUTO_CURSOR_MAX_TERMINALS`, default 12)
- Multi-spec + multi-subtask coordination (`docs/parallel-execution.md`)

### 2.7 Provider model

Pluggable providers (default `cursor_cli`); per-phase model overrides; composite failover; `CURSOR.md` prepended to agent prompts.

---

## 3. OPM inventory

### 3.1 Dashboard routes (`OPM-Dashboard` `src/App.jsx`)

| Route | Page | Notes |
|-------|------|-------|
| `/` | Projects | Link GitHub repos via Hub orgs + ORA connectors |
| `/board` | Board | CRUD tasks, button move (no DnD); no plan/progress modal |
| `/roadmap` | Roadmap | Create phase/feature; limited edit/delete |
| `/ideation` | Ideation | Create ideas; promote to task |
| `/changelog` | Changelog | Read markdown |
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

### 3.3 Board columns

`backlog` → `queue` → `in_progress` → `review` → `human_review` → `done`  
(`review` is the automated review-runner column; AutoCursor’s `ai_review` maps here.)

### 3.4 Job actions (dashboard + store)

Enqueued from UI: `run-planning`, `run-implementation`, `run-review`, `run-qa-fix`, `run-roadmap-discovery`, `run-roadmap-features`, `run-ideation`, `generate-changelog`.

Store also maps `run-followup-planning` → planning state. Naming: AutoCursor `run-ai-review` ↔ OPM `run-review`.

**Execution today:** `stubRunJob` prepares ephemeral workspace + Open-Job-Go argv, sets `execution: "stub"`, completes with **no container exec / no model output**. Default runner tag env `OPM_RUNNER_TAG` (prefer `nas` on NAS — never smoke).

### 3.5 Data layout (`OPM_DATA_DIR`)

Mirrors AutoCursor artifact names under server storage (not local clone):

```text
projects/<id>/board.json, status.json, changelog.md
  specs/<specId>/{task.json,spec.md,implementation_plan.json,progress.json}
  roadmap/roadmap.json, ideation/ideation.json, runs/<runId>.json
```

Ideation type keys (underscored): `code_improvements`, `security`, `performance`, `documentation`, `ui_ux`, `code_quality`.

### 3.6 NAS verify (2026-08-04)

| Check | Result |
|-------|--------|
| `http://192.168.100.101:8096/api/health` | **200** `{ status: ok, service: opm-api, auth_mode: codeployed }` |
| `http://192.168.100.101:8098/` | **200** dashboard HTML |
| Host `:8099` | TrueNAS/nginx UI redirect — **not** `opm-orchestrator` public health (orchestrator is compose-internal; see [nas-deploy.md](nas-deploy.md)) |

---

## 4. Parity matrix

Legend: **Done** = OPM has usable equivalent · **Missing** = gap for implementers · **Different-by-design** = intentional OPM/family choice

### 4.1 Platform & projects

| Capability | Status | Notes |
|------------|--------|-------|
| Multi-project registry | **Done** | OPM: GitHub-linked; AutoCursor: local folders |
| Local folder / Electron app | **Different-by-design** | Web-only; API rejects path create |
| Hub auth + tenant headers | **Done** (OPM-only) | AutoCursor has no Hub |
| Project via ORA connectors | **Done** (OPM-only) | AutoCursor uses local git remotes optionally |
| Onboarding / welcome wizard | **Missing** | Thin first-run UX vs AutoCursor wizard |
| Settings (theme, providers, profiles) | **Missing** / partial | OPM inherits Hub; no per-phase model UI |

### 4.2 Board & tasks

| Capability | Status | Notes |
|------------|--------|-------|
| Six-column kanban | **Done** | `review` vs `ai_review` naming |
| Create / edit / delete / move tasks | **Done** | Dashboard CRUD + move |
| Drag-and-drop board | **Missing** | Button moves only |
| Require review before coding | **Done** (API field) | Surfacing + approve flow incomplete in UI |
| Approve-for-coding action | **Missing** | No dedicated API/job/UI (manual move only) |
| Task detail modal (overview/subtasks/logs/files) | **Missing** | Highest UX gap |
| Plan + progress read APIs | **Done** (API) | Dashboard does not consume yet |
| Spec artifacts (`spec.md`, plan JSON) | **Done** (store shape) | Populated only when runners actually write them |
| Generate title | **Missing** | No job/API |
| DnD + valid transition rules | **Missing** | AutoCursor enforces column transition sets |

### 4.3 Automation jobs

| Capability | Status | Notes |
|------------|--------|-------|
| Job list / enqueue / cancel | **Done** | Honest stub status fields |
| Optional `specId` on enqueue | **Done** | Jobs page picker |
| Real runner container + model output | **Missing** | Critical path |
| Orchestrator spawn/reaper loop | **Missing** | Health stub only in binary |
| `run-planning` (7 phases) | **Missing** (real) | Action exists; stub only on NAS path today |
| `run-implementation` + subtask loop | **Missing** (real) | |
| Retry / stuck / recover-subtask | **Missing** | |
| `run-review` / `run-qa-fix` loop | **Missing** (real) | |
| `run-followup-planning` | **Missing** (UI + enqueue) | Mapped in store; not in Jobs `ACTIONS` |
| Pause / resume / skip-to-phase | **Missing** | |
| Parallel multi-spec / terminal slots | **Missing** | Different runtime model (containers) |
| `run.py`-style autonomous build | **Missing** | Could be orchestrator workflow later |
| Provider / model selection | **Missing** | Runner image env only |

### 4.4 Roadmap / ideation / changelog

| Capability | Status | Notes |
|------------|--------|-------|
| Roadmap GET/PUT + create phase/feature UI | **Done** (partial) | Edit/delete inline still thin |
| Roadmap discovery/features **agents** | **Missing** (real jobs) | Actions stub |
| Ideation CRUD + promote to task | **Done** (partial) | Edit/delete incomplete |
| Ideation type agents | **Missing** (real jobs) | Types aligned |
| Changelog read | **Done** | |
| Changelog generate UX | **Missing** | Job action exists; page read-only |

### 4.5 Insights, context, agent tools

| Capability | Status | Notes |
|------------|--------|-------|
| Insights chat | **Missing** | |
| Project index / Context page | **Missing** | |
| Agent Tools page | **Missing** | |
| Agent terminals live view | **Missing** | Jobs list is coarse substitute |
| Memory / Graphiti-style | **Missing** | AutoCursor optional |

### 4.6 Worktrees, merge, PRs

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
| i18n | **Missing** | AutoCursor en/fr |
| App auto-update | **Different-by-design** | Container image deploys |
| `CURSOR.md` / prompt packs | **Missing** | Needed inside runners for quality |
| Pre-merge quality gates (tests/lint) | **Missing** | AutoCursor roadmap idea; valuable for OPM runners |
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
7. **ORA deep-links** — PR/review instead of cloning AutoCursor worktree merge UI.
8. **Insights / context** — only after core automation works.

---

## 6. Top 10 missing features (by user impact)

Ranked for an operator using OPM on NAS today:

1. **Real runner execution (not stub)** — jobs must produce specs, plans, and code changes; without this the product is a board CRUD shell.
2. **Task detail with plan / progress / logs** — AutoCursor’s primary “what is this task doing?” surface; API already half-ready.
3. **Working `run-implementation` loop** — subtask-by-subtask build with stuck/recover; core delivery value.
4. **Working `run-review` + `run-qa-fix`** — closes the quality loop before human_review / done.
5. **Working `run-planning` end-to-end** — seven phases writing `spec.md` + `implementation_plan.json` into `OPM_DATA_DIR`.
6. **Approve-for-coding + require-review UX** — human gate after planning (parity with AutoCursor’s trust model).
7. **Changelog generate + save UX** — operators expect release notes from done work; job action exists unused.
8. **Roadmap / ideation agent runs** — discovery/features/typed ideation that fill the boards users already edit by hand.
9. **Board drag-and-drop + task action menu** — daily friction vs AutoCursor kanban.
10. **Follow-up planning + pause/resume** — keeps long-running automation usable without restarting from scratch.

Honorable mentions: Insights chat, live terminals, create-PR helpers (prefer ORA), provider/model settings, parallel job slots.

---

## 7. Naming cheatsheet

| AutoCursor | OPM |
|------------|-----|
| `ai_review` column | `review` column |
| `run-ai-review` | `run-review` |
| Local `.auto-cursor/specs/…` | `$OPM_DATA_DIR/projects/<id>/specs/…` |
| Electron `runCommand` | `POST …/jobs` `{ action, specId }` |
| Worktree merge/discard | Ephemeral clone + GitHub PR / ORA |
| Ideation `code-improvements` | `code_improvements` |

---

## 8. Out of scope for parity

- Replicating Electron or local-folder projects
- Shipping smoke runner tags to NAS (`*:smoke`)
- Embedding full ORA Repo Watch / check-runs inside OPM
- Bit-for-bit Auto-Claude prompt pack cloning without runner design

When in doubt: **OPM owns kanban + task automation orchestration; ORA owns SCM credentials and deep code review; Hub owns identity.**
