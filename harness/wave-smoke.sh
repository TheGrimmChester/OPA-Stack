#!/usr/bin/env bash
# Wave 17–27 (plus light 13–16 baseline) API smoke suite against a running agent.
#
# Prerequisites:
#   Agent healthy at AGENT_HTTP (default http://127.0.0.1:8080).
#   Auth off unless OPA_AUTH_REQUIRED=1 (compose leaves auth open).
#   Prefer agent image built from wave27-diagnostics (see harness/rebuild-smoke-images.sh).
#
# Usage:
#   ./harness/wave-smoke.sh
#   AGENT_HTTP=http://127.0.0.1:8080 ./harness/wave-smoke.sh
#   docker compose --profile wave-smoke run --rm wave-smoke
#
# Exit 0 if FAIL==0 (SOFT empty-data warnings are non-fatal unless SMOKE_STRICT=1).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/smoke-common.sh
source "$ROOT/harness/lib/smoke-common.sh"

FIXTURES="$ROOT/harness/fixtures"
ORG_HDR=(-H "X-OPA-Organization-ID: ${ORG_ID}" -H "X-Organization-Id: ${ORG_ID}")
PROJ_HDR=(-H "X-OPA-Project-ID: ${PROJECT_ID}" -H "X-Project-Id: ${PROJECT_ID}")
JSON_HDR=(-H "Content-Type: application/json")

# Soft-fail when a list key is empty (feature wired but no demo data yet).
expect_json_key_or_soft_empty() {
  local body="$1" key="$2" label="$3"
  if ! printf '%s' "$body" | grep -q "\"$key\""; then
    fail "$label (missing .$key)"
    return 0
  fi
  # Heuristic: key present with empty array → soft
  if printf '%s' "$body" | grep -Eq "\"$key\"[[:space:]]*:[[:space:]]*\\[\\]"; then
    soft "$label (empty .$key — OK if no data yet)"
  else
    ok "$label (has .$key)"
  fi
}

get_json() {
  local path="$1"
  shift
  http_req GET "$path" "${ORG_HDR[@]}" "${PROJ_HDR[@]}" "$@"
}

post_json() {
  local path="$1" data="$2"
  shift 2
  http_req POST "$path" "${JSON_HDR[@]}" "${ORG_HDR[@]}" "${PROJ_HDR[@]}" \
    --data "$data" "$@"
}

# ---------------------------------------------------------------------------
smoke_baseline() {
  section "Baseline (health / version / topology / TQL)"

  local body
  body="$(get_json /api/health)"
  expect_http 200 "GET /api/health"
  expect_json_key "$body" "status" "health"

  body="$(get_json /api/version)"
  expect_http 200 "GET /api/version"

  body="$(get_json /api/topology)"
  expect_http_any "GET /api/topology" 200 204 404
  if [[ "$LAST_HTTP" == "200" ]]; then
    ok "topology responded"
  else
    soft "topology HTTP $LAST_HTTP (optional on older agents)"
  fi

  body="$(post_json /api/tql/query '{"query":"FIND spans LIMIT 1","dry_run":true}')"
  expect_http_any "POST /api/tql/query dry_run" 200 400 404
  if [[ "$LAST_HTTP" == "200" ]]; then
    expect_json_key "$body" "ok" "tql dry_run"
    expect_json_key "$body" "sql" "tql dry_run sql"
  else
    soft "tql dry_run HTTP $LAST_HTTP (Wave 13 optional)"
  fi
}

# ---------------------------------------------------------------------------
smoke_wave17() {
  section "Wave 17 — DB monitoring"

  local body
  body="$(get_json /api/db/instances)"
  expect_http 200 "GET /api/db/instances"
  expect_json_key_or_soft_empty "$body" "instances" "db instances"

  body="$(get_json /api/db/statements)"
  expect_http 200 "GET /api/db/statements"
  expect_json_key_or_soft_empty "$body" "statements" "db statements"

  body="$(get_json /api/db/fingerprint-match)"
  expect_http 200 "GET /api/db/fingerprint-match"
  expect_json_key "$body" "total" "fingerprint-match"
  expect_json_key "$body" "matched" "fingerprint-match matched"

  body="$(get_json /api/db/unused-indexes)"
  expect_http 200 "GET /api/db/unused-indexes"
  expect_json_key_or_soft_empty "$body" "indexes" "unused-indexes"
}

