#!/usr/bin/env bash
# Exhaustive Dashboard panel smoke — every SideRail nav route + backing Agent APIs.
#
# Usage:
#   ./harness/dashboard-smoke.sh
#   DASH_HTTP=http://127.0.0.1:8088 AGENT_HTTP=http://127.0.0.1:8080 ./harness/dashboard-smoke.sh
#   SKIP_BROWSER=1 ./harness/dashboard-smoke.sh   # SPA+API only
#
# Exit 0 when FAIL==0 (SOFT empty-data / auth-off cases are non-fatal).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/smoke-common.sh
source "$ROOT/harness/lib/smoke-common.sh"

DASH_HTTP="${DASH_HTTP:-http://127.0.0.1:8088}"
SKIP_BROWSER="${SKIP_BROWSER:-0}"
ORG_HDR=(-H "X-OPA-Organization-ID: ${ORG_ID}" -H "X-Organization-Id: ${ORG_ID}")
PROJ_HDR=(-H "X-OPA-Project-ID: ${PROJECT_ID}" -H "X-Project-Id: ${PROJECT_ID}")

get_json() {
  local path="$1"
  shift
  http_req GET "$path" "${ORG_HDR[@]}" "${PROJ_HDR[@]}" "$@"
}

# Assert body is not a ClickHouse Code 47 / UNKNOWN_IDENTIFIER fatal.
assert_no_ch_fatal() {
  local body="$1" label="$2"
  if printf '%s' "$body" | grep -Eqi 'UNKNOWN_IDENTIFIER|Code:\s*47|ClickHouse error|DB::Exception'; then
    fail "$label ClickHouse fatal in body"
    return 0
  fi
  ok "$label no CH fatal"
}

# GET Dashboard SPA path — nginx serves index.html for all client routes.
dash_route() {
  local path="$1"
  local tmp code
  tmp="$(mktemp)"
  set +e
  code=$(curl -sS -o "$tmp" -w '%{http_code}' --connect-timeout 5 --max-time 10 "${DASH_HTTP}${path}")
  set -e
  if [[ "$code" != "200" ]]; then
    fail "DASH ${path} (HTTP $code)"
    rm -f "$tmp"
    return 0
  fi
  if ! grep -Eqi '<div id="root"|src="/assets/|Open Profiling|vite' "$tmp"; then
    # Still OK if HTML shell is present (production nginx).
    if ! grep -Eqi '<!DOCTYPE html|<html' "$tmp"; then
      fail "DASH ${path} not HTML shell"
      rm -f "$tmp"
      return 0
    fi
  fi
  ok "DASH ${path}"
  rm -f "$tmp"
}

# Agent API for a panel — 200 preferred; 404 soft (older agent); CH fatals fail.
panel_api() {
  local path="$1" label="$2"
  local body
  body="$(get_json "$path")"
  local code
  code="$(smoke_last_http)"
  LAST_HTTP="$code"
  if [[ "$code" == "200" ]]; then
    ok "API $label (HTTP 200)"
    assert_no_ch_fatal "$body" "API $label"
  elif [[ "$code" == "404" || "$code" == "405" ]]; then
    soft "API $label HTTP $code (optional/older)"
  elif [[ "$code" == "401" || "$code" == "403" ]]; then
    soft "API $label HTTP $code (auth gated)"
  elif [[ "$code" == "0" ]]; then
    fail "API $label unreachable"
  else
    # 400 on some endpoints with missing params can be soft
    if [[ "$code" == "400" ]]; then
      soft "API $label HTTP 400 (params)"
    else
      fail "API $label HTTP $code"
    fi
    assert_no_ch_fatal "$body" "API $label"
  fi
}

smoke_dashboard_routes() {
  section "Dashboard SPA routes (SideRail inventory)"

  local route
  # SideRail inventory — Service only (Overview is the same view; do not smoke `/` as a panel).
  for route in \
    /services \
    /catalog \
    /key-transactions \
    /commands \
    /traces \
    /profiling \
    /errors \
    /logs \
    /alerts \
    /slos \
    /anomalies \
    /synthetics \
    /security \
    /diagnostics \
    /sql \
    /http \
    /service-map \
    /network \
    /rum \
    /performance \
    /compare \
    /infrastructure \
    /cloud \
    /metrics \
    /query \
    /dashboards \
    /live \
    /serverless \
    /collaborate \
    /system \
    /users \
    /api-keys \
    /automation \
    /federation \
    /login \
    /stats
  do
    dash_route "$route"
  done
}

