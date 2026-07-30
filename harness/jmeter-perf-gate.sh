#!/usr/bin/env bash
# Wave 31 — gate a Perf Lab run via /api/perf/runs/{id}/gate
set -euo pipefail
AGENT_URL="${AGENT_URL:-http://127.0.0.1:8080}"
RUN_ID="${RUN_ID:-}"
SCENARIO_ID="${SCENARIO_ID:-}"
if [[ -z "$RUN_ID" && -n "$SCENARIO_ID" ]]; then
  curl -fsS -X POST "$AGENT_URL/api/perf/runs" \
    -H 'content-type: application/json' \
    -d "{\"scenario_id\":\"$SCENARIO_ID\",\"vus\":2,\"dispatch\":false,\"engine\":\"jmeter\"}" \
    -o /tmp/opa-jmeter-run.json
  RUN_ID=$(python3 -c 'import json;d=json.load(open("/tmp/opa-jmeter-run.json"));print(d.get("load_run_id") or d.get("id",""))')
fi
if [[ -z "$RUN_ID" ]]; then
  echo "RUN_ID or SCENARIO_ID required" >&2
  exit 2
fi
curl -fsS -o /tmp/opa-jmeter-gate.json "$AGENT_URL/api/perf/runs/${RUN_ID}/gate"
cat /tmp/opa-jmeter-gate.json
echo
if grep -Eq '"ok"[[:space:]]*:[[:space:]]*false|"status"[[:space:]]*:[[:space:]]*"failed"' /tmp/opa-jmeter-gate.json; then
  exit 1
fi
exit 0