# ---------------------------------------------------------------------------
smoke_wave18() {
  section "Wave 18 — FaaS / serverless"

  local body
  body="$(post_json /v1/ndjson "$(cat <<EOF
{"type":"faas","organization_id":"${ORG_ID}","project_id":"${PROJECT_ID}","function_name":"smoke-fn","service":"smoke-faas","cold_start":true,"duration_ms":120.5,"init_duration_ms":80,"billed_duration_ms":130,"memory_mb":256,"max_memory_used_mb":128,"provider":"aws"}
EOF
)")"
  expect_http 200 "POST /v1/ndjson type:faas"
  expect_json_key "$body" "ok" "ndjson faas"
  expect_json_key "$body" "accepted" "ndjson faas accepted"

  sleep 1

  body="$(get_json /api/faas/summary)"
  expect_http 200 "GET /api/faas/summary"
  expect_json_key "$body" "invocations" "faas summary"

  body="$(get_json /api/faas/cold-starts)"
  expect_http 200 "GET /api/faas/cold-starts"
  expect_json_key_or_soft_empty "$body" "functions" "faas cold-starts"

  body="$(get_json /api/faas/cost)"
  expect_http 200 "GET /api/faas/cost"
  expect_json_key_or_soft_empty "$body" "functions" "faas cost"

  body="$(get_json '/api/faas/invocations?limit=20')"
  expect_http 200 "GET /api/faas/invocations"
  expect_json_key_or_soft_empty "$body" "invocations" "faas invocations"
}

# ---------------------------------------------------------------------------
smoke_wave19() {
  section "Wave 19 — Vuln / IAST"

  local sbom="{}"
  if [[ -f "$FIXTURES/sbom.smoke.json" ]]; then
    sbom="$(cat "$FIXTURES/sbom.smoke.json")"
  else
    sbom='{"service":"smoke-shop","release":"1.0.0","ecosystem":"npm","organization_id":"'"$ORG_ID"'","project_id":"'"$PROJECT_ID"'","packages":[{"name":"lodash","version":"4.17.20"}]}'
  fi

  local body
  body="$(post_json /v1/sbom "$sbom")"
  expect_http_any "POST /v1/sbom" 200 503
  if [[ "$LAST_HTTP" == "200" ]]; then
    expect_json_key "$body" "ok" "sbom ingest"
  else
    soft "sbom HTTP $LAST_HTTP (ClickHouse not ready?)"
  fi

  body="$(post_json /v1/ndjson "$(cat <<EOF
{"type":"iast","organization_id":"${ORG_ID}","project_id":"${PROJECT_ID}","service":"smoke-shop","sink":"sql.injection","evidence":"SELECT * FROM users WHERE id=","route":"/api/users","trace_id":"smoke-trace","span_id":"smoke-span"}
EOF
)")"
  expect_http 200 "POST /v1/ndjson type:iast"
  expect_json_key "$body" "ok" "ndjson iast"

  body="$(get_json /api/vulns/summary)"
  expect_http 200 "GET /api/vulns/summary"

  body="$(get_json /api/vulns/findings)"
  expect_http 200 "GET /api/vulns/findings"
  expect_json_key_or_soft_empty "$body" "findings" "vuln findings"

  body="$(get_json /api/vulns/inventory)"
  expect_http 200 "GET /api/vulns/inventory"

  body="$(get_json /api/iast/summary)"
  expect_http 200 "GET /api/iast/summary"

  body="$(get_json /api/iast/findings)"
  expect_http 200 "GET /api/iast/findings"
  expect_json_key_or_soft_empty "$body" "findings" "iast findings"
}

