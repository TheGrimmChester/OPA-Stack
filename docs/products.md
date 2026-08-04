# Open-* products

The Open-* family is five optional products plus shared modules. Install only what you need. Each product ships its own API (or hub), dashboard, and (where required) orchestrator + runners.

| Short | Full name | Control plane | Dashboard | Owns |
|-------|-----------|---------------|-----------|------|
| **OPA** | Open Profiling Agent | `opa-hub` (central) + `opa-agent` (edge) | `opa-dashboard` | Observability only: edge ingest, hub registry/query/auth, APM, RUM, metrics, alerts/SLOs, synthetics |
| **ORA** | Open Review Agent | `ora-api` + `ora-orchestrator` | `ora-dashboard` | Repo Watch, SCM connectors, automated code review, review check-runs, coding agents, roadmaps |
| **OSA** | Open Security Agent | `osa-api` + `osa-orchestrator` | `osa-dashboard` | AppSec findings (secrets/SAST/IaC), security runs, vulns/IAST, AppSec CI gates |
| **OPL** | Open Perf Lab | `opl-api` + `opl-orchestrator` | `opl-dashboard` | Load scenarios, runs, HAR/JMX, Docker JMeter, optional OPA correlation |
| **OPM** | Open Project Manager | `opm-api` + `opm-orchestrator` | `opm-dashboard` | Multi-project registry, kanban, roadmaps, ideation, task specs/plans, task-automation jobs |

## Topology (OPA)

Hub-and-spoke, push-primary: edge `opa-agent` registers and pushes telemetry outbound to `opa-hub`. `opa-dashboard` uses one URL and talks only to the hub.

Recent hub batches moved dashboard query routes off the edge agent onto **opa-hub** (NAS port `18080`):

| Batch | Routes (hub-owned) | Dashboard pages |
|-------|-------------------|-----------------|
| 2 | `GET /api/infra/hosts`, `GET /api/transactions/compare` | Infrastructure, Compare Traces (cohort) |
| 3 | `GET /api/version`, `GET /api/topology`, `GET /api/ops/status`, `GET /api/audit`, `GET /api/db/*` list surfaces | System, Databases |
| 4 | *(none — docs audit only)* | Network, Cloud, Catalog, Automation, Compare Traces (call-graph tab) |

Batch 4 audited remaining observability surfaces. **No hub routes were added.** Network, Cloud, Catalog, mgmt (`/api/mgmt/v1/*`), and call-graph compare are dashboard scaffolds with **no agent or hub backend** yet (NAS hub `:18080` → **404**). Filter suggestions exist on the edge agent only (`:18081` on NAS); the dashboard does not call them — stay edge-owned until wired.

The dashboard never calls edge hosts in production. See [OPA-Hub ownership](https://github.com/TheGrimmChester/OPA-Hub/blob/main/docs/ownership.md) for the full deferred table.

## Smoke ports (laptop)

API and dashboard host ports from `compose.all.yaml` (and the solo `compose.*.yaml` profiles). NAS production uses the same dashboard ports for OSA/OPL; see [nas-deploy.md](nas-deploy.md).

| Service | Port |
|---------|------|
| OPA hub | `8080` |
| OPA Dashboard | `8088` |
| ORA API | `8091` |
| ORA Dashboard | `8089` |
| OPL API | `8092` |
| OSA API | `8093` |
| OSA Dashboard | `8094` |
| OPL Dashboard | `8095` |
| OPM API | `8096` |
| OPM Dashboard | `8098` |

## Alert Test (OPA)

Dashboard **Test** on an alert rule calls hub `POST /api/alerts/{id}`. The hub queues `opa.alert_test_requests`; the edge agent leader force-delivers the rule’s channel (no condition/cooldown) and writes `opa.alert_history`. Use `OPA_ALERT_NOTIFY_MODE=log` on the agent for safe end-to-end checks without contacting real webhooks/Slack/email.

## Image tags

- Laptop / CI smoke: `*:smoke`
- Production and NAS: `*:nas` only — never deploy smoke tags to production hosts

## Repository visibility

Family GitHub repositories for Open-* products, modules, and SDKs are **public**.

They were held private during the product split and migration, then reopened on 2026-08-03 once the family layout was stable.

## No compatibility shims

Removed endpoints are absent (normal HTTP 404). Do not ship redirects, dual path namespaces, or keep-alive stubs for APIs that moved between products. Update callers in the same change set.

## Related docs

- [Modules catalog](modules.md)
- [Interop, auth modes, and ClickHouse databases](interop.md)
- [NAS production deploy](nas-deploy.md) — compose project `open-family`, path `/mnt/Apps/config-docker/open-stack`, images `*:nas` only
- Compose profile stubs: [`compose.opa.yaml`](../compose.opa.yaml), [`compose.ora.yaml`](../compose.ora.yaml), [`compose.osa.yaml`](../compose.osa.yaml), [`compose.opl.yaml`](../compose.opl.yaml), [`compose.opm.yaml`](../compose.opm.yaml), [`compose.all.yaml`](../compose.all.yaml) (laptop `*:smoke`), [`compose.nas.yaml`](../compose.nas.yaml) (production `*:nas`)

## Gateways

Optional peel docs: [gateways.md](gateways.md).

