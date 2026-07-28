#!/bin/sh
# Manual smoke for the node-app service (opa-node demo, see docker-compose.yaml).
# Hits /hello (outbound http-client instrumentation) and /db (manual SQL/span
# API) a few times so traces show up in the dashboard under service
# "node-smoke".
#
# Usage:
#   harness/node-smoke.sh [base-url] [passes]
#
#   base-url  default http://localhost:3000  (node-app publishes 3000:3000;
#             use http://node-app:3000 when running inside the compose network)
#   passes    default 5
set -eu

BASE_URL="${1:-http://localhost:3000}"
PASSES="${2:-5}"

i=1
while [ "$i" -le "$PASSES" ]; do
  echo "--- pass $i/$PASSES GET $BASE_URL/hello"
  curl -fsS "$BASE_URL/hello"
  echo
  echo "--- pass $i/$PASSES GET $BASE_URL/db"
  curl -fsS "$BASE_URL/db"
  echo
  i=$((i + 1))
done

echo "node-smoke: OK ($PASSES passes against $BASE_URL)"