# ---------------------------------------------------------------------------
smoke_wave20() {
  section "Wave 20 — Synthetics"

  local body
  body="$(get_json /api/synthetics)"
  expect_http 200 "GET /api/synthetics"
  expect_json_key_or_soft_empty "$body" "checks" "synthetics list"

  body="$(post_json /api/synthetics "$(cat <<EOF
{"name":"smoke-health","url":"http://127.0.0.1:8080/api/health","method":"GET","interval_seconds":60,"timeout_ms":3000,"assert_status":200,"enabled":1,"check_type":"http"}
EOF
)")"
  expect_http_any "POST /api/synthetics" 200 201 400 500
  if [[ "$LAST_HTTP" == "200" || "$LAST_HTTP" == "201" ]]; then
    expect_json_key "$body" "id" "synthetics create id"
    expect_json_key "$body" "url" "synthetics create url"
  else
    soft "synthetics create HTTP $LAST_HTTP"
  fi

  body="$(get_json /api/synthetics/locations)"
  expect_http_any "GET /api/synthetics/locations" 200 404
  if [[ "$LAST_HTTP" == "200" ]]; then
    ok "synthetics locations"
  else
    soft "synthetics locations HTTP $LAST_HTTP"
  fi
}

# ---------------------------------------------------------------------------
smoke_wave21() {
  section "Wave 21 — Service catalog"

  local body
  body="$(get_json /api/catalog)"
  expect_http 200 "GET /api/catalog"
  expect_json_key_or_soft_empty "$body" "entities" "catalog"

  body="$(get_json /api/catalog/entities)"
  expect_http 200 "GET /api/catalog/entities"
  expect_json_key_or_soft_empty "$body" "entities" "catalog entities"

  body="$(http_req POST /api/catalog/discover "${JSON_HDR[@]}" "${ORG_HDR[@]}" "${PROJ_HDR[@]}" --data '{}')"
  expect_http_any "POST /api/catalog/discover" 200 204 400 500
  if [[ "$LAST_HTTP" == "200" ]]; then
    expect_json_key "$body" "ok" "catalog discover"
  else
    soft "catalog discover HTTP $LAST_HTTP"
  fi

  body="$(get_json /api/catalog/teams)"
  expect_http 200 "GET /api/catalog/teams"
  expect_json_key_or_soft_empty "$body" "teams" "catalog teams"
}

# ---------------------------------------------------------------------------
smoke_wave22() {
  section "Wave 22 — Platform mgmt API"

  local body
  body="$(get_json /api/mgmt/v1)"
  expect_http 200 "GET /api/mgmt/v1"
  expect_json_key "$body" "apiVersion" "mgmt index"
  expect_json_key "$body" "resources" "mgmt resources"
  expect_json_key "$body" "operations" "mgmt operations"

  body="$(get_json /api/mgmt/v1/export)"
  expect_http 200 "GET /api/mgmt/v1/export"
  expect_json_key "$body" "apiVersion" "mgmt export"
  expect_json_key "$body" "kind" "mgmt export kind"
  expect_json_key "$body" "spec" "mgmt export spec"

  # Plan against current export (noop / empty diffs expected).
  body="$(post_json /api/mgmt/v1/plan "$body")"
  expect_http_any "POST /api/mgmt/v1/plan" 200 400
  if [[ "$LAST_HTTP" == "200" ]]; then
    expect_json_key "$body" "kind" "mgmt plan"
    expect_json_key "$body" "summary" "mgmt plan summary"
  else
    soft "mgmt plan HTTP $LAST_HTTP"
  fi
}

# ---------------------------------------------------------------------------
smoke_wave23() {
  section "Wave 23 — Cloud coverage"

  local body
  body="$(get_json /api/cloud/summary)"
  expect_http 200 "GET /api/cloud/summary"
  expect_json_key "$body" "configured" "cloud summary"
  expect_json_key "$body" "resources" "cloud summary resources"
  expect_json_key "$body" "providers" "cloud summary providers"

  body="$(get_json /api/cloud/resources)"
  expect_http 200 "GET /api/cloud/resources"
  expect_json_key_or_soft_empty "$body" "resources" "cloud resources"

  body="$(get_json /api/cloud/cost)"
  expect_http 200 "GET /api/cloud/cost"
  expect_json_key "$body" "by_service" "cloud cost"
  expect_json_key "$body" "days" "cloud cost days"

  body="$(get_json /api/cloud/tags)"
  expect_http 200 "GET /api/cloud/tags"
  expect_json_key "$body" "violations" "cloud tags"
  expect_json_key "$body" "required_tags" "cloud required_tags"

  body="$(http_req POST /api/cloud/scrape-now "${JSON_HDR[@]}" "${ORG_HDR[@]}" "${PROJ_HDR[@]}" --data '{}')"
  expect_http_any "POST /api/cloud/scrape-now" 200 400
  if [[ "$LAST_HTTP" == "200" ]]; then
    expect_json_key "$body" "ok" "cloud scrape-now"
  else
    soft "cloud scrape-now HTTP $LAST_HTTP (set OPA_CLOUD_MONITOR_CONFIG for mock scrape)"
  fi
}

