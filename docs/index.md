# Open Profiling Agent documentation


## Open-* family

- [Products](products.md) — OPA · ORA · OSA · OPL · OPM (smoke/NAS ports, Alert Test → edge)
- [Modules catalog](modules.md) — shared `Open-*` libraries and images
- [Interop](interop.md) — peer URLs, co-deployed `/hub-auth` login, service JWT scopes
- [NAS deploy](nas-deploy.md) — `open-family`, `*:nas` images, host ports

Single entry point for the self-hosted observability stack.

## Quick links

- [Five-minute quickstart](../harness/quickstart.sh) (run from repo root via `./harness/quickstart.sh`)
- [Rebuild smoke images](../harness/rebuild-smoke-images.sh) (`./harness/rebuild-smoke-images.sh`)
- [Waves 17–27 API smoke](../harness/wave-smoke.sh) (`./harness/wave-smoke.sh` or `WAVE_SMOKE=1 ./harness/quickstart.sh`)
- [Licensing FAQ](LICENSING.md)
- [Architecture](architecture.md)
- [Data model](data-model.md)
- [Generated config reference](config-reference.md)
- [Distribution](distribution.md)
- [OTLP compatibility](otlp-compatibility.md)
- [Benchmarks](../benchmarks/README.md)

## Wave smoke (17–27)

With Agent + ClickHouse up (prefer agent built from `wave27-diagnostics`):

```bash
./harness/rebuild-smoke-images.sh
docker compose up -d clickhouse agent dashboard
./harness/wave-smoke.sh
# or: docker compose --profile wave-smoke run --rm wave-smoke
```

Auth stays off unless `OPA_AUTH_REQUIRED=1`. Empty list payloads soft-fail; unexpected status codes fail the suite.

## Component docs (canonical repos)

| Topic | Location |
|-------|----------|
| Ingest API contract | OPA-Agent `docs/AGENT_API_CONTRACT.md` |
| TQL | OPA-Agent `docs/wave13a-tql.md` |
| Dashboards | OPA-Agent `docs/wave14-dashboards.md` |
| HA / scale | OPA-Agent `docs/wave15-ha-scale.md` |
| OpenAPI | OPA-Agent `docs/openapi.yaml` |

## Versioned site

This tree is the source for a searchable docs site (MkDocs):

```bash
pip install mkdocs-material
mkdocs serve -f mkdocs.yml
```
