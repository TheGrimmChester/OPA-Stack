# OPL load lab capabilities

Implementation guide for **sibling** work in [OPL-API](https://github.com/TheGrimmChester/OPL-API) and [OPL-Dashboard](https://github.com/TheGrimmChester/OPL-Dashboard). Inventories what **Open Perf Lab** ships today, what is still missing for a serious self-hosted load lab, and what OPL deliberately does differently from a commercial multi-cloud load grid.

**Sources (re-verified 2026-08-04):** OPL-API `origin/main` @ `51b4e87` (`jmeter.go` / `jmeter_engine.go` /
`load.go` / `lab_extras.go` / `postman.go` / `report_export.go` / `run_notify.go`); OPL-Dashboard `origin/main`
@ `487e2da` (`PerfLab.jsx` / `VuTree.jsx` / `LoadCurveEditor.jsx`); OPA-Stack
[opl-opm-backlog.md](opl-opm-backlog.md).

> **Deployment verification is not part of this pass.** `opl-api` `:8092` and `opl-dashboard` `:8095` answer
> their health/index routes, but the API reports an unversioned build id (`perf-lab-dev`) with no commit
> identity, and the capability routes need an operator token this pass does not hold. A behaviour observed on
> the deployed stack therefore could not be attributed to `origin/main` anyway. Nothing below claims to be
> verified on the deployed stack; every status is a source-code statement about `origin/main`.
> Production images stay `*:nas` only — never deploy `*:smoke` to NAS.

---

## How to read this

Three status states, plus one scope label:

| Bucket | Meaning |
|--------|---------|
| **Done** | Present on `origin/main` and re-read at the file:line cited in Notes |
| **On a branch, not merged** | Implemented on a named unmerged feature branch; absent from `origin/main` |
| **Missing** | No implementation on `origin/main` or on any known branch |
| **Different by design** | Deliberate scope decision, not a status |

Where a capability is real but narrower than its name suggests, the Notes column states in one sentence what
works and what does not.

OPL is a **self-hosted load lab** next to OPA, not a SaaS multi-cloud load grid. Gaps ranked for **load-test lab user impact** (design → run → analyze → gate), not for matching enterprise multi-region packaging.

### Flagship: JMeter Visual test case editor

**Aspirational destination:** hierarchical Virtual User tree (drag-and-drop actions, containers, logic, extractors) for building JMeter-compatible journeys **without editing raw JMX**.

**OPL today (Done — deepening):** Design tab is a **VU tree** (HTTP, Transaction, If / While / Loop / ForEach, Fragment + Link, extract, assert) with inspector + HTML5 DnD reorder/nest. Saves nested `steps_json` → JMX hashTrees; import round-trips controllers when parseable. Fragments emit disabled generic controllers; Link expands by name at JMX emit. Capture and plan-file import remain the on-ramp. Two honest limits: the action tree does not cover rendezvous, scripted samplers, or module-reference path fidelity; and **the tree cannot yet bind a dataset** — a `${var}` typed into a step is not fed by the CSV in the Users & data tab (see the first row of **Missing**).

---

## Done (shipped lab workflows)

| Capability area | OPL today | Notes / sibling codes |
|-----------------|-----------|------------------------|
| Virtual users / HTTP journeys | Scenario CRUD via upsert; Design VU tree + flat step fallback | `OPL-API` `load.go`, `jmeter_engine.go`; Dashboard Design |
| **JMeter Visual editor (MVP+)** | Nested VU tree → JMX; DnD reorder/nest; If/While/Loop/ForEach; Fragment + Link | `VuTree.jsx`; `appendStepJMXIndexed`; import tree parse |
| HAR → scenario | `POST /api/perf/scenarios/import-har` (+ Capture UI) | Skips private/metadata hosts (URL policy) |
| **Collection import** | `POST /api/perf/scenarios/import-postman` (+ Capture UI) | `postman.go:15`; collection v2/v2.1 → HTTP steps; `{{var}}` → `${var}`; scripts ignored |
| JMeter JMX import / export | `import-jmx`, `export-jmx`, JMX tab; nested controllers when parseable | `jmeter.go:22`, `:53`. Best-effort HTTP / timers / extractors / classic TG + If/While/Loop/ForEach/Txn/Fragment. CSV Data Set elements are **parsed on import** (`jmeter.go:110`) into scenario metadata, not re-emitted on generation |
| XHR capture import | `import-xhr` / `export-xhr` | Lab-oriented capture interchange |
| Soft-archive + **restore** | API + Dashboard (Show archived + restore) | Soft-delete; `POST .../unarchive`; list `?archived=1` |
| Load policy presets | `GET /api/perf/load-policies` + Run & scale picker | smooth / sustained / stress / custom |
| **Custom load curve** | `schedule.curve` + `curve_mode=vus\|arrivals` | Dashboard `LoadCurveEditor`; VU peak/ramp or arrivals open-model segments |
| **Scheduler UX** | `POST .../schedule` + in-process tick + Run & scale panel | `jmeter.go:67`; tick started at `main.go:30` → `lab_extras.go:283`. `every_minutes` / `daily_at` UTC; single-process, not a distributed campaign scheduler |
| **Multi-run history + sparklines** | Scenario-scoped run table (≤25) + p95/error sparklines on Run & scale | Complements two-run Compare |
| **Trend report widgets** | Trends tab: latency band (p50/p95/p99), error bars, best/worst/SLA breach KPIs; `GET .../scenarios/{id}/trends` | Beyond sparklines; widget/metric/window selection now comes from a saved template |
| **PDF / bench pack** | `report?format=html|pdf` + `bench-pack` ZIP (JSON+CSV+HTML+PDF) | Offline shareable pack from Results; `?template=<id>` applies a saved layout |
| **Report / trend templates** | `opl.report_templates` + `/api/perf/report-templates` CRUD; picker + editor on Results and Trends | Named org/project-scoped layouts (widgets / metrics / window); unknown names dropped on save |
| **Notification channels** | webhook + chat incoming-webhook + SMTP email over one terminal-run event; `OPL_RUN_NOTIFY_CHANNELS` / `_MODE` / `_STATUSES` | Unconfigured channels are reported in health and history, never silently dropped |
| **Notification history** | `opl.run_notifications` + `/api/perf/notifications` (+ per-run); Notification channels/history panels | One row per channel attempt: `sent` / `failed` / `logged` / `skipped` with the plain reason |
| CSV / datasets (**storage only — does not reach the run**) | Inline CSV is stored and materialised beside the plan, but generated plans never read it | See **Missing**; no CSV Data Set in generators |
| Extractors / assertions (basic) | Nested under HTTP in VU tree | Mirrored as JMX where supported |
| **Validate triage + auto-correlation** | `validate` returns `triage[]` + `correlation_suggestions[]`; UI Apply extract | Token/CSRF/Bearer heuristics from body_preview |
| Load profiles | `soak` / `spike` / `ramp` + presets | Run & scale tab |
| Multi-worker scale (same host) | `workers` / `OPA_JMETER_WORKERS` → N containers on the lab host | `perf_container.go:348-351`; VUs split at `jmeter_engine.go:552`. Same `load_run_id`; one host, not geo locations |
| Run lifecycle | Create, dispatch, cancel, metrics ingest, status | `created` / `running` / `failed` / `cancelled` honesty |
| SLA / pass criteria | Scenario `sla` + `GET .../runs/{id}/gate` (fail-closed) | `jmeter.go:59`, verdict at `jmeter.go:651`; SLA gates tab; CI harness in OPA-Stack |
| k6 script export | `GET .../runs/{id}/export-k6` | `load.go:450` → `handlePerfExportK6` at `load.go:557` |
| Results KPIs + samples | Results tab; `summary_json` + step samples | Prefer JMeter aggregates over client-posted pass/fail |
| Per-step stats / report / runners | Results tab wiring | `/steps`, `/report`, `/runners` |
| **JTL import** | `POST /api/perf/runs/import-jtl` + Results UI upload | Offline analysis path |
| Compare two runs | Compare tab (delta on KPIs) | Simpler than full trend report builder |
| APM correlation | `X-OPA-Load-Run-Id` / baggage → OPA Trace Explorer | First-party OPL ↔ OPA correlation |
| Tenant + hub auth | Org/project headers; co-deployed `/hub-auth/` | Hub JWT + org/project scopes |
| CI gate scripts | `harness/perf-gate.sh`, `harness/jmeter-perf-gate.sh`, workflow example | Scripts only; no per-CI-vendor setup wizards |
| On-prem execution | Docker JMeter on the Perf Lab host | Lab host workers; not public cloud regions |

---

## On a branch, not merged

| Capability | Branch | Notes |
|------------|--------|-------|
| Richer notify channels + notification history | `feature/notify-channels-report-templates` | `OPL-API/run_notify.go` (+452 lines), `run_notify_history.go`, and `OPL-Dashboard/src/components/NotifyChannels.jsx` exist on that branch in both repos; `origin/main` has webhook-only notification |
| Saved report / trend templates | `feature/notify-channels-report-templates` | `OPL-API/report_templates.go` and `OPL-Dashboard/src/components/ReportTemplateBar.jsx` exist on that branch; `origin/main` has fixed report and trend layouts only |

Local checkouts of OPL-API and OPL-Dashboard commonly sit on this branch — running it locally is not evidence
that it shipped. The PDF / bench-pack / trends work **did** merge (`OPL-API` `origin/main` @ `51b4e87` is the
merge commit for that branch) and is listed under **Done**.

---

## Missing (implementation candidates)

| Capability | Why labs need it | OPL gap | Suggested sibling work |
|------------|------------------|---------|------------------------|
| **Bind a dataset to the executed plan** | A parameterised test is the whole point of uploading a CSV | **Datasets never reach the running test.** `jmeter_engine.go:554-563` reads only `datasets_json.csv.inline` and writes it to `data.csv` next to `plan.jmx` (`:586`), but no plan generator emits a CSV Data Set element — `CSVDataSet` appears only in the *import* parser (`jmeter.go:110`, `:137`, `:176-180`) and nowhere in `jmeter_engine.go` or `jmeter_tree.go`. Generated plans therefore run with `${var}` unbound and **nothing warns**. The `variableNames`, `delimiter`, and `recycle` fields the dashboard collects (`PerfLab.jsx:1353-1381`) are stored and round-tripped by the importer only. One narrow exception: a scenario imported from a plan file keeps its original `jmx_xml` verbatim (`jmeter_engine.go:485`, `:542`), so a CSV element already present survives — but it still points at the original author's local path, not `data.csv` | Emit a CSV Data Set element referencing `data.csv` from the plan generators, honour `variableNames` / `delimiter` / `recycle`, and fail or warn on dispatch when a plan contains unbound `${var}` with no dataset bound |
| Richer **action tree** (rendezvous / queue / scripted samplers) | Nested logic beyond ForEach/fragments | Controllers + fragments Done; exotic later | Module-reference path fidelity; scripted samplers stay gated |
| **Real-browser virtual users** | Browser journeys under load | Explicitly out of scope today | New runner image or hybrid engine — large |
| **Recorded browser flows** | Capture a UI journey directly | Absent | Later; overlaps with real-browser VUs |
| **Variables** (secret, counter, random, file-backed CSV UX) | Safer, richer parameterization | Headers only — inline CSV is stored but never bound to the run (row 1) | Variable store + secret refs, on top of dataset binding |
| **Multi-profile** scenarios (mix VUs / locations) | Mixed traffic shapes | One scenario → one journey | Multi-scenario campaign or profiles array |
| **Geo / cloud locations** + IP ranges | Multi-region realism | Single-host Docker | Federation peers ≠ public regions (honesty) |
| Distributed **campaign** scheduler | Multi-host cron orchestration | In-process tick only | Orchestrator job fan-out |
| **Live reporting** sinks (external APM/metrics) | External ops sinks | ClickHouse + OPA only | Optional exporters |
| **Notifications** (webhook, chat, email, issue trackers) | Failures noticed outside dashboard | Webhook + chat + email channels Done, with per-attempt history | Issue-tracker adapters later |
| **Bench report** template builder | Custom widget layouts / branded PDF templates | HTML/PDF + ZIP pack and saved widget/metric/window templates Done; no branded PDF theming | Branded PDF theming later |
| Full **trend** template builder | Saved trend dashboards / widgets | Trends tab widgets + saved trend templates Done; no cross-scenario dashboards | Multi-scenario trend dashboards later |
| CSV / datasets binding | Parameterisation that actually reaches the run | Storage + `data.csv` only; no CSV Data Set in generated plans | Emit CSV Data Set + unbound-`${var}` warning |
| **Infrastructure monitoring** during test | Host/DB health while load runs | Defer to **OPA** | Deep-link OPA infra; do not fork monitors into OPL |
| **On-premise agent** install / capacity | Remote runner capacity | Docker only on lab host | K8s / remote runner backends (Later backlog) |
| **Tool-server interface** for agents | Agent tooling over the lab API | Absent | Optional thin tool server over the OPL REST API |
| CI/CD **setup wizards** | Faster gate adoption | Script/harness only (`harness/perf-gate.sh`, `harness/jmeter-perf-gate.sh`) | Copy-paste snippets in dashboard |
| Workspace **collaboration** polish (tags, copy across projects, markdown descriptions) | Multi-project hygiene | Tenant headers; limited metadata UX | Tags, cross-project copy |
| **Pass criteria** tied to monitoring SLAs | Infra + load gates together | Load SLA only | Keep infra SLOs in OPA |
| Plugin / marketplace fidelity | Exotic JMeter plugins | Hardened JMX subset | Stay fail-closed (`OPA_PERF_ALLOW_UNSAFE_JMX`) |

---

## Different by design

| Topic | Commercial / SaaS grid typical | OPL stance |
|-------|--------------------------------|------------|
| Deployment | SaaS + on-prem enterprise | Self-hosted Open-* family; NAS `*:nas` only |
| Scale story | Cloud regions, millions of VUs | Lab caps (`OPA_PERF_MAX_VUS` / duration); workers on one host; federation ≠ multi-cloud |
| APM | Third-party APM header injection | First-party **OPA** correlation via `load_run_id` |
| Engine surface | Protocol + real-browser hybrid | JMeter-first; k6 script export; real-browser VUs explicitly later |
| Monitoring | Built-in server/DB monitors | Observability is **OPA**; OPL owns load control plane |
| Auth / tenancy | Workspaces, subscriptions, OAuth | Hub JWT + org/project scopes |
| Honesty | Commercial grid marketing | Responses document local-sample / non-cloud limits |
| Unsafe script samplers | Scripted samplers / plugins enabled in product | Blocked unless `OPA_PERF_ALLOW_UNSAFE_JMX` (`OPL-API/harden.go:98-108`) |
| Product split | Monolithic perf platform | OPL scenarios/runs; OPA traces; ORA/OSA/OPM separate |
| Soft-delete | Hard delete in UI | Soft-archive (`archived=1`) + restore (`unarchive`) |

---

## Top 10 missing (load-test lab impact)

Ranked for a team that **designs HTTP/API load tests, runs them in lab, gates CI, and correlates to APM**. Items already **Done** no longer appear here.

| Rank | Gap | Why it hurts a lab | Sibling hint |
|------|-----|--------------------|--------------|
| 1 | **Dataset binding to the executed plan** | Users & data accepts CSV; the run silently ignores it; `${var}` stays literal | Emit CSV Data Set; warn on unbound `${var}` |
| 2 | Distributed **scheduler** | In-process tick is single-host only | Orchestrator cron fan-out |
| 3 | CI/CD **wizards** | Script/harness only slows adoption | Snippets in dashboard |
| 4 | ModuleController path fidelity | Link expands inline; not JMeter ModuleController | Optional ModuleController emit |
| 5 | **Variables** store (secret/counter/random) | Parameterization still thin (blocked behind gap 1) | Variable store + secret refs |
| 6 | Rendezvous / throughput / JSR223 (gated) | Exotic controllers still missing | Extend VU DSL carefully |
| 7 | Workspace collaboration polish | Multi-project hygiene | Tags, cross-project copy |
| 8 | Multi-scenario trend dashboards | Templates are per scenario | Cross-scenario roll-up |
| 9 | Issue-tracker notification adapters | Chat/email/webhook Done; tickets still manual | Tracker adapters over the same event |
| 10 | Geo / multi-host injectors + multi-profile campaigns | Single-host Docker only | Federation ≠ public regions; campaign / profiles array |


**Honorable mentions (high effort or owned elsewhere):** real-browser and recorded-flow VUs; geo cloud
locations; infrastructure monitors (use OPA); agent tool server.

---

## Implementation priority (siblings)

For **OPL-API / OPL-Dashboard** implementers working load lab capabilities:

1. **First:** bind datasets to the executed plan, and warn when a plan has unbound `${var}` and no dataset.
2. **Near-term:** Multi-profile campaigns; variables store; CI wizards; issue-tracker notify adapters.
3. **Flagship track:** Keep JMeter-compatible VU tree as the design destination; HAR/JMX/Postman import remains the on-ramp.
4. Keep **honesty strings** on run/list responses when adding fan-out, locations, or "cloud-like" UX.
5. Do **not** reimplement infrastructure monitoring inside OPL — link OPA (`load_run_id`, infra hosts).
6. NAS / production: rebuild and tag `opl-api:nas` / `opl-dashboard:nas` only; laptop smoke stays local. Always `sync-nas-src` before rebuild.
7. Cross-check [opl-opm-backlog.md](opl-opm-backlog.md) when closing Next items so backlog and this inventory stay aligned.


### Verified merged on `origin/main`

- Notification channels (webhook / chat / email) + per-attempt notification history
- Report and trend template persistence (`opl.report_templates`) applied to exports
- Arrivals-accurate load curve (`curve_mode=arrivals` open-model segments)
- PDF / HTML report + ZIP bench pack; Trends tab widgets + `/trends` API

### Next (this inventory)

- Dataset binding + unbound-variable warning (**highest impact**)
- ModuleController fidelity; variables store; CI wizards
- Issue-tracker notification adapters over the same terminal-run event
- Multi-scenario trend dashboards; distributed scheduler; geo honesty (federation ≠ cloud regions)

### Recently closed (this pass)

- Notification channels beyond the raw webhook (chat + SMTP email) sharing one event/history
- Report / trend template persistence applied via `?template=<id>`
- PDF / HTML report + ZIP bench pack; Trends tab widgets + `/trends` API
- Terminal-run webhook; arrivals-mode load curve (honesty-documented)

---

## Related

- [Products](products.md) — OPL ports `8092` / `8095`
- [OPL + OPM backlog](opl-opm-backlog.md) — Done / Next / Later
- [NAS deploy](nas-deploy.md) — `open-family`, `*:nas`
- OPL-API docs: [perf-lab.md](https://github.com/TheGrimmChester/OPL-API/blob/main/docs/perf-lab.md), [jmeter-perf.md](https://github.com/TheGrimmChester/OPL-API/blob/main/docs/jmeter-perf.md)