# ---------------------------------------------------------------------------
smoke_wave24() {
  section "Wave 24 — Network / eBPF"

  local body
  body="$(post_json /v1/network/flows "$(cat <<EOF
{"organization_id":"${ORG_ID}","project_id":"${PROJECT_ID}","host":"smoke-host","flows":[{"src_service":"web","dst_service":"api","src_addr":"10.0.0.1","dst_addr":"10.0.0.2","src_port":54321,"dst_port":8080,"protocol":"tcp","bytes_sent":1024,"bytes_recv":2048,"packets_sent":10,"packets_recv":12,"retransmits":0,"rtt_us":1500,"errors":0}]}
EOF
)")"
  expect_http 200 "POST /v1/network/flows"
  expect_json_key "$body" "ok" "network flows ingest"
  expect_json_key "$body" "accepted" "network flows accepted"

  sleep 1

  body="$(get_json /api/network/summary)"
  expect_http 200 "GET /api/network/summary"
  expect_json_key "$body" "flows_1h" "network summary"
  expect_json_key "$body" "sampler_enabled" "network sampler_enabled"

  body="$(get_json /api/network/flows)"
  expect_http 200 "GET /api/network/flows"
  expect_json_key_or_soft_empty "$body" "flows" "network flows query"

  body="$(get_json /api/network/dns)"
  expect_http 200 "GET /api/network/dns"
  expect_json_key_or_soft_empty "$body" "dns" "network dns"

  body="$(get_json /api/network/discovered)"
  expect_http 200 "GET /api/network/discovered"
  expect_json_key_or_soft_empty "$body" "services" "network discovered"
}

# ---------------------------------------------------------------------------
smoke_wave25() {
  section "Wave 25 — Federation / residency"

  local body
  body="$(get_json /api/federation/summary)"
  expect_http 200 "GET /api/federation/summary"
  expect_json_key "$body" "region" "federation summary"
  expect_json_key "$body" "peers" "federation peers count"

  body="$(get_json /api/federation/peers)"
  expect_http 200 "GET /api/federation/peers"
  expect_json_key "$body" "peers" "federation peers list"
  expect_json_key "$body" "region" "federation peers region"

  body="$(get_json /api/residency/policy)"
  expect_http 200 "GET /api/residency/policy"
  expect_json_key "$body" "region" "residency policy region"
  expect_json_key "$body" "write_allowed" "residency write_allowed"
}

# ---------------------------------------------------------------------------
smoke_wave26() {
  section "Wave 26 — Collaboration"

  local body ts
  ts="$(date +%s)"

  body="$(post_json /api/notebooks "$(cat <<EOF
{"title":"Smoke notebook ${ts}","description":"wave-smoke","cells":[{"type":"markdown","content":"hello smoke"}],"created_by":"smoke"}
EOF
)")"
  expect_http 200 "POST /api/notebooks"
  expect_json_key "$body" "ok" "notebook create"
  expect_json_key "$body" "id" "notebook id"

  body="$(get_json /api/notebooks)"
  expect_http 200 "GET /api/notebooks"
  expect_json_key_or_soft_empty "$body" "notebooks" "notebooks list"

  body="$(post_json /api/status/pages "$(cat <<EOF
{"slug":"smoke-${ts}","title":"Smoke Status","public":true,"components":[{"name":"API","status":"operational"}]}
EOF
)")"
  expect_http 200 "POST /api/status/pages"
  expect_json_key "$body" "ok" "status page create"
  expect_json_key "$body" "slug" "status page slug"

  body="$(get_json /api/status/pages)"
  expect_http 200 "GET /api/status/pages"
  expect_json_key_or_soft_empty "$body" "pages" "status pages list"

  body="$(post_json /api/comments "$(cat <<EOF
{"anchor_type":"notebook","anchor_id":"smoke-nb","body":"smoke comment ${ts}","author":"smoke"}
EOF
)")"
  expect_http 200 "POST /api/comments"
  expect_json_key "$body" "ok" "comment create"

  body="$(get_json '/api/comments?anchor_type=notebook&anchor_id=smoke-nb')"
  expect_http 200 "GET /api/comments"
  expect_json_key_or_soft_empty "$body" "comments" "comments list"

  body="$(post_json /api/reports "$(cat <<EOF
{"name":"Smoke weekly ${ts}","cadence":"weekly","channel":"log","recipients":"smoke@example.com","enabled":true}
EOF
)")"
  expect_http 200 "POST /api/reports"
  expect_json_key "$body" "ok" "report create"

  body="$(get_json /api/reports)"
  expect_http 200 "GET /api/reports"
  expect_json_key_or_soft_empty "$body" "reports" "reports list"
}

