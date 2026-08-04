# OPL load lab capabilities

Implementation guide for **sibling** work in [OPL-API](https://github.com/TheGrimmChester/OPL-API) and [OPL-Dashboard](https://github.com/TheGrimmChester/OPL-Dashboard). Inventories what **Open Perf Lab** ships today, what is still missing for a serious self-hosted load lab, and what OPL deliberately does differently from a commercial multi-cloud load grid.

**Sources (2026-08-04):** OPL-API `docs/perf-lab.md`, `docs/jmeter-perf.md`, load-lab capability routes (`jmeter.go` / `load.go` and related); OPL-Dashboard `PerfLab.jsx`; OPA-Stack [opl-opm-backlog.md](opl-opm-backlog.md).

**NAS spot-check (optional, same day):** `http://192.168.100.101:8092/api/health` → `status=ok`, `service=opl-api`, `auth_mode=codeployed`; `:8095/` → HTTP 200 (OPL dashboard). `GET /api/perf/load-policies` → **404** on NAS (newer capability routes not in the running `:nas` image yet). Production images stay `*:nas` only — never deploy `*:smoke` to NAS.

---

## How to read this

| Bucket | Meaning |
|--------|---------|
| **Done** | Usable today for a lab workflow (API + typically UI; present on NAS unless noted) |
| **Code-ready** | Implemented on OPL-API `main` (load-lab capability routes / related), but missing Dashboard and/or NAS `:nas` roll-out |
| **Missing** | Expected load-lab capability; OPL does not ship it yet — candidate sibling PRs |
| **Different by design** | Related capability exists, but OPL’s model / honesty boundary differs |

OPL is a **self-hosted load lab** next to OPA, not a SaaS multi-cloud load grid. Gaps ranked for **load-test lab user impact** (design → run → analyze → gate), not for matching enterprise multi-region packaging.

### Flagship gap: JMeter Visual test case editor

The **most advanced design capability** a JMeter-first load lab should offer is a **JMeter Visual test case editor** — a hierarchical Virtual User tree (drag-and-drop actions, containers, logic, extractors, search/replace) for building JMeter-compatible journeys **without editing raw JMX**.

**OPL today:** Design tab is a **flat form step list** (`http` / `think` / `extract` / `assert` / `transaction`) that generates JMX on save, plus **HAR/XHR/JMX import** and a raw **JMX** tab. That is codeless enough for simple HTTP labs, but it is **not** a visual JMeter plan/tree editor.

**Aspirational (not “different by design”):** OPL should aim for **visual scenario editing compatible with JMeter semantics** (tree or equivalent structured canvas → same JMX/engine path). Staying form-only forever would leave this flagship design gap unaddressed; raw JMX-only is a fallback, not the target UX.

---

## Done (shipped lab workflows)

| Capability area | OPL today | Notes / sibling codes |
|-----------------|-----------|------------------------|
| Virtual users / HTTP journeys | Scenario CRUD via upsert; Design tab steps (`http`, `think`, `extract`, `assert`, …) | `OPL-API` `load.go`, `jmeter_engine.go`; Dashboard Design |
| HAR → scenario | `POST /api/perf/scenarios/import-har` (+ Capture UI) | Skips private/metadata hosts (URL policy) |
| JMeter JMX import / export | `import-jmx`, `export-jmx`, JMX tab | Best-effort HTTP samplers / timers / extractors / CSV / classic thread groups |
| XHR capture import | `import-xhr` / `export-xhr` | Lab-oriented capture interchange |
| Codeless / form designer → JMX | Dashboard builds **flat** steps; API stores `jmx_xml` | Not a visual JMeter tree editor (see Flagship gap) |
| CSV / datasets | `datasets_json` → CSVDataSet in generated JMX | Inline CSV in Users & data tab |
| Extractors / assertions (basic) | Step types `extract`, `assert`; selector metadata (css/xpath/correlate) | Mirrored as JMX where supported; not full nested action tree |
| Load profiles | `soak` / `spike` / `ramp` + presets (smoke, stress) | Run & scale tab |
| Multi-worker scale (same host) | `workers` / `OPA_JMETER_WORKERS` → N Docker JMeter containers | Same `load_run_id`; not geo locations |
| Run lifecycle | Create, dispatch, cancel, metrics ingest, status | `created` / `running` / `failed` / `cancelled` honesty |
| SLA / pass criteria | Scenario `sla` + `GET .../runs/{id}/gate` (fail-closed) | SLA gates tab; CI harness in OPA-Stack |
| k6 export | `GET .../runs/{id}/export-k6` | OPL adds k6 export alongside JMeter |
| Results KPIs + samples | Results tab; `summary_json` + step samples | Prefer JMeter aggregates over client-posted pass/fail |
| Compare two runs | Compare tab (delta on KPIs) | Simpler than multi-run trend reports |
| APM correlation | `X-OPA-Load-Run-Id` / baggage → OPA Trace Explorer | First-party OPL ↔ OPA correlation |
| Tenant + hub auth | Org/project headers; co-deployed `/hub-auth/` | Hub JWT + org/project scopes |
| CI gate scripts | `harness/perf-gate.sh`, `jmeter-perf-gate.sh`, workflow example | Wizards for Jenkins/GitLab/Azure not ported |
| On-prem execution | Docker JMeter on the Perf Lab host | Lab host workers; not public cloud regions |

---

## Code-ready (ship UI + `:nas`)

Present on **OPL-API `main`** (load-lab capability routes, `jmeter.go` / `load.go` wiring). **Not** exposed in OPL-Dashboard yet. NAS running image may lag (`load-policies` 404 as of 2026-08-04).

| Capability | API | Lab analogue | Sibling follow-up |
|------------|-----|--------------|-------------------|
| Soft-archive scenario | `POST\|DELETE .../scenarios/{id}/archive` | Delete / retire scenario | Dashboard confirm + filter archived; rebuild `opl-api:nas` |
| Duplicate scenario | `POST .../scenarios/{id}/duplicate` | Duplicate journey | Dashboard “Duplicate” action |
| Load policy presets | `GET /api/perf/load-policies` (+ resolve on run) | Smooth / Sustained / Stress / Custom labels | Run & scale policy picker; NAS deploy |
| Per-step stats | `GET .../runs/{id}/steps` | Results table / request stats | Results tab table |
| Structured report | `GET .../runs/{id}/report` (`?format=csv`) | Bench report export (JSON/CSV, not PDF) | Download button; PDF still Missing |
| Runner live status | `GET .../runs/{id}/runners` | Injector / load-generator visibility | Results “workers” panel (docker inspect) |

---

## Missing (implementation candidates)

| Capability | Why labs need it | OPL gap | Suggested sibling work |
|------------|------------------|---------|------------------------|
| **JMeter Visual test case editor** (flagship) | Nested JMeter journeys without raw JMX | Flat form steps + JMX/HAR import only — no hierarchical visual JMeter plan editor | Visual tree/canvas UX → JMeter-semantic model → existing JMX engine; keep import as on-ramp |
| **Postman** collection import | Common API collections enter the lab | Absent | `import-postman` → HTTP steps / JMX |
| **Playwright** / real-browser VUs | Browser journeys under load | Explicitly out of scope today | New runner image or hybrid engine — large |
| **WebDriver** / Selenium record | Recorded browser flows | Absent | Later; overlap with Playwright |
| **VU fragments** + Link actions | Reuse shared journey pieces | No shared fragments | Reusable scenario fragments / includes |
| Rich **action tree** (if/while/foreach/rendezvous/queue/JSR223…) | Nested logic and containers | Flat step list + limited JMX | Extend visual/step DSL toward JMeter containers & logic (pairs with flagship editor) |
| **Auto-correlation** studio | Dynamic tokens are the #1 replay failure | Selector metadata only | Detect dynamic tokens; suggest extractors |
| **Validate VU** triage (functional check before load) | Catch broken correlation before engine minutes burn | `validate` thinner than needed | Per-step request/response triage UI |
| **Variables** (secret, counter, random, file-backed CSV UX) | Safer, richer parameterization | Headers + inline CSV | Variable store + secret refs |
| **Multi-profile** scenarios (mix VUs / locations) | Mixed traffic shapes | One scenario → one journey | Multi-scenario campaign or profiles array |
| **Geo / cloud locations** + IP ranges | Multi-region realism | Single-host Docker | Federation peers ≠ public regions (honesty) |
| **Custom load curve** editor (point chart) | Realistic arrival curves | Preset mapping only (code-ready); no inflexion editor | Timeline points → thread group |
| **Scheduler** / cron / one-shot | Nightly soak & regression | `schedule_json` stored; no runner | Orchestrator cron + UI |
| **Live reporting** sinks (Datadog, Dynatrace, Influx, …) | External ops sinks | ClickHouse + OPA only | Optional exporters |
| **Notifications** (email, Slack, Teams, Jira, webhook) | Failures noticed outside dashboard | None in OPL | Hook OPA alerts or OPL webhooks on terminal status |
| **Bench report** builder (widgets, templates, **PDF**) | Shareable offline packs | JSON/CSV report code-ready | PDF/HTML pack later |
| **Trend** reports (≤25 results) | Sprint-over-sprint regressions | Two-run compare only | Trend over N runs in CH |
| **JTL import** for offline analysis | Bring external JMeter results in | Engine writes JTL internally | `import-jtl` → samples + summary |
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

Ranked for a team that **designs HTTP/API load tests, runs them in lab, gates CI, and correlates to APM** — not for matching SaaS geo scale. Items already **code-ready** still count until Dashboard + NAS `:nas` make them usable. **#1 is the flagship product gap** (see above); near-term ship work still prefers Code-ready → Done first (Implementation priority).

| Rank | Gap | Why it hurts a lab | Sibling hint |
|------|-----|--------------------|--------------|
| 1 | **JMeter Visual test case editor** | Form+import cannot compose nested JMeter journeys | Visual tree/canvas ↔ JMeter-semantic steps → existing JMX path |
| 2 | **Archive/delete end-to-end** | Lab clutter; API soft-archive on `main` but no UI / may lag NAS | Dashboard + `opl-api:nas` roll-out |
| 3 | **Scheduler / cron runs** | Manual click-to-run blocks nightly soak & regression | Orchestrator job + `schedule_json` consumer |
| 4 | **Custom / visual load policy** | Presets ≠ realistic arrival curves; point editor absent | Timeline JSON → JMeter; expose `load-policies` in UI |
| 5 | **VU validation triage (pre-load)** | Broken correlation burns engine minutes | Expand validate + per-step RR UI |
| 6 | **Auto-correlation assistance** | Dynamic tokens are the #1 replay failure mode | Suggest extractors from HAR/validate |
| 7 | **Postman import** | Common API collections never enter the lab | Map Postman → steps/JMX |
| 8 | **Trend / multi-run history** | Two-run compare hides regressions over a sprint | CH queries + Compare/Trend tab |
| 9 | **Terminal-run notifications** | Failures unnoticed outside the dashboard | Webhook/Slack on `failed` / gate fail |
| 10 | **Runner live status + report/JTL** | Operators lack injector visibility / shareable offline artifacts | Wire `/runners` + `/report`; add `import-jtl` |

**Honorable mentions (high effort or owned elsewhere):** Playwright/WebDriver VUs; geo cloud locations; full action-tree coverage beyond the visual editor MVP; infrastructure monitors (use OPA); MCP server; multi-profile geo campaigns.

---

## Implementation priority (siblings)

For **OPL-API / OPL-Dashboard** implementers working load lab capabilities:

1. **Near-term:** Prefer **closing Code-ready → Done** (archive, duplicate, policies, steps, report, runners) — smallest path to a cleaner lab UX on NAS `:nas`.
2. **Flagship track (parallel / next major design investment):** **JMeter Visual test case editor** — visual scenario editing with **JMeter-compatible semantics**, not a permanent “form-only” stance. HAR/JMX import remains the on-ramp; the editor is the destination for complex journeys. Grow action coverage (containers, logic, fragments) on that model rather than only extending the flat step list.
3. Then Top 10 **#3–#6** (scheduler, custom curve, validate triage, auto-correlation).
4. Keep **honesty strings** on run/list responses when adding fan-out, locations, or “cloud-like” UX.
5. Do **not** reimplement infrastructure monitoring inside OPL — link OPA (`load_run_id`, infra hosts).
6. NAS / production: rebuild and tag `opl-api:nas` / `opl-dashboard:nas` only; laptop smoke is fine locally.
7. Cross-check [opl-opm-backlog.md](opl-opm-backlog.md) when closing Next items so backlog and this inventory stay aligned (backlog “upsert-only delete” / “runner live status” should flip once Code-ready ships to NAS + UI).

---

## Related

- [Products](products.md) — OPL ports `8092` / `8095`
- [OPL + OPM backlog](opl-opm-backlog.md) — Done / Next / Later
- [NAS deploy](nas-deploy.md) — `open-family`, `*:nas`
- OPL-API docs: [perf-lab.md](https://github.com/TheGrimmChester/OPL-API/blob/main/docs/perf-lab.md), [jmeter-perf.md](https://github.com/TheGrimmChester/OPL-API/blob/main/docs/jmeter-perf.md)
