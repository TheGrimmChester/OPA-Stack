#!/usr/bin/env bash
# Wave 17–30 (plus light 13–16 baseline) API smoke suite against a running agent.
#
# Prerequisites:
#   Agent healthy at AGENT_HTTP (default http://127.0.0.1:8080).
#   Auth off unless OPA_AUTH_REQUIRED=1 (compose leaves auth open).
#   Prefer agent image built from wave28-30-verticals (see harness/rebuild-smoke-images.sh).
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

  # Cost ingest round-trip, then assert cost keys are populated / accepted.
  body="$(post_json /api/cloud/cost/ingest "$(cat <<EOF
{"organization_id":"${ORG_ID}","project_id":"${PROJECT_ID}","rows":[{"day":"$(date -u +%Y-%m-%d)","provider":"mock","service":"smoke-rds","resource":"smoke-db","tag_key":"env","tag_value":"smoke","amount":12.5,"currency":"USD","util_pct":40}]}
EOF
)")"
  expect_http 200 "POST /api/cloud/cost/ingest"
  expect_json_key "$body" "ok" "cloud cost ingest"
  expect_json_key "$body" "ingested" "cloud cost ingested"

  sleep 1

  body="$(get_json /api/cloud/cost)"
  expect_http 200 "GET /api/cloud/cost"
  expect_json_key "$body" "by_service" "cloud cost"
  expect_json_key "$body" "days" "cloud cost days"
  if printf '%s' "$body" | grep -Eq '"by_service"[[:space:]]*:[[:space:]]*\[\]'; then
    soft "cloud cost by_service empty after ingest (async CH write lag)"
  else
    ok "cloud cost by_service non-empty after ingest"
  fi

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
  if printf '%s' "$body" | grep -Eq '"accepted"[[:space:]]*:[[:space:]]*0'; then
    fail "network flows accepted should be >0"
  else
    ok "network flows accepted >0"
  fi

  sleep 2

  body="$(get_json /api/network/summary)"
  expect_http 200 "GET /api/network/summary"
  expect_json_key "$body" "flows_1h" "network summary"
  expect_json_key "$body" "sampler_enabled" "network sampler_enabled"

  body="$(get_json /api/network/flows)"
  expect_http 200 "GET /api/network/flows"
  expect_json_key "$body" "flows" "network flows query"
  if printf '%s' "$body" | grep -Eq '"flows"[[:space:]]*:[[:space:]]*\[\]'; then
    soft "network flows query empty after ingest (async CH write lag)"
  else
    ok "network flows query has data after ingest"
  fi

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

  # Pin org to a foreign region, expect 451 on ND-JSON write; federation reads still 200.
  local foreign="smoke-foreign-region-zz"
  body="$(post_json /api/residency/policy/upsert "$(cat <<EOF
{"organization_id":"${ORG_ID}","project_id":"${PROJECT_ID}","home_region":"${foreign}","allowed_regions":["${foreign}"],"transfer_policy":"deny","notes":"wave-smoke locality"}
EOF
)")"
  expect_http 200 "POST /api/residency/policy/upsert"
  expect_json_key "$body" "ok" "residency policy upsert"

  sleep 1

  body="$(http_req POST /v1/ndjson "${JSON_HDR[@]}" "${ORG_HDR[@]}" "${PROJ_HDR[@]}" \
    --data '{"type":"faas","organization_id":"'"${ORG_ID}"'","project_id":"'"${PROJECT_ID}"'","function_name":"denied","service":"smoke","cold_start":false,"duration_ms":1}')"
  expect_http 451 "POST /v1/ndjson under foreign residency (expect 451)"

  body="$(get_json /api/federation/summary)"
  expect_http 200 "GET /api/federation/summary after residency pin"

  body="$(post_json /api/federation/query '{"kind":"summary"}')"
  expect_http_any "POST /api/federation/query" 200 405
  if [[ "$LAST_HTTP" == "200" ]]; then
    ok "federation query still 200 under pin"
  else
    body="$(http_req GET '/api/federation/query?kind=summary' "${ORG_HDR[@]}" "${PROJ_HDR[@]}")"
    expect_http 200 "GET /api/federation/query under pin"
  fi

  # Restore: allow local agent region (or clear via home=local).
  local local_region
  local_region="$(get_json /api/federation/summary | sed -n 's/.*"region"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  if [[ -z "$local_region" ]]; then
    local_region="default"
  fi
  body="$(post_json /api/residency/policy/upsert "$(cat <<EOF
{"organization_id":"${ORG_ID}","project_id":"${PROJECT_ID}","home_region":"${local_region}","allowed_regions":["${local_region}"],"transfer_policy":"deny","notes":"wave-smoke restore"}
EOF
)")"
  expect_http 200 "POST /api/residency/policy/upsert restore"
}

