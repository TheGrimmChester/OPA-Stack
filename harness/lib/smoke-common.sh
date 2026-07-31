# shellcheck shell=bash
# Shared helpers for OPA-stack wave smoke scripts.

AGENT_HTTP="${AGENT_HTTP:-http://127.0.0.1:8080}"
# Default sibling ports when hitting host-published smoke stack; compose sets explicit URLs.
if [[ -z "${ORCHESTRATOR_HTTP:-}" ]]; then
  if [[ "$AGENT_HTTP" == "http://127.0.0.1:8080" || "$AGENT_HTTP" == "http://localhost:8080" ]]; then
    ORCHESTRATOR_HTTP="http://127.0.0.1:8091"
  else
    ORCHESTRATOR_HTTP="$AGENT_HTTP"
  fi
fi
if [[ -z "${PERF_LAB_HTTP:-}" ]]; then
  if [[ "$AGENT_HTTP" == "http://127.0.0.1:8080" || "$AGENT_HTTP" == "http://localhost:8080" ]]; then
    PERF_LAB_HTTP="http://127.0.0.1:8092"
  else
    PERF_LAB_HTTP="$AGENT_HTTP"
  fi
fi
ORG_ID="${ORG_ID:-test-org}"
PROJECT_ID="${PROJECT_ID:-default-project}"
SMOKE_TIMEOUT_S="${SMOKE_TIMEOUT_S:-5}"
SMOKE_STRICT="${SMOKE_STRICT:-0}" # 1 = treat soft failures as hard

PASS=0
FAIL=0
SOFT=0

# Persist last HTTP status across command-substitution subshells (body="$(http_req …)").
SMOKE_LAST_HTTP_FILE="${SMOKE_LAST_HTTP_FILE:-${TMPDIR:-/tmp}/opa-smoke-last-http-$$}"

smoke_reset_counters() { PASS=0; FAIL=0; SOFT=0; }

section() {
  printf '\n======== %s ========\n' "$1"
}

ok() {
  PASS=$((PASS + 1))
  printf '  OK  %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL %s\n' "$1" >&2
  if [[ "${SMOKE_STRICT}" == "1" ]]; then
    return 1
  fi
  return 0
}

soft() {
  SOFT=$((SOFT + 1))
  printf '  SOFT %s\n' "$1"
}

# Route extracted verticals to sibling services (fallback Agent URL).
smoke_base_for_path() {
  local path="$1"
  case "$path" in
    /api/perf|/api/perf/*)
      printf '%s' "$PERF_LAB_HTTP"
      ;;
    /api/scm|/api/scm/*|/api/connectors|/api/connectors/*|/api/security/runs|/api/security/runs/*|/api/security/profiles|/v1/scm|/v1/scm/*)
      printf '%s' "$ORCHESTRATOR_HTTP"
      ;;
    *)
      printf '%s' "$AGENT_HTTP"
      ;;
  esac
}

# http_code METHOD PATH [curl args...]
# prints body to stdout; sets global LAST_HTTP (and SMOKE_LAST_HTTP_FILE for subshells)
LAST_HTTP=0
http_req() {
  local method="$1" path="$2"
  shift 2
  local base url
  base="$(smoke_base_for_path "$path")"
  url="${base}${path}"
  local tmp
  tmp="$(mktemp)"
  set +e
  LAST_HTTP=$(curl -sS -o "$tmp" -w '%{http_code}' \
    --connect-timeout "$SMOKE_TIMEOUT_S" --max-time "$SMOKE_TIMEOUT_S" \
    -X "$method" "$@" "$url")
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    LAST_HTTP=0
    printf '%s' "0" >"$SMOKE_LAST_HTTP_FILE"
    echo ""
    rm -f "$tmp"
    return 0
  fi
  printf '%s' "$LAST_HTTP" >"$SMOKE_LAST_HTTP_FILE"
  cat "$tmp"
  rm -f "$tmp"
}

smoke_last_http() {
  if [[ -f "$SMOKE_LAST_HTTP_FILE" ]]; then
    cat "$SMOKE_LAST_HTTP_FILE"
  else
    printf '%s' "${LAST_HTTP:-0}"
  fi
}

expect_http() {
  local want="$1" label="$2"
  local got
  got="$(smoke_last_http)"
  LAST_HTTP="$got"
  if [[ "$got" == "$want" ]]; then
    ok "$label (HTTP $want)"
  else
    fail "$label (HTTP $got, want $want)"
  fi
}

expect_http_any() {
  local label="$1"
  shift
  local got code
  got="$(smoke_last_http)"
  LAST_HTTP="$got"
  for code in "$@"; do
    if [[ "$got" == "$code" ]]; then
      ok "$label (HTTP $got)"
      return 0
    fi
  done
  fail "$label (HTTP $got, want one of: $*)"
}

# expect_json_key BODY KEY LABEL — BODY must contain "KEY"
expect_json_key() {
  local body="$1" key="$2" label="$3"
  if printf '%s' "$body" | grep -q "\"$key\""; then
    ok "$label (has .$key)"
  else
    fail "$label (missing .$key)"
  fi
}

json_get() {
  # Best-effort extract with python3 when available.
  local body="$1" expr="$2"
  if command -v python3 >/dev/null 2>&1; then
    BODY="$body" EXPR="$expr" python3 - <<'PY' 2>/dev/null || true
import json, os
raw = os.environ.get("BODY") or ""
expr = os.environ.get("EXPR") or ""
try:
    data = json.loads(raw)
except Exception:
    print("")
    raise SystemExit(0)
cur = data
for part in expr.split("."):
    if part == "":
        continue
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        print("")
        raise SystemExit(0)
if isinstance(cur, (dict, list)):
    print(json.dumps(cur))
else:
    print(cur)
PY
  fi
}

wait_agent() {
  local i
  for i in $(seq 1 60); do
    if curl -fsS --connect-timeout 2 --max-time 2 "${AGENT_HTTP}/api/health" >/dev/null 2>&1; then
      ok "agent healthy at ${AGENT_HTTP}"
      return 0
    fi
    sleep 1
  done
  fail "agent not healthy at ${AGENT_HTTP}"
  return 1
}

smoke_summary() {
  printf '\n======== SUMMARY ========\n'
  printf 'pass=%s soft=%s fail=%s\n' "$PASS" "$SOFT" "$FAIL"
  if [[ "$FAIL" -gt 0 ]]; then
    return 1
  fi
  return 0
}
