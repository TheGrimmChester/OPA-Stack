#!/usr/bin/env bash
# Wave 29 — CI perf gate helper (single-runner honesty).
# Usage: AGENT_URL=http://127.0.0.1:8080 BASELINE_ID=... ./harness/perf-gate.sh
set -euo pipefail
AGENT_URL="${AGENT_URL:-http://127.0.0.1:8080}"
BASELINE_ID="${BASELINE_ID:-}"
if [[ -z "$BASELINE_ID" ]]; then
  echo "BASELINE_ID required (from POST /api/performance/baselines)" >&2
  exit 2
fi
code=$(curl -sS -o /tmp/opa-perf-gate.json -w '%{http_code}' \
  "${AGENT_URL}/api/performance/gate?id=${BASELINE_ID}")
cat /tmp/opa-perf-gate.json
echo
# Gate handler returns JSON with pass/fail; treat HTTP>=400 or fail:true as failure
if [[ "$code" -ge 400 ]]; then
  exit 1
fi
if grep -q '"pass":false\|"ok":false\|"failed":true' /tmp/opa-perf-gate.json 2>/dev/null; then
  exit 1
fi
exit 0
