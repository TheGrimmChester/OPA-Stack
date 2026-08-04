# Architecture

```
[ App + SDK / PHP ext / RUM / OTLP ]
              |
              v
         OPA-Agent (edge)
      - ND-JSON TCP / Unix socket (:9090)
      - OTLP/HTTP traces (/v1/traces; optional :4318)
      - optional OTLP/gRPC (:4317)
      - Tail sampling, query + admin HTTP, Prometheus
              ^
              |
   opa-collector (host/container metrics)
      - ND-JSON metric points → agent :9090
      - not an OTLP receiver
              |
              v
     OPA-Hub  →  ClickHouse
              ^
              |
     OPA-Dashboard (React SPA)
```

**Design rule:** prefer pure functions of local data (hash sampling, CH-derived aggregates) over new coordination stores. Only tail-buffer correctness and alert fire-state need shared semantics — solved by shard sticky routing and durable `alert_state`.

Single-node (`docker compose up`) is the default; Helm and replica count are additive knobs. On NAS (`open-family`), `opa-collector:nas` runs host-networked and ships to `OPA_AGENT_ADDR=127.0.0.1:9090`; see [nas-deploy.md](nas-deploy.md).
