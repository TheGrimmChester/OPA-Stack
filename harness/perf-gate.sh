#!/usr/bin/env bash
# Wave 29 — CI perf gate helper (single-runner honesty).
# Usage:
#   AGENT_URL=http://127.0.0.1:8080 SERVICE=smoke-shop ./harness/perf-gate.sh
#   AGENT_URL=... SERVICE=smoke-shop BASELINE_ID=smoke-shop::p95_ms ./harness/perf-gate.sh
set -euo pipefail
AGENT_URL="${AGENT_URL:-http://127.0.0.1:8080}"
SERVICE="${SERVICE:-}"
METRIC="${METRIC:-p95_ms}"
BASELINE_ID="${BASELINE_ID:-}"
if [[ -z "$SERVICE" ]]; then
  echo "SERVICE required (e.g. SERVICE=smoke-shop)" >&2
  exit 2
fi
qs="service=${SERVICE}&metric=${METRIC}"
if [[ -n "$BASELINE_ID" ]]; then
  qs="${qs}&baseline_id=${BASELINE_ID}"
fi
code=$(curl -sS -o /tmp/opa-perf-gate.json -w '%{http_code}' \
  "${AGENT_URL}/api/performance/gate?${qs}")
cat /tmp/opa-perf-gate.json
echo
# Gate handler returns JSON with pass/fail; treat HTTP>=400 or ok:false as failure
if [[ "$code" -ge 400 ]]; then
  exit 1
fi
if grep -Eq '"ok"[[:space:]]*:[[:space:]]*false|"pass"[[:space:]]*:[[:space:]]*false|"failed"[[:space:]]*:[[:space:]]*true' /tmp/opa-perf-gate.json 2>/dev/null; then
  exit 1
fi
exit 0
