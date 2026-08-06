# OPM project manager capabilities

Implementation guide for **Open Project Manager** (`OPM-API` + `OPM-Dashboard`): what a self-hosted, Hub-linked project manager should ship for kanban, task automation, roadmap/ideation, and job orchestration — and where OPM stands today.

**Sources checked (re-verified 2026-08-04):**

| Repo | Ref judged |
|------|------------|
| OPM-API | `origin/main` @ `a7c60ee` |
| OPM-Dashboard | `origin/main` @ `674cece` |
| ORA-API (peer `scm:pm`) | `origin/main` @ `a44d387` |

Status is judged against **`origin/main`**, never the local checkout — these repos are often checked out on a
feature branch based on an older `main`, which makes shipped features look absent and unmerged ones look
shipped. Method and evidence conventions are set out in §4.

> **Deployment verification is not part of this pass.** `opm-api` `:8096` and `opm-dashboard` `:8098` answer
> their health/index routes, but the images report an unversioned build id (`opm-api-dev`) with no commit
> identity, and capability routes need an operator token this pass does not hold (`GET /api/projects` →
> **401**). A behaviour observed on the deployed stack could not be attributed to a particular `origin/main`
> anyway. No row below claims "live on the deployed stack"; every status is a source-code statement.

Companion product backlog: [opl-opm-backlog.md](opl-opm-backlog.md). Product boundaries vs ORA/Hub: [interop.md](interop.md).

---

## 1. Product shape (different-by-design)

| Dimension | OPM stance |
|-----------|------------|
| Delivery | Web dashboard + HTTP API + runner containers (not a desktop Electron app). The `opm-orchestrator` service is a health/probe endpoint, not a scheduler — it calls itself a "job scheduler stub" at `OPM-API/main.go:114` |
| Project identity | **GitHub `owner/repo`** via Hub orgs + ORA connectors (not local folder paths) |
| Execution | **Container spawn** of `opm-runner-task:nas` when `spawnReady`, then shared artifact helpers. AI jobs **fail closed** on spawn/credential failure; in-process builtins only for control-plane actions or explicit `OPM_FORCE_BUILTIN=1`. Job output goes to `OPM_DATA_DIR`, never to the repository |
| Auth | Co-deployed Hub JWT + tenant headers |
| Review depth | Automated review column; **deep review owned by ORA** |
| Multi-tenancy | Org-scoped projects (`X-Organization-ID`) |

