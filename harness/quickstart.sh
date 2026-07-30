#!/usr/bin/env bash
# Wave 16-1: five-minute quickstart — one command to a populated dashboard.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> OPA quickstart"
echo "    Working directory: $ROOT"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1"; exit 1; }; }
need docker
docker compose version >/dev/null

export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-opa-quickstart}"

echo "==> Building / pulling stack images (smoke tags)"
# Prefer prebuilt smoke images; build agent/dashboard if local Dockerfiles exist beside this stack.
if [[ -f ../OPA-Agent/Dockerfile ]]; then
  docker build -t opa-agent:smoke ../OPA-Agent || true
fi
if [[ -f ../OPA-Dashboard/Dockerfile ]]; then
  docker build -t opa-dashboard:smoke ../OPA-Dashboard || true
fi

echo "==> Starting ClickHouse + agent + dashboard"
docker compose up -d clickhouse agent dashboard

echo "==> Waiting for agent health"
for i in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:8080/api/health >/dev/null 2>&1; then
    echo "    agent is up"
    break
  fi
  sleep 2
  if [[ $i -eq 60 ]]; then
    echo "agent did not become healthy in time"; exit 1
  fi
done

echo "==> Generating demo traffic"
bash harness/demo-traffic.sh

if [[ "${WAVE_SMOKE:-0}" == "1" ]]; then
  echo "==> Running Waves 17–27 API smoke (WAVE_SMOKE=1)"
  bash harness/wave-smoke.sh
fi

echo
echo "Dashboard:  http://127.0.0.1:8088"
echo "Agent API:  http://127.0.0.1:8080/api/health"
echo "Version:    $(curl -fsS http://127.0.0.1:8080/api/version 2>/dev/null || echo '{}')"
echo
echo "Done. Open the dashboard — Overview should already show spans."
echo "Wave smoke: WAVE_SMOKE=1 ./harness/quickstart.sh   or   ./harness/wave-smoke.sh"
echo "Rebuild:    ./harness/rebuild-smoke-images.sh"
echo "Tear down: docker compose -p $COMPOSE_PROJECT_NAME down"
