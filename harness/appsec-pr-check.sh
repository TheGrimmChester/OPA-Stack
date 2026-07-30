#!/usr/bin/env bash
# Wave 30 — PR security check against Agent /api/security/pr-check
set -euo pipefail
AGENT_URL="${AGENT_URL:-http://127.0.0.1:8080}"
resp=$(curl -sS "${AGENT_URL}/api/security/pr-check")
echo "$resp"
if echo "$resp" | grep -q '"fail":true\|"status":"fail"'; then
  exit 1
fi
exit 0
