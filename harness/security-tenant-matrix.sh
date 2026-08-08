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
OAM_PORT="${OAM_PORT:-18090}"
HUB_PORT="${HUB_PORT:-18080}"
CHECK_IMAGES="${CHECK_IMAGES:-0}"

pass=0; fail=0; note_n=0
ok()   { printf 'PASS  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf 'FAIL  %s — %s\n' "$1" "$2"; fail=$((fail+1)); }
note() { printf 'NOTE  %s\n' "$1"; note_n=$((note_n+1)); }

# Per-process body file avoids n=-1 races when another matrix run shares /tmp.
# Must be a stable path: http_code is often called as code=$(http_code …) in a
# subshell, so a mktemp assignment inside would not reach json_get/json_len.
BODY_FILE="${BODY_FILE:-${TMPDIR:-/tmp}/opa_tenant_matrix_body.$$}"
http_code() {
  local method="$1"; shift
  local url="$1"; shift
  curl -sS -o "$BODY_FILE" -w '%{http_code}' --connect-timeout 8 \
    -X "$method" "$@" "$url" 2>/dev/null || echo 000
}

body() { cat "${BODY_FILE:-/dev/null}" 2>/dev/null; }

json_get() {
  local path="$1"
  local f="${BODY_FILE:-}"
  python3 -c "
import json,sys
try:
  d=json.load(open(sys.argv[1]))
  cur=d
  for p in '''$path'''.strip('.').split('.'):
    if not p: continue
    if isinstance(cur, dict): cur=cur.get(p)
    else: cur=None; break
  if cur is None: print('')
  elif isinstance(cur, bool): print('true' if cur else 'false')
  else: print(cur)
except Exception:
  print('')
" "$f" 2>/dev/null
}

json_len() {
  local path="$1"
  local f="${BODY_FILE:-}"
  python3 -c "
import json,sys
try:
  d=json.load(open(sys.argv[1]))
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
" "$f" 2>/dev/null
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
echo "========== 1. HUB JWT (OAM issuer when PEER_OAM_URL set) =========="
http_code POST "http://$HOST:$HUB_PORT/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' >/dev/null
TOKEN="$(json_get token)"
HUB_ISSUER="$(json_get issuer)"
HUB_ACCT="$(json_get account_type)"
if [ -n "$TOKEN" ]; then ok "hub login admin/admin -> JWT"; else bad "hub login" "no token"; exit 1; fi
HUB_MODE="$(json_get mode)"
if [ "$HUB_ISSUER" = "oam-api" ]; then
  ok "hub login issuer=oam-api (OAM proxy)"
  if [ -n "$HUB_ACCT" ]; then ok "hub login returns account_type=$HUB_ACCT"; else bad "hub login account_type" "missing"; fi
elif [ "$HUB_ISSUER" = "opa-hub" ] || [ "$HUB_MODE" = "hub" ]; then
  note "hub login pre-cutover (issuer=opa-hub or mode=hub) — redeploy opa-hub:nas + oam-api:nas for OAM issuer"
else
  bad "hub login issuer" "got '$HUB_ISSUER' mode='$HUB_MODE'"
fi

echo
echo "========== 1b. OAM LOGIN + /oam-auth BRIDGE =========="
oam_login_code=$(http_code POST "http://$HOST:$OAM_PORT/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}')
OAM_ISSUER="$(json_get issuer)"
OAM_ACCT="$(json_get account_type)"
if [ "$oam_login_code" = 200 ]; then ok "OAM direct login -> 200"; else bad "OAM login" "HTTP $oam_login_code"; fi
if [ "$OAM_ISSUER" = "oam-api" ]; then ok "OAM login issuer=oam-api"; else bad "OAM issuer" "got '$OAM_ISSUER'"; fi
if [ -n "$OAM_ACCT" ]; then
  ok "OAM login account_type=$OAM_ACCT"
  ACCOUNT_TYPE_CUTOVER=1
else
  note "OAM login missing account_type — redeploy oam-api:nas after immutable account_type migration"
  ACCOUNT_TYPE_CUTOVER=0
fi

for dash_port in 8089 8094 8095 8098; do
  bridge_code=$(http_code GET "http://$HOST:$dash_port/oam-auth/api/auth/status")
  bridge_iss="$(json_get issuer)"
  if [ "$bridge_code" = 200 ] && [ "$bridge_iss" = "oam-api" ]; then
    ok "dashboard :$dash_port /oam-auth status issuer=oam-api"
  elif [ "$bridge_code" = 200 ] && [ -z "$bridge_iss" ]; then
    note "dashboard :$dash_port /oam-auth not wired yet (SPA fallback) — redeploy *-dashboard:nas"
  elif [ "$bridge_code" = 000 ]; then
    note "dashboard :$dash_port /oam-auth unreachable"
  else
    bad "dashboard :$dash_port /oam-auth" "HTTP $bridge_code issuer=$bridge_iss"
  fi
done

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
    if [ "$c" != 200 ] && [ "$c" != 403 ] && [ "$c" != 400 ]; then
      bad "$product JWT $label $path" "HTTP $c"
      return
    fi
  done

  # nohdr must NOT silently equal default-org (empty / 400 / JWT-pin)
  if [ "$code_nohdr" = 400 ] || [ "$code_nohdr" = 403 ]; then
    ok "$product JWT no-headers -> $code_nohdr (no default-org fallback) $path"
  elif [ "$code_nohdr" = 200 ]; then
    if [ "$n_nohdr" = "$n_def" ] && [ "$n_def" -gt 0 ]; then
      bad "$product JWT no-headers must NOT equal default-org" "nohdr=$n_nohdr def=$n_def"
    elif [ "$n_nohdr" = 0 ]; then
      ok "$product JWT no-headers -> empty (no default-org fallback) $path"
    elif [ "$n_nohdr" != "$n_def" ]; then
      ok "$product JWT no-headers JWT-pin/own-scope (n=$n_nohdr != def=$n_def) $path"
    else
      # both empty — no silent shared bucket
      ok "$product JWT no-headers -> empty; default-org also empty $path"
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
check_no_jwt hub "$HUB_PORT" /api/infra/hosts
check_no_jwt hub "$HUB_PORT" /api/alerts
check_no_jwt hub "$HUB_PORT" /api/tenancy/organizations
check_no_jwt ora 8091 /api/connectors
check_no_jwt ora 8091 /api/scm/jobs
check_no_jwt osa 8093 /api/security/runs
check_no_jwt osa 8093 /api/security/secrets
check_no_jwt opl 8092 /api/perf/scenarios
check_no_jwt opl 8092 /api/perf/runs
check_no_jwt opm 8096 /api/projects

echo
echo "========== 3. LOCAL LOGIN → 503 (codeployed) =========="
hub_login_code=$(http_code POST "http://$HOST:$HUB_PORT/api/auth/login" \
  -H 'Content-Type: application/json' -d '{"username":"admin","password":"admin"}')
if [ "$hub_login_code" = 200 ]; then ok "hub login allowed (OAM proxy) -> 200"; else bad "hub login" "HTTP $hub_login_code"; fi
check_local_login_503 ora 8091
check_local_login_503 osa 8093
check_local_login_503 opl 8092
check_local_login_503 opm 8096

echo
echo "========== 4. TENANT SCOPE MATRIX =========="
check_tenant_scope hub "$HUB_PORT" /api/infra/hosts hosts
check_tenant_scope hub "$HUB_PORT" /api/alerts alerts
check_tenant_scope ora 8091 '/api/scm/jobs?limit=50' jobs
check_tenant_scope ora 8091 /api/connectors connectors
check_tenant_scope osa 8093 '/api/security/runs?limit=50' runs
check_tenant_scope osa 8093 /api/security/secrets findings
check_tenant_scope opl 8092 /api/perf/scenarios scenarios
check_tenant_scope opl 8092 '/api/perf/runs?limit=50' runs
check_tenant_scope opm 8096 /api/projects projects

echo
echo "========== 5. ACCOUNT TYPE + JWT-BOUND HEADERS =========="
if [ "${ACCOUNT_TYPE_CUTOVER:-0}" != 1 ]; then
  note "account_type checks skipped — OAM not reporting account_type yet"
else
  # Personal non-admin accounts must reject org headers (403). The lab seed
  # admin is account_type=personal WITH role=admin — platform operators may
  # select orgs (Open-Auth IsPersonalAccount is false for admin). Probe a
  # disposable personal viewer instead of the seed token.
  PERS_USER="harness-pers-$$"
  PERS_PASS="harness-pers-pass-$$"
  if [ -n "$TOKEN" ]; then
    pers_create=$(http_code POST "http://$HOST:$OAM_PORT/api/users/set" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' \
      -d "{\"username\":\"$PERS_USER\",\"password\":\"$PERS_PASS\",\"role\":\"viewer\",\"account_type\":\"personal\"}")
    if [ "$pers_create" = 200 ] || [ "$pers_create" = 201 ]; then
      ok "created personal viewer $PERS_USER"
      http_code POST "http://$HOST:$OAM_PORT/api/auth/login" \
        -H 'Content-Type: application/json' \
        -d "{\"username\":\"$PERS_USER\",\"password\":\"$PERS_PASS\"}" >/dev/null
      PERS_TOKEN="$(json_get token)"
      PERS_ACCT="$(json_get account_type)"
      if [ -n "$PERS_TOKEN" ] && [ "$PERS_ACCT" = "personal" ]; then
        code_personal_org=$(http_code GET "http://$HOST:8093/api/security/runs?limit=5" \
          -H "Authorization: Bearer $PERS_TOKEN" \
          -H "X-Organization-ID: nas" -H "X-Project-ID: infra")
        if [ "$code_personal_org" = 403 ]; then
          ok "personal account + org header -> 403 (OSA runs)"
        else
          bad "personal account org header" "expected 403 got $code_personal_org"
        fi
      else
        bad "personal viewer login" "account_type=$PERS_ACCT token_empty=$([ -z \"$PERS_TOKEN\" ] && echo 1 || echo 0)"
      fi
    elif [ "$pers_create" = 000 ]; then
      note "OAM personal user create unreachable — skip personal org-header check"
    else
      note "OAM personal user create HTTP $pers_create — skip personal org-header check"
    fi
  else
    note "no admin token — skip personal org-header check"
  fi

  # Create a disposable organization member and verify foreign org header -> 403.
  ORG_USER="harness-org-$$"
  ORG_PASS="harness-org-pass-$$"
  if [ -n "$TOKEN" ]; then
    create_code=$(http_code POST "http://$HOST:$OAM_PORT/api/users/set" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' \
      -d "{\"username\":\"$ORG_USER\",\"password\":\"$ORG_PASS\",\"role\":\"viewer\",\"account_type\":\"organization\",\"organization_id\":\"nas\",\"project_ids\":[\"infra\"]}")
    if [ "$create_code" = 200 ] || [ "$create_code" = 201 ]; then
      ok "created org test user $ORG_USER (nas/infra)"
      http_code POST "http://$HOST:$OAM_PORT/api/auth/login" \
        -H 'Content-Type: application/json' \
        -d "{\"username\":\"$ORG_USER\",\"password\":\"$ORG_PASS\"}" >/dev/null
      ORG_TOKEN="$(json_get token)"
      ORG_ACCT="$(json_get account_type)"
      ORG_ID="$(json_get org_id)"
      if [ "$ORG_ACCT" = "organization" ] && [ "$ORG_ID" = "nas" ]; then
        ok "org user login account_type=organization org_id=nas"
      else
        bad "org user login claims" "account_type=$ORG_ACCT org_id=$ORG_ID"
      fi
      if [ -n "$ORG_TOKEN" ]; then
        ORG_HDR_CODE=$(http_code GET "http://$HOST:8093/api/security/runs?limit=5" \
          -H "Authorization: Bearer $ORG_TOKEN" \
          -H "X-Organization-ID: default-org" -H "X-Project-ID: default-project")
        if [ "$ORG_HDR_CODE" = 403 ]; then
          ok "org account + foreign org header -> 403 (OSA runs)"
        else
          bad "org account foreign org header" "expected 403 got $ORG_HDR_CODE"
        fi
      fi
      detach_code=$(http_code POST "http://$HOST:$OAM_PORT/api/users/set" \
        -H "Authorization: Bearer $TOKEN" \
        -H 'Content-Type: application/json' \
        -d "{\"username\":\"$ORG_USER\",\"organization_id\":\"\"}")
      if [ "$detach_code" = 400 ] || [ "$detach_code" = 403 ]; then
        ok "detach org (empty organization_id) -> $detach_code"
      else
        bad "detach org rejected" "expected 400/403 got $detach_code"
      fi
      type_code=$(http_code POST "http://$HOST:$OAM_PORT/api/users/set" \
        -H "Authorization: Bearer $TOKEN" \
        -H 'Content-Type: application/json' \
        -d "{\"username\":\"$ORG_USER\",\"account_type\":\"personal\"}")
      if [ "$type_code" = 400 ] || [ "$type_code" = 403 ]; then
        ok "account_type change -> $type_code"
      else
        bad "immutable account_type" "expected 400/403 got $type_code"
      fi
    elif [ "$create_code" = 000 ]; then
      note "OAM user create unreachable — skip org-account header checks"
    else
      note "OAM user create HTTP $create_code — skip org-account checks (ensure org nas exists in OAM directory)"
    fi
  fi
fi

echo
echo "========== 6. HUB EXPLORE FACETS =========="
c1=$(http_code GET "http://$HOST:$HUB_PORT/api/explore/facets?signal=spans&field=service&hours=24")
c2=$(http_code GET "http://$HOST:$HUB_PORT/api/explore/facets?signal=spans&field=service&hours=24" "${DEF[@]}")
if [ "$c1" = 401 ] || [ "$c1" = 403 ]; then ok "hub facets no-JWT -> $c1"; else bad "hub facets no-JWT" "HTTP $c1"; fi
if [ "$c2" = 200 ]; then ok "hub facets +JWT -> 200"; else bad "hub facets +JWT" "HTTP $c2"; fi

echo
echo "========== SUMMARY =========="
echo "PASS=$pass FAIL=$fail NOTES=$note_n"
if [ "$fail" -gt 0 ]; then exit 1; fi
exit 0
