# Changelog

## [Unreleased]

### Added
- Waves 17–27 API smoke suite (`harness/wave-smoke.sh`, `harness/lib/smoke-common.sh`, fixtures) and compose profile `wave-smoke`.
- `harness/rebuild-smoke-images.sh` to build `opa-agent:smoke` / `opa-dashboard:smoke` from sibling repos and recreate agent/dashboard.
- Compose agent env for cloud monitor fixture, network sampler, region, and required tags (demo-safe).
- Optional `WAVE_SMOKE=1` hook in `harness/quickstart.sh`.
- Wave 16: community files, docs portal (MkDocs), five-minute quickstart, ingest JSON Schema, benchmarks stub, Helm docs index.
- Wave 15: Helm chart and HA compose overlay.
