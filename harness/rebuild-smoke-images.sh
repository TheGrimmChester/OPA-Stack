#!/usr/bin/env bash
# Build opa-agent:smoke + opa-dashboard:smoke from sibling checkouts and
# recreate compose agent/dashboard (optionally ClickHouse).
#
# Usage (from OPA-stack root):
#   ./harness/rebuild-smoke-images.sh
#   RECREATE_CLICKHOUSE=1 ./harness/rebuild-smoke-images.sh
#   AGENT_REF=wave27-diagnostics DASH_REF=wave27-diagnostics ./harness/rebuild-smoke-images.sh
#
# Sibling paths default to ../OPA-Agent and ../OPA-Dashboard. Prefer checking
# out wave27-diagnostics (or later) so Waves 17–27 APIs are present for wave-smoke.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

AGENT_DIR="${AGENT_DIR:-$ROOT/../OPA-Agent}"
DASH_DIR="${DASH_DIR:-$ROOT/../OPA-Dashboard}"
AGENT_REF="${AGENT_REF:-}"
DASH_REF="${DASH_REF:-}"
RECREATE_CLICKHOUSE="${RECREATE_CLICKHOUSE:-0}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-opa-stack}"
export COMPOSE_PROJECT_NAME

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 1; }; }
need docker
docker compose version >/dev/null

if [[ ! -f "$AGENT_DIR/Dockerfile" ]]; then
  echo "OPA-Agent Dockerfile not found at $AGENT_DIR" >&2
  exit 1
fi
if [[ ! -f "$DASH_DIR/Dockerfile" ]]; then
  echo "OPA-Dashboard Dockerfile not found at $DASH_DIR" >&2
  exit 1
fi

checkout_tip() {
  local dir="$1" ref="$2" label="$3"
  if [[ -z "$ref" ]]; then
    return 0
  fi
  echo "==> Checking out $label @ $ref in $dir"
  git -C "$dir" fetch --quiet origin "$ref" 2>/dev/null || true
  if git -C "$dir" rev-parse --verify "$ref" >/dev/null 2>&1; then
    git -C "$dir" checkout -q "$ref"
  elif git -C "$dir" rev-parse --verify "origin/$ref" >/dev/null 2>&1; then
    git -C "$dir" checkout -q -B "$ref" "origin/$ref"
  else
    echo "    warning: ref $ref not found in $dir — building current HEAD" >&2
  fi
}

# Prefer wave27-diagnostics tips when refs are unset but the branch exists locally.
if [[ -z "$AGENT_REF" ]] && git -C "$AGENT_DIR" rev-parse --verify wave27-diagnostics >/dev/null 2>&1; then
  AGENT_REF=wave27-diagnostics
fi
if [[ -z "$DASH_REF" ]] && git -C "$DASH_DIR" rev-parse --verify wave27-diagnostics >/dev/null 2>&1; then
  DASH_REF=wave27-diagnostics
fi

checkout_tip "$AGENT_DIR" "$AGENT_REF" "OPA-Agent"
checkout_tip "$DASH_DIR" "$DASH_REF" "OPA-Dashboard"

echo "==> Building opa-agent:smoke from $AGENT_DIR"
docker build -t opa-agent:smoke "$AGENT_DIR"

echo "==> Building opa-dashboard:smoke from $DASH_DIR"
docker build -t opa-dashboard:smoke "$DASH_DIR"

if [[ "$RECREATE_CLICKHOUSE" == "1" ]]; then
  echo "==> Recreating clickhouse + agent + dashboard"
  docker compose up -d --force-recreate clickhouse agent dashboard
else
  echo "==> Recreating agent + dashboard (ClickHouse left running)"
  docker compose up -d --force-recreate --no-deps agent dashboard
fi

echo "==> Waiting for agent /api/health"
for i in $(seq 1 90); do
  if curl -fsS --connect-timeout 2 --max-time 2 http://127.0.0.1:8080/api/health >/dev/null 2>&1; then
    echo "    agent healthy"
    echo "Agent:     http://127.0.0.1:8080/api/health"
    echo "Dashboard: http://127.0.0.1:8088"
    echo "Version:   $(curl -fsS http://127.0.0.1:8080/api/version 2>/dev/null || echo '{}')"
    exit 0
  fi
  sleep 2
done

echo "agent did not become healthy in time" >&2
exit 1
