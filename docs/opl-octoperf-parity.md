# OctoPerf → OPL parity inventory

Implementation guide for **sibling** work in [OPL-API](https://github.com/TheGrimmChester/OPL-API) and [OPL-Dashboard](https://github.com/TheGrimmChester/OPL-Dashboard). Maps public [OctoPerf](https://octoperf.com/) capabilities (docs at [api.octoperf.com/doc](https://api.octoperf.com/doc/)) to what **Open Perf Lab** ships, what is still missing, and what OPL deliberately does differently.

**Sources (2026-08-04):** OctoPerf sitemap + design / runtime / analysis / monitoring / MCP docs; OPL-API `docs/perf-lab.md`, `docs/jmeter-perf.md`, `octoperf_parity.go`; OPL-Dashboard `PerfLab.jsx`; OPA-Stack [opl-opm-backlog.md](opl-opm-backlog.md).

**NAS spot-check (optional, same day):** `http://192.168.100.101:8092/api/health` → `status=ok`, `service=opl-api`, `auth_mode=codeployed`; `:8095/` → HTTP 200 (OPL dashboard). `GET /api/perf/load-policies` → **404** on NAS (newer parity routes not in the running `:nas` image yet). Production images stay `*:nas` only — never deploy `*:smoke` to NAS.

---

## How to read this

| Bucket | Meaning |
|--------|---------|
| **Done** | Usable today for a lab workflow (API + typically UI; present on NAS unless noted) |
| **Code-ready** | Implemented on OPL-API `main` (`octoperf_parity.go` / related), but missing Dashboard and/or NAS `:nas` roll-out |
| **Missing** | OctoPerf has it; OPL does not — candidate sibling PRs |
| **Different by design** | Related capability exists, but OPL’s model / honesty boundary differs |

OPL is a **self-hosted load lab** next to OPA, not a SaaS multi-cloud load grid. Gaps ranked for **load-test lab user impact** (design → run → analyze → gate), not for matching OctoPerf enterprise packaging.

---

## Done (parity-ish)

| OctoPerf area | OPL today | Notes / sibling codes |
|---------------|-----------|------------------------|
| Virtual users / HTTP journeys | Scenario CRUD via upsert; Design tab steps (`http`, `think`, `extract`, `assert`, …) | `OPL-API` `load.go`, `jmeter_engine.go`; Dashboard Design |
| HAR → VU | `POST /api/perf/scenarios/import-har` (+ Capture UI) | Skips private/metadata hosts (URL policy) |
| JMeter JMX import / export | `import-jmx`, `export-jmx`, JMX tab | Best-effort HTTP samplers / timers / extractors / CSV / classic thread groups |
| XHR capture import | `import-xhr` / `export-xhr` | Lab-oriented; not an OctoPerf product name |
| Codeless / form designer → JMX | Dashboard builds steps; API stores `jmx_xml` | Users need not author JMeter XML |
| CSV / datasets | `datasets_json` → CSVDataSet in generated JMX | Inline CSV in Users & data tab |
| Extractors / assertions (basic) | Step types `extract`, `assert`; selector metadata (css/xpath/correlate) | Mirrored as JMX where supported; not full OctoPerf action tree |
| Load profiles | `soak` / `spike` / `ramp` + presets (smoke, stress) | Run & scale tab |
| Multi-worker scale (same host) | `workers` / `OPA_JMETER_WORKERS` → N Docker JMeter containers | Same `load_run_id`; not geo locations |
| Run lifecycle | Create, dispatch, cancel, metrics ingest, status | `created` / `running` / `failed` / `cancelled` honesty |
| SLA / pass criteria | Scenario `sla` + `GET .../runs/{id}/gate` (fail-closed) | SLA gates tab; CI harness in OPA-Stack |
| k6 export | `GET .../runs/{id}/export-k6` | OctoPerf focuses on JMeter/Playwright; OPL adds k6 |
| Results KPIs + samples | Results tab; `summary_json` + step samples | Prefer JMeter aggregates over client-posted pass/fail |
| Compare two runs | Compare tab (delta on KPIs) | Simpler than OctoPerf comparison / trend reports |
| APM correlation | `X-OPA-Load-Run-Id` / baggage → OPA Trace Explorer | OctoPerf APM = third-party headers; OPL ↔ OPA is first-party |
| Tenant + hub auth | Org/project headers; co-deployed `/hub-auth/` | Workspace ≠ OctoPerf workspace product |
| CI gate scripts | `harness/perf-gate.sh`, `jmeter-perf-gate.sh`, workflow example | Wizards for Jenkins/GitLab/Azure not ported |
| On-prem execution | Docker JMeter on the Perf Lab host | OctoPerf also offers cloud regions + on-prem agents |

---

## Code-ready (ship UI + `:nas`)

Present on **OPL-API `main`** (`octoperf_parity.go`, `jmeter.go` / `load.go` wiring). **Not** exposed in OPL-Dashboard yet. NAS running image may lag (`load-policies` 404 as of 2026-08-04).

| Capability | API | OctoPerf analogue | Sibling follow-up |
|------------|-----|-------------------|-------------------|
| Soft-archive scenario | `POST\|DELETE .../scenarios/{id}/archive` | Delete VU / scenario | Dashboard confirm + filter archived; rebuild `opl-api:nas` |
| Duplicate scenario | `POST .../scenarios/{id}/duplicate` | Duplicate VU | Dashboard “Duplicate” action |
| Load policy presets | `GET /api/perf/load-policies` (+ resolve on run) | Smooth / Sustained / Stress / Custom labels | Run & scale policy picker; NAS deploy |
| Per-step stats | `GET .../runs/{id}/steps` | Results table / request stats | Results tab table |
| Structured report | `GET .../runs/{id}/report` (`?format=csv`) | Bench report export (JSON/CSV, not PDF) | Download button; PDF still Missing |
| Runner live status | `GET .../runs/{id}/runners` | Injector / LG visibility | Results “workers” panel (docker inspect) |

---

## Missing (implementation candidates)

| OctoPerf capability | Doc anchor | OPL gap | Suggested sibling work |
|---------------------|------------|---------|------------------------|
| **Postman** collection import | `design/create-virtual-user/import-postman-collection` | Absent | `import-postman` → HTTP steps / JMX |
| **Playwright** / real-browser VUs | Playwright import + actions | Explicitly out of scope today | New runner image or hybrid engine — large |
| **WebDriver** / Selenium record | `record-selenium-web-driver` | Absent | Later; overlap with Playwright |
| **VU fragments** + Link actions | Fragments VU type | No shared fragments | Reusable scenario fragments / includes |
| Rich **action tree** (if/while/foreach/rendezvous/queue/JSR223…) | `design/edit-virtual-user/action-types/*` | Flat step list + limited JMX | Extend step DSL or trust raw JMX only |
| **Auto-correlation** studio | `configuration/auto-correlation` | Selector metadata only | Detect dynamic tokens; suggest extractors |
| **Validate VU** triage (functional check before load) | `edit-virtual-user/validation` | `validate` thinner than OctoPerf | Per-step request/response triage UI |
| **Variables** (secret, counter, random, file-backed CSV UX) | `configuration/variables/*` | Headers + inline CSV | Variable store + secret refs |
| **Multi-profile** scenarios (mix VUs / locations) | Advanced scenario | One scenario → one journey | Multi-scenario campaign or profiles array |
| **Geo / cloud locations** + IP ranges | Runtime location + `ip-ranges` | Single-host Docker | Federation peers ≠ public regions (honesty) |
| **Custom load curve** editor (point chart) | Smooth/Sustained/Stress/**Custom** | Preset mapping only (code-ready); no inflexion editor | Timeline points → thread group |
| **Scheduler** / cron / one-shot | `runtime/scheduler` | `schedule_json` stored; no runner | Orchestrator cron + UI |
| **Live reporting** sinks (Datadog, Dynatrace, Influx, …) | Live reporting docs | ClickHouse + OPA only | Optional exporters |
| **Notifications** (email, Slack, Teams, Jira, webhook) | Notifications | None in OPL | Hook OPA alerts or OPL webhooks on terminal status |
| **Bench report** builder (widgets, templates, **PDF**) | Analysis edit-bench-report | JSON/CSV report code-ready | PDF/HTML pack later |
| **Trend** reports (≤25 results) | `analysis/trend-bench-results` | Two-run compare only | Trend over N runs in CH |
| **JTL import** for offline analysis | `analysis/import-jtl` | Engine writes JTL internally | `import-jtl` → samples + summary |
| **Infrastructure monitoring** during test | Monitoring connections | Defer to **OPA** | Deep-link OPA infra; do not fork monitors into OPL |
| **On-premise agent** install / capacity | `on-premise-agent` / infra | Docker only on lab host | K8s / remote runner backends (Later backlog) |
| **MCP server** (~150 tools) for agents | `mcp/` | No OPL MCP | Optional thin MCP over OPL REST |
| CI/CD **wizards** (Jenkins, GH Actions, GitLab, Azure, Maven) | Runtime CI/CD | Script/harness only | Copy-paste snippets in dashboard |
| Workspace **collaboration** polish (tags, copy across projects, markdown descriptions) | Design copy / metadata | Tenant headers; limited metadata UX | Tags, cross-project copy |
| **Pass criteria** tied to monitoring SLAs | Pass criteria step | Load SLA only | Keep infra SLOs in OPA |
| Plugin / marketplace fidelity | Plugins usage | Hardened JMX subset | Stay fail-closed (`OPA_PERF_ALLOW_UNSAFE_JMX`) |

---

## Different by design

| Topic | OctoPerf | OPL stance |
|-------|----------|------------|
| Deployment | SaaS + on-prem enterprise | Self-hosted Open-* family; NAS `*:nas` only |
| Scale story | Cloud regions, millions of VUs | Lab caps (`OPA_PERF_MAX_VUS` / duration); workers on one host; federation ≠ multi-cloud |
| APM | Third-party APM header injection | First-party **OPA** correlation via `load_run_id` |
| Engine surface | JMeter + Playwright hybrid | JMeter-first; k6 export; Playwright explicitly later |
| Monitoring | Built-in server/DB monitors | Observability is **OPA**; OPL owns load control plane |
| Auth / tenancy | Workspaces, subscriptions, OAuth MCP | Hub JWT + org/project scopes |
| Honesty | Commercial grid marketing | Responses document local-sample / non-cloud limits |
| Unsafe script samplers | JSR223 / plugins in product | Blocked unless `OPA_PERF_ALLOW_UNSAFE_JMX` |
| Product split | Monolithic perf platform | OPL scenarios/runs; OPA traces; ORA/OSA/OPM separate |
| Soft-delete | Hard delete in UI | Soft-archive (`archived=1`) when shipped; restore not implemented |

---

## Top 10 missing (load-test lab impact)

Ranked for a team that **designs HTTP/API load tests, runs them in lab, gates CI, and correlates to APM** — not for matching SaaS geo scale. Items already **code-ready** still count until Dashboard + NAS `:nas` make them usable.

| Rank | Gap | Why it hurts a lab | Sibling hint |
|------|-----|--------------------|--------------|
| 1 | **Archive/delete end-to-end** | Lab clutter; API soft-archive on `main` but no UI / may lag NAS | Dashboard + `opl-api:nas` roll-out |
| 2 | **Scheduler / cron runs** | Manual click-to-run blocks nightly soak & regression | Orchestrator job + `schedule_json` consumer |
| 3 | **Custom / visual load policy** | Presets ≠ realistic arrival curves; point editor absent | Timeline JSON → JMeter; expose `load-policies` in UI |
| 4 | **VU validation triage (pre-load)** | Broken correlation burns engine minutes | Expand validate + per-step RR UI |
| 5 | **Auto-correlation assistance** | Dynamic tokens are the #1 replay failure mode | Suggest extractors from HAR/validate |
| 6 | **Postman import** | Common API collections never enter the lab | Map Postman → steps/JMX |
| 7 | **Trend / multi-run history** | Two-run compare hides regressions over a sprint | CH queries + Compare/Trend tab |
| 8 | **Terminal-run notifications** | Failures unnoticed outside the dashboard | Webhook/Slack on `failed` / gate fail |
| 9 | **Runner live status in UI** | API `/runners` on `main`; operators still stare at “running” | Results workers panel + `:nas` |
| 10 | **Report export + JTL import** | Shareable artifacts / offline JMeter; PDF still out | Wire `/report` download; add `import-jtl` |

**Honorable mentions (high effort or owned elsewhere):** Playwright/WebDriver VUs; geo cloud locations; full action-tree parity; OctoPerf-style infrastructure monitors (use OPA); MCP server; multi-profile geo campaigns.

---

## Implementation guidance (siblings)

1. Prefer **closing Code-ready → Done** (archive, duplicate, policies, steps, report, runners) before large Missing items — smallest path to OctoPerf-familiar lab UX.
2. Then Top 10 **#2–#5** (scheduler, custom curve, validate triage, auto-correlation).
3. Keep **honesty strings** on run/list responses when adding fan-out, locations, or “cloud-like” UX.
4. Do **not** reimplement OctoPerf monitoring inside OPL — link OPA (`load_run_id`, infra hosts).
5. NAS / production: rebuild and tag `opl-api:nas` / `opl-dashboard:nas` only; laptop smoke is fine locally.
6. Cross-check [opl-opm-backlog.md](opl-opm-backlog.md) when closing Next items so backlog and this inventory stay aligned (backlog “upsert-only delete” / “runner live status” should flip once Code-ready ships to NAS + UI).

---

## Related

- [Products](products.md) — OPL ports `8092` / `8095`
- [OPL + OPM backlog](opl-opm-backlog.md) — Done / Next / Later
- [NAS deploy](nas-deploy.md) — `open-family`, `*:nas`
- OPL-API docs: [perf-lab.md](https://github.com/TheGrimmChester/OPL-API/blob/main/docs/perf-lab.md), [jmeter-perf.md](https://github.com/TheGrimmChester/OPL-API/blob/main/docs/jmeter-perf.md)
- OctoPerf: [What is OctoPerf?](https://octoperf.com/what-is-octoperf/), [Documentation](https://api.octoperf.com/doc/), [MCP](https://api.octoperf.com/doc/mcp/)
