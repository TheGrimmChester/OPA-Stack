# Open-* products

The Open-* family is four optional products plus shared modules. Install only what you need. Each product ships its own API (or hub), dashboard, and (where required) orchestrator + runners.

| Short | Full name | Control plane | Dashboard | Owns |
|-------|-----------|---------------|-----------|------|
| **OPA** | Open Profiling Agent | `opa-hub` (central) + `opa-agent` (edge) | `opa-dashboard` | Observability only: edge ingest, hub registry/query/auth, APM, RUM, metrics, alerts/SLOs, synthetics |
| **ORA** | Open Review Agent | `ora-api` + `ora-orchestrator` | `ora-dashboard` | Repo Watch, SCM connectors, automated code review, review check-runs, coding agents, roadmaps |
| **OSA** | Open Security Agent | `osa-api` + `osa-orchestrator` | `osa-dashboard` | AppSec findings (secrets/SAST/IaC), security runs, vulns/IAST, AppSec CI gates |
| **OPL** | Open Perf Lab | `opl-api` + `opl-orchestrator` | `opl-dashboard` | Load scenarios, runs, HAR/JMX, Docker JMeter, optional OPA correlation |

## Topology (OPA)

Hub-and-spoke, push-primary: edge `opa-agent` registers and pushes telemetry outbound to `opa-hub`. `opa-dashboard` uses one URL and talks only to the hub.

## Smoke ports (laptop)

| Product | Port |
|---------|------|
| OPA hub | `8080` |
| ORA | `8091` |
| OPL | `8092` |
| OSA | `8093` |

## Image tags

- Laptop / CI smoke: `*:smoke`
- Production and NAS: `*:nas` only — never deploy smoke tags to production hosts

## Repository visibility

Family GitHub repositories are **private** during the product split and migration. Re-opening repositories as public is a deliberate later release step — not part of bootstrap.

## No compatibility shims

Removed endpoints are absent (normal HTTP 404). Do not ship redirects, dual path namespaces, or keep-alive stubs for APIs that moved between products. Update callers in the same change set.

## Related docs

- [Modules catalog](modules.md)
- [Interop and peer auth](interop.md)
- Compose profile stubs: [`compose.opa.yaml`](../compose.opa.yaml), [`compose.ora.yaml`](../compose.ora.yaml), [`compose.osa.yaml`](../compose.osa.yaml), [`compose.opl.yaml`](../compose.opl.yaml), [`compose.all.yaml`](../compose.all.yaml)