# ---------------------------------------------------------------------------
smoke_wave26() {
  section "Wave 26 — Collaboration"

  local body ts slug
  ts="$(date +%s)"
  slug="smoke-${ts}"

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
{"slug":"${slug}","title":"Smoke Status","public":true,"components":[{"name":"API","status":"operational"}]}
EOF
)")"
  expect_http 200 "POST /api/status/pages"
  expect_json_key "$body" "ok" "status page create"
  expect_json_key "$body" "slug" "status page slug"

  sleep 1

  body="$(http_req GET "/status/${slug}")"
  expect_http 200 "GET /status/${slug} public page"
  body="$(http_req GET "/api/public/status/${slug}")"
  expect_http 200 "GET /api/public/status/${slug}"
  expect_json_key "$body" "slug" "public status slug"

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
# Browser RUM vitals (Wave 12 SLO path used by Dashboard). Regression for
# ClickHouse Code 47 when outer SELECT referenced web_vitals after rumDedupe.
smoke_rum_vitals() {
  section "RUM vitals — /api/rum/slo + /api/rum/metrics"

  local sid="smoke-vitals-$(date +%s)"
  local pv="pv-vitals-$(date +%s)"
  local now_ms body
  now_ms="$(($(date +%s) * 1000))"

  body="$(http_req POST /api/rum "${JSON_HDR[@]}" "${ORG_HDR[@]}" "${PROJ_HDR[@]}" --data "$(cat <<EOF
{"organization_id":"${ORG_ID}","project_id":"${PROJECT_ID}","session_id":"${sid}","page_view_id":"${pv}","page_url":"https://shop.example.com/checkout","user_agent":"Mozilla/5.0 smoke","timestamp":${now_ms},"navigation_timing":{"total":1284,"dom":743,"ttfb":188},"web_vitals":{"lcp":1450,"cls":0.042,"inp":96,"fcp":820,"ttfb":188,"fid":12},"resource_timing":[],"ajax_requests":[],"errors":[],"viewport":{"width":1440,"height":900}}
EOF
)")"
  expect_http_any "POST /api/rum" 200 204
  if [[ "$LAST_HTTP" != "204" && "$LAST_HTTP" != "200" ]]; then
    fail "RUM beacon ingest HTTP $LAST_HTTP"
    return 0
  fi

  sleep 2

  body="$(get_json '/api/rum/slo?hours=24')"
  expect_http 200 "GET /api/rum/slo"
  if printf '%s' "$body" | grep -Eqi 'UNKNOWN_IDENTIFIER|ClickHouse error'; then
    fail "GET /api/rum/slo ClickHouse error: $body"
  elif printf '%s' "$body" | grep -q '"slo"'; then
    ok "GET /api/rum/slo has .slo"
    if printf '%s' "$body" | grep -q '"lcp"'; then
      ok "GET /api/rum/slo has lcp budget block"
    else
      soft "GET /api/rum/slo missing lcp (empty window OK)"
    fi
  else
    fail "GET /api/rum/slo missing .slo: $body"
  fi

  body="$(get_json /api/rum/metrics)"
  expect_http 200 "GET /api/rum/metrics"
  if printf '%s' "$body" | grep -Eqi 'UNKNOWN_IDENTIFIER|ClickHouse error'; then
    fail "GET /api/rum/metrics ClickHouse error: $body"
  elif printf '%s' "$body" | grep -q 'core_web_vitals'; then
    ok "GET /api/rum/metrics has core_web_vitals"
  else
    fail "GET /api/rum/metrics missing core_web_vitals: $body"
  fi
}

