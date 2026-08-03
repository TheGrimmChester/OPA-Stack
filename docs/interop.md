# Product interop

Products are **optional peers**. No hard dependency at boot. An empty peer URL disables the feature or returns `503` with `peer_unavailable`.

## User auth

| Mode | Mechanism |
|------|-----------|
| Co-deployed | Shared `JWT_SECRET`; **OPA-Hub** issues user JWTs; ORA/OSA/OPL validate |
| Standalone | Local auth or auth off for lab |
| CI | Product tokens (not `JWT_SECRET`) |

Headers: `Authorization: Bearer <user-jwt>`, `X-Organization-ID`, `X-Project-ID`.

## Service-to-service

Caller sets `PEER_{OPA|ORA|OSA|OPL}_URL` and mints a **service JWT** with `OPEN_SERVICE_JWT_SECRET` (prefer distinct from user `JWT_SECRET`):

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
| Dashboard → foreign API | **Forbidden** — UI → own API only | — |

## Config sketch

```bash
JWT_SECRET=
OPEN_SERVICE_JWT_SECRET=
PEER_OPA_URL=
PEER_ORA_URL=
PEER_OSA_URL=
PEER_OPL_URL=
OPA_PUBLIC_URL=
ORA_PUBLIC_URL=
OSA_PUBLIC_URL=
OPL_PUBLIC_URL=
```
