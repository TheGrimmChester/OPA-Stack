#!/usr/bin/env bash
# Wave 31 — gate a Perf Lab run via /api/perf/runs/{id}/gate (fail-closed).
# Asserts Docker-first dispatch (mode=docker) unless OPA_PERF_ALLOW_HOST_JMETER=1.
# Used standalone or as the reference contract for wave-smoke's smoke_wave31.
set -euo pipefail
AGENT_URL="${AGENT_URL:-http://127.0.0.1:8092}"
RUN_ID="${RUN_ID:-}"
SCENARIO_ID="${SCENARIO_ID:-}"
DISPATCH="${DISPATCH:-true}"
WORKERS="${WORKERS:-1}"
REQUIRE_DOCKER="${REQUIRE_DOCKER:-1}"
ORG_ID="${ORG_ID:-default}"
PROJECT_ID="${PROJECT_ID:-default}"
AUTH_ARGS=()
ORG_ARGS=(-H "X-OPA-Organization-Id: ${ORG_ID}" -H "X-OPA-Project-Id: ${PROJECT_ID}")
if [[ -n "${AGENT_TOKEN:-}" ]]; then
  AUTH_ARGS=(-H "Authorization: Bearer ${AGENT_TOKEN}")
fi
if [[ -z "$RUN_ID" && -n "$SCENARIO_ID" ]]; then
  curl -fsS -X POST "$AGENT_URL/api/perf/runs" \
    -H 'content-type: application/json' \
    "${AUTH_ARGS[@]}" "${ORG_ARGS[@]}" \
    -d "{\"scenario_id\":\"$SCENARIO_ID\",\"vus\":2,\"dispatch\":${DISPATCH},\"engine\":\"jmeter\",\"workers\":${WORKERS}}" \
    -o /tmp/opa-jmeter-run.json
  cat /tmp/opa-jmeter-run.json
  echo
  if [[ "$REQUIRE_DOCKER" == "1" ]]; then
    if ! grep -Eq '"mode"[[:space:]]*:[[:space:]]*"docker"' /tmp/opa-jmeter-run.json; then
      echo "expected dispatch.mode=docker (Docker-first JMeter)" >&2
      exit 3
    fi
    if ! grep -Eq '"dispatched"[[:space:]]*:[[:space:]]*true' /tmp/opa-jmeter-run.json; then
      echo "expected dispatched=true" >&2
      exit 3
    fi
  fi
  RUN_ID=$(python3 -c 'import json;d=json.load(open("/tmp/opa-jmeter-run.json"));print(d.get("load_run_id") or d.get("id",""))')
fi
if [[ -z "$RUN_ID" ]]; then
  echo "RUN_ID or SCENARIO_ID required" >&2
  exit 2
fi
# Poll until terminal status (or timeout) — JMeter container cold start can be slow
for _ in $(seq 1 90); do
  curl -fsS -o /tmp/opa-jmeter-status.json "${AUTH_ARGS[@]}" "${ORG_ARGS[@]}" "$AGENT_URL/api/perf/runs/${RUN_ID}" || true
  if grep -Eq '"status"[[:space:]]*:[[:space:]]*"(passed|failed|completed|error)"' /tmp/opa-jmeter-status.json 2>/dev/null; then
    break
  fi
  sleep 2
done
# Gate may briefly lag ClickHouse after status=passed
GATE_OK=0
for _ in $(seq 1 15); do
  curl -fsS -o /tmp/opa-jmeter-gate.json "${AUTH_ARGS[@]}" "${ORG_ARGS[@]}" "$AGENT_URL/api/perf/runs/${RUN_ID}/gate"
  if grep -Eq '"ok"[[:space:]]*:[[:space:]]*true' /tmp/opa-jmeter-gate.json; then
    GATE_OK=1
    break
  fi
  sleep 2
done
cat /tmp/opa-jmeter-gate.json
echo
if [[ "$GATE_OK" != "1" ]]; then
  echo "expected gate ok=true" >&2
  exit 1
fi
if ! grep -Eq '"status"[[:space:]]*:[[:space:]]*"(passed|completed)"' /tmp/opa-jmeter-status.json; then
  echo "expected run status passed/completed" >&2
  cat /tmp/opa-jmeter-status.json >&2
  exit 1
fi
# Samples prove JTL was merged
curl -fsS -o /tmp/opa-jmeter-samples.json "${AUTH_ARGS[@]}" "${ORG_ARGS[@]}" \
  "$AGENT_URL/api/perf/runs/${RUN_ID}/samples?limit=5"
if ! grep -Eq '"samples"[[:space:]]*:[[:space:]]*\[\{' /tmp/opa-jmeter-samples.json; then
  echo "expected non-empty samples after JMeter run" >&2
  cat /tmp/opa-jmeter-samples.json >&2
  exit 1
fi
echo "jmeter-perf-gate: OK run_id=${RUN_ID}"
exit 0
