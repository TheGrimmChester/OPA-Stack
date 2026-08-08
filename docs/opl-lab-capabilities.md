# OPL load lab capabilities

Implementation guide for **sibling** work in [OPL-API](https://github.com/TheGrimmChester/OPL-API) and [OPL-Dashboard](https://github.com/TheGrimmChester/OPL-Dashboard). Inventories what **Open Perf Lab** ships today, what is still missing for a serious self-hosted load lab, and what OPL deliberately does differently from a commercial multi-cloud load grid.

**Sources (2026-08-04):** OPL-API `docs/perf-lab.md`, `docs/jmeter-perf.md`, load-lab capability routes (`jmeter.go` / `load.go` / `lab_extras.go` / `postman.go`); OPL-Dashboard `PerfLab.jsx` / `VuTree.jsx` / `LoadCurveEditor.jsx`; OPA-Stack [opl-opm-backlog.md](opl-opm-backlog.md).

**Refs judged:** OPL-API `origin/main` @ `3cff6ee`, OPL-Dashboard `origin/main` @ `cd91121`. Status is judged
against `origin/main`, never the local checkout — these repos are often checked out on a feature branch based on
an older `main`.

> **Deployment verification is not part of this pass.** `opl-api` `:8092` and `opl-dashboard` `:8095` answer
> their health/index routes, but the API reports an unversioned build id (`perf-lab-dev`) with no commit
> identity, and capability routes need an operator token this pass does not hold. A behaviour observed on the
> deployed stack could not be attributed to a particular `origin/main` anyway, so nothing below is claimed as
> verified on the deployed stack. Production images stay `*:nas` only — never deploy `*:smoke` to NAS.

> **Search caveat.** A command hook in this environment rewrites `git diff`, `grep`, and `rg` output, so an
> empty result can be a tool artifact rather than a fact. Every negative below was taken with `rtk proxy rg` /
> `rtk proxy git grep` carrying a **positive control that fired in the same command**, or by reading the whole
> file from the `origin/main` blob.

---

## How to read this

| Bucket | Meaning |
|--------|---------|
| **Done** | Present on `origin/main`, verified at the file:line cited in Notes |
| **On a branch, not merged** | Implemented on a named unmerged branch; absent from `origin/main` |
| **Missing** | Expected load-lab capability; OPL does not ship it yet — candidate sibling PRs |
| **Different by design** | Related capability exists, but OPL’s model / honesty boundary differs |

OPL is a **self-hosted load lab** next to OPA, not a SaaS multi-cloud load grid. Gaps ranked for **load-test lab user impact** (design → run → analyze → gate), not for matching enterprise multi-region packaging.

### Flagship: JMeter Visual test case editor

**Aspirational destination:** hierarchical Virtual User tree (drag-and-drop actions, containers, logic, extractors) for building JMeter-compatible journeys **without editing raw JMX**.

**OPL today (Done — deepening):** Design tab is a **VU tree** (HTTP, Transaction, If / While / Loop / ForEach, Fragment + Link, extract, assert) with inspector + HTML5 DnD reorder/nest. Saves nested `steps_json` → JMX hashTrees; import round-trips controllers when parseable. Fragments emit disabled generic controllers; Link expands by name at JMX emit. Capture and plan-file import remain the on-ramp. One honest limit remains: the action tree does not cover rendezvous, scripted samplers, or module-reference path fidelity. Datasets **do** bind now — a `${var}` in a step is fed by the CSV in the Users & data tab (see the CSV datasets row under **Done**).

---

## Done (shipped lab workflows)

| Capability area | OPL today | Notes / sibling codes |
|-----------------|-----------|------------------------|
| Virtual users / HTTP journeys | Scenario CRUD via upsert; Design VU tree + flat step fallback | `OPL-API` `load.go`, `jmeter_engine.go`; Dashboard Design |
| **JMeter Visual editor (MVP+)** | Nested VU tree → JMX; DnD reorder/nest; If/While/Loop/ForEach; Fragment + Link | `VuTree.jsx`; `appendStepJMXIndexed`; import tree parse |
| HAR → scenario | `POST /api/perf/scenarios/import-har` (+ Capture UI) | Lab/private hosts kept on import with warnings; cloud metadata still skipped; validate/dispatch still needs `OPA_PERF_INTERNAL_HOSTS` |
| **Collection import** | `POST /api/perf/scenarios/import-postman` (+ Capture UI) | `postman.go:15`; collection v2/v2.1 → HTTP steps; `{{var}}` → `${var}`, which a CSV dataset can now bind at run time; scripts ignored |
| JMeter JMX import / export | `import-jmx`, `export-jmx`, JMX tab; nested controllers when parseable | Best-effort HTTP / timers / extractors / CSV / classic TG + If/While/Loop/ForEach/Txn/Fragment |
| XHR capture import | `import-xhr` / `export-xhr` | Lab-oriented capture interchange |
| Soft-archive + **restore** | API + Dashboard (Show archived + restore) | Soft-delete; `POST .../unarchive`; list `?archived=1` |
| Load policy presets | `GET /api/perf/load-policies` + Run & scale picker | smooth / sustained / stress / custom |
| **Custom load curve** | `schedule.curve` + `curve_mode=vus\|arrivals` | Dashboard `LoadCurveEditor`; VU peak/ramp or arrivals open-model segments |
| **Scheduler UX** | `POST .../schedule` + in-process tick + Run & scale panel | `every_minutes` / `daily_at` UTC; not distributed campaign scheduler |
| **Multi-run history + sparklines** | Scenario-scoped run table (≤25) + p95/error sparklines on Run & scale | Complements two-run Compare |
| **Trend report widgets** | Trends tab: latency band (p50/p95/p99), error bars, best/worst/SLA breach KPIs; `GET .../scenarios/{id}/trends` | Beyond sparklines; widget/metric/window selection now comes from a saved template |
| **PDF / bench pack** | `report?format=html|pdf` + `bench-pack` ZIP (JSON+CSV+HTML+PDF) | Offline shareable pack from Results; `?template=<id>` applies a saved layout |
| **Report / trend templates** | `opl.report_templates` + `/api/perf/report-templates` CRUD; picker + editor on Results and Trends | Named org/project-scoped layouts (widgets / metrics / window); unknown names dropped on save |
| **Notification channels** | webhook + chat incoming-webhook + SMTP email over one terminal-run event; `OPL_RUN_NOTIFY_CHANNELS` / `_MODE` / `_STATUSES` | Unconfigured channels are reported in health and history, never silently dropped |
| **Notification history** | `opl.run_notifications` + `/api/perf/notifications` (+ per-run); Notification channels/history panels | One row per channel attempt: `sent` / `failed` / `logged` / `skipped` with the plain reason |
| **CSV datasets bound to the plan** | Inline CSV is written to `data.csv` **and** the generated plan carries a matching CSV Data Set element, so `${var}` resolves at run time | `jmeter_datasets.go:47` (`perfCSVDataset`), `:66` (parse), `:317` (`writeJMXCSVDataSet`), `:378` (`syncJMXCSVDataSet` back-fills stored/imported plans); generators take the dataset at `jmeter_engine.go:32`, `:71`, `:110`; dispatch wires it at `:547`, `:559`, `:589`. Honours `variableNames`, `delimiter`, `recycle`, `stop_thread`, `share_mode`, `quoted`, `ignore_first_line`, `encoding`, and reports parse problems as `warnings` (`jmeter_datasets.go:94-166`, surfaced at `:298`) plus `dataset_injected` on dispatch (`jmeter_engine.go:718`) |
| Extractors / assertions (basic) | Nested under HTTP in VU tree | Mirrored as JMX where supported |
| **Validate triage + auto-correlation** | `validate` returns `triage[]` + `correlation_suggestions[]`; UI Apply extract | Token/CSRF/Bearer heuristics from body_preview |
| Load profiles | `soak` / `spike` / `ramp` + presets | Run & scale tab |
| Multi-worker scale (same host) | `workers` / `OPA_JMETER_WORKERS` → N Docker JMeter containers | Same `load_run_id`; not geo locations |
| Run lifecycle | Create, dispatch, cancel, metrics ingest, status | `created` / `running` / `failed` / `cancelled` honesty |
| SLA / pass criteria | Scenario `sla` + `GET .../runs/{id}/gate` (fail-closed) | SLA gates tab; CI harness in OPA-Stack |
| k6 export | `GET .../runs/{id}/export-k6` | OPL adds k6 export alongside JMeter |
| Results KPIs + samples | Results tab; `summary_json` + step samples | Prefer JMeter aggregates over client-posted pass/fail |
| Per-step stats / report / runners | Results tab wiring | `/steps`, `/report`, `/runners` |
| **JTL import** | `POST /api/perf/runs/import-jtl` + Results UI upload | Offline analysis path |
| Compare two runs | Compare tab (delta on KPIs) | Simpler than full trend report builder |
| APM correlation | `X-OPA-Load-Run-Id` / baggage → OPA Trace Explorer | First-party OPL ↔ OPA correlation |
| Tenant + OAM auth | Org/project headers; co-deployed `/oam-auth/` (`iss=oam-api`) | OAM JWT + org/project scopes |
| CI gate scripts | `harness/perf-gate.sh`, `harness/jmeter-perf-gate.sh`, workflow example | Scripts only; no per-CI-vendor setup wizards |
| On-prem execution | Docker JMeter on the Perf Lab host | Lab host workers; not public cloud regions |

---

## On a branch, not merged

Nothing in this inventory is currently waiting on a branch. The notification-channel and report/trend-template
work merged into both OPL repos during this review (`OPL-API` `origin/main` @ `1f1a0ff`, `OPL-Dashboard` @
`a196057` are the merge commits) and has moved to **Done** / **Missing** rows accordingly.

---

## Missing (implementation candidates)

| Capability | Why labs need it | OPL gap | Suggested sibling work |
|------------|------------------|---------|------------------------|
| Richer **action tree** (rendezvous / queue / scripted samplers) | Nested logic beyond ForEach/fragments | Controllers + fragments Done; exotic later | Module-reference path fidelity; scripted samplers stay gated |
| **Real-browser virtual users** | Browser journeys under load | Explicitly out of scope today | New runner image or hybrid engine — large |
| **Recorded browser flows** | Capture a UI journey directly | Absent | Later; overlaps with real-browser VUs |
| **Variables** (secret, counter, random) | Safer, richer parameterization | CSV datasets bind to the plan now; there is still no secret store, counter, or random generator | Variable store + secret refs |
| **Multi-profile** scenarios (mix VUs / locations) | Mixed traffic shapes | One scenario → one journey | Multi-scenario campaign or profiles array |
| **Geo / cloud locations** + IP ranges | Multi-region realism | Single-host Docker | Federation peers ≠ public regions (honesty) |
| Distributed **campaign** scheduler | Multi-host cron orchestration | In-process tick only | Orchestrator job fan-out |
| **Live reporting** sinks (external APM/metrics) | External ops sinks | ClickHouse + OPA only | Optional exporters |
| **Notifications** (webhook, chat, email, issue trackers) | Failures noticed outside dashboard | Webhook + chat + email channels Done, with per-attempt history | Issue-tracker adapters later |
| **Bench report** template builder | Custom widget layouts / branded PDF templates | HTML/PDF + ZIP pack and saved widget/metric/window templates Done; no branded PDF theming | Branded PDF theming later |
| Full **trend** template builder | Saved trend dashboards / widgets | Trends tab widgets + saved trend templates Done; no cross-scenario dashboards | Multi-scenario trend dashboards later |
| **Infrastructure monitoring** during test | Host/DB health while load runs | Defer to **OPA** | Deep-link OPA infra; do not fork monitors into OPL |
| **On-premise agent** install / capacity | Remote runner capacity | Docker only on lab host | K8s / remote runner backends (Later backlog) |
| **Tool-server interface** for agents | Agent tooling over the lab API | Absent | Optional thin tool server over the OPL REST API |
| CI/CD **setup wizards** | Faster gate adoption | Scripts only (`harness/perf-gate.sh`, `harness/jmeter-perf-gate.sh`) | Copy-paste snippets in dashboard |
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
| 1 | Distributed **scheduler** | In-process tick is single-host only | Orchestrator cron fan-out |
| 2 | CI/CD **setup wizards** | Scripts only, which slows adoption | Snippets in dashboard |
| 3 | Module-reference path fidelity | Link expands inline rather than as a module reference | Optional module-reference emit |
| 4 | **Variables** store (secret/counter/random) | CSV datasets bind now; secrets/counters/random still absent | Variable store + secret refs |
| 5 | Rendezvous / queue / scripted samplers (gated) | Exotic controllers still missing | Extend VU DSL carefully |
| 7 | Workspace collaboration polish | Multi-project hygiene | Tags, cross-project copy |
| 8 | Multi-scenario trend dashboards | Templates are per scenario | Cross-scenario roll-up |
| 9 | Issue-tracker notification adapters | Chat/email/webhook Done; tickets still manual | Tracker adapters over the same event |
| 10 | Geo / multi-host injectors + multi-profile campaigns | Single-host containers only; one scenario → one journey | Federation ≠ public regions; campaign / profiles array |

**Honorable mentions (high effort or owned elsewhere):** real-browser and recorded-flow VUs; geo cloud locations; infrastructure monitors (use OPA); agent tool server.

---

## Implementation priority (siblings)

For **OPL-API / OPL-Dashboard** implementers working load lab capabilities:

1. **Near-term:** multi-profile campaigns; a variables store for secrets/counters/random values on top of the
   CSV dataset binding that now ships; CI setup wizards.
2. **Flagship track:** Keep the JMeter-compatible VU tree as the design destination; capture and plan-file import remain the on-ramp.
3. Keep **honesty strings** on run/list responses when adding fan-out, locations, or “cloud-like” UX.
4. Do **not** reimplement infrastructure monitoring inside OPL — link OPA (`load_run_id`, infra hosts).
5. NAS / production: rebuild and tag `opl-api:nas` / `opl-dashboard:nas` only; laptop smoke is fine locally. Always `sync-nas-src` before rebuild.
6. Cross-check [opl-opm-backlog.md](opl-opm-backlog.md) when closing Next items so backlog and this inventory stay aligned.

### Verified merged on `origin/main`

- CSV dataset binding: generated plans now carry a CSV Data Set element matching the written `data.csv`, with
  per-scenario delimiter/recycle/share-mode/quoting and parse `warnings` (`jmeter_datasets.go`)
- Notification channels (webhook / chat / email) + per-attempt notification history (`run_notify.go`, `run_notify_history.go`)
- Report and trend template persistence (`report_templates.go`, `opl.report_templates`) applied to exports
- PDF / HTML report + ZIP bench pack (`report_export.go:143`, `:209`, `:330`; route `load.go:478`)
- Trends API + Trends tab widgets (`report_export.go:382`; `jmeter.go:69`; `TrendBandChart.jsx`, `TrendErrorBars.jsx`)
- Arrivals-accurate load curve (`curve_mode=arrivals` open-model segments, `jmeter_engine.go:502-541`)

### Next (this inventory)

- Module-reference fidelity; variables store (secrets/counters/random); CI setup wizards
- Issue-tracker notification adapters over the same terminal-run event
- Multi-scenario trend dashboards; distributed scheduler; geo honesty (federation ≠ cloud regions)

### Recently closed (this pass)

- Notification channels beyond the raw webhook (chat incoming-webhook + SMTP email) sharing one event, one mode/status filter and one history
- Report / trend template persistence in `opl.report_templates`, applied to `report`, `bench-pack` and `trends` via `?template=<id>`
- PDF / HTML report + ZIP bench pack; Trends tab widgets + `/trends` API
- Terminal-run webhook; arrivals-mode load curve (honesty-documented)

---

## Related

- [Products](products.md) — OPL ports `8092` / `8095`
- [OPL + OPM backlog](opl-opm-backlog.md) — Done / Next / Later
- [NAS deploy](nas-deploy.md) — `open-family`, `*:nas`
- OPL-API docs: [perf-lab.md](https://github.com/TheGrimmChester/OPL-API/blob/main/docs/perf-lab.md), [jmeter-perf.md](https://github.com/TheGrimmChester/OPL-API/blob/main/docs/jmeter-perf.md)
