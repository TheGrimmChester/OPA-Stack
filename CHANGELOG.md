# Changelog

## [Unreleased]

### Added
- API smoke suite (`harness/api-smoke.sh`, `harness/lib/smoke-common.sh`, fixtures) and compose profile `api-smoke`.
- `harness/rebuild-smoke-images.sh` to build `opa-agent:smoke` / `opa-dashboard:smoke` from sibling repos and recreate agent/dashboard.
- Compose agent env for cloud monitor fixture, network sampler, region, and required tags (demo-safe).
- Optional `API_SMOKE=1` hook in `harness/quickstart.sh`.
- OSS launch: community files, docs portal (MkDocs), five-minute quickstart, ingest JSON Schema, benchmarks stub, Helm docs index.
- HA / scale: Helm chart and HA compose overlay.
