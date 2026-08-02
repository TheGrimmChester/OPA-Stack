# Open Profiling Agent documentation

Single entry point for the self-hosted observability stack.

## Quick links

- [Five-minute quickstart](../harness/quickstart.sh) (run from repo root via `./harness/quickstart.sh`)
- [Rebuild smoke images](../harness/rebuild-smoke-images.sh) (`./harness/rebuild-smoke-images.sh`)
- [API smoke](../harness/api-smoke.sh) (`./harness/api-smoke.sh` or `API_SMOKE=1 ./harness/quickstart.sh`)
- [Licensing FAQ](LICENSING.md)
- [Architecture](architecture.md)
- [Data model](data-model.md)
- [Generated config reference](config-reference.md)
- [Distribution](distribution.md)
- [OTLP compatibility](otlp-compatibility.md)
- [Benchmarks](../benchmarks/README.md)

## API smoke

With Agent + ClickHouse up (prefer a current Agent tip via `rebuild-smoke-images.sh`):

```bash
./harness/rebuild-smoke-images.sh
docker compose up -d clickhouse agent dashboard
./harness/api-smoke.sh
# or: docker compose --profile api-smoke run --rm api-smoke
```

Auth stays off unless `OPA_AUTH_REQUIRED=1`. Empty list payloads soft-fail; unexpected status codes fail the suite.

## Component docs (canonical repos)

| Topic | Location |
|-------|----------|
| Ingest API contract | OPA-Agent `docs/AGENT_API_CONTRACT.md` |
| TQL | OPA-Agent `docs/tql.md` |
| Dashboards | OPA-Agent `docs/dashboards.md` |
| HA / scale | OPA-Agent `docs/ha-scale.md` |
| OpenAPI | OPA-Agent `docs/openapi.yaml` |

## Versioned site

This tree is the source for a searchable docs site (MkDocs):

```bash
pip install mkdocs-material
mkdocs serve -f mkdocs.yml
```
