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

## HA overlay (Wave 15)

```bash
docker compose -f docker-compose.yaml -f docker-compose.ha.yaml up -d
```

## Helm (optional)

See [helm/opa/README.md](helm/opa/README.md). Compose remains the default one-box path.

## Docs

Start at [docs/index.md](docs/index.md).

## License

EUPL-1.2 for this packaging repo — see [LICENSE](LICENSE) and [docs/LICENSING.md](docs/LICENSING.md).
