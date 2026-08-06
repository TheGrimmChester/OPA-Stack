#!/usr/bin/env bash
# Build Open-* family images with *:nas tags only.
# Never tags *:smoke. Run on the NAS (or a build host that can load into NAS Docker).
#
# Usage (from family repos root, e.g. /mnt/Apps/config-docker/open-stack/src):
#   OPA-Stack/harness/rebuild-nas-images.sh
#   OPA-Stack/harness/rebuild-nas-images.sh hub ora-api dashboards
#
set -euo pipefail

FAMILY_ROOT="${FAMILY_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# When invoked from OPA-Stack/harness, ../.. is OPA-Stack — prefer parent of OPA-Stack.
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
TAG=nas
# Rebuild without layer cache: NO_CACHE=1 OPA-Stack/harness/rebuild-nas-images.sh …
NO_CACHE_ARGS=()
if [[ "${NO_CACHE:-}" == "1" || "${NO_CACHE:-}" == "true" ]]; then
  NO_CACHE_ARGS=(--no-cache)
  echo "==> NO_CACHE enabled (docker build --no-cache)"
fi

echo "==> FAMILY_ROOT=$FAMILY_ROOT"
echo "==> tagging all builds as *:$TAG (production)"

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
  docker build "${NO_CACHE_ARGS[@]}" -f "$DOCKER_DIR/$dockerfile" -t "$image" "$@" "$FAMILY_ROOT"
}

build_ctx() {
  local ctx="$1"
  local image="$2"
  shift 2
  echo "==> Building $image from $ctx"
  docker build "${NO_CACHE_ARGS[@]}" -t "$image" "$@" "$FAMILY_ROOT/$ctx"
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
  need Open-Cache-Go
  need Open-Crypto-Go
  build_df opa-hub.nas.Dockerfile "opa-hub:$TAG"
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
  need Open-Job-Env-Go
  need Open-Tenant-Go
  need Open-ClickHouse-Go
  need Open-HTTP-Go
  need Open-Logger-Go
  need Open-Cache-Go
  need Open-Crypto-Go
  build_df ora-api.nas.Dockerfile "ora-api:$TAG" --target ora-api
  docker build "${NO_CACHE_ARGS[@]}" -f "$DOCKER_DIR/ora-api.nas.Dockerfile" -t "ora-runner-git:$TAG" --target ora-runner-git "$FAMILY_ROOT"
  docker build "${NO_CACHE_ARGS[@]}" -f "$DOCKER_DIR/ora-api.nas.Dockerfile" -t "ora-runner-ai:$TAG" --target ora-runner-ai "$FAMILY_ROOT"
fi

if wants osa-api || wants all; then
  need OSA-API
  need Open-Auth-Go
  need Open-Client-Go
  need Open-Job-Go
  need Open-Job-Env-Go
  need Open-Tenant-Go
  need Open-ClickHouse-Go
  need Open-HTTP-Go
  need Open-Logger-Go
  need Open-Cache-Go
  need Open-Crypto-Go
  build_df osa-api.nas.Dockerfile "osa-api:$TAG" --target osa-api
  docker build "${NO_CACHE_ARGS[@]}" -f "$DOCKER_DIR/osa-api.nas.Dockerfile" -t "osa-runner-scan:$TAG" --target osa-runner-scan "$FAMILY_ROOT"
fi

if wants oam-api || wants all; then
  need OAM-API
  need Open-Auth-Go
  need Open-Tenant-Go
  need Open-ClickHouse-Go
  need Open-HTTP-Go
  need Open-Logger-Go
  need Open-Cache-Go
  need Open-Crypto-Go
  build_df oam-api.nas.Dockerfile "oam-api:$TAG" --target oam-api
fi

if wants opl-api || wants all; then
  need OPL-API
  need Open-Auth-Go
  need Open-Job-Go
  need Open-Tenant-Go
  need Open-ClickHouse-Go
  need Open-HTTP-Go
  need Open-Logger-Go
  need Open-Cache-Go
  need Open-Crypto-Go
  build_df opl-api.nas.Dockerfile "opl-api:$TAG" --target opl-api
  docker build "${NO_CACHE_ARGS[@]}" -f "$DOCKER_DIR/opl-api.nas.Dockerfile" -t "opl-runner-jmeter:$TAG" --target opl-runner-jmeter "$FAMILY_ROOT"
fi

if wants opm-api || wants all; then
  need OPM-API
  need Open-Auth-Go
  need Open-Client-Go
  need Open-Job-Go
  need Open-Job-Env-Go
  need Open-Tenant-Go
  need Open-HTTP-Go
  need Open-Logger-Go
  need Open-Cache-Go
  need Open-Crypto-Go
  build_df opm-api.nas.Dockerfile "opm-api:$TAG" --target opm-api
  docker build "${NO_CACHE_ARGS[@]}" -f "$DOCKER_DIR/opm-api.nas.Dockerfile" -t "opm-runner-task:$TAG" --target opm-runner-task "$FAMILY_ROOT"
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
  need OAM-Dashboard
  need Open-Client-JS
  need Open-UI-JS
  # All product dashboards depend on file:../Open-UI-JS (and most on Open-Client-JS).
  # Build from the family root so those siblings are in the context — the product's
  # own Dockerfile only copies that one repo and fails on @open-family/ui.
  for pair in \
    "OPA-Dashboard:opa-dashboard" \
    "ORA-Dashboard:ora-dashboard" \
    "OSA-Dashboard:osa-dashboard" \
    "OPL-Dashboard:opl-dashboard" \
    "OPM-Dashboard:opm-dashboard" \
    "OAM-Dashboard:oam-dashboard"
  do
    product="${pair%%:*}"
    image="${pair##*:}"
    echo "==> Building ${image}:$TAG (PRODUCT=$product)"
    # NAS publishes OAM on :18097 (smoke uses :8097). Bake peer ports into SPA
    # external links so ORA CTAs open the right origin without nginx 302s.
    docker build "${NO_CACHE_ARGS[@]}" -f "$DOCKER_DIR/dashboard.nas.Dockerfile" \
      --build-arg "PRODUCT=$product" \
      --build-arg "VITE_OAM_DASHBOARD_PORT=18097" \
      --build-arg "VITE_OPM_DASHBOARD_PORT=8098" \
      -t "${image}:$TAG" \
      "$FAMILY_ROOT"
  done
fi

echo "==> Done. Images tagged *:$TAG:"
docker images --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}' \
  | grep -E ":(nas)\s" | grep -E '^(opa-|ora-|osa-|opl-|opm-|oam-|open-)' || true