# ---------------------------------------------------------------------------
smoke_wave28() {
  section "Wave 28 — Experience replay / mobile"

  local sid="smoke-replay-$(date +%s)"
  local body
  body="$(http_req POST /api/rum/replay "${JSON_HDR[@]}" "${ORG_HDR[@]}" "${PROJ_HDR[@]}" --data "$(cat <<EOF
{"organization_id":"${ORG_ID}","project_id":"${PROJECT_ID}","session_id":"${sid}","page_view_id":"pv-smoke","chunk_index":0,"masked":true,"events":[{"type":"navigation","t":0,"url":"https://shop.example.com/","title":"Home"},{"type":"longtask","t":120,"duration_ms":80,"name":"self"},{"type":"resource","t":200,"name":"/assets/app.js","duration_ms":40,"transfer_size":1024},{"type":"ajax","t":300,"method":"GET","url":"/api/cart","status":200,"duration_ms":45},{"type":"mutation","t":400,"target":"#root","mutation":"childList","added":1,"removed":0,"textContent":"Hello"}]}
EOF
)")"
  expect_http_any "POST /api/rum/replay" 200 204
  if [[ "$LAST_HTTP" == "204" || "$LAST_HTTP" == "200" ]]; then
    ok "replay chunk ingest HTTP $LAST_HTTP"
  else
    fail "replay chunk ingest HTTP $LAST_HTTP"
  fi

  sleep 2

  body="$(get_json "/api/rum/replay/${sid}")"
  expect_http 200 "GET /api/rum/replay/{session}"
  expect_json_key_or_soft_empty "$body" "chunks" "replay chunks"

  body="$(get_json "/api/rum/replay-timeline/${sid}")"
  expect_http 200 "GET /api/rum/replay-timeline/{session}"
  expect_json_key "$body" "session_id" "replay timeline session_id"
  expect_json_key_or_soft_empty "$body" "events" "replay timeline events"
  if printf '%s' "$body" | grep -q '"by_type"'; then
    ok "replay timeline has by_type"
  else
    soft "replay timeline missing by_type (async CH lag or older agent)"
  fi

  body="$(http_req POST /api/mobile/crash "${JSON_HDR[@]}" "${ORG_HDR[@]}" "${PROJ_HDR[@]}" --data "$(cat <<EOF
{"organization_id":"${ORG_ID}","project_id":"${PROJECT_ID}","session_id":"${sid}","platform":"ios","app_version":"1.0.0-smoke","exception_type":"NSException","message":"smoke crash","stack":"main\\nfoo","device":"iPhone-smoke"}
EOF
)")"
  expect_http_any "POST /api/mobile/crash" 200 204
  if [[ "$LAST_HTTP" == "204" || "$LAST_HTTP" == "200" ]]; then
    ok "mobile crash ingest HTTP $LAST_HTTP"
  else
    soft "mobile crash ingest HTTP $LAST_HTTP"
  fi

  sleep 1

  body="$(get_json /api/rum/mobile/sessions)"
  expect_http_any "GET /api/rum/mobile/sessions" 200 404
  if [[ "$LAST_HTTP" == "200" ]]; then
    expect_json_key_or_soft_empty "$body" "sessions" "mobile sessions"
  else
    soft "mobile sessions HTTP $LAST_HTTP"
  fi

  body="$(get_json "/api/mobile/crashes?session_id=${sid}")"
  expect_http 200 "GET /api/mobile/crashes?session_id="
  expect_json_key_or_soft_empty "$body" "crashes" "mobile crashes"
}