Do **not** chase Electron, local-folder registry, or duplicating ORA Repo Watch inside OPM. Those are explicit non-goals ([OPM-API backlog](https://github.com/TheGrimmChester/OPM-API/blob/main/docs/backlog.md)).

---

## 2. Target project manager surface

Capabilities a mature OPM should cover (UI + jobs + storage). **Everything in section 2 is a target, not a
status claim** — some rows here are not implemented. Section 4 is the only place that states status.

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
| Settings | Theme; AI providers / models live in **OAM** (deep-link), not Hub |
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
| `pause-task` / `resume-task` / `skip-to-phase` | Interruptible pipeline checkpoints (all three implemented — §4.3) |
| `run-roadmap-discovery` / `run-roadmap-features` | Roadmap generators (implemented from fixed templates — §4.4) |
| `run-ideation` (typed) | Ideation generators (implemented from fixed templates — §4.4) |
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
| `/` | Projects | Link GitHub repos via Hub orgs + ORA connector list (manage installs in OAM) |
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

Enqueued from UI (`OPM-Dashboard/src/pages/Jobs.jsx`): `run-planning`, `run-implementation`, `run-review`, `run-qa-fix`, `run-followup-planning`, `recover-subtask`, `mark-stuck`, `pause-task`, `resume-task`, `skip-to-phase` (with a `targetPhase` field, `Jobs.jsx:17`, `:100`, `:179`), `run-roadmap-discovery`, `run-roadmap-features`, `run-ideation`, `generate-changelog`.

Store also maps `run-followup-planning` → planning state.

**Execution today:** when spawnReady (docker CLI + daemon + `opm-runner-task:nas`), jobs `docker run` one hardened ephemeral runner (`execution: "container"`), then shared helpers write `spec.md` / plan / progress / review + QA / changelog. AI-backed actions fail closed without spawn + OAM credentials; builtins are for control-plane actions or `OPM_FORCE_BUILTIN=1` only. Orchestrator `/api/spawn-probe` reports `spawnReady: true` when docker works. Default runner tag env `OPM_RUNNER_TAG` (prefer `nas` on NAS — never smoke).

**Two limits that shape the rows below.**

1. **Jobs never write to the cloned repository.** `job_runner.go:45-50` clones via `prepareJobWorkspace` and
   discards the handle (`_ = workDir`); the only git invocations in the whole service are two `git clone` calls
   (`workspace.go:57`, `:69`). There is no `git add`, `commit`, `push`, branch creation, or pull-request call.
   "Implementation" flips the next plan subtask to `completed` (`job_runner.go:321-341`) and, on the model path,
   appends to `IMPLEMENTATION_NOTES.md` (`model_apply.go:111-135`).
2. **Only three actions have a model-backed path.** `model_apply.go:17-29` dispatches planning,
   implementation, and review; everything else falls to `default: return false` and takes the builtin path. The
   runner binary carries prompts for those three only (`cmd/opm-runner/main.go:136-153`), so roadmap and
   ideation generation is deterministic template output whether or not a model key is set.

### 3.4 Data layout (`OPM_DATA_DIR`)

Server-side project artifacts (not a local desktop clone):

```text
projects/<id>/board.json, status.json, changelog.md
  specs/<specId>/{task.json,spec.md,implementation_plan.json,progress.json,logs/*.log,review_state.json}
  roadmap/roadmap.json, ideation/ideation.json, runs/<runId>.json
```

### 3.5 Deployment verification (not performed this pass)

This section previously recorded capability-level results against the deployed stack. They are not reproducible
in this pass, so they are withdrawn rather than restated:

| Check | Status this pass |
|-------|------------------|
| `:8096/api/health` · `:8098/` | Reachable, but the payload reports build id `opm-api-dev` — no commit identity, so no result can be attributed to a particular `origin/main` |
| `GET /api/projects` (operator token + `X-Organization-ID`) | **Not verified** — **401** without a Hub token, and this pass holds none |
| Plan → approve → implementation loop → review → changelog end-to-end | **Not verified** — needs an authenticated session |
| Container spawn / `spawnReady` | **Not verified** on the deployed stack. In source, `probeRunnerSpawn()` shells out to `docker info` / `docker image inspect` (`OPM-API/orchestrator_probe.go:47-55`) |
| Host `:8099` | **404** for `/api/spawn-probe`, consistent with `:8099` being the appliance UI rather than orchestrator health (orchestrator is compose-internal; see [nas-deploy.md](nas-deploy.md)) |

Re-add rows here only with a reproducible command, its output, and the image build id that produced it.

---

## 4. Capability matrix

**Status basis.** Re-verified 2026-08-04 against `OPM-API` `origin/main` @ `a7c60ee`, `OPM-Dashboard`
`origin/main` @ `674cece`, `ORA-API` `origin/main` @ `a44d387`. Two method notes, because both changed rows in
this revision:

- **Judge `origin/main`, not the checkout.** These repos are often checked out on a feature branch based on an
  older `main`, which makes shipped features look absent and unmerged ones look shipped. Every row was checked
  against the `origin/main` blob, not the working tree.
- **Search output here is unreliable.** A command hook rewrites `git diff`, `grep`, and `rg` output, so an empty
  result can be a tool artifact rather than a fact about the code. Negative findings below were taken with
  `rtk proxy rg` / `rtk proxy git grep`, each carrying a **positive control that fired in the same command**;
  where practical the whole function or file was read from the `origin/main` blob instead of searched. Nothing
  is marked absent on the strength of an empty search alone.

Three status states, plus one scope label:

| Status | Meaning |
|--------|---------|
| **Done** | Present on `origin/main`, verified at the file:line cited in Notes |
| **On a branch, not merged** | Implemented on a named unmerged branch; absent from `origin/main` |
| **Not implemented** | No implementation on `origin/main`, established by a positive-control search or a whole-file read |
| **Different-by-design** | Deliberate scope decision, not a status |

Where a capability is real but narrower than its name suggests, Notes says in one sentence what works and what
does not. "Done" is a claim about source code on `origin/main` only — see §3.5.

### 4.1 Platform & projects

| Capability | Status | Notes |
|------------|--------|-------|
| Multi-project registry | **Done** | GitHub-linked via Hub + ORA protocol; credentials in OAM |
| Local folder / Electron app | **Different-by-design** | Web-only; API rejects path create |
| Hub auth + tenant headers | **Done** | Co-deployed `/hub-auth/` |
| Project via ORA connectors | **Done** | List via ORA; storage in OAM |
| Onboarding / welcome wizard | **Not implemented** | No onboarding route in `OPM-Dashboard/src/App.jsx` |
| Settings (theme, providers, profiles) | **Partial** | Theme may be local; AI providers / per-agent models belong in **OAM** (`PEER_OAM_URL`); legacy `OPM_MODEL_*` only when OAM unset |

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
| Generate title | **Not implemented** | No such action in the `job_runner.go` dispatch switch and no route in `handlers.go` |
| Valid column transition rules | **Not implemented** | `handlers.go:241` `move` accepts any known column; no allowed-transition table |

### 4.3 Automation jobs

| Capability | Status | Notes |
|------------|--------|-------|
| Job list / enqueue / cancel | **Done** | `execution` + `message` fields |
| Optional `specId` on enqueue | **Done** | Jobs page + board/detail |
| Runner container calls a model | **Done** | With `PEER_OAM_URL`, model + API key resolve from OAM per job phase (`creds:resolve`); legacy `OPM_MODEL_API_KEY` / `CURSOR_API_KEY` when OAM unset. Runner writes `/out/result.json`; control plane applies planning/implementation/review/ideation/roadmap. Builtin path is fallback only |
| Orchestrator spawn / reaper loop | **Not implemented** | `runOrchestrator` in `OPM-API/main.go` registers only `/api/health` and `/api/spawn-probe`, and its own startup log calls it a "job scheduler stub" (`main.go:114`) — verified by reading the whole function from the `origin/main` blob, not by search. Spawn happens in-process in `opm-api` (`job_runner.go:60-91`); nothing reaps stale containers |
| `run-planning` (multi-phase) | **Done** | Writes `spec.md` + plan; moves for require-review |
| `run-implementation` + subtask loop | **Done** | Model runner returns `files[]` into a task-session workspace; change set recorded for delivery (§4.6). Builtin-only path still advances plan state without source changes |
| Retry / stuck / recover-subtask | **Done** | `mark-stuck`, `recover-subtask` (`job_runner.go:137-140`); cancel marks stuck |
| `run-review` / `run-qa-fix` loop | **Done** | PASS/FAIL + `QA_FIX_REQUEST.md`. The verdict comes from plan completeness, not from reading a diff (`model_apply.go:146-152`) |
| `run-followup-planning` | **Done** | `job_runner.go:129-130`; Jobs picker + detail action |
| Pause / resume | **Done** | `pause-task` / `resume-task` (`job_runner.go:141-144`); gate at `job_runner.go:101-104` |
| Skip-to-phase | **Done** | API: `handlers.go:429` declares `TargetPhase int \`json:"targetPhase"\``, `:441-442` rejects a missing or `<1` value with 400, `:451` assigns it; dispatch at `job_runner.go:153-154` → `builtinSkipToPhase` (`job_runner.go:930-995`), which resolves the target phase, marks earlier phases complete, and rewrites `progress.json`. UI: `OPM-Dashboard/src/components/TaskDetail.jsx:18`, `:311`; `src/pages/Jobs.jsx:17`, `:100`, `:179` |
| Parallel multi-spec / runner slots | **Not implemented** | One container per job; no slot accounting |
| Autonomous multi-spec build workflow | **Not implemented** | Every step is a separate operator enqueue |
| Provider / model selection UI | **Different-by-design** | Configure in **OAM** Agents & Models; OPM should deep-link, not re-own. Legacy `OPM_MODEL_*` env only when `PEER_OAM_URL` unset |

### 4.4 Roadmap / ideation / changelog

| Capability | Status | Notes |
|------------|--------|-------|
| Roadmap read/write + create phase/feature UI | **Done** | `OPM-API/handlers.go:117`; inline edit/delete in `OPM-Dashboard/src/pages/Roadmap.jsx` |
| Roadmap discovery / features **generation** | **Done** (deterministic, not model-backed) | Real artifacts are written: `job_runner.go:147-150` dispatches `builtinRoadmapDiscovery` (body at `:714`) and `builtinRoadmapFeatures` (`:769`), which set vision, target audience, phases, and features and persist through `PutRoadmap`; features bootstraps by calling discovery first (`:779`). The content is **template text composed from the project name and the board's task titles**, not model output — the runner carries no roadmap prompts and `model_apply.go:17-29` does not route these actions, so a model key changes nothing here |
| Ideation CRUD + promote to task | **Done** | `handlers.go:119`, `:366`/`:377`; edit/delete/promote in `OPM-Dashboard/src/pages/Ideation.jsx` |
| Ideation type **generation** | **Done** (deterministic, not model-backed) | `job_runner.go:151-152` → `builtinIdeation` (`:844`) inserts ideas per type from a fixed template table, skips titles already present, and persists through `PutIdeation`. Honours `ideationType`, all types when omitted. Same caveat as roadmap: fixed templates, no model involvement |
| Changelog read | **Done** | `handlers.go:121` |
| Changelog generate + save | **Done** | `builtinChangelog` composes from done tasks (`job_runner.go:145-146`, body at `:662`); `PUT …/changelog` saves edits |

### 4.5 Insights, context, agent tools

| Capability | Status | Notes |
|------------|--------|-------|
| Insights chat | **Not implemented** | No route, no job action |
| Project index / Context page | **Not implemented** | No index build in OPM-API |
| Agent Tools page | **Not implemented** | |
| Agent terminals live view | **Not implemented** | The Jobs list is the only run visibility |
| Long-term memory store | **Not implemented** | |

### 4.6 Workspaces, merge, PRs

| Capability | Status | Notes |
|------------|--------|-------|
| Durable per-task worktrees | **Done** (task sessions) | Coding/review share `$OPM_JOB_TMP/tasks/{projectId}/{specId}/repo` until deliver / human gate / done |
| **Code delivery from a task (edit / commit / branch / push)** | **Done** | Apply recorded change set; commit on `opm/<specId>`; push + open PR via ORA `scm:pr` (`delivery.go`, `peer_delivery.go`). Builtin path still produces no source changes |
| Create / open pull request from task | **Done** | `POST …/tasks/{specId}/deliver`; auto-deliver after review PASS when `OPM_IMPL_AUTO_DELIVER` |
| Review / Merge / Discard UI | **Partial** / **Different-by-design** | Autopilot can merge via ORA `scm:pr`; deep-link to ORA Repo Watch still preferred for full review UX |
| Task diff in UI | **Partial** | Change set listed on task Delivery; full diff viewer may still be thin |

### 4.7 External issue sync

| Capability | Status | Notes |
|------------|--------|-------|
| In-app GitHub Issues/PRs views | **Different-by-design** | Link out / ORA; optional later sync |
| Non-GitHub issue import | **Different-by-design** | Later backlog |
| GitHub Milestones bind + sync | **Done** | List/assign via ORA `scm:pm` (`OPM-API/github_pm.go:31`, `:46`); roadmap phases + tasks |
| GitHub Projects v2 bind + item sync | **Done** (create and status only) | Binding a project and creating draft items work — `ORA-API/github_projects.go:270-292` issues a real `addProjectV2DraftIssue` mutation — and Status-on-move is best-effort; needs `organization_projects`. **Renaming an existing draft item silently does nothing:** `githubUpdateProjectV2DraftIssue` (`ORA-API/github_projects.go:294-302`) returns `nil` without contacting the API (whole function read from the `origin/main` blob), and the caller discards its return value (`ORA-API/peer_scm_pm.go:268`). The response is `{"ok": true}` with no `status_note`, so a rename looks synced and is not |
| GitHub Issues two-way sync | **Done** | Task ↔ Issue link/unlink/push/pull via ORA `scm:pm` — `OPM-API/github_issue_sync.go:260-284` routes `link`/`unlink`/`push`/`pull`, handlers at `:286`, `:369`, `:409`, `:473`; needs only `issues: write`. Mapping below |
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
| Pre-merge quality gates (tests/lint) | **Not implemented** | Nothing executes tests or linters inside OPM; OSA/OPL gates are separate products |
| Analytics (cycle time, pass rates) | **Not implemented** | |
| Durable job history | **Not implemented** | Runs are files under `$OPM_DATA_DIR/projects/<id>/runs/<runId>.json` |

---

## 5. Suggested implementation order

1. **Live-stack verify delivery + OAM resolve** on NAS after `*:nas` rebuild (§4.6 shipped in code).
2. **Real orchestrator loop** — replace the `main.go:114` scheduler stub with actual dispatch and container
   reaping, so spawn is not driven in-process by `opm-api`.
3. **PR state tracking** — poll or webhook via ORA (`prState` is a snapshot today).
4. **ORA review deep-link** — do not duplicate Repo Watch inside OPM.
5. **Insights / context** — after core automation matures.

---

## 6. Top remaining gaps (by user impact)

Ranked for an operator running OPM today:

1. **NAS image lag / live delivery proof** — delivery is in OPM-API; confirm against a real GitHub App on the deployed stack.
2. **Live terminals / richer job logs UI** — the Jobs list is the only run visibility.
3. **Provider / model settings UI** — configure in **OAM**; OPM should deep-link, not re-own.
4. **PR state not tracked** after open — merged/closed PRs may still show `open` until re-deliver.
5. **Pre-merge quality gates** — OSA/OPL, not duplicated in OPM.
6. **ORA Repo Watch deep-link** from a task — still policy-only.

Shipped and verified on `origin/main` this pass: code delivery (`scm:pr`); per-job OAM model/key resolve; task ↔ GitHub Issue two-way sync; roadmap/ideation generators and skip-to-phase; containerized task spawn; board drag-and-drop; stuck/recover; pause/resume.

**Correction (2026-08-04).** An earlier revision of this document downgraded skip-to-phase and the
roadmap/ideation generators to "not implemented", citing a `builtinMetaNote` placeholder. That was accurate for
the `origin/main` of a few hours earlier but became wrong when PR #18 merged (`a7c60ee`) mid-review;
`builtinMetaNote` no longer exists. The rows in §4.3 and §4.4 now reflect the merged code, with the remaining
narrowness (fixed template text rather than model output) stated rather than the capability denied. Deployment
state is a separate question and is not claimed either way — see §3.5.

Honorable mentions: parallel job slots, durable ClickHouse job history, analytics.

---

## 7. Naming cheatsheet

| Concept | OPM |
|---------|-----|
| Automated review column | `review` |
| Review job action | `run-review` |
| Spec storage | `$OPM_DATA_DIR/projects/<id>/specs/…` |
| Enqueue automation | `POST …/jobs` `{ action, specId }` |
| Merge path | Change set → deliver (`scm:pr`) → optional autopilot merge via ORA (§4.6 Done) |
| Ideation type key | `code_improvements` (underscored) |

---

## 8. Out of scope

- Replicating Electron or local-folder projects
- Shipping smoke runner tags to NAS (`*:smoke`)
- Embedding full ORA Repo Watch / check-runs inside OPM
- Bit-for-bit third-party prompt pack cloning without runner design

When in doubt: **OPM owns kanban + task automation orchestration; ORA owns SCM credentials and deep code review; Hub owns identity.**
