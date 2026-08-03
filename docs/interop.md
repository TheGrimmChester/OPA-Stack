# Product interop

Products are **optional peers**. No hard dependency at boot. An empty peer URL disables the feature or returns `503` with `peer_unavailable`.

## User auth

| Mode | Mechanism | How to enable |
|------|-----------|---------------|
| **Standalone** | Each product issues JWTs with its own `JWT_SECRET` via local `/api/auth/login` | `AUTH_MODE=standalone`, or leave `PEER_OPA_URL` empty |
| **Co-deployed** | Shared `JWT_SECRET`; **OPA-Hub** issues user JWTs; ORA/OSA/OPL/OPM validate | `AUTH_MODE=codeployed`, or set `PEER_OPA_URL` to the hub |
| **CI** | Product tokens (not `JWT_SECRET`) | Pipeline secrets |

Headers: `Authorization: Bearer <user-jwt>`, `X-Organization-ID`, `X-Project-ID`.

Lab default when standalone: username `admin` / password `admin` (override with `AUTH_ADMIN_USER` / `AUTH_ADMIN_PASSWORD`).

## ClickHouse databases

One ClickHouse server can host all products. Each service sets its own database:

| Product | `CLICKHOUSE_DB` |
|---------|-----------------|
| OPA hub | `opa` |
| ORA | `ora` |
| OSA | `osa` |
| OPL | `opl` |

`compose.all.yaml` creates all four databases on first boot (`clickhouse/init-databases.sql`). Solo profiles create the same init script so a shared server stays consistent. Prefer `CLICKHOUSE_DB`; `CLICKHOUSE_DATABASE` is an accepted alias.

## Service-to-service

Caller sets `PEER_{OPA|ORA|OSA|OPL|OPM}_URL` and mints a **service JWT** with `OPEN_SERVICE_JWT_SECRET` (prefer distinct from user `JWT_SECRET`):

- Claims: `iss`, `aud`, `sub=service`, `scope`, short `exp`, optional `org_id`
- Callee rejects bad `aud` / unknown `iss` / missing scope

| Scope | Meaning |
|-------|---------|
| `findings:read` | Read AppSec findings / run summaries |
| `runs:write` | Create/link security run from review |
| `traces:read` | Trace metadata for correlation |
| `ingest:load_run` | Load-run correlation |
| `health:read` | Peer probe |

## Allowed peer calls

| Caller → Callee | Purpose | Required? |
|-----------------|---------|-----------|
| OPL → OPA hub | `load_run_id` correlation | Optional |
| ORA → OSA | findings / `security_run_id` / gate status | Optional |
| OSA → OPA hub | runtime context deep links | Optional |
| ORA → OPA hub | dashboard deep links | Optional |
| ORA → OPM | Roadmap / task handoff (optional) | Optional |
| OPM → ORA | Delegate review jobs / deep-link | Optional |
| Dashboard → foreign API | **Forbidden** — UI → own API only | — |

## Config sketch

```bash
JWT_SECRET=
AUTH_MODE=                 # standalone | codeployed (auto from PEER_OPA_URL when empty)
OPEN_SERVICE_JWT_SECRET=
CLICKHOUSE_URL=http://clickhouse:8123
CLICKHOUSE_DB=             # opa | ora | osa | opl per service
PEER_OPA_URL=
PEER_ORA_URL=
PEER_OSA_URL=
PEER_OPL_URL=
PEER_OPM_URL=
OPA_PUBLIC_URL=
ORA_PUBLIC_URL=
OSA_PUBLIC_URL=
OPL_PUBLIC_URL=
OPM_PUBLIC_URL=
```

## All-in-one compose

See [`compose.all.yaml`](../compose.all.yaml): one ClickHouse, databases `opa`/`ora`/`osa`/`opl`, shared `JWT_SECRET`, hub-issued tokens (`AUTH_MODE=codeployed`).
