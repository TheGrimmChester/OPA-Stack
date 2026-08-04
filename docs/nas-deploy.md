# NAS production deploy (Open-* family)

This document describes the production Open-* stack on the TrueNAS host.

## Identity

| Item | Value |
|------|--------|
| Compose project | `open-family` |
| Directory | `/mnt/Apps/config-docker/open-stack` |
| Legacy path | `/mnt/Apps/config-docker/opa` — kept as a **symlink** to `open-stack` so existing overlays and bind mounts keep working |
| Compose file | `compose.nas.yaml` (copied or linked as `docker-compose.yaml` on the host) |
| Image tags | `*:nas` only — never deploy `*:smoke` on this host |

## Services and ports

| Service | Image | Host port |
|---------|-------|-----------|
| ClickHouse | `clickhouse/clickhouse-server:24.3` | `8123` |
| OPA Hub | `opa-hub:nas` | `18080` → `8080` |
| OPA edge agent | `opa-agent:nas` (`container_name: opa_agent`) | `18081` → `8080`, plus `9090`, `2112`, `8082` |
| OPA Dashboard | `opa-dashboard:nas` | `8088` |
| ORA API | `ora-api:nas` | `8091` (LAN); public base `ORA_PUBLIC_URL` / `OPA_PUBLIC_URL` — on this host `https://ai-orchestrator.clouded.fr` (legacy DNS name for **ora-api** webhooks and review callbacks; compose service `ora-api` in project `open-family`) |
| ORA Dashboard | `ora-dashboard:nas` | `8089` |
| OSA API | `osa-api:nas` | `8093` |
| OSA Dashboard | `osa-dashboard:nas` | `8094` |
| OPL API | `opl-api:nas` | `8092` |
| OPL Dashboard | `opl-dashboard:nas` | `8095` |
| OPM API | `opm-api:nas` | `8096` |
| OPM Dashboard | `opm-dashboard:nas` | `8098` |
| Egress proxy | `open-egress-proxy:nas` | (internal) |
| Collector | `opa-collector:nas` | host network → agent `:9090` |

Orchestrators for ORA/OSA/OPL/OPM use the same API images with an `orchestrator` command. Runner images (`ora-runner-git:nas`, `osa-runner-scan:nas`, `opl-runner-jmeter:nas`, `opm-runner-task:nas`) are built for on-demand jobs and are not always-on services.

## ClickHouse

One server, four product databases: `opa`, `ora`, `osa`, `opl`.

**Volume migration:** the compose file mounts the existing Docker volume `opa-stack_opa_clickhouse_data` as an **external** volume. Do not delete or recreate this volume. Create missing product databases with:

```sql
CREATE DATABASE IF NOT EXISTS opa;
CREATE DATABASE IF NOT EXISTS ora;
CREATE DATABASE IF NOT EXISTS osa;
CREATE DATABASE IF NOT EXISTS opl;
```

Pre-split review/security/perf tables that still live under database `opa` are left in place. New ORA/OSA/OPL writes go to their own databases. No destructive table moves are performed by this stack rename.

