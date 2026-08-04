# OPL load lab capabilities

Implementation guide for **sibling** work in [OPL-API](https://github.com/TheGrimmChester/OPL-API) and [OPL-Dashboard](https://github.com/TheGrimmChester/OPL-Dashboard). Inventories what **Open Perf Lab** ships today, what is still missing for a serious self-hosted load lab, and what OPL deliberately does differently from a commercial multi-cloud load grid.

**Sources (2026-08-04):** OPL-API `docs/perf-lab.md`, `docs/jmeter-perf.md`, load-lab capability routes (`jmeter.go` / `load.go` / `lab_extras.go`); OPL-Dashboard `PerfLab.jsx` / `VuTree.jsx` / `LoadCurveEditor.jsx`; OPA-Stack [opl-opm-backlog.md](opl-opm-backlog.md).

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

**OPL today (Done — deepening):** Design tab is a **VU tree** (HTTP, Transaction, If / While / Loop, extract, assert) with inspector + HTML5 DnD reorder/nest. Saves nested `steps_json` → JMX hashTrees; import round-trips controllers when parseable. Flat form-only is no longer the only path; HAR/JMX import remains the on-ramp. Still not full action-tree coverage (foreach / rendezvous / JSR223 / fragments).

---

## Done (shipped lab workflows)

| Capability area | OPL today | Notes / sibling codes |
|-----------------|-----------|------------------------|
| Virtual users / HTTP journeys | Scenario CRUD via upsert; Design VU tree + flat step fallback | `OPL-API` `load.go`, `jmeter_engine.go`; Dashboard Design |
| **JMeter Visual editor (MVP+)** | Nested VU tree → JMX; DnD reorder/nest; If/While/Loop controllers | `VuTree.jsx`; `appendStepJMXIndent`; import tree parse |
| HAR → scenario | `POST /api/perf/scenarios/import-har` (+ Capture UI) | Skips private/metadata hosts (URL policy) |
| JMeter JMX import / export | `import-jmx`, `export-jmx`, JMX tab; nested controllers when parseable | Best-effort HTTP / timers / extractors / CSV / classic TG + If/While/Loop/Txn |
| XHR capture import | `import-xhr` / `export-xhr` | Lab-oriented capture interchange |
| Soft-archive + duplicate | API + Dashboard actions | Soft-delete; restore still Missing |
| Load policy presets | `GET /api/perf/load-policies` + Run & scale picker | smooth / sustained / stress / custom |
| **Custom load curve** | `schedule.curve` points → peak VUs / duration / ramp | Dashboard `LoadCurveEditor`; ThreadGroup honesty |
| **Scheduler UX** | `POST .../schedule` + in-process tick + Run & scale panel | `every_minutes` / `daily_at` UTC; not distributed campaign scheduler |
| **Multi-run history** | Scenario-scoped run table (≤25) on Run & scale | Complements two-run Compare |
| CSV / datasets | `datasets_json` → CSVDataSet in generated JMX | Inline CSV in Users & data tab |
| Extractors / assertions (basic) | Nested under HTTP in VU tree | Mirrored as JMX where supported |
| Load profiles | `soak` / `spike` / `ramp` + presets | Run & scale tab |
| Multi-worker scale (same host) | `workers` / `OPA_JMETER_WORKERS` → N Docker JMeter containers | Same `load_run_id`; not geo locations |
| Run lifecycle | Create, dispatch, cancel, metrics ingest, status | `created` / `running` / `failed` / `cancelled` honesty |
| SLA / pass criteria | Scenario `sla` + `GET .../runs/{id}/gate` (fail-closed) | SLA gates tab; CI harness in OPA-Stack |
| k6 export | `GET .../runs/{id}/export-k6` | OPL adds k6 export alongside JMeter |
| Results KPIs + samples | Results tab; `summary_json` + step samples | Prefer JMeter aggregates over client-posted pass/fail |
| Per-step stats / report / runners | Results tab wiring | `/steps`, `/report`, `/runners` |
| JTL import | `POST /api/perf/runs/import-jtl` | Offline analysis path |
| Compare two runs | Compare tab (delta on KPIs) | Simpler than full trend report builder |
| APM correlation | `X-OPA-Load-Run-Id` / baggage → OPA Trace Explorer | First-party OPL ↔ OPA correlation |
| Tenant + hub auth | Org/project headers; co-deployed `/hub-auth/` | Hub JWT + org/project scopes |
| CI gate scripts | `harness/perf-gate.sh`, `jmeter-perf-gate.sh`, workflow example | Wizards for Jenkins/GitLab/Azure not ported |
| On-prem execution | Docker JMeter on the Perf Lab host | Lab host workers; not public cloud regions |

---

## Code-ready (ship UI + `:nas`)

Most prior Code-ready items are now Done (archive/duplicate/policies/steps/report/runners/curve/scheduler). Remaining:

| Capability | API | Lab analogue | Sibling follow-up |
|------------|-----|--------------|-------------------|
| Restore archived scenario | Soft-archive only (`archived=1`) | Undelete | `POST .../unarchive` + UI filter |
| PDF bench pack | JSON/CSV report only | Shareable PDF | Report builder later |

---

## Missing (implementation candidates)

| Capability | Why labs need it | OPL gap | Suggested sibling work |
|------------|------------------|---------|------------------------|
| Richer **action tree** (foreach/rendezvous/queue/JSR223…) | Nested logic beyond If/While/Loop | Controllers MVP only | Extend VU DSL + JMX emit |
| **VU fragments** + Link actions | Reuse shared journey pieces | No shared fragments | Reusable scenario fragments / includes |
| **Postman** collection import | Common API collections enter the lab | Absent | `import-postman` → HTTP steps / JMX |
| **Playwright** / real-browser VUs | Browser journeys under load | Explicitly out of scope today | New runner image or hybrid engine — large |
| **WebDriver** / Selenium record | Recorded browser flows | Absent | Later; overlap with Playwright |
| **Auto-correlation** studio | Dynamic tokens are the #1 replay failure | Selector metadata only | Detect dynamic tokens; suggest extractors |
| **Validate VU** triage (deeper) | Catch broken correlation before engine minutes burn | `validate` + triage exists; UI still light | Per-step request/response triage polish |
| **Variables** (secret, counter, random, file-backed CSV UX) | Safer, richer parameterization | Headers + inline CSV | Variable store + secret refs |
| **Multi-profile** scenarios (mix VUs / locations) | Mixed traffic shapes | One scenario → one journey | Multi-scenario campaign or profiles array |
| **Geo / cloud locations** + IP ranges | Multi-region realism | Single-host Docker | Federation peers ≠ public regions (honesty) |
| Arrivals-accurate **load curve** injectors | Point-accurate arrival rates | ThreadGroup peak/ramp/duration approximation | Optional plugin path — honesty first |
| Distributed **campaign** scheduler | Multi-host cron orchestration | In-process tick only | Orchestrator job fan-out |
| **Live reporting** sinks (external APM/metrics) | External ops sinks | ClickHouse + OPA only | Optional exporters |
| **Notifications** (email, Slack, Teams, Jira, webhook) | Failures noticed outside dashboard | None in OPL | Hook OPA alerts or OPL webhooks on terminal status |
| **Bench report** builder (widgets, templates, **PDF**) | Shareable offline packs | JSON/CSV report Done | PDF/HTML pack later |
| Full **trend** report builder (charts, ≤25 UI polish) | Sprint-over-sprint regressions | Multi-run history table Done; no chart builder | CH queries + Trend tab charts |
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
| Soft-delete | Hard delete in UI | Soft-archive (`archived=1`) when shipped; restore not implemented |

---

## Top 10 missing (load-test lab impact)

Ranked for a team that **designs HTTP/API load tests, runs them in lab, gates CI, and correlates to APM**. Items already **Done** no longer appear here.

| Rank | Gap | Why it hurts a lab | Sibling hint |
|------|-----|--------------------|--------------|
| 1 | Richer **action tree** / fragments | If/While/Loop MVP still blocks complex journeys | foreach, fragments, link actions on VU tree |
| 2 | **VU validation triage** polish | Broken correlation burns engine minutes | Expand per-step RR UI on validate |
| 3 | **Auto-correlation** assistance | Dynamic tokens are the #1 replay failure mode | Suggest extractors from HAR/validate |
| 4 | **Postman** import | Common API collections never enter the lab | Map collection → steps/JMX |
| 5 | Arrivals-accurate **curve** / multi-profile | ThreadGroup approximation ≠ realistic arrivals | Honesty-preserving injector path |
| 6 | **Notifications** on terminal runs | Failures unnoticed outside the dashboard | Webhook on `failed` / gate fail |
| 7 | **Trend** chart builder | History table lacks visual regression view | CH + spark/trend charts |
| 8 | **PDF / bench pack** | Shareable offline artifacts incomplete | HTML/PDF from `/report` |
| 9 | Distributed **scheduler** | In-process tick is single-host only | Orchestrator cron fan-out |
| 10 | CI/CD **wizards** | Script/harness only slows adoption | Snippets in dashboard |

**Honorable mentions (high effort or owned elsewhere):** Playwright/WebDriver VUs; geo cloud locations; infrastructure monitors (use OPA); MCP server; restore archived scenarios.

---

## Implementation priority (siblings)

For **OPL-API / OPL-Dashboard** implementers working load lab capabilities:

1. **Near-term:** Grow visual editor action coverage (fragments, foreach) and validate triage polish.
2. **Flagship track:** Keep JMeter-compatible VU tree as the design destination; HAR/JMX import remains the on-ramp.
3. Then Top 10 **#3–#6** (auto-correlation, Postman, arrivals curve honesty, notifications).
4. Keep **honesty strings** on run/list responses when adding fan-out, locations, or “cloud-like” UX.
5. Do **not** reimplement infrastructure monitoring inside OPL — link OPA (`load_run_id`, infra hosts).
6. NAS / production: rebuild and tag `opl-api:nas` / `opl-dashboard:nas` only; laptop smoke is fine locally. Always `sync-nas-src` before rebuild.
7. Cross-check [opl-opm-backlog.md](opl-opm-backlog.md) when closing Next items so backlog and this inventory stay aligned.

### Next (this inventory)

- Action-tree depth beyond If/While/Loop (fragments, foreach)
- Validate triage UI polish + auto-correlation studio
- Postman import; notifications; trend charts; PDF pack
- Restore archived scenarios; arrivals-accurate curve (optional, honesty-first)

---

## Related

- [Products](products.md) — OPL ports `8092` / `8095`
- [OPL + OPM backlog](opl-opm-backlog.md) — Done / Next / Later
- [NAS deploy](nas-deploy.md) — `open-family`, `*:nas`
- OPL-API docs: [perf-lab.md](https://github.com/TheGrimmChester/OPL-API/blob/main/docs/perf-lab.md), [jmeter-perf.md](https://github.com/TheGrimmChester/OPL-API/blob/main/docs/jmeter-perf.md)
