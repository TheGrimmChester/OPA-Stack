#!/usr/bin/env bash
# Sync Open-* family source trees on the NAS build host to origin/main.
#
# Converts stale rsync copies into shallow git clones on first run, then
# fast-forwards with `git fetch origin main` on later runs.
#
# Run on the NAS (or any host whose FAMILY_ROOT contains the family repos):
#   export FAMILY_ROOT=/mnt/Apps/config-docker/open-stack/src
#   "$FAMILY_ROOT/OPA-Stack/harness/sync-nas-src.sh"
#   "$FAMILY_ROOT/OPA-Stack/harness/sync-nas-src.sh" OPA-Hub ORA-API
#
# Audit only (no changes):
#   "$FAMILY_ROOT/OPA-Stack/harness/sync-nas-src.sh" --audit
#
# Laptop rsync fallback when NAS cannot reach GitHub:
#   "$FAMILY_ROOT/OPA-Stack/harness/sync-nas-src.sh" --rsync \
#     --nas-host root@192.168.100.101 \
#     --laptop-root "$HOME/Documents/repos"
#
set -euo pipefail

FAMILY_ROOT="${FAMILY_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
if [[ -d "$FAMILY_ROOT/../OPA-Hub" ]]; then
  FAMILY_ROOT="$(cd "$FAMILY_ROOT/.." && pwd)"
elif [[ -d "$FAMILY_ROOT/OPA-Hub" ]]; then
  :
elif [[ -d "$(pwd)/OPA-Hub" ]]; then
  FAMILY_ROOT="$(pwd)"
fi

ORG="TheGrimmChester"
REPOS=(
  OPA-Stack
  OPA-Hub
  OPA-Agent
  opa-collector
  ORA-API
  OSA-API
  OPL-API
  OPM-API
  OAM-API
  Open-Auth-Go
  Open-ClickHouse-Go
  Open-Client-Go
  Open-Job-Go
  Open-Tenant-Go
  Open-HTTP-Go
  Open-Logger-Go
  Open-Egress-Proxy
  OPA-Dashboard
  ORA-Dashboard
  OSA-Dashboard
  OPL-Dashboard
  OPM-Dashboard
  OAM-Dashboard
  Open-Client-JS
  Open-UI-JS
)

repo_url() {
  local name="$1"
  echo "https://github.com/${ORG}/${name}.git"
}

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

MODE=git
AUDIT=0
DRY_RUN=0
NAS_HOST=""
LAPTOP_ROOT=""

ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --audit) AUDIT=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --rsync) MODE=rsync; shift ;;
    --nas-host) NAS_HOST="${2:?--nas-host requires value}"; shift 2 ;;
    --laptop-root) LAPTOP_ROOT="${2:?--laptop-root requires value}"; shift 2 ;;
    --) shift; ARGS+=("$@"); break ;;
    -*) echo "error: unknown flag $1" >&2; usage 1 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

