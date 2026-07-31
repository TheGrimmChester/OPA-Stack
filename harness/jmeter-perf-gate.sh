#!/usr/bin/env bash
# Wave 31 — gate a Perf Lab run via /api/perf/runs/{id}/gate (fail-closed).
set -euo pipefail
AGENT_URL="${AGENT_URL:-http://127.0.0.1:8080}"
RUN_ID="${RUN_ID:-}"
SCENARIO_ID="${SCENARIO_ID:-}"
DISPATCH="${DISPATCH:-true}"
AUTH_ARGS=()
if [[ -n "${AGENT_TOKEN:-}" ]]; then
  AUTH_ARGS=(-H "Authorization: Bearer ${AGENT_TOKEN}")
fi
if [[ -z "$RUN_ID" && -n "$SCENARIO_ID" ]]; then
  curl -fsS -X POST "$AGENT_URL/api/perf/runs" \
    -H 'content-type: application/json' \
    "${AUTH_ARGS[@]}" \
    -d "{\"scenario_id\":\"$SCENARIO_ID\",\"vus\":2,\"dispatch\":${DISPATCH},\"engine\":\"jmeter\"}" \
    -o /tmp/opa-jmeter-run.json
  RUN_ID=$(python3 -c 'import json;d=json.load(open("/tmp/opa-jmeter-run.json"));print(d.get("load_run_id") or d.get("id",""))')
fi
if [[ -z "$RUN_ID" ]]; then
  echo "RUN_ID or SCENARIO_ID required" >&2
  exit 2
fi
# Poll until terminal status (or timeout)
for _ in $(seq 1 60); do
  curl -fsS -o /tmp/opa-jmeter-status.json "${AUTH_ARGS[@]}" "$AGENT_URL/api/perf/runs/${RUN_ID}" || true
  if grep -Eq '"status"[[:space:]]*:[[:space:]]*"(passed|failed|completed|error)"' /tmp/opa-jmeter-status.json 2>/dev/null; then
    break
  fi
  sleep 2
done
curl -fsS -o /tmp/opa-jmeter-gate.json "${AUTH_ARGS[@]}" "$AGENT_URL/api/perf/runs/${RUN_ID}/gate"
cat /tmp/opa-jmeter-gate.json
echo
if grep -Eq '"ok"[[:space:]]*:[[:space:]]*false|"status"[[:space:]]*:[[:space:]]*"failed"|"status"[[:space:]]*:[[:space:]]*"running"' /tmp/opa-jmeter-gate.json; then
  exit 1
fi
exit 0
