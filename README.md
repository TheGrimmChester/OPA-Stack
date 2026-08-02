# OPA Stack — smoke rig + quickstart

Self-hosted compose for ClickHouse + Agent + Dashboard (+ optional app harnesses).

## Five-minute quickstart

```bash
chmod +x harness/quickstart.sh harness/demo-traffic.sh
./harness/quickstart.sh
```

Open http://127.0.0.1:8088 — the dashboard should already contain demo spans.

Tear down:

```bash
docker compose -p opa-quickstart down
```

## Rebuild local smoke images

After pulling Agent/Dashboard branches, rebuild and recreate containers:

```bash
chmod +x harness/rebuild-smoke-images.sh
./harness/rebuild-smoke-images.sh
```

Defaults to sibling `../OPA-Agent` and `../OPA-Dashboard`, preferring current local feature tips when present. Options:

| Env | Effect |
|-----|--------|
| `AGENT_REF` / `DASH_REF` | Checkout that git ref before build |
| `RECREATE_CLICKHOUSE=1` | Also force-recreate ClickHouse |
| `AGENT_DIR` / `DASH_DIR` | Override sibling paths |

Waits for `http://127.0.0.1:8080/api/health` before exiting.

## API smoke

Exercises new Agent APIs (DB, FaaS, vuln/IAST, synthetics, catalog, mgmt, cloud, network, federation, collab, diagnostics) plus a light baseline (health, version, topology, TQL dry-run). Soft-fails empty datasets; hard-fails unexpected HTTP/missing keys.

```bash
# Agent must be up (auth left open unless OPA_AUTH_REQUIRED=1)
./harness/rebuild-smoke-images.sh   # once, from current local tips
docker compose up -d clickhouse agent dashboard

chmod +x harness/api-smoke.sh
./harness/api-smoke.sh
```

Or via compose profile:

```bash
docker compose --profile api-smoke run --rm api-smoke
```

Or fold into quickstart:

```bash
API_SMOKE=1 ./harness/quickstart.sh
```

Fixtures live under `harness/fixtures/` (e.g. `cloud-monitor.smoke.json`). Compose mounts them and sets `OPA_CLOUD_MONITOR_CONFIG`, `OPA_NETWORK_SAMPLER=1`, `OPA_REGION`, and `OPA_CLOUD_REQUIRED_TAGS` on the agent.

## HA overlay (HA / scale)

```bash
docker compose -f docker-compose.yaml -f docker-compose.ha.yaml up -d
```

## Helm (optional)

See [helm/opa/README.md](helm/opa/README.md). Compose remains the default one-box path.

## Docs

Start at [docs/index.md](docs/index.md).

## License

EUPL-1.2 for this packaging repo — see [LICENSE](LICENSE) and [docs/LICENSING.md](docs/LICENSING.md).
