#!/usr/bin/env bash
# Wave 30/34 — PR security check against Agent /v1/security/pr-check (token-gated when set).
set -euo pipefail
AGENT_URL="${AGENT_URL:-http://127.0.0.1:8080}"
TOKEN="${OPA_SECURITY_INGEST_TOKEN:-}"
SCOPE_ARGS=()
if [[ -n "${SECURITY_RUN_ID:-}" ]]; then
  SCOPE_ARGS=(-H "Content-Type: application/json" -d "{\"security_run_id\":\"${SECURITY_RUN_ID}\"}")
fi
if [[ -n "$TOKEN" ]]; then
  resp=$(curl -sS -X POST \
    -H "X-OPA-Security-Token: ${TOKEN}" \
    -H "Authorization: Bearer ${TOKEN}" \
    "${SCOPE_ARGS[@]}" \
    "${AGENT_URL%/}/v1/security/pr-check")
else
  if [[ ${#SCOPE_ARGS[@]} -gt 0 ]]; then
    resp=$(curl -sS -X POST "${SCOPE_ARGS[@]}" "${AGENT_URL%/}/api/security/pr-check")
  else
    resp=$(curl -sS "${AGENT_URL%/}/api/security/pr-check")
  fi
fi
echo "$resp"
if echo "$resp" | grep -Eq '"fail"[[:space:]]*:[[:space:]]*true|"status"[[:space:]]*:[[:space:]]*"fail"'; then
  exit 1
fi
exit 0
