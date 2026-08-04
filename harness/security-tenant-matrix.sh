#!/usr/bin/env bash
# Cross-product org/user scope security matrix (co-deployed NAS / lab).
# Usage:
#   HOST=192.168.100.101 ./harness/security-tenant-matrix.sh
# Optional NAS image check (root SSH):
#   CHECK_IMAGES=1 SSHPASS=… HOST=192.168.100.101 ./harness/security-tenant-matrix.sh
# Never uses or builds *:smoke images.
set -u
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:${PATH:-}"
HOST="${HOST:-192.168.100.101}"
CHECK_IMAGES="${CHECK_IMAGES:-0}"

pass=0; fail=0; note_n=0
ok()   { printf 'PASS  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf 'FAIL  %s — %s\n' "$1" "$2"; fail=$((fail+1)); }
note() { printf 'NOTE  %s\n' "$1"; note_n=$((note_n+1)); }

http_code() {
  local method="$1"; shift
  local url="$1"; shift
  curl -sS -o /tmp/opa_tenant_matrix_body.json -w '%{http_code}' --connect-timeout 8 \
    -X "$method" "$@" "$url" 2>/dev/null || echo 000
}

body() { cat /tmp/opa_tenant_matrix_body.json 2>/dev/null; }

json_len() {
  local path="$1"
  python3 -c "
import json
try:
  d=json.load(open('/tmp/opa_tenant_matrix_body.json'))
  cur=d
  for p in '''$path'''.strip('.').split('.'):
    if not p: continue
    if isinstance(cur, dict): cur=cur.get(p)
    else: cur=None; break
  if cur is None: print(-1)
  elif isinstance(cur, list): print(len(cur))
  else: print(0 if cur in (None, {}, []) else 1)
except Exception:
  print(-1)
" 2>/dev/null
}

if [ "$CHECK_IMAGES" = 1 ]; then
  if [ -z "${SSHPASS:-}" ]; then
    bad "CHECK_IMAGES" "set SSHPASS for root@$HOST"
  else
    echo "========== 0. IMAGE TAGS (*:nas only) =========="
    IMG=$(sshpass -e ssh -o StrictHostKeyChecking=no \
      -o PreferredAuthentications=password -o PubkeyAuthentication=no \
      -o ConnectTimeout=20 root@"$HOST" \
      'cd /mnt/Apps/config-docker/open-stack && docker compose -p open-family ps --format "{{.Name}} {{.Image}}"')
    printf '%s\n' "$IMG" | grep -Ei 'hub|ora.api|osa.api|opl.api|opm.api' || true
    if printf '%s\n' "$IMG" | grep -qE ':smoke'; then
      bad "open-family *:nas only" "smoke tag found"
    else
      ok "open-family images have no :smoke"
    fi
    ALL_SMOKE=$(sshpass -e ssh -o StrictHostKeyChecking=no \
      -o PreferredAuthentications=password -o PubkeyAuthentication=no \
      root@"$HOST" 'docker ps --format "{{.Names}} {{.Image}}" | grep -E ":smoke(\s|$)" || true')
    if [ -n "$ALL_SMOKE" ]; then
      bad "NAS no *:smoke containers" "$ALL_SMOKE"
    else
      ok "no *:smoke containers on NAS"
    fi
    for svc in open_hub open_ora_api open_osa_api open_opl_api open_opm_api; do
      cfg=$(sshpass -e ssh -o StrictHostKeyChecking=no \
        -o PreferredAuthentications=password -o PubkeyAuthentication=no \
        root@"$HOST" "docker inspect $svc --format '{{.Config.Image}}' 2>/dev/null" || true)
      if printf '%s' "$cfg" | grep -qE ':nas$'; then
        ok "image $svc Config.Image=$cfg"
      else
        bad "image $svc is *:nas" "Config.Image=$cfg"
      fi
    done
  fi
fi

echo
echo "========== 1. HUB JWT =========="
TOKEN=$(curl -sS -X POST "http://$HOST:18080/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("token",""))')
if [ -n "$TOKEN" ]; then ok "hub login admin/admin -> JWT"; else bad "hub login" "no token"; exit 1; fi

AUTH=(-H "Authorization: Bearer $TOKEN")
DEF=(-H "Authorization: Bearer $TOKEN" -H "X-Organization-ID: default-org" -H "X-Project-ID: default-project")
NAS_T=(-H "Authorization: Bearer $TOKEN" -H "X-Organization-ID: nas" -H "X-Project-ID: infra")
WRONG=(-H "Authorization: Bearer $TOKEN" -H "X-Organization-ID: nonexistent-org-xyz" -H "X-Project-ID: nonexistent-project-xyz")

check_no_jwt() {
  local product="$1" port="$2" path="$3"
  local code
  code=$(http_code GET "http://$HOST:$port$path")
  if [ "$code" = 401 ] || [ "$code" = 403 ]; then
    ok "$product no-JWT $path -> $code"
  else
    bad "$product no-JWT $path" "expected 401/403 got $code body=$(body | head -c 120)"
  fi
}

check_local_login_503() {
  local product="$1" port="$2"
  local code
  code=$(http_code POST "http://$HOST:$port/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d '{"username":"admin","password":"admin"}')
  if [ "$code" = 503 ]; then
    ok "$product local /api/auth/login -> 503"
  else
    bad "$product local login 503" "got $code body=$(body | head -c 160)"
  fi
}

check_tenant_scope() {
  local product="$1" port="$2" path="$3" arr="$4"
  local code_nohdr code_def code_wrong code_nas
  local n_nohdr n_def n_wrong n_nas

  code_nohdr=$(http_code GET "http://$HOST:$port$path" "${AUTH[@]}")
  n_nohdr=$(json_len "$arr")
  code_def=$(http_code GET "http://$HOST:$port$path" "${DEF[@]}")
  n_def=$(json_len "$arr")
  code_wrong=$(http_code GET "http://$HOST:$port$path" "${WRONG[@]}")
  n_wrong=$(json_len "$arr")
  code_nas=$(http_code GET "http://$HOST:$port$path" "${NAS_T[@]}")
  n_nas=$(json_len "$arr")

  printf '  %s %s  nohdr=%s(n=%s) def=%s(n=%s) wrong=%s(n=%s) nas=%s(n=%s)\n' \
    "$product" "$path" "$code_nohdr" "$n_nohdr" "$code_def" "$n_def" "$code_wrong" "$n_wrong" "$code_nas" "$n_nas"

  for pair in "nohdr:$code_nohdr" "def:$code_def" "wrong:$code_wrong"; do
    label=${pair%%:*}; c=${pair##*:}
    if [ "$c" != 200 ] && [ "$c" != 403 ]; then
      bad "$product JWT $label $path" "HTTP $c"
      return
    fi
  done

  if [ "$code_nohdr" = 200 ] && [ "$code_def" = 200 ]; then
    if [ "$n_nohdr" = "$n_def" ]; then
      ok "$product JWT no-headers scopes like default-org (n=$n_def) $path"
    else
      bad "$product JWT no-headers == default-org" "nohdr=$n_nohdr def=$n_def"
    fi
  else
    bad "$product JWT no-headers" "HTTP $code_nohdr"
  fi

  if [ "$code_wrong" = 403 ]; then
    ok "$product JWT wrong-org -> 403 $path"
  elif [ "$code_wrong" = 200 ]; then
    if [ "$n_wrong" = 0 ]; then
      ok "$product JWT wrong-org -> empty $path"
    elif [ "$n_wrong" = "$n_def" ] && [ "$n_def" -gt 0 ]; then
      bad "$product JWT wrong-org never foreign" "wrong==default n=$n_wrong"
    elif [ "$n_wrong" = "$n_nas" ] && [ "$n_nas" -gt 0 ]; then
      bad "$product JWT wrong-org never foreign" "wrong==nas n=$n_wrong"
    else
      bad "$product JWT wrong-org empty" "got n=$n_wrong"
    fi
  else
    bad "$product JWT wrong-org" "HTTP $code_wrong"
  fi

  if [ "$code_def" = 200 ]; then
    if [ "$n_def" -gt 0 ]; then
      ok "$product JWT correct-org has data (n=$n_def) $path"
    else
      note "$product correct-org default empty (n=0)"
      ok "$product JWT correct-org -> 200 $path"
    fi
  else
    bad "$product JWT correct-org" "HTTP $code_def"
  fi

  if [ "$code_nas" = 200 ] && [ "$n_nas" -gt 0 ] && [ "$n_nas" != "$n_def" ]; then
    if [ "$n_wrong" = "$n_nas" ]; then
      bad "$product wrong-org leaked nas rows" "n=$n_wrong"
    else
      ok "$product nas tenant distinct (n=$n_nas) not leaked $path"
    fi
  fi
}

echo
echo "========== 2. NO JWT → 401 =========="
check_no_jwt hub 18080 /api/infra/hosts
check_no_jwt hub 18080 /api/alerts
check_no_jwt hub 18080 /api/tenancy/organizations
check_no_jwt ora 8091 /api/connectors
check_no_jwt ora 8091 /api/scm/jobs
check_no_jwt osa 8093 /api/security/runs
check_no_jwt osa 8093 /api/security/secrets
check_no_jwt opl 8092 /api/perf/scenarios
check_no_jwt opl 8092 /api/perf/runs
check_no_jwt opm 8096 /api/projects

echo
echo "========== 3. LOCAL LOGIN → 503 (codeployed) =========="
hub_login_code=$(http_code POST "http://$HOST:18080/api/auth/login" \
  -H 'Content-Type: application/json' -d '{"username":"admin","password":"admin"}')
if [ "$hub_login_code" = 200 ]; then ok "hub local login allowed (issuer) -> 200"; else bad "hub login" "HTTP $hub_login_code"; fi
check_local_login_503 ora 8091
check_local_login_503 osa 8093
check_local_login_503 opl 8092
check_local_login_503 opm 8096

echo
echo "========== 4. TENANT SCOPE MATRIX =========="
check_tenant_scope hub 18080 /api/infra/hosts hosts
check_tenant_scope hub 18080 /api/alerts alerts
check_tenant_scope ora 8091 '/api/scm/jobs?limit=50' jobs
check_tenant_scope ora 8091 /api/connectors connectors
check_tenant_scope osa 8093 '/api/security/runs?limit=50' runs
check_tenant_scope osa 8093 /api/security/secrets findings
check_tenant_scope opl 8092 /api/perf/scenarios scenarios
check_tenant_scope opl 8092 '/api/perf/runs?limit=50' runs
check_tenant_scope opm 8096 /api/projects projects

echo
echo "========== 5. HUB EXPLORE FACETS =========="
c1=$(http_code GET "http://$HOST:18080/api/explore/facets?signal=spans&field=service&hours=24")
c2=$(http_code GET "http://$HOST:18080/api/explore/facets?signal=spans&field=service&hours=24" "${DEF[@]}")
if [ "$c1" = 401 ] || [ "$c1" = 403 ]; then ok "hub facets no-JWT -> $c1"; else bad "hub facets no-JWT" "HTTP $c1"; fi
if [ "$c2" = 200 ]; then ok "hub facets +JWT -> 200"; else bad "hub facets +JWT" "HTTP $c2"; fi

echo
echo "========== SUMMARY =========="
echo "PASS=$pass FAIL=$fail NOTES=$note_n"
if [ "$fail" -gt 0 ]; then exit 1; fi
exit 0