**Legacy hub product tables:** before per-product databases, some ORA/OSA rows were written only to `opa.*`. On boot, `ora-api:nas` and `osa-api:nas` backfill missing rows into `ora.*` / `osa.*` when hub counts exceed product counts (connectors use row-level backfill; other tables use bulk `INSERT SELECT`). See [interop.md](interop.md#legacy-hub-opa-product-tables). After recreate, check API logs for `legacy backfill` / `table rows backfilled`; no manual SQL is required on new deploys.

## Networks

- `open_internal` — stack-private bridge
- `opa_network` — **external**, unchanged name so Planner / PHP app overlays (`OPA_SOCKET_PATH=opa_agent:9090`) keep resolving

## Auth

Co-deployed mode: shared `JWT_SECRET`, `AUTH_MODE=codeployed`, and `OPA_AUTH_REQUIRED=1` on **hub, ora-api, osa-api, opl-api, and opm-api**. Peers set `PEER_OPA_URL=http://hub:8080`. Hub issues user JWTs; product APIs validate them. Product-local `/api/auth/login` returns `503` in co-deployed mode.

**Dashboard login:** ora-dashboard (`8089`), osa-dashboard (`8094`), opl-dashboard (`8095`), and opm-dashboard (`8098`) expose a same-origin **`/hub-auth/`** proxy to `hub:8080`. Browsers sign in via `/hub-auth/api/auth/login`; product API `/api/auth/login` stays disabled (`503`). Verify with:

```bash
for port in 8089 8094 8095 8098; do
  curl -sf "http://127.0.0.1:$port/hub-auth/api/auth/status" | jq -r .issuer   # opa-hub
done
curl -sf -X POST http://127.0.0.1:8098/hub-auth/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' | jq -r .token
```

Set **`OPEN_SERVICE_JWT_SECRET`** to a second secret (≥32 bytes), **distinct from** `JWT_SECRET`. Do not reuse the user JWT secret for service-to-service mint/validate. Compose passes it through without falling back to `JWT_SECRET`. After rotating the service secret, recreate **hub, ora-api, osa-api, opl-api, and opm-api** so all peers share the new value.

OPM/OSA GitHub targets: `opm-api` and `osa-api` use `PEER_OPA_URL` (org directory) and `PEER_ORA_URL` (connectors / clone credentials). Configure GitHub App or PAT on **ora-api** (`OPA_GITHUB_APP_*`, `OPA_CONNECTOR_SECRET`). **`opm-api:nas` runtime must include `git`** — task jobs clone via ORA credentials inside the API image. After image upgrades, redeploy `opa-hub`, `ora-api`, `opm-api`, `opm-orchestrator`, `opm-dashboard`, `osa-api`, and `osa-dashboard` (`*:nas` tags only).

### Public URLs (`ORA_PUBLIC_URL` / `OPA_PUBLIC_URL`)

Compose sets both to the same public base used for GitHub App webhooks and review callbacks. On this NAS host that base is still `https://ai-orchestrator.clouded.fr` — a **legacy DNS name** that fronts **`ora-api`** (not a separate product). New installs should prefer an `ora-api.*` hostname when DNS is updated; until then keep the existing name so webhook deliveries continue. Do not point these variables at `opa-hub` or dashboard ports.

### GitHub App slug (`OPA_GITHUB_APP_SLUG`)

ORA uses `OPA_GITHUB_APP_SLUG` as the GitHub App login when requesting reviewers. The compose default for new installs is `ora`. **Production must set the slug of the App that is actually installed** — do not change a live slug to match a code default.

On this NAS host the installed App slug is `opa-ai-orchestrator` (set in `/mnt/Apps/config-docker/open-stack/.env`). Keep that value until the GitHub App itself is renamed or replaced.

## Sync source before rebuild

NAS image builds read from sibling checkouts under `src/`. Those trees **must track `origin/main`** — stale rsync copies (no `.git`) have caused rebuilds that ship old code even after PR merges.

### On the NAS (preferred)

Git is available on the host; use the harness sync script to shallow-clone or fast-forward every family repo:

```bash
export FAMILY_ROOT=/mnt/Apps/config-docker/open-stack/src
chmod +x "$FAMILY_ROOT/OPA-Stack/harness/sync-nas-src.sh"

# Audit git vs stale and HEAD vs GitHub main
"$FAMILY_ROOT/OPA-Stack/harness/sync-nas-src.sh" --audit

# Sync everything (or pass repo names: OPA-Hub ORA-API …)
"$FAMILY_ROOT/OPA-Stack/harness/sync-nas-src.sh"
```

First run converts stale copies into shallow git clones; later runs are `git fetch origin main` + fast-forward.

**Before every NAS rebuild:** run sync, then `rebuild-nas-images.sh`. Skipping sync ships stale source even when GitHub main has merged fixes.

### From the laptop (fallback)

When the NAS cannot reach GitHub, rsync from a local sibling tree (for example `~/Documents/repos`):

```bash
export FAMILY_ROOT=~/Documents/repos
OPA-Stack/harness/sync-nas-src.sh --rsync \
  --nas-host root@192.168.100.101 \
  --laptop-root "$FAMILY_ROOT" \
  OPA-Hub ORA-API
```

Then rebuild on the NAS. Prefer converting to git clones on the NAS when network access is restored.

## Build images on the NAS

From a sibling checkout tree (for example `/mnt/Apps/config-docker/open-stack/src`):

```bash
export FAMILY_ROOT=/mnt/Apps/config-docker/open-stack/src
"$FAMILY_ROOT/OPA-Stack/harness/rebuild-nas-images.sh"
```

This script tags **only** `*:nas`. Do not run `harness/rebuild-smoke-images.sh` on the NAS.

## Bring-up

```bash
cd /mnt/Apps/config-docker/open-stack
# ensure docker-compose.yaml is the NAS file (compose.nas.yaml)
docker compose pull clickhouse   # or rely on local *:nas images
docker compose up -d
docker compose ps
```

## Health checks

```bash
curl -sf http://127.0.0.1:18080/api/health   # hub
curl -sf http://127.0.0.1:8091/api/health    # ora
curl -sf http://127.0.0.1:8093/api/health    # osa
curl -sf http://127.0.0.1:8092/api/health    # opl
curl -sf http://127.0.0.1:8096/api/health    # opm
curl -sf -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8088/
curl -sf -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8089/
curl -sf -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8094/
curl -sf -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8095/
curl -sf -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8098/
```

### Hub dashboard routes (authenticated)

Recent hub batches moved Infrastructure, Compare Traces, System, and Databases reads to **opa-hub** (`18080`). Smoke with hub login:

```bash
TOKEN=$(curl -sf -X POST http://127.0.0.1:18080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' | jq -r .token)

for path in \
  /api/infra/hosts \
  '/api/transactions/compare?dimension=name' \
  /api/version \
  /api/topology \
  /api/ops/status \
  /api/audit \
  /api/db/instances \
  /api/db/statements \
  /api/db/fingerprint-match \
  /api/db/unused-indexes; do
  curl -sf -o /dev/null -w '%{http_code} %s\n' -H "Authorization: Bearer $TOKEN" \
    "http://127.0.0.1:18080$path" "$path"
done
```

Expect `200` on each path. Product APIs should return `503` on local login in co-deployed mode:

```bash
curl -sf -o /dev/null -w '%{http_code} ora\n' -X POST http://127.0.0.1:8091/api/auth/login \
  -H 'Content-Type: application/json' -d '{"username":"admin","password":"admin"}'
```

### Product list APIs need tenant headers

With `OPA_AUTH_REQUIRED=1`, OSA/OPL ClickHouse list endpoints scope to **`default-org` / `default-project`** when `X-Organization-ID` / `X-Project-ID` are omitted (HTTP 200, after Open-Tenant-Go ≥ 0.2.2). Send both headers to target another tenant. Canonical curl matrix: [interop.md — Tenant headers](interop.md#tenant-headers-required-when-auth-is-on).

```bash
TOKEN=$(curl -sf -X POST http://127.0.0.1:18080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' | jq -r .token)
H=(-H "Authorization: Bearer $TOKEN" -H "X-Organization-ID: default-org" -H "X-Project-ID: default-project")
curl -sf "http://127.0.0.1:8093/api/security/runs?limit=5" "${H[@]}" | jq '.runs | length'
curl -sf "http://127.0.0.1:8092/api/perf/scenarios" "${H[@]}" | jq '.scenarios | length'
```

**Batch 4 deferred routes (expected 404 on hub `:18080`):** Network (`/api/network/*`), Cloud (`/api/cloud/*`), Catalog (`/api/catalog*`), mgmt (`/api/mgmt/v1*`), and call-graph compare (`/api/callgraph/compare`). These dashboard pages are scaffolds with no backend yet — do not treat 404 as a regression. Filter suggestions (`/api/filter-suggestions/*`) return **404 on hub** and **200 on edge** `:18081` (dashboard does not call them today).

## Alert email delivery

Alert **evaluation and notification delivery** run on the edge agent (`opa_agent`). The hub stores rules in `opa.alerts` and queues manual tests in `opa.alert_test_requests`; the agent leader polls every ~2s and writes `opa.alert_history`.

Email recipients live in each rule’s `action_config.to` (dashboard Alerts UI). **SMTP credentials stay on the agent host** — set them in `/mnt/Apps/config-docker/open-stack/.env`, not in ClickHouse or git.

| Variable | Default | Effect |
|----------|---------|--------|
| `OPA_ALERT_NOTIFY_MODE` | `deliver` | `deliver` sends to configured channels. `log` (aliases: `log-only`, `dry-run`) records intent only — history `status=logged`. |
| `OPA_SMTP_HOST` | *(unset)* | SMTP hostname. When unset, email actions append history with `status=logged` instead of failing silently. |
| `OPA_SMTP_PORT` | `587` | SMTP port (STARTTLS when advertised) |
| `OPA_SMTP_USER` | *(unset)* | Optional auth username |
| `OPA_SMTP_PASS` | *(unset)* | Optional auth password — **host `.env` only** |
| `OPA_SMTP_FROM` | `OPA_SMTP_USER` or `opa-agent@localhost` | Envelope From address |

See [`compose.nas.env.example`](../compose.nas.env.example) for a copy-paste SMTP block. Full agent env reference: [OPA-Agent configuration](https://github.com/TheGrimmChester/OPA-Agent/blob/main/docs/configuration.md#alert-notification-channels).

### Enable real email on NAS

1. Add SMTP variables to `.env` on the host (example — use your provider’s values):

   ```bash
   OPA_ALERT_NOTIFY_MODE=deliver
   OPA_SMTP_HOST=smtp.example.com
   OPA_SMTP_PORT=587
   OPA_SMTP_USER=your-user
   OPA_SMTP_PASS=your-password
   OPA_SMTP_FROM=opa-alerts@your-domain.example
   ```

2. Recreate **only** the edge agent (never smoke tags):

   ```bash
   cd /mnt/Apps/config-docker/open-stack
   docker compose up -d opa_agent
   ```

3. Create or edit an alert with `action_type=email` and a valid `to` address in the dashboard (Alerts → Test) or via hub API.

### Verify the delivery path (safe without SMTP)

With SMTP unset, a manual test should still complete end-to-end with `status=logged`:

```bash
# Hub login (co-deployed default user)
TOKEN=$(curl -sf -X POST http://127.0.0.1:18080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' | jq -r .token)

# Create a test rule (adjust org/project if your tenancy differs)
ALERT_ID=$(curl -sf -X POST http://127.0.0.1:18080/api/alerts \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"email-path-test","enabled":true,"condition_type":"custom",
       "condition_config":{"threshold":0,"operator":"gt"},
       "action_type":"email","action_config":{"to":"ops@example.com"}}' | jq -r .id)

# Fire Test (queues opa.alert_test_requests → agent force-delivers)
curl -sf -X POST "http://127.0.0.1:18080/api/alerts/$ALERT_ID" \
  -H "Authorization: Bearer $TOKEN" | jq .

# History: logged = no SMTP; sent = delivered; failed = SMTP/dest error
curl -sf "http://127.0.0.1:18080/api/alerts/$ALERT_ID/history" \
  -H "Authorization: Bearer $TOKEN" | jq .
```

After SMTP is configured, repeat the test and expect `status=sent` (or `failed` if credentials/network are wrong).

## Egress proxies (compose vs orchestrator)

Two long-lived egress containers are expected on NAS — do **not** treat the orchestrator proxy as an open-family leftover:

| Container | Owner | Purpose |
|-----------|-------|---------|
| `open_egress_proxy` | Compose project `open-family` (`open-egress-proxy` service) | Stack-internal allowlist proxy (`*:nas` image only) |
| `open-egress-proxy-<OPA_INSTANCE_ID>` (prod: `open-egress-proxy-nas-prod`) | Orchestrator (`opa.owner=opa-orchestrator`, `opa.role=egress-proxy`) | Shared job-sandbox proxy; ORA attaches it to `opa-egress-<instance>` and per-job `opa-job-*` networks with DNS alias `open-egress-proxy` |

### Safe orphan cleanup

Inspect before deleting:

```bash
docker ps -a --filter name=egress --format \
  '{{.Names}}\tproject={{.Label "com.docker.compose.project"}}\toneoff={{.Label "com.docker.compose.oneoff"}}\towner={{.Label "opa.owner"}}\trole={{.Label "opa.role"}}'
```

**Remove only when clearly stale:**

- `egress-connect-probe` (or similar) with `com.docker.compose.oneoff=True` — leftover from `docker compose run`
- Pre-rename `opa-egress-proxy-<instance>` once `open-egress-proxy-<instance>` is healthy and in use
- Empty `opa-job-*` networks that only still list the shared orchestrator proxy (disconnect proxy, then `docker network rm`)

**Keep** `open_egress_proxy` and `open-egress-proxy-<instance>`. If unsure, leave the container and document it — do not delete production unknowns. Never recreate NAS services with `*:smoke` tags.

### Post-cleanup checks

```bash
docker exec open_egress_proxy wget -qO- http://127.0.0.1:3128/healthz
# CONNECT to a non-allowlisted host must 403, e.g.:
# curl -x http://open_egress_proxy:3128 https://example.com/  → CONNECT tunnel failed, response 403
cd /mnt/Apps/config-docker/open-stack && docker compose -p open-family ps
```

## Rollback

1. `docker compose -p open-family down` (does **not** remove the external ClickHouse volume).
2. Restore the previous `docker-compose.yaml` under the stack directory (backups are timestamped beside the file).
3. `docker compose -p opa-stack up -d` with the legacy file if needed.
4. Confirm volume `opa-stack_opa_clickhouse_data` is still present: `docker volume ls | grep opa_clickhouse`.

## Related

- [Products](products.md)
- [Interop and ClickHouse databases](interop.md)
- Laptop smoke: `compose.all.yaml` + `*:smoke` only
