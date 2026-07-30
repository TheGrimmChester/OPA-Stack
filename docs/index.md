# Open Profiling Agent documentation

Single entry point for the self-hosted observability stack.

## Quick links

- [Five-minute quickstart](../harness/quickstart.sh) (run from repo root via `./harness/quickstart.sh`)
- [Licensing FAQ](LICENSING.md)
- [Architecture](architecture.md)
- [Data model](data-model.md)
- [Generated config reference](config-reference.md)
- [Distribution](distribution.md)
- [OTLP compatibility](otlp-compatibility.md)
- [Benchmarks](../benchmarks/README.md)

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
