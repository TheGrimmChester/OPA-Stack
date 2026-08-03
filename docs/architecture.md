# Architecture

```
[ App + SDK / PHP ext / RUM / OTLP ]
              |
              v
     OPA-Agent (Go collector)
      - ND-JSON TCP / Unix socket
      - OTLP/HTTP (+ optional gRPC)
      - Tail sampling (in-process / shard-sticky)
      - Query + Admin HTTP API
      - Prometheus metrics
              |
              v
         ClickHouse
              ^
              |
     OPA-Dashboard (React SPA)
```

**Design rule (Wave 15):** prefer pure functions of local data (hash sampling, CH-derived aggregates) over new coordination stores. Only tail-buffer correctness and alert fire-state need shared semantics — solved by shard sticky routing and durable `alert_state`.

Single-node (`docker compose up`) is the default; Helm and replica count are additive knobs.