smoke_dashboard_apis() {
  section "Dashboard panel backing APIs"

  # Monitor — Service panel (Overview removed; same view)
  panel_api "/api/services" "services"
  panel_api "/api/metrics/performance" "services performance"
  panel_api "/api/catalog" "catalog"
  panel_api "/api/catalog/scorecards" "catalog scorecards"
  panel_api "/api/catalog/teams" "catalog teams"
  panel_api "/api/catalog/groups" "catalog groups"
  panel_api "/api/key-transactions" "key-transactions"
  panel_api "/api/commands" "commands"
  panel_api "/api/traces?limit=10" "traces"
  panel_api "/api/services/metadata" "services metadata"
  panel_api "/api/profiles?limit=20" "profiling"
  panel_api "/api/errors?limit=50" "errors"
  panel_api "/api/logs?limit=50" "logs"

  # Reliability
  panel_api "/api/alerts" "alerts"
  panel_api "/api/slos" "slos"
  panel_api "/api/anomalies" "anomalies"
  panel_api "/api/synthetics" "synthetics"
  panel_api "/api/synthetics/locations" "synthetics locations"
  panel_api "/api/vulns/summary?hours=24" "security vulns summary"
  panel_api "/api/vulns/findings?limit=50" "security vulns findings"
  panel_api "/api/vulns/inventory?limit=50" "security inventory"
  panel_api "/api/iast/summary?hours=24" "security iast summary"
  panel_api "/api/iast/findings?limit=50" "security iast"
  panel_api "/api/security/secrets?limit=50" "security secrets"
  panel_api "/api/security/sast?limit=50" "security sast"
  panel_api "/api/security/iac?limit=50" "security iac"
  panel_api "/api/security/policies" "security policies"
  panel_api "/api/security/pr-check" "security pr-check"
  panel_api "/api/diagnostics/suspect-commits?hours=24" "diagnostics suspects"
  panel_api "/api/diagnostics/heap" "diagnostics heap"
  panel_api "/api/diagnostics/threads" "diagnostics threads"
  panel_api "/api/diagnostics/locks" "diagnostics locks"
  panel_api "/api/releases" "diagnostics releases"

  # Analyze
  panel_api "/api/sql/queries?limit=50" "sql queries"
  panel_api "/api/redis/operations?limit=50" "redis ops"
  panel_api "/api/db/instances" "db instances"
  panel_api "/api/db/statements" "db statements"
  panel_api "/api/db/fingerprint-match" "db fingerprint"
  panel_api "/api/db/unused-indexes" "db unused indexes"
  panel_api "/api/http-calls?limit=50" "http calls"
  panel_api "/api/service-map" "service-map"
  panel_api "/api/service-map/thresholds" "service-map thresholds"
  panel_api "/api/network/summary" "network summary"
  panel_api "/api/network/flows?limit=50" "network flows"
  panel_api "/api/network/dependencies" "network deps"
  panel_api "/api/network/dns?limit=50" "network dns"
  panel_api "/api/network/tls?limit=50" "network tls"
  panel_api "/api/network/discovered?limit=50" "network discovered"
  panel_api "/api/network/host-profiles?limit=50" "network host-profiles"
  panel_api "/api/rum/metrics" "rum metrics"
  panel_api "/api/rum/detail" "rum detail"
  panel_api "/api/rum/slo" "rum slo"
  panel_api "/api/rum/facets" "rum facets"
  panel_api "/api/rum/sessions" "rum sessions"
  panel_api "/api/rum/mobile/sessions" "rum mobile sessions"
  panel_api "/api/mobile/crashes" "mobile crashes"
  panel_api "/api/metrics/network" "performance network"
  # Perf Lab — light API smoke only (UI/UX owned by sibling agent)
  panel_api "/api/perf/scenarios" "perf-lab scenarios"
  panel_api "/api/perf/runs" "perf-lab runs"
  panel_api "/api/performance/baselines" "perf baselines"

  # Infra
  panel_api "/api/infra/hosts" "infrastructure hosts"
  panel_api "/api/cloud/summary" "cloud summary"
  panel_api "/api/cloud/resources?limit=50" "cloud resources"
  panel_api "/api/cloud/cost?days=7" "cloud cost"
  panel_api "/api/cloud/tags" "cloud tags"
  panel_api "/api/cloud/scrapes?limit=50" "cloud scrapes"
  panel_api "/api/integrations" "integrations"
  panel_api "/api/metrics/names" "metrics names"
  panel_api "/api/tql/saved" "query saved"
  panel_api "/api/tql/attrs" "query attrs"
  panel_api "/api/dashboards?user_id=me" "dashboards"
  panel_api "/api/dashboards/templates" "dashboard templates"

  # Operate
  panel_api "/api/dumps?limit=50" "live dumps"
  panel_api "/api/faas/summary?hours=24" "serverless summary"
  panel_api "/api/faas/cold-starts?hours=24" "serverless cold"
  panel_api "/api/faas/cost?hours=24" "serverless cost"
  panel_api "/api/faas/invocations?limit=50" "serverless inv"
  panel_api "/api/notebooks" "collaborate notebooks"
  panel_api "/api/status/pages" "collaborate status pages"
  panel_api "/api/comments" "collaborate comments"
  panel_api "/api/reports" "collaborate reports"
  panel_api "/api/reports/runs" "collaborate report runs"
  panel_api "/api/version" "system version"
  panel_api "/api/topology" "system topology"
  panel_api "/api/ops/status" "system ops"
  panel_api "/api/audit?limit=20" "system audit"
  panel_api "/api/stats" "stats"

  # Admin
  panel_api "/api/users" "users"
  panel_api "/api/organizations" "api-keys orgs"
  panel_api "/api/api-keys" "api-keys"
  panel_api "/api/mgmt/v1" "automation mgmt"
  panel_api "/api/mgmt/v1/revisions" "automation revisions"
  panel_api "/api/mgmt/v1/openapi.json" "automation openapi"
  panel_api "/api/federation/summary" "federation summary"
  panel_api "/api/federation/peers" "federation peers"
  panel_api "/api/residency/policy" "residency policy"
  panel_api "/api/residency/transfers" "residency transfers"
  panel_api "/api/auth/status" "auth status"
  panel_api "/api/auth/oidc/status" "auth oidc status"
}

