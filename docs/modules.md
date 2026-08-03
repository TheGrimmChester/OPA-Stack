# Open-* modules catalog

Reusable code and images used by **two or more** products live in dedicated `Open-*` module repositories. Product repos stay thin: domain logic and wiring only. Depend via Go module, npm, or base image — never by copying source between products.

| Repo | Provides | Typical dependents | Incorporate |
|------|----------|--------------------|-------------|
| `Open-Client-JS` | Typed control-plane HTTP clients + user-auth header helpers | `*-Dashboard` (incl. OPM) | npm `@open-family/client` |
| `Open-Client-Go` | Typed peer/product HTTP clients | Go APIs, hub, orchestrators | `github.com/TheGrimmChester/open-client-go` |
| `Open-Auth-Go` | User JWT validate + service JWT mint/validate | All Go APIs | `github.com/TheGrimmChester/open-auth-go` |
| `Open-Tenant-Go` | `X-Organization-ID` / `X-Project-ID` helpers | All Go APIs | `github.com/TheGrimmChester/open-tenant-go` |
| `Open-ClickHouse-Go` | ClickHouse HTTP client, dial/config, migrate helpers | Go APIs using ClickHouse | `github.com/TheGrimmChester/open-clickhouse-go` |
| `Open-Job-Go` | Sandboxed job lifecycle, hardened `docker run`, labels, env scrub | Product orchestrators (incl. OPM) | `github.com/TheGrimmChester/open-job-go` |
| `Open-HTTP-Go` | Error JSON, CORS, health, request IDs | All Go APIs | `github.com/TheGrimmChester/open-http-go` |
| `Open-Logger-Go` | Structured logger | Go services / orchestrators | `github.com/TheGrimmChester/open-logger-go` |
| `Open-UI-JS` | Dashboard shell kit (layout, session helpers, tokens) | `*-Dashboard` (incl. OPM) | npm `@open-family/ui` |
| `Open-Egress-Proxy` | Allowlisted egress proxy image + source | ORA/OSA job sandboxes | image `open-egress-proxy:{smoke\|nas}` |

## Not modules

Domain APIs and ingest SDKs stay product- or ingest-scoped (`opa-node`, `opa-python`, `opa-rum-js`, `OPA-PHP-extension`, `OPA-PHP-lib`, `opa-collector`).

## Versioning

Modules use semver. Products pin versions. Modules follow family visibility (currently public).
