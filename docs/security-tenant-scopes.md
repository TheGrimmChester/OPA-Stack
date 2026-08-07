# Security: tenant and auth scopes

Cross-product matrix for **co-deployed** Open-* on NAS (`open-family`, `*:nas` images only). Lab hub user: `admin` / `admin`.

Related: [interop.md](interop.md) (tenant headers), [nas-deploy.md](nas-deploy.md) (ports).

## Expected behavior

| Case | Expected |
|------|----------|
| No JWT on protected route | **401** (or **403**) |
| JWT, no `X-Organization-ID` / `X-Project-ID` | **Never** silent `default-org`. Personal → owner-only empty org; org member → JWT `org_id` pin; platform admin (not impersonating) → **empty list** or **400** on tenant product data. |
| JWT + `X-Project-ID: all` | Stripped under auth — does **not** widen to org-wide unscoped; same as missing project for list scope (still no silent `default-org`) |
| JWT + list-only `X-Project-IDs: id1,id2,…` | List/read scope `project_id IN (…)` (cap **32**); every id ACL-checked. Writes ignore this header. Most product writes still need a concrete single `X-Project-ID`; **OAM** Endpoints / Agents / Connectors treat a missing project as org/user-global (`default-project`). |
| JWT + wrong / unknown org | **Empty list** or **403** — never rows belonging to another org |
| JWT + correct / concrete org | Tenant’s data (HTTP **200**) |
| JWT with `project_ids` + non-member project | Hub + ORA/OSA/OPL/OPM → **403** (`project access denied`); admins exempt from project allowlist (not from needing a concrete org / impersonation for tenant data) |
| Product-local `POST /api/auth/login` (ORA/OSA/OPL/OPM) | **503** when `AUTH_MODE=codeployed` |
| Hub or OAM `POST /api/auth/login` (co-deployed + `PEER_OAM_URL`) | **200** — OAM is the issuer (`iss=oam-api`); response includes `account_type` |
| Personal account + non-empty org header | **403** (`tenant mismatch`) on protected routes |
| Organization account + org header ≠ JWT `org_id` | **403** (`tenant mismatch`) |
| Platform admin directory | **Users** + **organisations** listings work without impersonation |
| Platform admin tenant product work | Impersonate a user (`POST /api/auth/impersonate`) or send a **concrete** org — never silent `default-org` |

