#!/bin/sh
# POST a canned, realistic RUM beacon to the agent's /api/rum ingest endpoint.
# The payload mirrors exactly what opa-rum-js buildPayload() ships: web_vitals,
# navigation_timing, resource_timing, ajax_requests, errors, viewport, plus
# session/page-view ids and tenant fields. Expects HTTP 204 back.
#
# Usage:
#   harness/rum-smoke.sh [base-url] [organization-id] [project-id]
#
#   base-url         default http://localhost:8088 (dashboard nginx proxies
#                    /api/ -> agent:8080). Other useful values:
#                      http://localhost:8080  agent directly, from the host
#                      http://agent:8080      inside the compose network
#   organization-id  default test-org         (matches php-cli / node-app)
#   project-id       default default-project
set -eu

BASE_URL="${1:-http://localhost:8088}"
ORG_ID="${2:-test-org}"
PROJECT_ID="${3:-default-project}"

rand_hex() { od -An -N8 -tx1 /dev/urandom | tr -d ' \n'; }

SESSION_ID="sess-$(rand_hex)"
PAGE_VIEW_ID="pv-$(rand_hex)"
NOW_MS="$(($(date +%s) * 1000))"

PAYLOAD=$(cat <<EOF
{
  "organization_id": "$ORG_ID",
  "project_id": "$PROJECT_ID",
  "session_id": "$SESSION_ID",
  "page_view_id": "$PAGE_VIEW_ID",
  "page_url": "https://shop.example.com/checkout?step=payment",
  "user_agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
  "timestamp": $NOW_MS,
  "navigation_timing": { "total": 1284, "dom": 743, "ttfb": 188 },
  "web_vitals": { "lcp": 1450, "cls": 0.042, "inp": 96, "fcp": 820, "ttfb": 188, "fid": 12 },
  "resource_timing": [
    { "name": "https://shop.example.com/assets/app.js", "type": "script", "duration": 213, "size": 148223 }
  ],
  "ajax_requests": [
    { "url": "https://shop.example.com/api/cart", "method": "GET", "duration": 87, "status": 200 }
  ],
  "errors": [],
  "viewport": { "width": 1440, "height": 900 }
}
EOF
)

echo "POST $BASE_URL/api/rum  (org=$ORG_ID project=$PROJECT_ID session=$SESSION_ID)"
STATUS=$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' \
  --data "$PAYLOAD" \
  "$BASE_URL/api/rum")

echo "HTTP $STATUS"
if [ "$STATUS" != "204" ]; then
  echo "rum-smoke: FAILED (expected 204)" >&2
  exit 1
fi

# Dashboard Browser RUM hits /api/rum/slo (and metrics). Outer aggregates must use
# rumDedupe aliases (v_lcp/…) — referencing web_vitals here was ClickHouse Code 47.
echo "Waiting briefly for ClickHouse ingest…"
sleep 2

SLO_BODY=$(mktemp)
SLO_STATUS=$(curl -sS -o "$SLO_BODY" -w '%{http_code}' \
  -H "X-OPA-Organization-ID: $ORG_ID" -H "X-OPA-Project-ID: $PROJECT_ID" \
  "$BASE_URL/api/rum/slo?hours=24")
echo "GET $BASE_URL/api/rum/slo → HTTP $SLO_STATUS"
if [ "$SLO_STATUS" != "200" ]; then
  echo "rum-smoke: FAILED /api/rum/slo (want 200)" >&2
  cat "$SLO_BODY" >&2 || true
  rm -f "$SLO_BODY"
  exit 1
fi
if grep -Eqi 'UNKNOWN_IDENTIFIER|ClickHouse error' "$SLO_BODY"; then
  echo "rum-smoke: FAILED /api/rum/slo ClickHouse error (outer web_vitals regression?)" >&2
  cat "$SLO_BODY" >&2
  rm -f "$SLO_BODY"
  exit 1
fi
if ! grep -q '"slo"' "$SLO_BODY"; then
  echo "rum-smoke: FAILED /api/rum/slo missing .slo" >&2
  cat "$SLO_BODY" >&2
  rm -f "$SLO_BODY"
  exit 1
fi
rm -f "$SLO_BODY"

MET_BODY=$(mktemp)
MET_STATUS=$(curl -sS -o "$MET_BODY" -w '%{http_code}' \
  -H "X-OPA-Organization-ID: $ORG_ID" -H "X-OPA-Project-ID: $PROJECT_ID" \
  "$BASE_URL/api/rum/metrics")
echo "GET $BASE_URL/api/rum/metrics → HTTP $MET_STATUS"
if [ "$MET_STATUS" != "200" ]; then
  echo "rum-smoke: FAILED /api/rum/metrics (want 200)" >&2
  cat "$MET_BODY" >&2 || true
  rm -f "$MET_BODY"
  exit 1
fi
if grep -Eqi 'UNKNOWN_IDENTIFIER|ClickHouse error' "$MET_BODY"; then
  echo "rum-smoke: FAILED /api/rum/metrics ClickHouse error" >&2
  cat "$MET_BODY" >&2
  rm -f "$MET_BODY"
  exit 1
fi
if ! grep -q 'core_web_vitals' "$MET_BODY"; then
  echo "rum-smoke: FAILED /api/rum/metrics missing core_web_vitals" >&2
  cat "$MET_BODY" >&2
  rm -f "$MET_BODY"
  exit 1
fi
rm -f "$MET_BODY"

echo "rum-smoke: OK (ingest + slo + metrics)"
