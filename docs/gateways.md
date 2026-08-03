# Product gateways (optional)

Each product plane may later terminate HTTP at a product gateway and peel domain micro-services. Dashboards keep a single product API URL.

| Product | Gateway image | Upstream examples |
|---------|---------------|-------------------|
| ORA | `ora-gateway` | `ora-scm`, `ora-review`, `ora-agents`, `ora-ai`, `ora-roadmap` |
| OSA | `osa-gateway` | `osa-inventory`, `osa-runs`, `osa-gate` |
| OPL | `opl-gateway` | `opl-scenarios`, `opl-runs` |
| OPA | (hub remains `opa-hub`) | edge agents push to hub; no dashboard→edge |

Compose profiles continue to expose `ora-api` / `osa-api` / `opl-api` until a gateway image is published. Do not add legacy path aliases when introducing a gateway.

NAS production uses `*:nas` tags only.
