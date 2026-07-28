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
if [ "$STATUS" = "204" ]; then
  echo "rum-smoke: OK"
else
  echo "rum-smoke: FAILED (expected 204)" >&2
  exit 1
fi
