# Security: tenant and auth scopes

Cross-product matrix for **co-deployed** Open-* on NAS (`open-family`, `*:nas` images only). Lab hub user: `admin` / `admin`.

Related: [interop.md](interop.md) (tenant headers), [nas-deploy.md](nas-deploy.md) (ports).

## Expected behavior

| Case | Expected |
|------|----------|
| No JWT on protected route | **401** (or **403**) |
| JWT, no `X-Organization-ID` / `X-Project-ID` | Scope to **`default-org` / `default-project`** (same as write tenant; Open-Tenant-Go ≥ 0.2.2). HTTP **200**, not an unscoped dump. |
| JWT + wrong / unknown org | **Empty list** or **403** — never rows belonging to another org |
| JWT + correct org | Tenant’s data (HTTP **200**) |
| Product-local `POST /api/auth/login` (ORA/OSA/OPL/OPM) | **503** when `AUTH_MODE=codeployed` |
| Hub `POST /api/auth/login` | **200** (hub is the JWT issuer) |

Canonical headers (case-insensitive): `Authorization: Bearer <hub-jwt>`, `X-Organization-ID`, `X-Project-ID`. Query fallbacks `organization_id` / `project_id` match. Picker marker `"all"` is stripped under auth and does **not** widen scope.

## NAS ports

| Product | API host port | Representative protected list |
|---------|---------------|-------------------------------|
| Hub | `18080` | `GET /api/infra/hosts`, `GET /api/alerts`, `GET /api/tenancy/organizations` |
| ORA | `8091` | `GET /api/connectors`, `GET /api/scm/jobs` |
| OSA | `8093` | `GET /api/security/runs`, `GET /api/security/secrets` |
| OPL | `8092` | `GET /api/perf/scenarios`, `GET /api/perf/runs` |
| OPM | `8096` | `GET /api/projects` |

From the NAS host use `127.0.0.1`; from the LAN use `192.168.100.101`.

## Curl matrix (LAN)

```bash
HOST=192.168.100.101   # or 127.0.0.1 on the NAS

TOKEN=$(curl -sf -X POST "http://$HOST:18080/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' | jq -r .token)

AUTH=(-H "Authorization: Bearer $TOKEN")
DEF=(-H "Authorization: Bearer $TOKEN" \
  -H "X-Organization-ID: default-org" -H "X-Project-ID: default-project")
WRONG=(-H "Authorization: Bearer $TOKEN" \
  -H "X-Organization-ID: nonexistent-org-xyz" \
  -H "X-Project-ID: nonexistent-project-xyz")
NAS_T=(-H "Authorization: Bearer $TOKEN" \
  -H "X-Organization-ID: nas" -H "X-Project-ID: infra")

# --- no JWT → 401 ---
for url in \
  "http://$HOST:18080/api/infra/hosts" \
  "http://$HOST:8091/api/connectors" \
  "http://$HOST:8093/api/security/runs" \
  "http://$HOST:8092/api/perf/scenarios" \
  "http://$HOST:8096/api/projects"
do
  curl -s -o /dev/null -w "%{http_code} $url\n" "$url"
done

# --- product local login → 503 ---
for port in 8091 8093 8092 8096; do
  curl -s -o /dev/null -w "%{http_code} :$port/api/auth/login\n" \
    -X POST "http://$HOST:$port/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d '{"username":"admin","password":"admin"}'
done

# --- tenant scopes (example: OSA runs) ---
curl -sf "http://$HOST:8093/api/security/runs?limit=50" "${AUTH[@]}" \
  | jq '.runs | length'          # == default-org count
curl -sf "http://$HOST:8093/api/security/runs?limit=50" "${DEF[@]}" \
  | jq '.runs | length'
curl -sf "http://$HOST:8093/api/security/runs?limit=50" "${WRONG[@]}" \
  | jq '.runs | length'          # 0
curl -sf "http://$HOST:8093/api/security/runs?limit=50" "${NAS_T[@]}" \
  | jq '.runs | length'          # nas/infra only (may differ from default)

# Repeat the four AUTH/DEF/WRONG/NAS_T GETs for:
#   hub  /api/infra/hosts          → .hosts
#   hub  /api/alerts               → .alerts
#   ora  /api/connectors           → .connectors
#   ora  /api/scm/jobs?limit=50    → .jobs
#   osa  /api/security/secrets     → .findings
#   opl  /api/perf/scenarios       → .scenarios
#   opl  /api/perf/runs?limit=50   → .runs
#   opm  /api/projects             → .projects
```

Automated checklist: [`harness/security-tenant-matrix.sh`](../harness/security-tenant-matrix.sh)

```bash
HOST=192.168.100.101 ./harness/security-tenant-matrix.sh
# Optional image check on NAS (needs SSHPASS for root@HOST):
#   CHECK_IMAGES=1 SSHPASS=… HOST=192.168.100.101 ./harness/security-tenant-matrix.sh
```

## Pass criteria

- Every protected route above returns **401** without JWT.
- Peer product local login returns **503**.
- Wrong-org list length is **0** (or HTTP **403**); counts must not match another real tenant’s non-empty set.
- No-header counts match explicit `default-org` / `default-project` for ClickHouse-backed lists (OSA, OPL, and WriteTenant-aligned ORA/OPM/hub surfaces).
- Running containers for hub / ora-api / osa-api / opl-api / opm-api resolve to **`*:nas`** image names (never `*:smoke`).

## Notes

- Some legacy ORA SCM admin honesty text may still say tenant “All” when headers are omitted; prefer always sending concrete headers. After WriteTenant alignment, wrong-org must still be empty.
- Hub observability rows may omit an `organization_id` column in JSON; scoping is still enforced via query filters when headers are present.
- Dashboard `/hub-auth/` bridges (ports `8089` / `8094` / `8095` / `8098`) are browser login only — product APIs stay on the ports above.
