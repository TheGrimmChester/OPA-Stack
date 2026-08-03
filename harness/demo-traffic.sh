#!/usr/bin/env bash
# Demo traffic generator — posts synthetic ND-JSON spans to the agent TCP ingest via a one-shot container,
# or curls the OTLP/HTTP path when available. Prefer TCP ingest through docker network.
set -euo pipefail

AGENT_HTTP="${AGENT_HTTP:-http://127.0.0.1:8080}"
OTLP="${OTLP:-$AGENT_HTTP/v1/traces}"

echo "Sending demo OTLP/JSON spans to $OTLP"

now_ns() { python3 - <<'PY'
import time
print(int(time.time()*1e9))
PY
}

send_span() {
  local name="$1" status="$2" dur_ms="$3"
  local start end
  start="$(now_ns)"
  end=$((start + dur_ms * 1000000))
  local tid sid
  tid="$(openssl rand -hex 16)"
  sid="$(openssl rand -hex 8)"
  curl -fsS -X POST "$OTLP" \
    -H 'Content-Type: application/json' \
    -d "$(cat <<JSON
{
  "resourceSpans": [{
    "resource": {"attributes": [
      {"key": "service.name", "value": {"stringValue": "demo-api"}},
      {"key": "deployment.environment", "value": {"stringValue": "quickstart"}}
    ]},
    "scopeSpans": [{
      "spans": [{
        "traceId": "$tid",
        "spanId": "$sid",
        "name": "$name",
        "kind": 2,
        "startTimeUnixNano": "$start",
        "endTimeUnixNano": "$end",
        "status": {"code": $status}
      }]
    }]
  }]
}
JSON
)" >/dev/null || true
}

for i in $(seq 1 40); do
  st=1 # OK
  [[ $((i % 7)) -eq 0 ]] && st=2 # ERROR
  dur=$((20 + RANDOM % 200))
  send_span "GET /api/items/$i" "$st" "$dur"
done

# Also hit a few RUM-shaped beacons if the endpoint exists
curl -fsS -X POST "${AGENT_HTTP}/api/rum/beacon" \
  -H 'Content-Type: application/json' \
  -d '{"type":"view","service":"demo-web","path":"/","duration_ms":320}' >/dev/null 2>&1 || true

echo "Demo traffic sent (40 spans)."
