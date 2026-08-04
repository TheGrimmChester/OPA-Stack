# OTLP compatibility matrix

| Signal | Protocol | Path / port | Status |
|--------|----------|-------------|--------|
| Traces | OTLP/HTTP JSON & protobuf | `/v1/traces` (admin API and/or `:4318`) | supported |
| Traces | OTLP/gRPC | `:4317` when `OPA_OTLP_GRPC=1` | supported |
| Metrics | OTLP | — | partial (native metric ND-JSON preferred) |
| Logs | OTLP | — | prefer native log ND-JSON |
| Profiles | OTLP profiles / pprof-ish JSON | `/api/v1/profiles/pprof` | experimental |

**Host / container metrics (`opa-collector`)** do not use OTLP. The collector ships native ND-JSON metric points to the edge agent’s `TRANSPORT_TCP` address (NAS: `127.0.0.1:9090`). Do not point OTel SDKs or an OpenTelemetry Collector at `open_collector` — there is no OTLP listener there. See [nas-deploy.md](nas-deploy.md#host-metrics-collector-open_collector).

Semantic conventions: Agent maps resource `service.name`, HTTP, DB attributes where present (`otlp_semconv.go`). Gaps vs upstream OTel Collector are expected; file issues with a minimal repro.

Third-party SDKs should prefer the [ingest JSON Schema](../schemas/ingest-span.schema.json) for native ND-JSON or OTLP for standards-based export.
