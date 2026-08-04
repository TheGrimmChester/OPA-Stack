#!/usr/bin/env bash
# Build Open-* family images with *:smoke tags for laptop only.
# Never run this on the NAS — use harness/rebuild-nas-images.sh (*:nas) there.
#
# Usage (from family repos root, e.g. ~/Documents/repos):
#   OPA-Stack/harness/rebuild-smoke-images.sh
#   OPA-Stack/harness/rebuild-smoke-images.sh hub ora-api dashboards
#
set -euo pipefail

FAMILY_ROOT="${FAMILY_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
if [[ -d "$FAMILY_ROOT/../OPA-Hub" ]]; then
  FAMILY_ROOT="$(cd "$FAMILY_ROOT/.." && pwd)"
elif [[ -d "$FAMILY_ROOT/OPA-Hub" ]]; then
  :
elif [[ -d "$(pwd)/OPA-Hub" ]]; then
  FAMILY_ROOT="$(pwd)"
else
  echo "error: set FAMILY_ROOT to the directory that contains OPA-Hub, ORA-API, Open-*, …" >&2
  exit 1
fi

STACK_DIR="${STACK_DIR:-$FAMILY_ROOT/OPA-Stack}"
DOCKER_DIR="$STACK_DIR/harness/docker"
TAG=smoke
COMPOSE_FILE="${COMPOSE_FILE:-$STACK_DIR/compose.all.yaml}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-open-family}"
export COMPOSE_PROJECT_NAME

echo "==> FAMILY_ROOT=$FAMILY_ROOT"
echo "==> tagging all builds as *:$TAG (laptop smoke only)"

need() {
  local d="$1"
  if [[ ! -d "$FAMILY_ROOT/$d" ]]; then
    echo "error: missing $FAMILY_ROOT/$d" >&2
    exit 1
  fi
}

build_df() {
  local dockerfile="$1"
  local image="$2"
  shift 2
  echo "==> Building $image from $dockerfile"
  docker build -f "$DOCKER_DIR/$dockerfile" -t "$image" "$@" "$FAMILY_ROOT"
}

build_ctx() {
  local ctx="$1"
  local image="$2"
  shift 2
  echo "==> Building $image from $ctx"
  docker build -t "$image" "$@" "$FAMILY_ROOT/$ctx"
}

TARGETS=("$@")
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  TARGETS=(all)
fi

wants() {
  local name="$1"
  local t
  for t in "${TARGETS[@]}"; do
    if [[ "$t" == "all" || "$t" == "$name" ]]; then
      return 0
    fi
  done
  return 1
}

if wants hub || wants all; then
  need OPA-Hub
  need Open-Auth-Go
  need Open-ClickHouse-Go
  need Open-HTTP-Go
  need Open-Logger-Go
  if [[ -f "$DOCKER_DIR/opa-hub.nas.Dockerfile" ]]; then
    build_df opa-hub.nas.Dockerfile "opa-hub:$TAG"
  else
    build_ctx OPA-Hub "opa-hub:$TAG"
  fi
fi

if wants agent || wants all; then
  need OPA-Agent
  build_ctx OPA-Agent "opa-agent:$TAG"
fi

if wants collector || wants all; then
  need opa-collector
  build_ctx opa-collector "opa-collector:$TAG"
fi

if wants ora-api || wants all; then
  need ORA-API
  need Open-Auth-Go
  need Open-Client-Go
  need Open-Job-Go
  need Open-Tenant-Go
  need Open-ClickHouse-Go
  need Open-HTTP-Go
  need Open-Logger-Go
  if [[ -f "$DOCKER_DIR/ora-api.nas.Dockerfile" ]]; then
    build_df ora-api.nas.Dockerfile "ora-api:$TAG" --target ora-api
    docker build -f "$DOCKER_DIR/ora-api.nas.Dockerfile" -t "ora-runner-git:$TAG" --target ora-runner-git "$FAMILY_ROOT"
  else
    build_ctx ORA-API "ora-api:$TAG"
  fi
fi

if wants osa-api || wants all; then
  need OSA-API
  need Open-Auth-Go
  need Open-Job-Go
  need Open-Tenant-Go
  need Open-ClickHouse-Go
  need Open-HTTP-Go
  need Open-Logger-Go
  if [[ -f "$DOCKER_DIR/osa-api.nas.Dockerfile" ]]; then
    build_df osa-api.nas.Dockerfile "osa-api:$TAG" --target osa-api
    docker build -f "$DOCKER_DIR/osa-api.nas.Dockerfile" -t "osa-runner-scan:$TAG" --target osa-runner-scan "$FAMILY_ROOT"
  else
    build_ctx OSA-API "osa-api:$TAG"
  fi
fi

if wants opl-api || wants all; then
  need OPL-API
  need Open-Auth-Go
  need Open-Job-Go
  need Open-Tenant-Go
  need Open-ClickHouse-Go
  need Open-HTTP-Go
  need Open-Logger-Go
  if [[ -f "$DOCKER_DIR/opl-api.nas.Dockerfile" ]]; then
    build_df opl-api.nas.Dockerfile "opl-api:$TAG" --target opl-api
    docker build -f "$DOCKER_DIR/opl-api.nas.Dockerfile" -t "opl-runner-jmeter:$TAG" --target opl-runner-jmeter "$FAMILY_ROOT"
  else
    build_ctx OPL-API "opl-api:$TAG"
  fi
fi

if wants opm-api || wants all; then
  need OPM-API
  need Open-Auth-Go
  need Open-Job-Go
  need Open-Tenant-Go
  need Open-HTTP-Go
  need Open-Logger-Go
  if [[ -f "$DOCKER_DIR/opm-api.nas.Dockerfile" ]]; then
    build_df opm-api.nas.Dockerfile "opm-api:$TAG" --target opm-api
  else
    build_ctx OPM-API "opm-api:$TAG"
  fi
fi

if wants egress || wants all; then
  need Open-Egress-Proxy
  build_ctx Open-Egress-Proxy "open-egress-proxy:$TAG"
fi

if wants dashboards || wants all; then
  need OPA-Dashboard
  need ORA-Dashboard
  need OSA-Dashboard
  need OPL-Dashboard
  need OPM-Dashboard
  need Open-Client-JS
  need Open-UI-JS
  build_ctx OPA-Dashboard "opa-dashboard:$TAG"
  if [[ -f "$DOCKER_DIR/dashboard.nas.Dockerfile" ]]; then
    for pair in \
      "ORA-Dashboard:ora-dashboard" \
      "OSA-Dashboard:osa-dashboard" \
      "OPL-Dashboard:opl-dashboard" \
      "OPM-Dashboard:opm-dashboard"
    do
      product="${pair%%:*}"
      image="${pair##*:}"
      echo "==> Building ${image}:$TAG (PRODUCT=$product)"
      docker build -f "$DOCKER_DIR/dashboard.nas.Dockerfile" \
        --build-arg "PRODUCT=$product" \
        -t "${image}:$TAG" \
        "$FAMILY_ROOT"
    done
  fi
fi

if [[ "${RECREATE:-0}" == "1" ]]; then
  echo "==> Recreating compose project $COMPOSE_PROJECT_NAME from $COMPOSE_FILE"
  docker compose -f "$COMPOSE_FILE" up -d --force-recreate
fi

echo "==> Done. Images tagged *:$TAG:"
docker images --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}' \
  | grep -E ":(smoke)\s" | grep -E '^(opa-|ora-|osa-|opl-|opm-|open-)' || true
