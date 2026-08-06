#!/usr/bin/env bash
# Gate a Perf Lab run via OPL GET /api/perf/runs/{id}/gate (fail-closed).
# Default base is opl-api (:8092). Do not call the legacy hub/agent
# /api/performance/gate path.
#
# Usage:
#   RUN_ID=<id> ./harness/perf-gate.sh
#   AGENT_URL=http://127.0.0.1:8092 RUN_ID=<id> ./harness/perf-gate.sh
#   AGENT_URL=... SCENARIO_ID=<id> ./harness/perf-gate.sh   # create a run then gate it
set -euo pipefail
AGENT_URL="${AGENT_URL:-http://127.0.0.1:8092}"
RUN_ID="${RUN_ID:-}"
SCENARIO_ID="${SCENARIO_ID:-}"
ORG_ID="${ORG_ID:-default}"
PROJECT_ID="${PROJECT_ID:-default}"
AUTH_ARGS=()
ORG_ARGS=(-H "X-OPA-Organization-Id: ${ORG_ID}" -H "X-OPA-Project-Id: ${PROJECT_ID}"
  -H "X-Organization-ID: ${ORG_ID}" -H "X-Project-ID: ${PROJECT_ID}")
if [[ -n "${AGENT_TOKEN:-}" ]]; then
  AUTH_ARGS=(-H "Authorization: Bearer ${AGENT_TOKEN}")
fi

if [[ -z "$RUN_ID" && -n "$SCENARIO_ID" ]]; then
  curl -fsS -X POST "$AGENT_URL/api/perf/runs" \
    -H 'content-type: application/json' \
    "${AUTH_ARGS[@]}" "${ORG_ARGS[@]}" \
    -d "{\"scenario_id\":\"$SCENARIO_ID\",\"vus\":1,\"dispatch\":false}" \
    -o /tmp/opa-perf-gate-run.json
  RUN_ID=$(python3 -c 'import json;d=json.load(open("/tmp/opa-perf-gate-run.json"));print(d.get("load_run_id") or d.get("id",""))')
fi
if [[ -z "$RUN_ID" ]]; then
  echo "RUN_ID or SCENARIO_ID required" >&2
  echo "usage: RUN_ID=<id> $0   # gates GET \$AGENT_URL/api/perf/runs/{id}/gate" >&2
  exit 2
fi

code=$(curl -sS -o /tmp/opa-perf-gate.json -w '%{http_code}' \
  "${AUTH_ARGS[@]}" "${ORG_ARGS[@]}" \
  "${AGENT_URL%/}/api/perf/runs/${RUN_ID}/gate")
cat /tmp/opa-perf-gate.json
echo
# Gate handler returns JSON with pass/fail; treat HTTP>=400 or ok:false as failure
if [[ "$code" -ge 400 ]]; then
  exit 1
fi
if grep -Eq '"ok"[[:space:]]*:[[:space:]]*false|"pass"[[:space:]]*:[[:space:]]*false|"failed"[[:space:]]*:[[:space:]]*true' /tmp/opa-perf-gate.json 2>/dev/null; then
  exit 1
fi
if ! grep -Eq '"ok"[[:space:]]*:[[:space:]]*true' /tmp/opa-perf-gate.json 2>/dev/null; then
  echo "expected gate ok=true" >&2
  exit 1
fi
exit 0
