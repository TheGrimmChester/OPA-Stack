# OPM project manager capabilities

Implementation guide for **Open Project Manager** (`OPM-API` + `OPM-Dashboard`): what a self-hosted, Hub-linked project manager should ship for kanban, task automation, roadmap/ideation, and job orchestration — and where OPM stands today.

**Sources checked (re-verified 2026-08-04):**

| Repo | Ref judged |
|------|------------|
| OPM-API | `origin/main` @ `8cd0562` |
| OPM-Dashboard | `origin/main` @ `6d43452` |
| ORA-API (peer `scm:pm`) | `origin/main` @ `5a706fb` |

Every **Done** row below was re-checked by reading the named file and line on `origin/main`. Work that
exists only on an unmerged feature branch is labelled **On a branch, not merged** with the branch name —
local checkouts of these repos frequently sit on those branches, so "it works when I run it here" is not
evidence that a capability shipped.

> **Deployment verification is not part of this pass.** `opm-api` `:8096` and `opm-dashboard` `:8098` answer
> their health/index routes, but the images report an unversioned build id (`opm-api-dev`) with no commit
> identity, and every capability route needs an operator token this pass does not hold (`GET /api/projects`
> → **401**). A behaviour observed on the deployed stack therefore could not be attributed to `origin/main`
> anyway. No row below claims "live on the deployed stack"; treat all statuses as source-code statements.

Companion product backlog: [opl-opm-backlog.md](opl-opm-backlog.md). Product boundaries vs ORA/Hub: [interop.md](interop.md).

---

## 1. Product shape (different-by-design)

| Dimension | OPM stance |
|-----------|------------|
| Delivery | Web dashboard + HTTP API + runner containers (not a desktop Electron app). The `opm-orchestrator` service is a health/probe endpoint, not a scheduler — `main.go:114` |
| Project identity | **GitHub `owner/repo`** via Hub orgs + ORA connectors (not local folder paths) |
| Execution | **Container spawn** of `opm-runner-task:nas` when `spawnReady`, then shared artifact helpers; **builtin** in-process fallback (`OPM_FORCE_BUILTIN` / spawn failure). A tmp clone is prepared but currently unused (`job_runner.go:45-50`) — job output goes to `OPM_DATA_DIR`, never to the repository |
| Auth | Co-deployed Hub JWT + tenant headers |
| Review depth | Automated review column; **deep review owned by ORA** |
| Multi-tenancy | Org-scoped projects (`X-Organization-ID`) |