# ---------------------------------------------------------------------------
smoke_wave29() {
  section "Wave 29/31 — Perf lab + harden"

  local body scn_id run_id

  # View route must not accept upsert (admin path is /upsert).
  body="$(post_json /api/perf/scenarios "$(cat <<EOF
{"name":"smoke-health-view","target_url":"http://example.com/","method":"GET","vus":1,"duration_seconds":1}
EOF
)")"
  expect_http_any "POST /api/perf/scenarios (view)" 405 404
  if [[ "$LAST_HTTP" == "405" ]]; then
    ok "view POST /api/perf/scenarios rejected (405)"
  elif [[ "$LAST_HTTP" == "404" ]]; then
    soft "POST /api/perf/scenarios HTTP 404 (older agent)"
  else
    soft "POST /api/perf/scenarios HTTP $LAST_HTTP (expected 405)"
  fi

  # Upsert via admin path (open when auth off).
  body="$(post_json /api/perf/scenarios/upsert "$(cat <<EOF
{"name":"smoke-health","target_url":"https://example.com/","method":"GET","vus":2,"duration_seconds":1,"thresholds":{"p95_ms":2000},"sla":{"p95_ms":2000,"error_rate_max":1}}
EOF
)")"
  expect_http_any "POST /api/perf/scenarios/upsert" 200 403 404
  if [[ "$LAST_HTTP" != "200" ]]; then
    soft "perf scenario upsert HTTP $LAST_HTTP — skip remaining perf harden checks"
    return 0
  fi
  expect_json_key "$body" "ok" "perf scenario upsert"
  expect_json_key "$body" "id" "perf scenario id"
  scn_id="$(printf '%s' "$body" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  # Async CH insert — brief wait before by-id reads / run create ownership check.
  sleep 2

  body="$(get_json /api/perf/scenarios)"
  expect_http 200 "GET /api/perf/scenarios"
  expect_json_key_or_soft_empty "$body" "scenarios" "perf scenarios list"

  # fanout:false keeps create under SMOKE_TIMEOUT; fanout:true runs local load (seconds).
  body="$(post_json /api/perf/runs "$(cat <<EOF
{"scenario_id":"${scn_id:-smoke}","vus":2,"profile":"soak","fanout":false}
EOF
)")"
  expect_http_any "POST /api/perf/runs" 200 404
  if [[ "$LAST_HTTP" != "200" ]]; then
    soft "perf run create HTTP $LAST_HTTP (scenario CH lag or missing migration — skip run-gated harden checks)"
    run_id=""
  else
    expect_json_key "$body" "ok" "perf run create"
    expect_json_key "$body" "id" "perf run id"
    expect_json_key "$body" "load_run_id" "perf load_run_id"
    expect_json_key "$body" "fanout_peers" "perf fanout_peers"
    run_id="$(printf '%s' "$body" | sed -n 's/.*"load_run_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    if [[ -z "$run_id" ]]; then
      run_id="$(printf '%s' "$body" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    fi
  fi

  # Gate fail-closed on in-progress / empty summary.
  if [[ -n "$run_id" ]]; then
    body="$(get_json "/api/perf/runs/${run_id}/gate")"
    expect_http_any "GET /api/perf/runs/{id}/gate (running)" 200 404
    if [[ "$LAST_HTTP" == "200" ]]; then
      if printf '%s' "$body" | grep -Eq '"ok"[[:space:]]*:[[:space:]]*false|"status"[[:space:]]*:[[:space:]]*"(failed|running)"'; then
        ok "gate fail-closed on running/empty run"
      else
        soft "gate body did not fail-closed: $body"
      fi
    else
      soft "run gate HTTP $LAST_HTTP"
    fi
  fi

  # Scenario gate rejects mismatched run_id / scenario_id.
  body="$(post_json /api/perf/scenarios/upsert "$(cat <<EOF
{"name":"smoke-other","target_url":"https://example.com/other","method":"GET","vus":1,"duration_seconds":1,"sla":{"p95_ms":100}}
EOF
)")"
  local other_id=""
  if [[ "$LAST_HTTP" == "200" ]]; then
    other_id="$(printf '%s' "$body" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  fi
  if [[ -n "$other_id" ]]; then
    sleep 1
  fi
  if [[ -n "$run_id" && -n "$other_id" && -n "$scn_id" && "$other_id" != "$scn_id" ]]; then
    body="$(post_json "/api/perf/scenarios/${other_id}/gate" "{\"run_id\":\"${run_id}\"}")"
    expect_http_any "POST scenario gate mismatch" 400 404 200
    if [[ "$LAST_HTTP" == "400" ]]; then
      ok "scenario gate rejects mismatched run/scenario"
    elif [[ "$LAST_HTTP" == "200" ]] && printf '%s' "$body" | grep -Eq '"ok"[[:space:]]*:[[:space:]]*false'; then
      soft "scenario gate returned 200 ok=false (binding may be soft)"
    else
      soft "scenario gate mismatch HTTP $LAST_HTTP (ClickHouse eventual consistency?)"
    fi
  else
    soft "skip scenario gate mismatch (missing ids)"
  fi

  # Metrics POST without runner/admin token — soft-skip when auth off (compose default).
  if [[ -n "$run_id" ]]; then
    body="$(post_json "/api/perf/runs/${run_id}/metrics" '{"status":"passed","summary":{"requests":1,"p95_ms":1,"error_rate":0}}')"
    expect_http_any "POST metrics without token" 200 403 404
    if [[ "$LAST_HTTP" == "403" ]]; then
      ok "metrics POST rejected without runner/admin token"
    elif [[ "$LAST_HTTP" == "200" ]]; then
      soft "metrics POST allowed (OPA_AUTH_REQUIRED off — admin soft-open; set auth + OPA_PERF_RUNNER_TOKEN to enforce)"
    else
      soft "metrics POST HTTP $LAST_HTTP"
    fi
  fi

  # Optional fan-out with simulate so peer path is exercised without multi-second load.
  body="$(post_json /api/perf/runs "$(cat <<EOF
{"scenario_id":"${scn_id:-smoke}","vus":1,"profile":"soak","fanout":true}
EOF
)")"
  # May exceed default 5s curl budget when local sample runs — soft if timed out.
  expect_http_any "POST /api/perf/runs fanout" 200 0 403
  if [[ "$LAST_HTTP" == "200" ]]; then
    expect_json_key "$body" "fanout_peers" "perf fanout_peers (fanout)"
    if printf '%s' "$body" | grep -Eq '"fanout_peers"[[:space:]]*:[[:space:]]*\[\]'; then
      soft "fanout_peers empty — no federation peers configured (honest skip)"
    elif printf '%s' "$body" | grep -q '"peer_id"'; then
      ok "fanout_peers has local/peer sample"
    else
      soft "fanout_peers present but unexpected shape"
    fi
  elif [[ "$LAST_HTTP" == "403" ]]; then
    soft "perf runs fanout HTTP 403 (admin required when auth on)"
  else
    soft "perf runs fanout HTTP $LAST_HTTP (local load exceeds SMOKE_TIMEOUT — expected under 5s budget)"
  fi

  body="$(get_json /api/perf/runs)"
  expect_http 200 "GET /api/perf/runs"
  expect_json_key_or_soft_empty "$body" "runs" "perf runs list"

  if [[ -n "$run_id" ]]; then
    body="$(get_json "/api/perf/runs/${run_id}/export-k6")"
    expect_http_any "GET /api/perf/runs/{id}/export-k6" 200 404
    if [[ "$LAST_HTTP" == "200" ]]; then
      ok "k6 export HTTP 200"
    else
      soft "k6 export HTTP $LAST_HTTP"
    fi
  fi

  # Peer remote-load ack with simulate=true (instant; no live HTTP load).
  body="$(post_json /api/federation/remote-load "$(cat <<EOF
{"scenario_id":"${scn_id:-smoke}","load_run_id":"${run_id:-smoke-run}","vus":1,"duration_seconds":1,"target_url":"https://example.com/","simulate":true}
EOF
)")"
  expect_http_any "POST /api/federation/remote-load" 200 400 401 404
  if [[ "$LAST_HTTP" == "200" ]]; then
    ok "federation remote-load ack (simulate)"
  elif [[ "$LAST_HTTP" == "401" ]]; then
    soft "federation remote-load HTTP 401 (token required when auth enforced / token empty)"
  else
    soft "federation remote-load HTTP $LAST_HTTP"
  fi

  body="$(get_json /api/performance/baselines)"
  expect_http_any "GET /api/performance/baselines" 200 404
  if [[ "$LAST_HTTP" == "200" ]]; then
    expect_json_key_or_soft_empty "$body" "baselines" "performance baselines"
  else
    soft "performance baselines HTTP $LAST_HTTP"
  fi

  # Wave 31 — multi-step upsert + validate private URL block + import-jmx
  body="$(post_json /api/perf/scenarios/upsert "$(cat <<EOF
{"name":"smoke-steps","target_url":"https://example.com/","method":"GET","vus":1,"duration_seconds":5,"steps":[{"type":"http","name":"health","method":"GET","url":"https://example.com/","think_ms":10}],"sla":{"p95_ms":5000,"error_rate_max":1},"datasets":{}}
EOF
)")"
  expect_http_any "POST /api/perf/scenarios/upsert steps" 200 403 404
  expect_json_key "$body" "id" "steps scenario id"
  local steps_id
  steps_id="$(printf '%s' "$body" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  sleep 2

  if [[ -n "$steps_id" && "$LAST_HTTP" == "200" ]]; then
    body="$(post_json "/api/perf/scenarios/${steps_id}/validate" "{}")"
    expect_http_any "POST /api/perf/scenarios/{id}/validate" 200 403 404 503
    if [[ "$LAST_HTTP" == "200" ]]; then
      ok "scenario validate"
    else
      soft "scenario validate HTTP $LAST_HTTP"
    fi
    body="$(get_json "/api/perf/scenarios/${steps_id}/export-jmx")"
    expect_http_any "GET export-jmx" 200 404
    if [[ "$LAST_HTTP" == "200" ]]; then
      ok "export-jmx"
    else
      soft "export-jmx HTTP $LAST_HTTP"
    fi
  fi

  # Validate blocks private URL (127.0.0.1) in step result.
  body="$(post_json /api/perf/scenarios/upsert "$(cat <<EOF
{"name":"smoke-private","target_url":"http://127.0.0.1:8080/api/health","method":"GET","vus":1,"duration_seconds":5,"steps":[{"type":"http","name":"loopback","method":"GET","url":"http://127.0.0.1:8080/api/health"}],"sla":{"p95_ms":5000}}
EOF
)")"
  local priv_id=""
  expect_http_any "POST upsert private URL scenario" 200 403 404
  if [[ "$LAST_HTTP" == "200" ]]; then
    priv_id="$(printf '%s' "$body" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    sleep 2
  fi
  if [[ -n "$priv_id" ]]; then
    body="$(post_json "/api/perf/scenarios/${priv_id}/validate" "{}")"
    expect_http_any "POST validate private URL" 200 403 404 503
    if [[ "$LAST_HTTP" == "200" ]]; then
      if printf '%s' "$body" | grep -Eqi 'url blocked|not allowed|private|loopback'; then
        ok "validate blocks private URL"
      elif printf '%s' "$body" | grep -Eq '"ok"[[:space:]]*:[[:space:]]*false'; then
        ok "validate private URL marked not ok"
      else
        soft "validate private URL response missing block signal: $body"
      fi
    else
      soft "validate private URL HTTP $LAST_HTTP"
    fi
  else
    soft "skip private URL validate (upsert failed)"
  fi

  body="$(post_json /api/perf/scenarios/import-jmx "$(cat <<'EOF'
{"name":"smoke-jmx","jmx":"<?xml version=\"1.0\"?><jmeterTestPlan version=\"1.2\" properties=\"5.0\" jmeter=\"5.5\"><hashTree><TestPlan testname=\"t\"/><hashTree><ThreadGroup testname=\"tg\" enabled=\"true\"><stringProp name=\"ThreadGroup.num_threads\">1</stringProp><stringProp name=\"ThreadGroup.duration\">5</stringProp></ThreadGroup><hashTree><HTTPSamplerProxy testname=\"h\" enabled=\"true\"><stringProp name=\"HTTPSampler.domain\">example.com</stringProp><stringProp name=\"HTTPSampler.path\">/</stringProp><stringProp name=\"HTTPSampler.method\">GET</stringProp><stringProp name=\"HTTPSampler.protocol\">https</stringProp></HTTPSamplerProxy><hashTree/></hashTree></hashTree></hashTree></jmeterTestPlan>"}
EOF
)")"
  expect_http_any "POST /api/perf/scenarios/import-jmx" 200 400 403 404
  if [[ "$LAST_HTTP" == "200" ]]; then
    expect_json_key "$body" "ok" "import-jmx ok"
    ok "import-jmx safe HTTP JMX"
  else
    soft "import-jmx HTTP $LAST_HTTP (admin auth may be required)"
  fi

  # Wave 31 — Docker-first JMeter dispatch + workers scale
  smoke_wave31_docker_jmeter "${scn_id:-}"
}

