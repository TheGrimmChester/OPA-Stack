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
| ORA API | `ora-api:nas` | `8091` (public: `https://ai-orchestrator.clouded.fr`) |
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

## Networks

- `open_internal` — stack-private bridge
- `opa_network` — **external**, unchanged name so Planner / PHP app overlays (`OPA_SOCKET_PATH=opa_agent:9090`) keep resolving

## Auth

Co-deployed mode: shared `JWT_SECRET`, `AUTH_MODE=codeployed`, peers set `PEER_OPA_URL=http://hub:8080`. Hub issues user JWTs; product APIs validate them.

OPM/OSA GitHub targets: `opm-api` and `osa-api` use `PEER_OPA_URL` (org directory) and `PEER_ORA_URL` (connectors / clone credentials). Configure GitHub App or PAT on **ora-api** (`OPA_GITHUB_APP_*`, `OPA_CONNECTOR_SECRET`). After image upgrades, redeploy `opa-hub`, `ora-api`, `opm-api`, `opm-dashboard`, `osa-api`, and `osa-dashboard` (`*:nas` tags only).

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

## Rollback

1. `docker compose -p open-family down` (does **not** remove the external ClickHouse volume).
2. Restore the previous `docker-compose.yaml` under the stack directory (backups are timestamped beside the file).
3. `docker compose -p opa-stack up -d` with the legacy file if needed.
4. Confirm volume `opa-stack_opa_clickhouse_data` is still present: `docker volume ls | grep opa_clickhouse`.

## Related

- [Products](products.md)
- [Interop and ClickHouse databases](interop.md)
- Laptop smoke: `compose.all.yaml` + `*:smoke` only