Do **not** chase Electron, local-folder registry, or duplicating ORA Repo Watch inside OPM. Those are explicit non-goals ([OPM-API backlog](https://github.com/TheGrimmChester/OPM-API/blob/main/docs/backlog.md)).

---

## 2. Target project manager surface

Capabilities a mature OPM should cover (UI + jobs + storage). **Everything in section 2 is a target, not a
status claim** — several rows here are not implemented. Section 4 is the only place that states status.

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
| Agent tools | Agent utility / tool-server surface |
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
| `pause-task` / `resume-task` / `skip-to-phase` | Interruptible pipeline checkpoints (`skip-to-phase` not implemented — §4.3) |
| `run-roadmap-discovery` / `run-roadmap-features` | Roadmap generators (placeholder today — §4.4) |
| `run-ideation` (typed) | Ideation generators (placeholder today — §4.4) |
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

Pluggable providers; per-phase model overrides; prompt packs (a repo-level prompt file) prepended inside runners.

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

Enqueued from UI (`OPM-Dashboard/src/pages/Jobs.jsx:7-20`): `run-planning`, `run-implementation`, `run-review`, `run-qa-fix`, `run-followup-planning`, `recover-subtask`, `mark-stuck`, `pause-task`, `resume-task`, `run-roadmap-discovery`, `run-roadmap-features`, `run-ideation`, `generate-changelog`. `skip-to-phase` is **not** in that list on `origin/main`.

Store also maps `run-followup-planning` → planning state.

**Execution today:** when spawnReady (docker CLI + daemon + `opm-runner-task:nas`), jobs `docker run` one hardened ephemeral runner (`execution: "container"`), then shared helpers write `spec.md` / plan / progress / review + QA / changelog. Builtin in-process path (`execution: "builtin"`) remains the fallback (`OPM_FORCE_BUILTIN=1` or spawn failure). Orchestrator `/api/spawn-probe` reports `spawnReady: true` when docker works. Default runner tag env `OPM_RUNNER_TAG` (prefer `nas` on NAS — never smoke).

**Two limits that shape every row below.**

1. **Jobs never write to the cloned repository.** `OPM-API/job_runner.go:45-50` clones the repo through
   `prepareJobWorkspace` and immediately discards the handle (`_ = workDir`); the only git invocations in the
   whole service are two `git clone` calls (`OPM-API/workspace.go:57` and `:69`). There is no `git add`,
   `commit`, `push`, branch creation, or pull-request call anywhere in OPM-API. "Implementation" means
   flipping the next plan subtask to `completed` (`job_runner.go:321-341`) and, on the model path, appending a
   section to `IMPLEMENTATION_NOTES.md` (`OPM-API/model_apply.go:111-135`, which itself calls
   `builtinImplementation` first). Code delivery is out of scope of the current job runner, not a
   configuration gap.
2. **Only three actions have a model-backed path.** `OPM-API/model_apply.go:17-29` dispatches
   `run-planning` / `run-followup-planning`, `run-implementation`, and `run-review`; every other action falls
   through `default: return false` to the builtin switch. The runner binary
   (`OPM-API/cmd/opm-runner/main.go:136-153`) likewise only carries prompts and output keys for those three.
   Roadmap and ideation therefore run the placeholder path whether or not a model key is configured.

### 3.4 Data layout (`OPM_DATA_DIR`)

Server-side project artifacts (not a local desktop clone):

```text
projects/<id>/board.json, status.json, changelog.md
  specs/<specId>/{task.json,spec.md,implementation_plan.json,progress.json,logs/*.log,review_state.json}
  roadmap/roadmap.json, ideation/ideation.json, runs/<runId>.json
```

### 3.5 Deployment verification (not performed this pass)

This section previously recorded capability-level results against the deployed stack. Those results are not
reproducible right now, so they have been withdrawn rather than restated:

| Check | Status this pass |
|-------|------------------|
| `:8096/api/health` · `:8098/` | Reachable, but the payload reports build id `opm-api-dev` — no commit identity, so a result cannot be tied to `origin/main` |
| `GET /api/projects` (operator token + `X-Organization-ID`) | **Not verified** — returns **401** without a Hub token, and this pass holds none |
| Plan → approve → implementation loop → review → changelog end-to-end | **Not verified** — requires an authenticated session |
| Container spawn / `spawnReady` | **Not verified** on the deployed stack. In source, `preferContainerSpawn()` gates it and `probeRunnerSpawn()` shells out to `docker info` / `docker image inspect` (`OPM-API/orchestrator_probe.go:47-55`) |
| Host `:8099` | Returns **404** for `/api/spawn-probe`, consistent with `:8099` being the appliance UI rather than orchestrator health (orchestrator is compose-internal; see [nas-deploy.md](nas-deploy.md)) |

Re-add rows here only with a reproducible command, its output, and the image build id that produced it.

---

## 4. Capability matrix

Legend — three status states, plus one scope label:

| Status | Meaning |
|--------|---------|
| **Done** | Present on `origin/main` and re-read at the file:line cited in Notes |
| **On a branch, not merged** | Implemented on a named unmerged feature branch; absent from `origin/main` |
| **Not implemented** | No implementation on `origin/main` or on any known branch |
| **Different-by-design** | Deliberate scope decision, not a status — nothing is expected to land |

Where a capability is real but narrower than its name suggests, the Notes column states in one sentence what
works and what does not. "Done" is a claim about source code on `origin/main` only — see the deployment note
at the top of this document.

### 4.1 Platform & projects

| Capability | Status | Notes |
|------------|--------|-------|
| Multi-project registry | **Done** | GitHub-linked via Hub + ORA; `OPM-API/store.go:134` `CreateProject`, `handlers.go:38` |
| Local folder / Electron app | **Different-by-design** | Web-only; API rejects path create (`store_test.go:100` guards it) |
| Hub auth + tenant headers | **Done** | Co-deployed `/hub-auth/`; `OPM-API/auth_wire.go`, `tenant_scope.go` |
| Project via ORA connectors | **Done** | `OPM-API/github_handlers.go:16` proxies connectors/repos through ORA |
| Onboarding / welcome wizard | **Not implemented** | No onboarding route in `OPM-Dashboard/src/App.jsx` |
| Settings (theme, providers, profiles) | **Not implemented** | No settings page; per-phase model ids come from runner env only (`OPM-API/cmd/opm-runner/main.go:118-134`) |

### 4.2 Board & tasks

| Capability | Status | Notes |
|------------|--------|-------|
| Six-column kanban | **Done** | `review` column for automated review |
| Create / edit / delete / move tasks | **Done** | `OPM-API/handlers.go:115` (`tasks`), `:241` (`move`) |
| Drag-and-drop board | **Done** | HTML5 DnD: `OPM-Dashboard/src/pages/Board.jsx:415-448` |
| Require review before coding | **Done** | Create checkbox; gate enforced at `OPM-API/job_runner.go:296-312` |
| Approve-for-coding action | **Done** | `OPM-API/handlers.go:262` (`approve`) + board/detail UI |
| Task detail (overview / plan / spec / logs) | **Done** | `handlers.go:273-317` back the drawer. Files/diff tabs do not exist — the drawer shows stored artifacts, never repository contents |
| Plan + progress read APIs | **Done** | `handlers.go:273` (`plan`), `:284` (`progress`) |
| Spec artifacts (`spec.md`, plan JSON) | **Done** | Written by `builtinPlanning` and by `applyModelPlanning` (`OPM-API/model_apply.go:32-51`) |
| Generate title | **Not implemented** | No such action in `job_runner.go:128-152` and no route in `handlers.go` |
| Valid column transition rules | **Not implemented** | `handlers.go:241` `move` accepts any known column; no allowed-transition table |

### 4.3 Automation jobs

| Capability | Status | Notes |
|------------|--------|-------|
| Job list / enqueue / cancel | **Done** | `OPM-API/handlers.go:134` + `:424`; `execution` + `message` fields |
| Optional `specId` on enqueue | **Done** | Jobs page + board/detail |
| Runner container calls a model | **Done** (three actions only) | `OPM-API/cmd/opm-runner/main.go:69-100` calls a chat-completions endpoint when `OPM_MODEL_API_KEY` is set and writes `/out/result.json`; the control plane applies it for planning, implementation, and review only (`model_apply.go:17-29`). Output is prose and plan JSON — no repository changes |
| Orchestrator spawn / reaper loop | **Not implemented** | `OPM-API/main.go:103-121` serves only `/api/health` and `/api/spawn-probe` and logs itself a "job scheduler stub" at `main.go:114`. Jobs are spawned in-process by `opm-api`, not by the orchestrator; nothing reaps stale containers |
| `run-planning` (multi-phase) | **Done** | Writes `spec.md` + plan; honours require-review move |
| `run-implementation` + subtask loop | **Done** (plan bookkeeping only) | One subtask flipped to `completed` per enqueue (`job_runner.go:321-341`); writes no code — see §4.6 |
| Retry / stuck / recover-subtask | **Done** | `mark-stuck`, `recover-subtask` at `job_runner.go:139-140`, `:137-138`; cancel marks stuck |
| `run-review` / `run-qa-fix` loop | **Done** | PASS/FAIL + `QA_FIX_REQUEST.md`; review verdict is derived from plan completeness, not from reading a diff (`model_apply.go:146-152`) |
| `run-followup-planning` | **Done** | `job_runner.go:129-130`; Jobs picker + detail action |
| Pause / resume | **Done** | `pause-task` / `resume-task` at `job_runner.go:141-144`; gate at `job_runner.go:101-104` |
| Skip-to-phase | **On a branch, not merged** (`feature/agent-roadmap-ideation-skip`) | Absent from `origin/main`: `skipToPhase` / `skip-to-phase` / `targetPhase` match no source file in OPM-API or OPM-Dashboard, only `OPM-API/docs/backlog.md:26` ("skip still missing"). The implementation sits on `origin/feature/agent-roadmap-ideation-skip` in both repos (open PR, never merged) |
| Parallel multi-spec / runner slots | **Not implemented** | One container per job; no slot accounting |
| Autonomous multi-spec build workflow | **Not implemented** | Every step is a separate operator enqueue |
| Provider / model selection UI | **Not implemented** | Runner-image env only (`spawn_container.go:74-90`); no dashboard surface |

### 4.4 Roadmap / ideation / changelog

| Capability | Status | Notes |
|------------|--------|-------|
| Roadmap read/write + create phase/feature UI | **Done** | `OPM-API/handlers.go:117` (`GET|PUT …/roadmap`); inline edit/delete in `OPM-Dashboard/src/pages/Roadmap.jsx` |
| Roadmap discovery / features **generation** | **Not implemented** | Roadmap phases and features can be created and edited by hand; automated generation is a placeholder that records an acknowledgement only. `job_runner.go:147-148` routes `run-roadmap-discovery` and `run-roadmap-features` to `builtinMetaNote`, which appends one log line and returns `"builtin placeholder — agent prompts not wired yet"` (`job_runner.go:688-691`). The model path does not cover these actions either (`model_apply.go:27-29`). A generator implementation exists on `origin/feature/agent-roadmap-ideation-skip` but is not merged |
| Ideation CRUD + promote to task | **Done** | `handlers.go:119` + `:366`/`:377`; edit/delete/promote in `OPM-Dashboard/src/pages/Ideation.jsx` |
| Ideation type **generation** | **Not implemented** | Typed idea lists can be created and edited by hand; `run-ideation` records an acknowledgement only via the same `builtinMetaNote` path (`job_runner.go:147-148`, `:688-691`). `ideationType` is accepted but nothing generates entries |
| Changelog read | **Done** | `handlers.go:121` |
| Changelog generate + save | **Done** | `builtinChangelog` composes from done tasks (`job_runner.go:145-146`, ends `:682-685`); `PUT …/changelog` saves edits |

### 4.5 Insights, context, agent tools

| Capability | Status | Notes |
|------------|--------|-------|
| Insights chat | **Not implemented** | No route, no job action |
| Project index / Context page | **Not implemented** | No index build anywhere in OPM-API |
| Agent Tools page | **Not implemented** | |
| Agent terminals live view | **Not implemented** | Jobs list is the only run visibility |
| Long-term memory store | **Not implemented** | |

### 4.6 Workspaces, merge, PRs

| Capability | Status | Notes |
|------------|--------|-------|
| Durable per-task worktrees | **Different-by-design** | OPM uses an ephemeral job clone under `OPM_JOB_TMP` |
| **Code delivery from a task (edit / commit / branch / push)** | **Not implemented** | The job clone is created and then discarded unused (`OPM-API/job_runner.go:45-50`, `_ = workDir`). The only git calls in the service are `git clone` (`workspace.go:57`, `:69`) — no `git add`, `commit`, `push`, or branch creation exists. Nothing OPM runs can change a repository |
| Create / open pull request from task | **Not implemented** | No pull-request call anywhere in OPM-API; ORA deep-link is the intended path but is not wired from a task either |
| Review / Merge / Discard UI | **Not implemented** / **Different-by-design** | Nothing to merge while §4.6 row 2 holds; deep-link to ORA is preferred over in-app merge |
| Task diff in UI | **Not implemented** | No diff is produced, so none can be shown |

### 4.7 External issue sync

| Capability | Status | Notes |
|------------|--------|-------|
| In-app GitHub Issues/PRs views | **Different-by-design** | Link out / ORA; optional later sync |
| Non-GitHub issue import | **Different-by-design** | Later backlog |
| GitHub Milestones bind + sync | **Done** | List/assign via ORA `scm:pm` (`OPM-API/github_pm.go:31`, `:46`); roadmap phases + tasks |
| GitHub Projects v2 bind + item sync | **Done** (create and status only) | Binding a project and creating draft items work (`ORA-API/github_projects.go:270-292` issues a real `addProjectV2DraftIssue` mutation), and Status-on-move is best-effort; needs `organization_projects`. **Renaming an existing draft item silently does nothing**: `githubUpdateProjectV2DraftIssue` (`ORA-API/github_projects.go:294-302`) returns `nil` without calling the API — verified by reading the whole function from the `origin/main` blob — and the caller discards its return value (`ORA-API/peer_scm_pm.go:268`). The response is `{"ok": true}` with no `status_note`, so a rename looks synced and is not |
| GitHub Issues two-way sync | **Done** | Task ↔ Issue link/unlink/push/pull via ORA `scm:pm` (`OPM-API/github_issue_sync.go:260-284` routes `link`/`unlink`/`push`/`pull`, handlers at `:286`, `:369`, `:409`, `:473`); needs only `issues: write`. Mapping below |
| Issue picker / candidate list | **Not implemented** | Attach is by number; no `GET …/issues` list endpoint |
| Issue comments ↔ task discussion | **Not implemented** | Not modelled in OPM |
| Webhook-driven issue refresh | **Not implemented** | Poll/refresh only; a receiver would go through ORA like other SCM webhooks |

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
| i18n | **Not implemented** | |
| App auto-update | **Different-by-design** | Container image deploys |
| Prompt packs in runners | **Not implemented** | Runner prompts are the hard-coded strings at `OPM-API/cmd/opm-runner/main.go:137-142`; no repo-level prompt file is read |
| Pre-merge quality gates (tests/lint) | **Not implemented** | Nothing executes tests or linters; there is also no merge to gate (§4.6) |
| Analytics (cycle time, pass rates) | **Not implemented** | |
| Durable job history | **Not implemented** | Runs are files under `$OPM_DATA_DIR/projects/<id>/runs/<runId>.json` |

---

## 5. Suggested implementation order

1. **Code delivery** — the single largest gap. Until a job can write to its clone and open a pull request,
   "implementation" and "review" are bookkeeping over a plan file (§4.6).
2. **Merge the two waiting branches** — `feature/agent-roadmap-ideation-skip` (roadmap/ideation generators +
   skip-to-phase) and `feature/github-issue-sync` (issue sync) are written but absent from `origin/main`;
   until they merge, neither capability exists for anyone who deploys from `main`.
3. **Real orchestrator loop** — replace the `main.go:114` scheduler stub with actual dispatch and container
   reaping, so spawn is not driven in-process by `opm-api`.
4. **Fix the silent no-op** in Projects v2 draft title refresh, or surface it as an error instead of
   discarding it (`ORA-API/peer_scm_pm.go:268`).
5. **Insights / context** — after core automation matures.

---

## 6. Top remaining gaps (by user impact)

Ranked for an operator running OPM today:

1. **No code delivery** — a completed task leaves the repository untouched (§4.6).
2. **Roadmap / ideation generation is an acknowledgement, not a generator** (§4.4) — the UI offers the
   actions, and they always "succeed" without producing content, which reads as a silent failure.
3. **Skip-to-phase is advertised but absent** from `main` (§4.3).
4. **Live terminals / richer job logs UI** — the Jobs list is the only run visibility.
5. **Provider / model settings** — runner image env only, no UI.
6. **Pre-merge quality gates** — nothing runs tests or linters.

Shipped this pass: task ↔ GitHub Issue two-way sync (link/unlink/push/pull via ORA `scm:pm`, explicit column↔state mapping, honest permission and missing-issue reporting); prior: roadmap/ideation agent generators + skip-to-phase; containerized task spawn; board DnD + stuck/recover + pause/resume. Health `:8096` and dashboard `:8098` on `*:nas`.

**Correction (2026-08-04).** Earlier revisions of this section claimed "shipped this pass: roadmap/ideation
agent generators + skip-to-phase". That was wrong. Both belong to a pull request that was never merged into
`OPM-API` `main` — the merge history runs #14, #15, #16, #17, #19, #20, #21 with no #18, and PR #18
(`feature/agent-roadmap-ideation-skip`) is still open. Containerized task spawn, board drag-and-drop,
stuck/recover, and pause/resume did land and are verified above.

---

## 7. Naming cheatsheet

| Concept | OPM |
|---------|-----|
| Automated review column | `review` |
| Review job action | `run-review` |
| Spec storage | `$OPM_DATA_DIR/projects/<id>/specs/…` |
| Enqueue automation | `POST …/jobs` `{ action, specId }` |
| Merge path | Intended: ephemeral clone → GitHub PR / ORA. Not implemented today (§4.6) |
| Ideation type key | `code_improvements` (underscored) |

---

## 8. Out of scope

- Replicating Electron or local-folder projects
- Shipping smoke runner tags to NAS (`*:smoke`)
- Embedding full ORA Repo Watch / check-runs inside OPM
- Bit-for-bit third-party prompt pack cloning without runner design

When in doubt: **OPM owns kanban + task automation orchestration; ORA owns SCM credentials and deep code review; Hub owns identity.**
