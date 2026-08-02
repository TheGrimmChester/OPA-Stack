#!/usr/bin/env bash
# Build opa-agent:smoke + opa-orchestrator:smoke + opa-perf-lab:smoke +
# opa-dashboard:smoke (+ optional opa-php:smoke) from sibling checkouts and
# recreate compose services (optionally ClickHouse).
#
# Usage (from OPA-stack root):
#   ./harness/rebuild-smoke-images.sh
#   RECREATE_CLICKHOUSE=1 ./harness/rebuild-smoke-images.sh
#   BUILD_PHP=1 ./harness/rebuild-smoke-images.sh
#
# Sibling paths default to ../OPA-Agent, ../OPA-Dashboard, ../OPA-PHP-extension,
# ../OPA-AI-Orchestrator, ../OPA-Perf-Lab.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

AGENT_DIR="${AGENT_DIR:-$ROOT/../OPA-Agent}"
DASH_DIR="${DASH_DIR:-$ROOT/../OPA-Dashboard}"
PHP_DIR="${PHP_DIR:-$ROOT/../OPA-PHP-extension}"
ORCH_DIR="${ORCH_DIR:-$ROOT/../OPA-AI-Orchestrator}"
PERF_DIR="${PERF_DIR:-$ROOT/../OPA-Perf-Lab}"
AGENT_REF="${AGENT_REF:-}"
DASH_REF="${DASH_REF:-}"
PHP_REF="${PHP_REF:-}"
BUILD_PHP="${BUILD_PHP:-1}"
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
if [[ ! -f "$ORCH_DIR/Dockerfile" ]]; then
  echo "OPA-AI-Orchestrator Dockerfile not found at $ORCH_DIR" >&2
  exit 1
fi
if [[ ! -f "$PERF_DIR/Dockerfile" ]]; then
  echo "OPA-Perf-Lab Dockerfile not found at $PERF_DIR" >&2
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

prefer_ref() {
  local dir="$1"
  if git -C "$dir" rev-parse --verify wave28-30-verticals >/dev/null 2>&1; then
    echo wave28-30-verticals
  elif git -C "$dir" rev-parse --verify wave27-diagnostics >/dev/null 2>&1; then
    echo wave27-diagnostics
  else
    echo ""
  fi
}

if [[ -z "$AGENT_REF" ]]; then
  AGENT_REF="$(prefer_ref "$AGENT_DIR")"
fi
if [[ -z "$DASH_REF" ]]; then
  DASH_REF="$(prefer_ref "$DASH_DIR")"
fi
if [[ -z "$PHP_REF" ]]; then
  PHP_REF="$(prefer_ref "$PHP_DIR")"
fi

checkout_tip "$AGENT_DIR" "$AGENT_REF" "OPA-Agent"
checkout_tip "$DASH_DIR" "$DASH_REF" "OPA-Dashboard"
if [[ "$BUILD_PHP" == "1" ]]; then
  checkout_tip "$PHP_DIR" "$PHP_REF" "OPA-PHP-extension"
fi

echo "==> Building opa-agent:smoke from $AGENT_DIR (HEAD=$(git -C "$AGENT_DIR" rev-parse --short HEAD 2>/dev/null || echo '?'))"
docker build -t opa-agent:smoke "$AGENT_DIR"

echo "==> Building opa-orchestrator:smoke from $ORCH_DIR (HEAD=$(git -C "$ORCH_DIR" rev-parse --short HEAD 2>/dev/null || echo '?'))"
docker build -t opa-orchestrator:smoke "$ORCH_DIR"

echo "==> Building opa-perf-lab:smoke from $PERF_DIR (HEAD=$(git -C "$PERF_DIR" rev-parse --short HEAD 2>/dev/null || echo '?'))"
docker build -t opa-perf-lab:smoke "$PERF_DIR"

echo "==> Pre-pulling JMeter image for Perf Lab Docker runner"
docker pull "${OPA_JMETER_IMAGE:-justb4/jmeter:5.5}" || true

echo "==> Building opa-dashboard:smoke from $DASH_DIR (HEAD=$(git -C "$DASH_DIR" rev-parse --short HEAD 2>/dev/null || echo '?'))"
docker build -t opa-dashboard:smoke "$DASH_DIR"

if [[ "$BUILD_PHP" == "1" ]]; then
  if [[ -f "$PHP_DIR/docker/Dockerfile" ]]; then
    echo "==> Building opa-php:smoke from $PHP_DIR (HEAD=$(git -C "$PHP_DIR" rev-parse --short HEAD 2>/dev/null || echo '?'))"
    docker build -f "$PHP_DIR/docker/Dockerfile" -t opa-php:smoke "$PHP_DIR"
  else
    echo "    warning: $PHP_DIR/docker/Dockerfile missing — skipping opa-php:smoke" >&2
  fi
fi

if [[ "$RECREATE_CLICKHOUSE" == "1" ]]; then
  echo "==> Recreating clickhouse + agent + orchestrator + perf-lab + dashboard"
  docker compose up -d --force-recreate clickhouse agent orchestrator perf-lab dashboard
else
  echo "==> Recreating agent + orchestrator + perf-lab + dashboard (ClickHouse left running)"
  docker compose up -d --force-recreate --no-deps agent orchestrator perf-lab dashboard
fi

echo "==> Waiting for agent / orchestrator / perf-lab health"
ok_agent=0 ok_orch=0 ok_perf=0
for i in $(seq 1 90); do
  curl -fsS --connect-timeout 2 --max-time 2 http://127.0.0.1:8080/api/health >/dev/null 2>&1 && ok_agent=1 || true
  curl -fsS --connect-timeout 2 --max-time 2 http://127.0.0.1:8091/api/health >/dev/null 2>&1 && ok_orch=1 || true
  curl -fsS --connect-timeout 2 --max-time 2 http://127.0.0.1:8092/api/health >/dev/null 2>&1 && ok_perf=1 || true
  if [[ "$ok_agent" == "1" && "$ok_orch" == "1" && "$ok_perf" == "1" ]]; then
    echo "    all healthy"
    echo "Agent:         http://127.0.0.1:8080/api/health"
    echo "Orchestrator:  http://127.0.0.1:8091/api/health"
    echo "Perf Lab:      http://127.0.0.1:8092/api/health"
    echo "Dashboard:     http://127.0.0.1:8088"
    docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}' | grep -E 'opa-(agent|dashboard|php|orchestrator|perf-lab)|REPOSITORY' || true
    exit 0
  fi
  sleep 2
done

echo "services did not become healthy in time (agent=$ok_agent orch=$ok_orch perf=$ok_perf)" >&2
exit 1