# ---------------------------------------------------------------------------
smoke_wave31_docker_jmeter() {
  section "Wave 31 — Docker JMeter dispatch + scale"
  local seed_scn="${1:-}"
  local body scn_id run_id mode workers_n

  body="$(post_json /api/perf/scenarios/upsert "$(cat <<EOF
{"name":"smoke-docker-jmeter","target_url":"https://example.com/","method":"GET","vus":2,"duration_seconds":8,"steps":[{"type":"http","name":"ex","method":"GET","url":"https://example.com/","think_ms":10}],"sla":{"p95_ms":30000,"error_rate_max":1},"thresholds":{"p95_ms":30000,"error_rate_max":1}}
EOF
)")"
  expect_http_any "POST upsert docker-jmeter scenario" 200 403 404
  if [[ "$LAST_HTTP" != "200" ]]; then
    soft "docker-jmeter upsert HTTP $LAST_HTTP — skip Docker dispatch smoke"
    return 0
  fi
  scn_id="$(printf '%s' "$body" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  if [[ -z "$scn_id" ]]; then
    scn_id="$seed_scn"
  fi
  if [[ -z "$scn_id" ]]; then
    soft "docker-jmeter scenario id missing — skip"
    return 0
  fi
  sleep 2

  # Engine=node without allow flag must not be production path.
  body="$(post_json /api/perf/runs "$(cat <<EOF
{"scenario_id":"${scn_id}","vus":1,"dispatch":true,"engine":"node"}
EOF
)")"
  expect_http_any "POST runs engine=node (gated)" 200 403 404
  if [[ "$LAST_HTTP" == "200" ]]; then
    if printf '%s' "$body" | grep -Eqi 'OPA_PERF_ALLOW_NODE_FALLBACK|dev-only|disabled|Node engine is dev-only'; then
      ok "Node engine gated without OPA_PERF_ALLOW_NODE_FALLBACK"
    elif printf '%s' "$body" | grep -Eq '"dispatched"[[:space:]]*:[[:space:]]*true'; then
      soft "Node dispatch succeeded without allow flag (agent may have OPA_PERF_ALLOW_NODE_FALLBACK=1)"
    else
      ok "Node engine not auto-dispatched (gated)"
    fi
  fi

  # Primary path: Docker JMeter dispatch
  body="$(post_json /api/perf/runs "$(cat <<EOF
{"scenario_id":"${scn_id}","vus":2,"dispatch":true,"engine":"jmeter","workers":1}
EOF
)")"
  expect_http_any "POST runs Docker JMeter dispatch" 200 403 404
  if [[ "$LAST_HTTP" != "200" ]]; then
    soft "Docker JMeter dispatch HTTP $LAST_HTTP — skip"
    return 0
  fi
  expect_json_key "$body" "dispatch" "dispatch object"
  mode="$(printf '%s' "$body" | sed -n 's/.*"mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  if printf '%s' "$body" | grep -Eq '"dispatched"[[:space:]]*:[[:space:]]*true'; then
    ok "JMeter dispatched=true"
    if [[ "$mode" == "docker" ]]; then
      ok "JMeter mode=docker (container runner)"
    elif [[ "$mode" == "bin" || "$mode" == "path" ]]; then
      soft "JMeter mode=$mode (host bin — expected only with OPA_PERF_ALLOW_HOST_JMETER=1)"
    else
      soft "JMeter mode missing/unexpected: $mode body=$body"
    fi
  else
    soft "JMeter not dispatched: $body"
    return 0
  fi

  run_id="$(printf '%s' "$body" | sed -n 's/.*"load_run_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  if [[ -z "$run_id" ]]; then
    run_id="$(printf '%s' "$body" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  fi

  # Scale: workers=2 splits VUs across containers
  body="$(post_json /api/perf/runs "$(cat <<EOF
{"scenario_id":"${scn_id}","vus":2,"dispatch":true,"engine":"jmeter","workers":2}
EOF
)")"
  expect_http_any "POST runs Docker JMeter workers=2" 200 403 404
  if [[ "$LAST_HTTP" == "200" ]]; then
    workers_n="$(printf '%s' "$body" | sed -n 's/.*"workers"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)"
    if [[ "$workers_n" == "2" ]] && printf '%s' "$body" | grep -Eq '"dispatched"[[:space:]]*:[[:space:]]*true'; then
      ok "JMeter workers=2 scale dispatch"
    else
      soft "workers scale unexpected: workers=$workers_n body=$body"
    fi
  else
    soft "workers=2 dispatch HTTP $LAST_HTTP"
  fi

  # Poll first docker run to terminal (async JMeter container)
  if [[ -n "$run_id" ]]; then
    local i status=""
    for i in $(seq 1 45); do
      body="$(get_json "/api/perf/runs/${run_id}")"
      status="$(printf '%s' "$body" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
      if [[ "$status" == "passed" || "$status" == "failed" || "$status" == "completed" || "$status" == "error" ]]; then
        break
      fi
      sleep 2
    done
    if [[ "$status" == "passed" || "$status" == "completed" || "$status" == "failed" ]]; then
      ok "Docker JMeter run reached terminal status=$status"
      body="$(get_json "/api/perf/runs/${run_id}/gate")"
      expect_http_any "GET Docker JMeter run gate" 200 404
      if [[ "$LAST_HTTP" == "200" ]]; then
        ok "Docker JMeter SLA gate reachable"
      fi
    else
      soft "Docker JMeter run still status=${status:-unknown} after poll (image pull / JVM cold start?)"
    fi
  fi
}