if [[ ${#ARGS[@]} -gt 0 ]]; then
  REPOS=("${ARGS[@]}")
fi

remote_main() {
  local url="$1"
  git ls-remote --exit-code "$url" refs/heads/main 2>/dev/null | awk '{print substr($1,1,7)}'
}

audit_repo() {
  local name="$1"
  local dir="$FAMILY_ROOT/$name"
  local url
  url="$(repo_url "$name")"
  local remote local_head state

  remote="$(remote_main "$url" || echo "?")"

  if [[ ! -d "$dir" ]]; then
    printf "%-22s %-6s %-8s %-8s %s\n" "$name" "MISSING" "-" "$remote" "$url"
    return
  fi

  if [[ -d "$dir/.git" ]]; then
    state="git"
    local_head="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "?")"
  else
    state="stale"
    local_head="-"
  fi

  local match="?"
  if [[ "$state" == "git" && "$remote" != "?" && "$local_head" == "$remote" ]]; then
    match="ok"
  elif [[ "$state" == "stale" ]]; then
    match="STALE"
  elif [[ "$remote" != "?" ]]; then
    match="DRIFT"
  fi

  printf "%-22s %-6s %-8s %-8s %s\n" "$name" "$state" "$local_head" "$remote" "$match"
}

run_audit() {
  echo "FAMILY_ROOT=$FAMILY_ROOT"
  printf "%-22s %-6s %-8s %-8s %s\n" "REPO" "TYPE" "HEAD" "ORIGIN" "STATUS"
  local name
  for name in "${REPOS[@]}"; do
    audit_repo "$name"
  done
}

sync_git_repo() {
  local name="$1"
  local url dir
  url="$(repo_url "$name")"
  dir="$FAMILY_ROOT/$name"

  if [[ -d "$dir/.git" ]]; then
    echo "==> $name: fetch origin/main"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      return 0
    fi
    if ! git -C "$dir" remote get-url origin >/dev/null 2>&1; then
      echo "    warning: broken clone (no origin) — re-cloning"
      rm -rf "$dir"
      git clone --depth 1 -b main "$url" "$dir"
      echo "    HEAD $(git -C "$dir" rev-parse --short HEAD) $(git -C "$dir" log -1 --format='%s')"
      return 0
    fi
    git -C "$dir" fetch --depth 1 origin main
    git -C "$dir" checkout -B main origin/main 2>/dev/null || git -C "$dir" checkout -B main FETCH_HEAD
    git -C "$dir" reset --hard origin/main 2>/dev/null || git -C "$dir" reset --hard FETCH_HEAD
    echo "    HEAD $(git -C "$dir" rev-parse --short HEAD) $(git -C "$dir" log -1 --format='%s')"
    return 0
  fi

  echo "==> $name: clone fresh (replacing stale copy)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi

  local bak tmp
  bak="${dir}.pre-sync.bak.$$"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  if [[ -d "$dir" ]]; then
    mv "$dir" "$bak"
  fi
  git clone --depth 1 -b main "$url" "$dir"
  rm -rf "$bak"
  echo "    HEAD $(git -C "$dir" rev-parse --short HEAD) $(git -C "$dir" log -1 --format='%s')"
}

sync_rsync_repo() {
  local name="$1"
  local src="$LAPTOP_ROOT/$name/"
  local dst="$NAS_HOST:/mnt/Apps/config-docker/open-stack/src/$name/"

  if [[ ! -d "$LAPTOP_ROOT/$name" ]]; then
    echo "error: missing laptop checkout $LAPTOP_ROOT/$name" >&2
    exit 1
  fi

  echo "==> $name: rsync $src -> $dst"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    rsync -azn --delete --exclude '.git' "$src" "$dst"
  else
    rsync -az --delete --exclude '.git' "$src" "$dst"
  fi
}

if [[ "$AUDIT" -eq 1 ]]; then
  run_audit
  exit 0
fi

if [[ "$MODE" == "rsync" ]]; then
  if [[ -z "$NAS_HOST" || -z "$LAPTOP_ROOT" ]]; then
    echo "error: --rsync requires --nas-host and --laptop-root" >&2
    exit 1
  fi
  echo "==> rsync mode: $LAPTOP_ROOT -> $NAS_HOST (FAMILY_ROOT/src on NAS)"
  local_name=""
  for local_name in "${REPOS[@]}"; do
    sync_rsync_repo "$local_name"
  done
  echo "==> Done (rsync). Re-run with --audit on NAS after converting to git clones."
  exit 0
fi

if ! command -v git >/dev/null 2>&1; then
  echo "error: git not found; use --rsync from laptop instead" >&2
  exit 1
fi

echo "==> FAMILY_ROOT=$FAMILY_ROOT"
echo "==> git sync to origin/main (${#REPOS[@]} repo(s))"

name=""
for name in "${REPOS[@]}"; do
  sync_git_repo "$name"
done

echo "==> Done. Audit:"
run_audit
