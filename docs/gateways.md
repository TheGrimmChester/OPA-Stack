# Product gateways (optional)

Each product plane may later terminate HTTP at a product gateway and peel domain micro-services. Dashboards keep a single product API URL.

| Product | Gateway image | Upstream examples |
|---------|---------------|-------------------|
| ORA | `ora-gateway` | `ora-scm`, `ora-review`, `ora-agents`, `ora-ai` |
| OSA | `osa-gateway` | `osa-inventory`, `osa-runs`, `osa-gate` |
| OPL | `opl-gateway` | `opl-scenarios`, `opl-runs` |
| OPM | `opm-gateway` | `opm-board`, `opm-roadmap`, `opm-jobs` |
| OPA | (hub remains `opa-hub`) | edge agents push to hub; no dashboard→edge |

Compose profiles continue to expose `ora-api` / `osa-api` / `opl-api` / `opm-api` until a gateway image is published. Do not add legacy path aliases when introducing a gateway.

NAS production uses `*:nas` tags only.
