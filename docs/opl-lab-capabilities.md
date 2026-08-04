# OPL load lab capabilities

Implementation guide for **sibling** work in [OPL-API](https://github.com/TheGrimmChester/OPL-API) and [OPL-Dashboard](https://github.com/TheGrimmChester/OPL-Dashboard). Inventories what **Open Perf Lab** ships today, what is still missing for a serious self-hosted load lab, and what OPL deliberately does differently from a commercial multi-cloud load grid.

**Sources (2026-08-04):** OPL-API `docs/perf-lab.md`, `docs/jmeter-perf.md`, load-lab capability routes (`jmeter.go` / `load.go` / `lab_extras.go` / `postman.go`); OPL-Dashboard `PerfLab.jsx` / `VuTree.jsx` / `LoadCurveEditor.jsx`; OPA-Stack [opl-opm-backlog.md](opl-opm-backlog.md).

**NAS spot-check:** `http://192.168.100.101:8092/api/health` → `status=ok`, `service=opl-api`, `auth_mode=codeployed`; `:8095/` → HTTP 200 (OPL dashboard). Production images stay `*:nas` only — never deploy `*:smoke` to NAS. Rebuild after this pass with `sync-nas-src` then `rebuild-nas-images.sh` for `opl-api` / `opl-dashboard`.

---

## How to read this

| Bucket | Meaning |
|--------|---------|
| **Done** | Usable today for a lab workflow (API + typically UI; present on NAS unless noted) |
| **Code-ready** | Implemented on OPL-API `main` (load-lab capability routes / related), but missing Dashboard and/or NAS `:nas` roll-out |
| **Missing** | Expected load-lab capability; OPL does not ship it yet — candidate sibling PRs |
| **Different by design** | Related capability exists, but OPL’s model / honesty boundary differs |

OPL is a **self-hosted load lab** next to OPA, not a SaaS multi-cloud load grid. Gaps ranked for **load-test lab user impact** (design → run → analyze → gate), not for matching enterprise multi-region packaging.

### Flagship: JMeter Visual test case editor

**Aspirational destination:** hierarchical Virtual User tree (drag-and-drop actions, containers, logic, extractors) for building JMeter-compatible journeys **without editing raw JMX**.

**OPL today (Done — deepening):** Design tab is a **VU tree** (HTTP, Transaction, If / While / Loop / ForEach, Fragment + Link, extract, assert) with inspector + HTML5 DnD reorder/nest. Saves nested `steps_json` → JMX hashTrees; import round-trips controllers when parseable. Fragments emit disabled GenericControllers; Link expands by name at JMX emit. HAR/JMX/Postman import remains the on-ramp. Still not full action-tree coverage (rendezvous / JSR223 / ModuleController path fidelity).

---

## Done (shipped lab workflows)

| Capability area | OPL today | Notes / sibling codes |
|-----------------|-----------|------------------------|
| Virtual users / HTTP journeys | Scenario CRUD via upsert; Design VU tree + flat step fallback | `OPL-API` `load.go`, `jmeter_engine.go`; Dashboard Design |
| **JMeter Visual editor (MVP+)** | Nested VU tree → JMX; DnD reorder/nest; If/While/Loop/ForEach; Fragment + Link | `VuTree.jsx`; `appendStepJMXIndexed`; import tree parse |
| HAR → scenario | `POST /api/perf/scenarios/import-har` (+ Capture UI) | Skips private/metadata hosts (URL policy) |
| **Postman collection import** | `POST /api/perf/scenarios/import-postman` (+ Capture UI) | Collection v2/v2.1 → HTTP steps; `{{var}}` → `${var}`; scripts ignored |
| JMeter JMX import / export | `import-jmx`, `export-jmx`, JMX tab; nested controllers when parseable | Best-effort HTTP / timers / extractors / CSV / classic TG + If/While/Loop/ForEach/Txn/Fragment |
| XHR capture import | `import-xhr` / `export-xhr` | Lab-oriented capture interchange |
| Soft-archive + **restore** | API + Dashboard (Show archived + restore) | Soft-delete; `POST .../unarchive`; list `?archived=1` |
| Load policy presets | `GET /api/perf/load-policies` + Run & scale picker | smooth / sustained / stress / custom |
| **Custom load curve** | `schedule.curve` + `curve_mode=vus\|arrivals` | Dashboard `LoadCurveEditor`; VU peak/ramp or arrivals open-model segments |
| **Scheduler UX** | `POST .../schedule` + in-process tick + Run & scale panel | `every_minutes` / `daily_at` UTC; not distributed campaign scheduler |
| **Multi-run history + sparklines** | Scenario-scoped run table (≤25) + p95/error sparklines on Run & scale | Complements two-run Compare |
| CSV / datasets | `datasets_json` → CSVDataSet in generated JMX | Inline CSV in Users & data tab |
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
| Tenant + hub auth | Org/project headers; co-deployed `/hub-auth/` | Hub JWT + org/project scopes |
| CI gate scripts | `harness/perf-gate.sh`, `jmeter-perf-gate.sh`, workflow example | Wizards for Jenkins/GitLab/Azure not ported |
| On-prem execution | Docker JMeter on the Perf Lab host | Lab host workers; not public cloud regions |

---

## Code-ready (ship UI + `:nas`)

Most prior Code-ready items are now Done. Remaining:

| Capability | API | Lab analogue | Sibling follow-up |
|------------|-----|--------------|-------------------|
| PDF bench pack | JSON/CSV report only | Shareable PDF | Report builder later |

---

## Missing (implementation candidates)

| Capability | Why labs need it | OPL gap | Suggested sibling work |
|------------|------------------|---------|------------------------|
| Richer **action tree** (rendezvous/queue/JSR223…) | Nested logic beyond ForEach/fragments | Controllers + fragments Done; exotic later | ModuleController path fidelity; JSR223 gated |
| **Playwright** / real-browser VUs | Browser journeys under load | Explicitly out of scope today | New runner image or hybrid engine — large |
| **WebDriver** / Selenium record | Recorded browser flows | Absent | Later; overlap with Playwright |
| **Variables** (secret, counter, random, file-backed CSV UX) | Safer, richer parameterization | Headers + inline CSV | Variable store + secret refs |
| **Multi-profile** scenarios (mix VUs / locations) | Mixed traffic shapes | One scenario → one journey | Multi-scenario campaign or profiles array |
| **Geo / cloud locations** + IP ranges | Multi-region realism | Single-host Docker | Federation peers ≠ public regions (honesty) |
| Distributed **campaign** scheduler | Multi-host cron orchestration | In-process tick only | Orchestrator job fan-out |
| **Live reporting** sinks (external APM/metrics) | External ops sinks | ClickHouse + OPA only | Optional exporters |
| **Notifications** (email, Slack, Teams, Jira, webhook) | Failures noticed outside dashboard | Webhook on terminal status (`OPL_RUN_WEBHOOK_URL`); email/Slack/Teams later | Extend channels; optional OPA alert bridge |
| **Bench report** builder (widgets, templates, **PDF**) | Shareable offline packs | JSON/CSV report Done | PDF/HTML pack later |
| Full **trend** report builder (widgets, templates) | Sprint-over-sprint regressions | Sparklines + history table Done; no widget builder | CH queries + Trend tab charts |
| **Infrastructure monitoring** during test | Host/DB health while load runs | Defer to **OPA** | Deep-link OPA infra; do not fork monitors into OPL |
| **On-premise agent** install / capacity | Remote runner capacity | Docker only on lab host | K8s / remote runner backends (Later backlog) |
| **MCP server** for agents | Agent tooling over the lab API | No OPL MCP | Optional thin MCP over OPL REST |
| CI/CD **wizards** (Jenkins, GH Actions, GitLab, Azure, Maven) | Faster gate adoption | Script/harness only | Copy-paste snippets in dashboard |
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
| Engine surface | JMeter + Playwright hybrid | JMeter-first; k6 export; Playwright explicitly later |
| Monitoring | Built-in server/DB monitors | Observability is **OPA**; OPL owns load control plane |
| Auth / tenancy | Workspaces, subscriptions, OAuth | Hub JWT + org/project scopes |
| Honesty | Commercial grid marketing | Responses document local-sample / non-cloud limits |
| Unsafe script samplers | JSR223 / plugins in product | Blocked unless `OPA_PERF_ALLOW_UNSAFE_JMX` |
| Product split | Monolithic perf platform | OPL scenarios/runs; OPA traces; ORA/OSA/OPM separate |
| Soft-delete | Hard delete in UI | Soft-archive (`archived=1`) + restore (`unarchive`) |

---

## Top 10 missing (load-test lab impact)

Ranked for a team that **designs HTTP/API load tests, runs them in lab, gates CI, and correlates to APM**. Items already **Done** no longer appear here.

| Rank | Gap | Why it hurts a lab | Sibling hint |
|------|-----|--------------------|--------------|
| 1 | Distributed **scheduler** | In-process tick is single-host only | Orchestrator cron fan-out |
| 2 | CI/CD **wizards** | Script/harness only slows adoption | Snippets in dashboard |
| 3 | ModuleController path fidelity | Link expands inline; not JMeter ModuleController | Optional ModuleController emit |
| 4 | **Variables** store (secret/counter/random) | Parameterization still thin | Variable store + secret refs |
| 5 | Rendezvous / queue / JSR223 (gated) | Exotic controllers still missing | Extend VU DSL carefully |
| 6 | Workspace collaboration polish | Multi-project hygiene | Tags, cross-project copy |
| 7 | Richer notify channels | Webhook Done; ops often want chat/email | Email / chat adapters |
| 8 | Trend/report **templates** | Packs/widgets may exist; no saved layouts | Persist templates |
| 9 | Geo / multi-host injectors | Single-host Docker only | Federation ≠ public regions |
| 10 | Multi-profile campaigns | One scenario → one journey | Campaign / profiles array |

**Honorable mentions (high effort or owned elsewhere):** Playwright/WebDriver VUs; geo cloud locations; infrastructure monitors (use OPA); MCP server.

---

## Implementation priority (siblings)

For **OPL-API / OPL-Dashboard** implementers working load lab capabilities:

1. **Near-term:** Multi-profile campaigns; report/trend templates; richer notify channels.
2. **Flagship track:** Keep JMeter-compatible VU tree as the design destination; HAR/JMX/Postman import remains the on-ramp.
3. Keep **honesty strings** on run/list responses when adding fan-out, locations, or “cloud-like” UX.
4. Do **not** reimplement infrastructure monitoring inside OPL — link OPA (`load_run_id`, infra hosts).
5. NAS / production: rebuild and tag `opl-api:nas` / `opl-dashboard:nas` only; laptop smoke is fine locally. Always `sync-nas-src` before rebuild.
6. Cross-check [opl-opm-backlog.md](opl-opm-backlog.md) when closing Next items so backlog and this inventory stay aligned.

### Recently closed

- Arrivals-accurate load curve (`curve_mode=arrivals` open-model segments)

### Next (this inventory)

- Multi-profile campaigns; ModuleController fidelity; variables store; CI wizards
- Report/trend templates; richer notify channels (webhook Done)
- Distributed scheduler; geo honesty (federation ≠ cloud regions)

---

## Related

- [Products](products.md) — OPL ports `8092` / `8095`
- [OPL + OPM backlog](opl-opm-backlog.md) — Done / Next / Later
- [NAS deploy](nas-deploy.md) — `open-family`, `*:nas`
- OPL-API docs: [perf-lab.md](https://github.com/TheGrimmChester/OPL-API/blob/main/docs/perf-lab.md), [jmeter-perf.md](https://github.com/TheGrimmChester/OPL-API/blob/main/docs/jmeter-perf.md)
