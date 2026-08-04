# OPL load lab capabilities

Implementation guide for **sibling** work in [OPL-API](https://github.com/TheGrimmChester/OPL-API) and [OPL-Dashboard](https://github.com/TheGrimmChester/OPL-Dashboard). Inventories what **Open Perf Lab** ships today, what is still missing for a serious self-hosted load lab, and what OPL deliberately does differently from a commercial multi-cloud load grid.

**Sources (2026-08-04):** OPL-API `docs/perf-lab.md`, `docs/jmeter-perf.md`, load-lab capability routes (`jmeter.go` / `load.go` / `lab_extras.go`); OPL-Dashboard `PerfLab.jsx` + `VuTree.jsx` on `main`; OPA-Stack [opl-opm-backlog.md](opl-opm-backlog.md).

**NAS spot-check (same day):** `http://192.168.100.101:8092/api/health` → `status=ok`, `service=opl-api`, `auth_mode=codeployed`; `:8095/` → HTTP 200 (OPL dashboard). With Hub JWT + tenant headers, `GET /api/perf/load-policies` → **200** (policies `smooth` / `sustained` / `stress` / `custom`); unauthenticated → **401** (route present — not 404). Soft-archive, duplicate, validate, `/runs/{id}/steps|report|runners`, and `import-jtl` likewise respond on `opl-api:nas`. Running `opl-dashboard:nas` still lags `main` (no VuTree / archive / duplicate / runners UI in the served bundle). Production images stay `*:nas` only — never deploy `*:smoke` to NAS.

---

## How to read this

| Bucket | Meaning |
|--------|---------|
| **Done** | Usable today for a lab workflow (API + typically UI; present on NAS unless noted) |
| **Code-ready** | Implemented on OPL-API / OPL-Dashboard `main`, but missing usable Dashboard on the running NAS `opl-dashboard:nas` image (API may already be live) |
| **Missing** | Expected load-lab capability; OPL does not ship it yet — candidate sibling PRs |
| **Different by design** | Related capability exists, but OPL’s model / honesty boundary differs |

OPL is a **self-hosted load lab** next to OPA, not a SaaS multi-cloud load grid. Gaps ranked for **load-test lab user impact** (design → run → analyze → gate), not for matching enterprise multi-region packaging.

### Flagship gap: JMeter Visual test case editor

The **most advanced design capability** a JMeter-first load lab should offer is a **JMeter Visual test case editor** — a hierarchical Virtual User tree (drag-and-drop actions, containers, logic, extractors, search/replace) for building JMeter-compatible journeys **without editing raw JMX**.

**OPL today:** OPL-Dashboard `main` ships a **first-slice JMeter visual test case editor** (`VuTree`: nest extract/assert under HTTP; transaction containers → JMX hashTrees). NAS `opl-dashboard:nas` still serves the older **flat form step list** plus HAR/XHR/JMX import — rebuild/redeploy the dashboard `:nas` image to expose the tree editor. Depth beyond that first slice (logic containers, DnD multi-select, search/replace) remains Missing.

**Aspirational (not “different by design”):** Grow **visual scenario editing compatible with JMeter semantics** (richer tree/canvas → same JMX/engine path). Form-only / raw JMX-only are fallbacks, not the destination UX.

---

## Done (shipped lab workflows)

| Capability area | OPL today | Notes / sibling codes |
|-----------------|-----------|------------------------|
| Virtual users / HTTP journeys | Scenario CRUD via upsert; Design tab steps (`http`, `think`, `extract`, `assert`, …) | `OPL-API` `load.go`, `jmeter_engine.go`; Dashboard Design |
| HAR → scenario | `POST /api/perf/scenarios/import-har` (+ Capture UI) | Skips private/metadata hosts (URL policy) |
| JMeter JMX import / export | `import-jmx`, `export-jmx`, JMX tab | Best-effort HTTP samplers / timers / extractors / CSV / classic thread groups |
| XHR capture import | `import-xhr` / `export-xhr` | Lab-oriented capture interchange |
| Codeless / form designer → JMX | Flat steps still work; **VuTree** on Dashboard `main` | NAS dashboard image still form-only until `:nas` rebuild |
| Soft-archive / duplicate (API) | `POST\|DELETE .../scenarios/{id}/archive`, `POST .../duplicate` | Verified on NAS `opl-api:nas` (Hub JWT); restore not implemented |
| Load policy presets (API) | `GET /api/perf/load-policies` → smooth / sustained / stress / custom | **200** on NAS with JWT; Dashboard `main` uses matching hardcoded presets (does not fetch the route yet) |
| Per-step stats / report / runners (API) | `GET .../runs/{id}/steps\|report\|runners` | **200** on NAS; Results wiring on Dashboard `main` |
| Validate 1 VU triage (API) | `POST .../scenarios/{id}/validate` | **200** on NAS; Validate button on Dashboard `main` |
| JTL import (API) | `POST .../runs/{id}/import-jtl` | **200** on NAS; no Dashboard affordance yet |
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

## Code-ready (ship `opl-dashboard:nas`)

Present on **OPL-API `main` and live on NAS `opl-api:nas`**. Implemented in **OPL-Dashboard `main`** (`PerfLab.jsx` / `VuTree.jsx`), but **not** in the running NAS `opl-dashboard:nas` bundle (spot-check: no VuTree / `/archive` / `/duplicate` / `/runners` strings).

| Capability | API (NAS) | Dashboard `main` | Sibling follow-up |
|------------|-----------|------------------|-------------------|
| Soft-archive scenario | Live | Archive actions | Rebuild/redeploy `opl-dashboard:nas`; filter archived |
| Duplicate scenario | Live | Duplicate actions | Same `:nas` roll-out |
| Load policy presets | Live (`/load-policies`) | Hardcoded Smooth/Sustained/Stress/Custom picker | Optional: fetch `/load-policies` instead of hardcoding; `:nas` roll-out |
| Per-step stats | Live | Results table poll | `:nas` roll-out |
| Structured report | Live (`?format=csv`) | Download on Results | `:nas` roll-out; PDF still Missing |
| Runner live status | Live | Workers panel (docker inspect) | `:nas` roll-out |
| Validate 1 VU triage | Live | Validate buttons + banner | `:nas` roll-out |
| JMeter visual editor (first slice) | Nested `children` → JMX | `VuTree` + inspector | `:nas` roll-out (flagship depth still Missing) |

---

## Missing (implementation candidates)

| Capability | Why labs need it | OPL gap | Suggested sibling work |
|------------|------------------|---------|------------------------|
| **JMeter Visual test case editor** (flagship depth) | Nested JMeter journeys without raw JMX | First slice on Dashboard `main` / API; NAS UI still flat; no If/While/Loop / fragments / DnD multi-select | Redeploy `opl-dashboard:nas`; then deepen tree (logic, fragments, search/replace) |
| **Postman** collection import | Common API collections enter the lab | Absent | `import-postman` → HTTP steps / JMX |
| **Playwright** / real-browser VUs | Browser journeys under load | Explicitly out of scope today | New runner image or hybrid engine — large |
| **WebDriver** / Selenium record | Recorded browser flows | Absent | Later; overlap with Playwright |
| **VU fragments** + Link actions | Reuse shared journey pieces | No shared fragments | Reusable scenario fragments / includes |
| Rich **action tree** (if/while/foreach/rendezvous/queue/JSR223…) | Nested logic and containers | Flat step list + limited JMX | Extend visual/step DSL toward JMeter containers & logic (pairs with flagship editor) |
| **Auto-correlation** studio | Dynamic tokens are the #1 replay failure | Selector metadata only | Detect dynamic tokens; suggest extractors |
| **Validate VU** triage (functional check before load) | Catch broken correlation before engine minutes burn | API + Dashboard `main` triage; NAS dashboard lag | Redeploy `opl-dashboard:nas`; deepen per-step RR UX |
| **Variables** (secret, counter, random, file-backed CSV UX) | Safer, richer parameterization | Headers + inline CSV | Variable store + secret refs |
| **Multi-profile** scenarios (mix VUs / locations) | Mixed traffic shapes | One scenario → one journey | Multi-scenario campaign or profiles array |
| **Geo / cloud locations** + IP ranges | Multi-region realism | Single-host Docker | Federation peers ≠ public regions (honesty) |
| **Custom load curve** editor (point chart) | Realistic arrival curves | API presets live; Dashboard picker hardcoded; no inflexion editor | Timeline points → thread group |
| **Scheduler** / cron / one-shot | Nightly soak & regression | `schedule_json` stored; no runner | Orchestrator cron + UI |
| **Live reporting** sinks (Datadog, Dynatrace, Influx, …) | External ops sinks | ClickHouse + OPA only | Optional exporters |
| **Notifications** (email, Slack, Teams, Jira, webhook) | Failures noticed outside dashboard | None in OPL | Hook OPA alerts or OPL webhooks on terminal status |
| **Bench report** builder (widgets, templates, **PDF**) | Shareable offline packs | JSON/CSV report API live on NAS; UI on Dashboard `main` | PDF/HTML pack later; `:nas` dashboard roll-out |
| **Trend** reports (≤25 results) | Sprint-over-sprint regressions | Two-run compare only | Trend over N runs in CH |
| **JTL import** for offline analysis | Bring external JMeter results in | API live on NAS; no Dashboard UI | Wire import control in Results |
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
| Soft-delete | Hard delete in UI | Soft-archive (`archived=1`) on NAS API; restore not implemented; Dashboard `:nas` lag for Archive action |

---

## Top 10 missing (load-test lab impact)

Ranked for a team that **designs HTTP/API load tests, runs them in lab, gates CI, and correlates to APM** — not for matching SaaS geo scale. Items already **code-ready on Dashboard `main`** still count until `opl-dashboard:nas` makes them usable on NAS. **#1 remains flagship editor depth** after the first-slice redeploy; near-term ship work still prefers Code-ready → Done first (Implementation priority).

| Rank | Gap | Why it hurts a lab | Sibling hint |
|------|-----|--------------------|--------------|
| 1 | **JMeter Visual editor depth + NAS UI** | Flat form on NAS; first slice only on Dashboard `main` | Redeploy `opl-dashboard:nas`; then logic/fragments/DnD |
| 2 | **Archive/duplicate end-to-end on NAS UI** | API soft-archive live; operators still lack dashboard actions on NAS | Rebuild `opl-dashboard:nas` |
| 3 | **Scheduler / cron runs** | Manual click-to-run blocks nightly soak & regression | Orchestrator job + `schedule_json` consumer |
| 4 | **Custom / visual load curve** | Presets ≠ realistic arrival curves; point editor absent | Timeline JSON → JMeter; optionally fetch `/load-policies` |
| 5 | **VU validation triage polish** | API validate live; richer RR triage + NAS UI lag | Expand validate UX; redeploy dashboard |
| 6 | **Auto-correlation assistance** | Dynamic tokens are the #1 replay failure mode | Suggest extractors from HAR/validate |
| 7 | **Postman import** | Common API collections never enter the lab | Map Postman → steps/JMX |
| 8 | **Trend / multi-run history** | Two-run compare hides regressions over a sprint | CH queries + Compare/Trend tab |
| 9 | **Terminal-run notifications** | Failures unnoticed outside the dashboard | Webhook/Slack on `failed` / gate fail |
| 10 | **JTL import UI + report polish** | API `import-jtl` / `/report` live; shareable offline UX thin | Wire Results import + PDF later |

**Honorable mentions (high effort or owned elsewhere):** Playwright/WebDriver VUs; geo cloud locations; full action-tree coverage beyond the visual editor MVP; infrastructure monitors (use OPA); MCP server; multi-profile geo campaigns.

---

## Implementation priority (siblings)

For **OPL-API / OPL-Dashboard** implementers working load lab capabilities:

1. **Near-term:** Prefer **closing Code-ready → Done** by rebuilding **`opl-dashboard:nas`** (VuTree, archive, duplicate, validate, steps/report/runners) — API routes are already live on NAS.
2. **Flagship track (parallel / next major design investment):** Deepen the **JMeter Visual test case editor** beyond the first slice — logic containers, fragments, search/replace — on the same JMX path. HAR/JMX import remains the on-ramp.
3. Then Top 10 **#3–#6** (scheduler, custom curve, validate polish, auto-correlation).
4. Keep **honesty strings** on run/list responses when adding fan-out, locations, or “cloud-like” UX.
5. Do **not** reimplement infrastructure monitoring inside OPL — link OPA (`load_run_id`, infra hosts).
6. NAS / production: rebuild and tag `opl-api:nas` / `opl-dashboard:nas` only; laptop smoke is fine locally.
7. Cross-check [opl-opm-backlog.md](opl-opm-backlog.md) when closing Next items so backlog and this inventory stay aligned.

---

## Related

- [Products](products.md) — OPL ports `8092` / `8095`
- [OPL + OPM backlog](opl-opm-backlog.md) — Done / Next / Later
- [NAS deploy](nas-deploy.md) — `open-family`, `*:nas`
- OPL-API docs: [perf-lab.md](https://github.com/TheGrimmChester/OPL-API/blob/main/docs/perf-lab.md), [jmeter-perf.md](https://github.com/TheGrimmChester/OPL-API/blob/main/docs/jmeter-perf.md)