smoke_dashboard_browser() {
  section "Dashboard browser panel render (Playwright)"
  if [[ "$SKIP_BROWSER" == "1" ]]; then
    soft "browser smoke skipped (SKIP_BROWSER=1)"
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    soft "browser smoke skipped (no docker)"
    return 0
  fi
  local out rc
  set +e
  out=$(docker run --rm --network host \
    -e DASH_HTTP="$DASH_HTTP" \
    -e AGENT_HTTP="$AGENT_HTTP" \
    -v "$ROOT/harness:/harness:ro" \
    mcr.microsoft.com/playwright:v1.49.1-jammy \
    bash -lc 'npm install --prefix /tmp/pw --silent playwright@1.49.1 >/dev/null 2>&1 && NODE_PATH=/tmp/pw/node_modules node /harness/dashboard-browser-smoke.cjs' 2>&1)
  rc=$?
  set -e
  printf '%s\n' "$out"
  if [[ $rc -eq 0 ]]; then
    ok "browser panel smoke exit 0"
  elif [[ $rc -eq 2 ]]; then
    soft "browser smoke soft failures only (see lines above)"
  else
    fail "browser panel smoke exit $rc"
  fi
}

main() {
  smoke_reset_counters
  printf 'OPA dashboard smoke → dash=%s agent=%s\n' "$DASH_HTTP" "$AGENT_HTTP"

  if ! wait_agent; then
    smoke_summary || true
    exit 1
  fi

  # Dashboard HTTP reachable
  local code
  set +e
  code=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "$DASH_HTTP/")
  set -e
  if [[ "$code" != "200" ]]; then
    fail "Dashboard ${DASH_HTTP}/ HTTP $code"
    smoke_summary || true
    exit 1
  fi
  ok "Dashboard root HTTP 200"

  smoke_dashboard_routes
  smoke_dashboard_apis
  smoke_dashboard_browser

  smoke_summary
}

# Library mode for wave-smoke (source then call run_dashboard_smoke_nested).
run_dashboard_smoke_nested() {
  smoke_dashboard_routes
  smoke_dashboard_apis
  if [[ "${SKIP_BROWSER:-1}" != "1" ]]; then
    smoke_dashboard_browser
  else
    soft "browser smoke deferred to host (SKIP_BROWSER=1 in compose)"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