Canonical headers (case-insensitive): `Authorization: Bearer <oam-jwt>`, `X-Organization-ID`, `X-Project-ID` (single), optional list-only `X-Project-IDs`. Query fallbacks `organization_id` / `project_id` match. Picker marker `"all"` on **`X-Project-ID`** is stripped under auth and does **not** widen scope. Dashboard UI “All projects” stamps **`X-Project-IDs`** with enabled OAM directory ids for that product — it does **not** redefine `X-Project-ID: all`. See [interop.md — Family project switcher](interop.md#family-project-switcher-oam-directory).

## Account types (JWT-bound tenancy)

Users are created in OAM with immutable `account_type`: **`personal`** or **`organization`**. There is no attach, detach, or type change after creation. There is **no** shared `default-org` fallback for empty / omitted headers.

| Caller | Behavior |
|--------|----------|
| **Personal** | Owner-only (`user_id`). Empty org. Never invent `default-org`. |
| **Organization member** | JWT `org_id` pinned. Foreign org → **403**. Never invent `default-org`. |
| **Platform admin (own session)** | **Users** + **organisations** directory listings OK. Tenant-scoped product lists/writes with no org and no impersonation → **empty / 400** — not `default-org`. |
| **Admin impersonating** | Session JWT is the **target user’s** tenancy plus `impersonator=<admin>`. Products treat them as that user. |

| `account_type` | JWT `org_id` | Org headers | Project headers |
|----------------|--------------|-------------|-----------------|
| `personal` | always empty | Rejected when set (except picker `"all"`, which is stripped) | Allowed — scope personal (owner-only) namespace |
| `organization` | fixed home org | Must match JWT `org_id` or be omitted (overwritten from JWT) | Allowed within org; `project_ids` ACL still applies |

Open-Auth-Go enforces this in `ApplyUserTenantHeaders` before list/write handlers run. Personal accounts always get `X-Tenant-User-ID` stamped from the JWT username; organization accounts get `X-Organization-ID` overwritten from JWT `org_id`. Admin impersonation is minted by OAM (`POST /api/auth/impersonate`); stop restores the admin token client-side (or via stop endpoint when present).

```bash
HOST=192.168.100.101   # NAS; OAM on :18090, hub on :18080

# Login — note account_type in the JSON body
curl -sf -X POST "http://$HOST:18090/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' \
  | jq '{issuer, account_type, org_id}'

PERSONAL_TOKEN=$(curl -sf -X POST "http://$HOST:18090/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' | jq -r .token)

# Personal account + explicit org header → 403 on a protected list
curl -s -o /dev/null -w '%{http_code}\n' \
  "http://$HOST:8093/api/security/runs?limit=5" \
  -H "Authorization: Bearer $PERSONAL_TOKEN" \
  -H "X-Organization-ID: nas" -H "X-Project-ID: infra"
# expect 403

# Organization member (create via OAM admin API first) — foreign org header → 403
# ORG_TOKEN=…  # user with account_type=organization, org_id=nas
# curl -s -o /dev/null -w '%{http_code}\n' \
#   "http://$HOST:8093/api/security/runs?limit=5" \
#   -H "Authorization: Bearer $ORG_TOKEN" \
#   -H "X-Organization-ID: default-org" -H "X-Project-ID: default-project"
# expect 403
```

Attempting to change `account_type` or `organization_id` via `POST /api/users/set` returns **400** (`immutable_account_type` / `immutable_organization`).

## NAS ports

| Product | API host port | Representative protected list |
|---------|---------------|-------------------------------|
| Hub | `18080` | `GET /api/infra/hosts`, `GET /api/alerts`, `GET /api/tenancy/organizations` |
| OAM | `18090` | `GET /api/users`, `POST /api/auth/login` |
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
# nohdr must NOT equal explicit default-org (empty / 400 / JWT-pin — never silent fallback)
curl -s -o /tmp/runs-nohdr.json -w '%{http_code}\n' \
  "http://$HOST:8093/api/security/runs?limit=50" "${AUTH[@]}"
jq '.runs | length' /tmp/runs-nohdr.json   # expect 0 (or HTTP 400 above) for unbound admin
curl -sf "http://$HOST:8093/api/security/runs?limit=50" "${DEF[@]}" \
  | jq '.runs | length'          # only when default-org is explicitly selected
curl -sf "http://$HOST:8093/api/security/runs?limit=50" "${WRONG[@]}" \
  | jq '.runs | length'          # 0
curl -sf "http://$HOST:8093/api/security/runs?limit=50" "${NAS_T[@]}" \
  | jq '.runs | length'          # nas/infra only

# Repeat the four AUTH/DEF/WRONG/NAS_T GETs for:
#   hub  /api/infra/hosts          → .hosts
#   hub  /api/alerts               → .alerts
#   ora  /api/connectors           → .connectors
#   ora  /api/scm/jobs?limit=50    → .jobs
#   osa  /api/security/secrets     → .findings
#   opl  /api/perf/scenarios       → .scenarios
#   opl  /api/perf/runs?limit=50   → .runs
#   opm  /api/projects             → .projects

# --- OPM IDOR (wrong org must not resolve another org's UUID) ---
PID=$(curl -sf "http://$HOST:8096/api/projects" "${DEF[@]}" | jq -r '.projects[0].id')
for suffix in '' /board /jobs /tasks /status; do
  curl -s -o /dev/null -w "%{http_code} projects/\$PID$suffix\n" \
    "http://$HOST:8096/api/projects/${PID}${suffix}" "${WRONG[@]}"
done   # expect 404 (not 200 with foreign project)
```

Automated checklist: [`harness/security-tenant-matrix.sh`](../harness/security-tenant-matrix.sh)

```bash
HOST=192.168.100.101 ./harness/security-tenant-matrix.sh
# Optional image check on NAS (needs SSHPASS for root@HOST):
#   CHECK_IMAGES=1 SSHPASS=… HOST=192.168.100.101 ./harness/security-tenant-matrix.sh
```

## GitHub connector lists

GitHub App connectors bind via signed install `state` or one-time claim nonce — organization Open accounts stamp `organization_id`; personal Open accounts stamp `user_id` (empty org, `scope=user`). Product APIs that list connectors for runtime must only return **active** connectors visible to the caller’s tenant. `pending_claim` / empty-org org-scoped rows are invisible until claimed.

| Product | List endpoint | Upstream | Isolation |
|---------|---------------|----------|-----------|
| **ORA** | `GET /api/connectors` | Live / CH | User + service JWT: active + matching org only; foreign get → **404**; pendings hidden |
| **OAM** | `GET /api/connectors` | Directory (`oam.connectors`) | Forced to actor org; foreign `?organization_id=` → **403**; platform admin cross-org only with `all_organizations=1` |
| **OPM** | `GET /api/github/connectors` | Peer service JWT → ORA | Re-filters active/same-org; attach uses directory `connector_ids`; foreign `connectorId` → **404**, pending → **403** |
| **OSA** | `GET /api/github/connectors` | Proxy user JWT → ORA | Re-filters active/same-org; create may resolve from OAM project; foreign `connector_id` → **403** |

**No product dashboard connector pickers** for scoping work. The family project switcher (single project or **All projects** → `X-Project-IDs`) drives which OAM `connector_ids` apply. **OAM Connectors** (`/connectors`) is the write home: install, claim, PAT, edit, delete, and watched-repo registration. ORA refuses browser mutations when `PEER_OAM_URL` is set; OPM/OSA deep-link “Manage in Account Manager” to OAM and never ship a second install/claim console.

**OAM directory vs OPM registry:** OAM `GET/POST /api/projects*` manage family directory tenancy (including `disabled_products` and `GET ?product=`). GitHub-backed directory rows may include `external_id` and `connector_ids` (import/discovery via `PEER_ORA_URL`). That does not replace OPM’s own project registry or link flow — the two remain separate. Family dashboard switchers consume OAM directory ids (`GET /api/oam/projects?product=opm`); OPM board UUIDs stay on Projects/Board flows.

### Per-product project access (`disabled_products`)

Directory projects may denylist Open products via `disabled_products` (empty = all enabled). **Only OAM Dashboard `/projects`** edits this (checkbox matrix + row/table select-all → `POST /api/projects/products/set` / `set-bulk`). Peer dashboards list enabled-only via `?product=<opa|osa|ora|opl|opm>` and never ship a second enablement UI. Job/scan entrypoints fail closed when the acting product is disabled for the concrete project (skip when `PEER_OAM_URL` unset or `X-Project-ID` empty/`all`). OPM nested board paths `/api/projects/{uuid}/…` are skipped (board UUID ≠ directory id). OPA-Hub has no directory-stamped job enqueue today.

**Install / claim / peer:**

- Install from OAM Connectors (`GET …/install-url` via OAM BFF). Organization Open sessions (org members, viewer+) bind by org; personal Open sessions bind under `user_id` (empty org) so they can install on GitHub orgs they admin. Platform admin may overview all connectors; Connect / claim / edit are not admin-only.
- Marketplace/orphan callback mints a one-time `claim_token` (hash stored) and redirects to `OAM_DASHBOARD_URL/connectors`; `POST /api/connectors/{id}/claim` `{ "claim_token": "…" }` on **oam-api** — wrong nonce **403**, double claim **409**, personal without username **400**. Org members and personal users claim into their own tenant.
- Peer resolve (`clone` / PM / PR): fail closed — require `status=active`. Org connectors need a non-empty matching `org_id`; personal user-scoped connectors (empty org) authorize when the peer service/job JWT carries a matching `user_id` (**403** otherwise).

```bash
# Connector list scopes (wrong org must never return another tenant’s installs)
curl -sf "http://$HOST:8091/api/connectors" "${WRONG[@]}" | jq '.connectors | length'   # 0
curl -sf "http://$HOST:18090/api/connectors" "${WRONG[@]}" | jq '.connectors | length'  # 0 or 403
curl -sf "http://$HOST:8096/api/github/connectors" "${WRONG[@]}" | jq '.connectors | length'  # 0
curl -sf "http://$HOST:8093/api/github/connectors" "${WRONG[@]}" | jq '.connectors | length'  # 0
```

## Pass criteria

- Every protected route above returns **401** without JWT.
- Peer product local login returns **503**.
- OAM (or hub-proxied) login returns **`account_type`** and **`issuer=oam-api`** when `PEER_OAM_URL` is set.
- Personal accounts reject non-empty org headers (**403**); organization accounts reject foreign org headers (**403**).
- `POST /api/users/set` rejects `account_type` / `organization_id` changes (**400**).
- Wrong-org list length is **0** (or HTTP **403**); counts must not match another real tenant’s non-empty set.
- No-header counts must **not** equal explicit `default-org` / `default-project` when that tenant has data — expect **empty**, **400**, or JWT-pinned own scope (personal owner-only / org pin). Never silent `default-org`.
- Platform admin directory (`GET /api/users`, org listings) works without impersonation; tenant product browsing uses impersonate or a concrete org.
- OPM `GET /api/projects/{id}` (+ board/jobs/tasks/status) with a foreign org header returns **404**, not another tenant’s project.
- OSA `GET /api/security/runs/{id}` returns **401** without JWT.
- `POST /api/peer/scm/clone-credentials` rejects hub user JWTs (**401**).
- Connector lists (ORA / OAM / OPM / OSA) never return another org’s installs; OAM bare admin GET is not an unfiltered dump.
- Running containers for hub / ora-api / osa-api / opl-api / opm-api resolve to **`*:nas`** image names (never `*:smoke`).

## NAS verification (2026-08-04)

> **Post-cutover note (2026-08-06):** OAM is now the family JWT issuer (`issuer=oam-api`, dashboard `/oam-auth/`). The matrix below used hub-issued tokens; re-run the harness against OAM-issued JWTs after NAS `*:nas` rebuild before declaring cutover complete.

Executed against `192.168.100.101` with hub JWT `admin`/`admin` and `CHECK_IMAGES=1` (all `Config.Image=*:nas`, no `*:smoke`):

| Surface | Hardener | Result |
|---------|----------|--------|
| Hub list scopes (`/api/infra/hosts`, `/api/alerts`, …) | [OPA-Hub #25](https://github.com/TheGrimmChester/OPA-Hub/pull/25), [Open-Auth-Go #5](https://github.com/TheGrimmChester/Open-Auth-Go/pull/5) | Historical: no-headers ≡ default-org (superseded — expect empty/400/JWT-pin, never silent default-org) |
| ORA connectors / SCM jobs | [ORA-API #21](https://github.com/TheGrimmChester/ORA-API/pull/21) | Historical WriteTenant default superseded — nohdr ≠ default-org; wrong-org empty; no all-tenant dump |
| ORA peer `POST /api/peer/scm/clone-credentials` | ORA-API #21 | **PASS** — user JWT → **401** (`invalid service token`) |
| OSA security runs / secrets lists | prior Open-Tenant-Go ≥ 0.2.2 | Wrong-org empty; nas/infra distinct; nohdr must not equal default-org |
| OSA `GET /api/security/runs/{id}` (+ findings) | [OSA-API #13](https://github.com/TheGrimmChester/OSA-API/pull/13) | **PASS** — no JWT → **401**; +JWT → **200** |
| OPL perf scenarios / runs | already tenant-scoped | Wrong-org empty; nohdr ≠ silent default-org |
| OPM projects list | [OPM-API #12](https://github.com/TheGrimmChester/OPM-API/pull/12), [OPM-Dashboard #7](https://github.com/TheGrimmChester/OPM-Dashboard/pull/7) | **PASS** — list filtered by org; wrong-org empty |
| OPM IDOR by UUID (board/jobs/tasks/status) | OPM-API #12 | **PASS** — wrong-org → **404** |
| No JWT / co-deployed local login | family auth | **PASS** — 401 on protected routes; peer `/api/auth/login` → 503 |

Family harness: **56 PASS / 0 FAIL**. Sibling ORA/OSA curl matrix reported **13/13 PASS** on `ora-api:nas` / `osa-api:nas`.

## Documented gaps

- **Per-user project ACLs (hub + peers + Open-Auth-Go):** JWT `project_ids` allowlist. Hub middleware and product `Gate.Middleware` (`AuthMiddleware`) call `EnforceProjectACL` after `ApplyUserTenantHeaders`. Role `admin` bypasses the project allowlist and may list users/orgs; tenant product data still requires impersonation or a concrete org — never silent `default-org`. Lab seed `admin`/`admin` stays unbound. No second membership store — OAM-minted claims.
- Prefer always sending concrete `X-Organization-ID` / `X-Project-ID` from dashboards and scripts (or admin impersonation for tenant browse). For multi-project list views, use `X-Project-IDs` (enabled directory ids); never overload `X-Project-ID: all` as org-wide unscoped. Never rely on silent `default-org`.
- Product access (`disabled_products`) is managed only on OAM `/projects`; peers consume filtered OAM lists.
- **Webhook-only orphan installs:** an install that arrives only via GitHub webhook (no browser callback) may create `pending_claim` **without** a one-time `claim_token` in a redirect. Those rows stay invisible until a callback/claim path issues a nonce — operators must re-run install-from-Open or use a future admin reclaim flow.

### Adoption notes (ORA / OSA / OPL / OPM) — done

1. ~~Bump `open-auth-go`~~ — peers replace `../Open-Auth-Go` (Open-Auth-Go #6); NAS Docker COPY picks it up via `sync-nas-src`.
2. ~~`EnforceProjectACL` after `ApplyUserTenantHeaders`~~ — via Open-Auth-Go `Gate.RequireUser` / `RequireUserOrService` (product `AuthMiddleware`).
3. ~~No second membership store~~ — trust hub-minted `org_id` / `project_ids`.
4. ~~Admin unrestricted~~ — role `admin` bypasses allowlist (lab login stays unlocked).
5. Optional: surface `user.project_ids` from hub login/status in each dashboard project picker.

## Notes

- Hub observability JSON may omit an `organization_id` field on rows; scoping is still enforced via query filters when headers are present ([OPA-Hub #25](https://github.com/TheGrimmChester/OPA-Hub/pull/25)).
- Peer clone credentials require a **service JWT** (`OPEN_SERVICE_JWT_SECRET`, scope `scm:clone`) — never a user JWT.
- Dashboard **`/oam-auth/`** bridges (ports `8089` / `8094` / `8095` / `8098`) are the preferred browser login path to OAM; **`/hub-auth/`** still works (hub proxies to OAM when `PEER_OAM_URL` is set). Product APIs stay on the ports above.