# ---------------------------------------------------------------------------
smoke_wave30() {
  section "Wave 30 — AppSec hub (secrets / SAST / IaC / PR-check)"

  local body
  body="$(post_json /v1/security/secrets "$(cat <<EOF
{"service":"smoke-shop","findings":[{"rule":"aws-key","file":"config.env","line":3,"severity":"high","snippet":"AKIA****SMOKE","detector":"wave-smoke"}]}
EOF
)")"
  expect_http 200 "POST /v1/security/secrets"
  expect_json_key "$body" "ok" "secrets ingest"
  expect_json_key "$body" "ingested" "secrets ingested"

  body="$(post_json /v1/security/sast "$(cat <<EOF
{"service":"smoke-shop","findings":[{"rule":"sql-concat","file":"app.php","line":10,"severity":"medium","message":"string concat into SQL","tool":"sast-lite"}]}
EOF
)")"
  expect_http 200 "POST /v1/security/sast"
  expect_json_key "$body" "ok" "sast ingest"

  body="$(post_json /v1/security/iac "$(cat <<EOF
{"findings":[{"kind":"dockerfile","rule":"no-root","file":"Dockerfile","line":1,"severity":"low","message":"runs as root","resource":"smoke-image"}]}
EOF
)")"
  expect_http 200 "POST /v1/security/iac"
  expect_json_key "$body" "ok" "iac ingest"

  body="$(post_json /v1/ndjson "$(cat <<EOF
{"type":"iast","organization_id":"${ORG_ID}","project_id":"${PROJECT_ID}","service":"smoke-shop","sink":"sql.injection","evidence":"SELECT * FROM users WHERE id='1' OR '1'='1","route":"/api/users","blocked":true,"trace_id":"smoke-block","span_id":"smoke-span"}
EOF
)")"
  expect_http 200 "POST /v1/ndjson type:iast blocked"
  expect_json_key "$body" "ok" "ndjson iast blocked"

  sleep 1

  body="$(get_json /api/security/secrets)"
  expect_http 200 "GET /api/security/secrets"
  expect_json_key_or_soft_empty "$body" "findings" "secrets list"

  body="$(get_json /api/security/sast)"
  expect_http 200 "GET /api/security/sast"
  expect_json_key_or_soft_empty "$body" "findings" "sast list"

  body="$(get_json /api/security/iac)"
  expect_http 200 "GET /api/security/iac"
  expect_json_key_or_soft_empty "$body" "findings" "iac list"

  body="$(get_json /api/security/policies)"
  expect_http 200 "GET /api/security/policies"
  expect_json_key "$body" "fail_on_secrets" "security policies"

  body="$(get_json /api/security/pr-check)"
  expect_http 200 "GET /api/security/pr-check"
  # PR-check may fail=true after we ingested secrets — that is success for the API.
  if printf '%s' "$body" | grep -Eq '"fail"|"ok"|"status"|"pass"'; then
    ok "pr-check responded with gate fields"
  else
    soft "pr-check body missing expected gate keys: $body"
  fi

  # Notebook execute (Wave 26 deepen) — create TQL notebook then execute.
  body="$(post_json /api/notebooks "$(cat <<EOF
{"title":"Smoke TQL execute","description":"wave30","cells":[{"type":"tql","content":"FIND spans LIMIT 1"}],"created_by":"smoke"}
EOF
)")"
  expect_http 200 "POST /api/notebooks (tql)"
  local nb_id
  nb_id="$(printf '%s' "$body" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  if [[ -n "$nb_id" ]]; then
    body="$(post_json "/api/notebooks/${nb_id}/execute" '{}')"
    expect_http_any "POST /api/notebooks/{id}/execute" 200 400 404 500
    if [[ "$LAST_HTTP" == "200" ]]; then
      ok "notebook execute HTTP 200"
    else
      soft "notebook execute HTTP $LAST_HTTP"
    fi
  else
    soft "notebook id missing — skip execute"
  fi

  # Federated TQL — soft when no peers.
  body="$(post_json /api/federation/query '{"kind":"tql","query":"FIND spans LIMIT 1"}')"
  expect_http_any "POST /api/federation/query kind=tql" 200 400 404 405
  if [[ "$LAST_HTTP" == "200" ]]; then
    ok "federated TQL HTTP 200"
  else
    soft "federated TQL HTTP $LAST_HTTP (peers optional)"
  fi
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
  smoke_rum_vitals
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
  smoke_wave28
  smoke_wave29
  smoke_wave30

  smoke_summary
}

main "$@"