# ---------------------------------------------------------------------------
smoke_wave27() {
  section "Wave 27 — Diagnostics"

  local body
  body="$(post_json /api/releases "$(cat <<EOF
{"service":"smoke-shop","release":"1.0.0-smoke","git_sha":"abc123deadbeef","git_repo":"https://example.com/opa/smoke","author":"smoke","message":"smoke release","commits":[{"sha":"abc123","message":"fix"}]}
EOF
)")"
  expect_http 200 "POST /api/releases"
  expect_json_key "$body" "ok" "release create"
  expect_json_key "$body" "id" "release id"

  body="$(get_json /api/releases)"
  expect_http 200 "GET /api/releases"
  expect_json_key_or_soft_empty "$body" "releases" "releases list"

  body="$(get_json '/api/diagnostics/suspect-commits?service=smoke-shop&hours=24')"
  expect_http 200 "GET /api/diagnostics/suspect-commits"
  expect_json_key "$body" "suspects" "suspect-commits"
  expect_json_key "$body" "disclaimer" "suspect-commits disclaimer"

  body="$(post_json /v1/heap "$(cat <<EOF
{"organization_id":"${ORG_ID}","project_id":"${PROJECT_ID}","service":"smoke-shop","host":"smoke-host","runtime":"go","total_bytes":1048576,"dominators":[{"type":"[]byte","bytes":4096}],"retained_paths":[]}
EOF
)")"
  expect_http 200 "POST /v1/heap"
  expect_json_key "$body" "ok" "heap ingest"

  body="$(get_json '/api/diagnostics/heap?service=smoke-shop')"
  expect_http 200 "GET /api/diagnostics/heap"
  expect_json_key_or_soft_empty "$body" "snapshots" "heap list"

  body="$(post_json /v1/threads "$(cat <<EOF
{"organization_id":"${ORG_ID}","project_id":"${PROJECT_ID}","service":"smoke-shop","host":"smoke-host","samples":[{"thread_id":"1","thread_name":"main","state":"RUNNABLE","stack":["main.main"],"lock_name":"","wait_ms":0}]}
EOF
)")"
  expect_http 200 "POST /v1/threads"
  expect_json_key "$body" "ok" "threads ingest"

  body="$(get_json '/api/diagnostics/threads?service=smoke-shop')"
  expect_http 200 "GET /api/diagnostics/threads"
  expect_json_key_or_soft_empty "$body" "threads" "threads query"

  body="$(post_json /v1/locks "$(cat <<EOF
{"organization_id":"${ORG_ID}","project_id":"${PROJECT_ID}","service":"smoke-shop","locks":[{"lock_name":"mu","waiters":1,"holders":["t1"],"wait_ms":12.5}]}
EOF
)")"
  expect_http 200 "POST /v1/locks"
  expect_json_key "$body" "ok" "locks ingest"

  body="$(get_json '/api/diagnostics/locks?service=smoke-shop')"
  expect_http 200 "GET /api/diagnostics/locks"
  expect_json_key_or_soft_empty "$body" "locks" "locks query"
}

# ---------------------------------------------------------------------------
main() {
  smoke_reset_counters
  printf 'OPA wave smoke → %s (org=%s project=%s)\n' "$AGENT_HTTP" "$ORG_ID" "$PROJECT_ID"

  if ! wait_agent; then
    smoke_summary || true
    exit 1
  fi

  smoke_baseline
  smoke_wave17
  smoke_wave18
  smoke_wave19
  smoke_wave20
  smoke_wave21
  smoke_wave22
  smoke_wave23
  smoke_wave24
  smoke_wave25
  smoke_wave26
  smoke_wave27

  smoke_summary
}

main "$@"
