# Benchmarks (OSS launch)

Reproducible harness stubs. Numbers below are placeholders until CI publishes artifacts.

## What we measure

| Metric | Method |
|--------|--------|
| Extension cost / request | PHP microbench with/without `opa` |
| Bytes / span | Agent ingest counter ÷ span count |
| ClickHouse CPU/RAM per 1k spans/s | compose load + `system.metrics` |

## Run locally

```bash
./benchmarks/run.sh
```

Results land in `benchmarks/out/` as JSON + markdown suitable for publishing.
