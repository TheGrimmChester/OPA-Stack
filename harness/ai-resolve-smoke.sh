#!/usr/bin/env bash
# Smoke: service health, tenant directory scoping, and OAM's AI model/credential
# resolve contract — the one surface with no coverage before this existed.
#
# Assumes a freshly created stack (compose.all.yaml, laptop *:smoke images):
#   docker compose -f compose.all.yaml up -d
#   HOST=127.0.0.1 ./harness/ai-resolve-smoke.sh
#
# Not idempotent by design: section 6 asserts that resolve FAILS CLOSED before
# any credential is stored, so re-running against a stack that already has the
# fixtures reports that one case as a failure. Recreate (`down -v && up -d`)
# between runs.
#
# What it pins down, beyond health:
#   - OAM login returns account_type (immutable personal|organization at creation)
#   - resolve accepts a service JWT only — never a user token, wrong scope, or
#     wrong audience
#   - model and credential come back in ONE response (they must never be able to
#     disagree), with no-store, and fail closed when no credential exists
#   - model precedence: per-task override > org binding > family default
#   - org isolation: one org's key/model never resolves for another, and an
#     org-pinned service token overrides a body that asks for a different org
set -u
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:${PATH:-}"

HOST="${HOST:-127.0.0.1}"
SVC_SECRET="${OPEN_SERVICE_JWT_SECRET:-dev-service-jwt-secret-at-least-32b}"
USR_SECRET="${JWT_SECRET:-dev-shared-jwt-secret-at-least-32b}"
MINT="${MINT:-$(dirname "$0")/lib/mint_service_jwt.py}"
BODY=/tmp/smoke_body.json

HUB="http://$HOST:8080"; OAM="http://$HOST:8090"; ORA="http://$HOST:8091"
OPL="http://$HOST:8092"; OSA="http://$HOST:8093"; OPM="http://$HOST:8096"

pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s — %s\n' "$1" "$2"; fail=$((fail+1)); }
sec() { printf '\n== %s ==\n' "$1"; }

code() { # code METHOD URL [curl args…]
  local m="$1" u="$2"; shift 2
  curl -sS -o "$BODY" -w '%{http_code}' --connect-timeout 5 -m 25 -X "$m" "$@" "$u" 2>/dev/null || echo 000
}
jq_get() { python3 -c "
import json,sys
try: d=json.load(open('$BODY'))
except Exception: print('<unparseable>'); sys.exit()
cur=d
for p in '''$1'''.strip('.').split('.'):
    if not p: continue
    if p.isdigit() and isinstance(cur,list): cur=cur[int(p)] if int(p)<len(cur) else None
    elif isinstance(cur,dict): cur=cur.get(p)
    else: cur=None
    if cur is None: break
# bool must print JSON-style (true/false), not Python's True/False repr.
print('' if cur is None else (json.dumps(cur) if isinstance(cur,(dict,list,bool)) else cur))
" 2>/dev/null; }

expect_code() { # expect_code LABEL WANT METHOD URL [args…]
  local label="$1" want="$2"; shift 2
  local got; got="$(code "$@")"
  if [[ "$got" == "$want" ]]; then ok "$label ($got)"; else bad "$label" "want $want got $got: $(head -c 160 "$BODY" 2>/dev/null)"; fi
}
expect_field() { # expect_field LABEL PATH WANT
  local got; got="$(jq_get "$2")"
  if [[ "$got" == "$3" ]]; then ok "$1 ($2=$got)"; else bad "$1" "$2: want '$3' got '$got'"; fi
}
expect_nonempty() {
  local got; got="$(jq_get "$2")"
  if [[ -n "$got" ]]; then ok "$1 ($2=$got)"; else bad "$1" "$2 empty"; fi
}

mint_svc() { python3 "$MINT" "$SVC_SECRET" "${2:-opm-api}" oam-api "${3:-creds:resolve}" "${1:-}"; }
mint_user() { python3 - "$USR_SECRET" "$1" <<'PY'
import base64,hashlib,hmac,json,sys,time
def b64(r): return base64.urlsafe_b64encode(r).decode().rstrip('=')
sec,role=sys.argv[1],sys.argv[2]
now=int(time.time())
c={"username":"smoke","role":role,"iat":now,"exp":now+300,"sub":"smoke"}
si=f"{b64(json.dumps({'alg':'HS256','typ':'JWT'}).encode())}.{b64(json.dumps(c).encode())}"
print(f"{si}.{b64(hmac.new(sec.encode(),si.encode(),hashlib.sha256).digest())}")
PY
}

JSON='Content-Type: application/json'

########################################################################
sec "1. Service health"
for pair in "hub:$HUB" "oam:$OAM" "ora:$ORA" "opl:$OPL" "osa:$OSA" "opm:$OPM"; do
  name="${pair%%:*}"; url="${pair#*:}"
  got="$(code GET "$url/api/health")"
  if [[ "$got" == 200 ]]; then ok "$name healthy ($(jq_get service))"; else bad "$name health" "got $got"; fi
done
for pair in "opa-dash:8088" "ora-dash:8089" "osa-dash:8094" "opl-dash:8095" "oam-dash:8097" "opm-dash:8098"; do
  name="${pair%%:*}"; port="${pair#*:}"
  got="$(code GET "http://$HOST:$port/")"
  if [[ "$got" == 200 ]]; then ok "$name serving"; else bad "$name" "got $got"; fi
done

########################################################################
sec "1b. OAM login contract (account_type)"
expect_code "OAM admin login" 200 POST "$OAM/api/auth/login" -H "$JSON" \
  -d '{"username":"admin","password":"admin"}'
expect_field "login issuer is OAM" issuer oam-api
ACCT="$(jq_get account_type)"
if [[ -n "$ACCT" ]]; then
  expect_field "seed admin is personal account" account_type personal
else
  printf '  NOTE  OAM login missing account_type — redeploy oam-api after immutable account_type migration\n'
fi

########################################################################
sec "2. Directory seed (OAM is authoritative)"
expect_code "create org acme"   200 POST "$OAM/api/organizations/set" -H "$JSON" -d '{"id":"acme","name":"Acme Corp"}'
expect_code "create org globex" 200 POST "$OAM/api/organizations/set" -H "$JSON" -d '{"id":"globex","name":"Globex"}'
expect_code "acme/web"      200 POST "$OAM/api/projects/set" -H "$JSON" -d '{"id":"web","organization_id":"acme","name":"Web Frontend"}'
expect_code "acme/billing"  200 POST "$OAM/api/projects/set" -H "$JSON" -d '{"id":"billing","organization_id":"acme","name":"Billing API"}'
expect_code "globex/mainframe" 200 POST "$OAM/api/projects/set" -H "$JSON" -d '{"id":"mainframe","organization_id":"globex","name":"Mainframe"}'

########################################################################
sec "3. Hub fronts the OAM directory for peers"
expect_code "hub tenancy orgs" 200 GET "$HUB/api/tenancy/organizations" -H "X-Organization-ID: all"
expect_field "hub reports oam as source" directory_source oam
expect_nonempty "hub carries org name" organizations.0.name

########################################################################
sec "4. OSA tenant picker (proxy + field aliasing)"
expect_code "osa orgs" 200 GET "$OSA/api/hub/organizations" -H "X-Organization-ID: all"
expect_nonempty "org row has id"     organizations.0.id
expect_nonempty "org row has org_id" organizations.0.org_id
expect_nonempty "org row has name"   organizations.0.name

expect_code "osa projects acme" 200 GET "$OSA/api/oam/projects?organization_id=acme"
expect_nonempty "project row has project_id" projects.0.project_id
n_acme="$(python3 -c "import json;print(len(json.load(open('$BODY')).get('projects',[])))" 2>/dev/null)"
[[ "$n_acme" == 2 ]] && ok "acme scoped to its 2 projects" || bad "acme project scope" "want 2 got $n_acme"

expect_code "osa projects globex" 200 GET "$OSA/api/oam/projects?organization_id=globex"
only="$(jq_get projects.0.organization_id)"
[[ "$only" == globex ]] && ok "globex sees only its own" || bad "globex scope" "got org '$only'"
n_glob="$(python3 -c "import json;print(len(json.load(open('$BODY')).get('projects',[])))" 2>/dev/null)"
[[ "$n_glob" == 1 ]] && ok "globex scoped to its 1 project" || bad "globex count" "want 1 got $n_glob"

expect_code "osa projects all" 200 GET "$OSA/api/oam/projects?organization_id=all"
n_all="$(python3 -c "import json;print(len(json.load(open('$BODY')).get('projects',[])))" 2>/dev/null)"
[[ "${n_all:-0}" -ge 3 ]] && ok "'all' widens rather than empties ($n_all)" || bad "'all' sentinel" "want >=3 got $n_all"

expect_code "osa /api/services" 200 GET "$OSA/api/services"

########################################################################
sec "5. Resolve auth gate (service token only)"
expect_code "no token -> 401"     401 POST "$OAM/api/agents/resolve" -H "$JSON" -d '{}'
expect_code "user token -> 401"   401 POST "$OAM/api/agents/resolve" -H "$JSON" -H "Authorization: Bearer $(mint_user admin)" -d '{}'
expect_code "wrong scope -> 403"  403 POST "$OAM/api/agents/resolve" -H "$JSON" \
  -H "Authorization: Bearer $(python3 "$MINT" "$SVC_SECRET" opm-api oam-api health:read)" -d '{}'
expect_code "wrong audience -> 401" 401 POST "$OAM/api/agents/resolve" -H "$JSON" \
  -H "Authorization: Bearer $(python3 "$MINT" "$SVC_SECRET" opm-api osa-api creds:resolve)" -d '{}'
expect_code "GET -> 405" 405 GET "$OAM/api/agents/resolve" -H "Authorization: Bearer $(mint_svc)"

########################################################################
sec "6. Resolve returns model AND key together (family default floor)"
TOK="$(mint_svc)"

# Resolve returns model AND credential in one call, so with no credential stored
# it must fail closed rather than hand back a model with an empty key.
expect_code "no credential -> fails closed" 404 POST "$OAM/api/agents/resolve" -H "$JSON" \
  -H "Authorization: Bearer $TOK" \
  -d '{"organization_id":"acme","product":"opm","agent_key":"run-implementation"}'
expect_field "fail-closed error is explicit" code credential_unavailable

# cursor_api_key is the logical key for provider cli_cursor (ORA's name, kept verbatim).
expect_code "store acme org credential" 200 POST "$OAM/api/credentials/set" -H "$JSON" \
  -H "X-Organization-ID: acme" -d '{"key":"cursor_api_key","value":"crsr-acme-secret-key","scope":"org"}'

expect_code "resolve coding agent" 200 POST "$OAM/api/agents/resolve" -H "$JSON" \
  -H "Authorization: Bearer $TOK" \
  -d '{"organization_id":"acme","product":"opm","agent_key":"run-implementation"}'
expect_field "family default provider" provider cli_cursor
expect_field "family default model"    model auto
expect_nonempty "model_source stated"  model_source
expect_field "key returned with the model" api_key crsr-acme-secret-key
expect_field "key scope reported"          key_scope org
nostore="$(curl -sS -D - -o /dev/null -m 20 -X POST "$OAM/api/agents/resolve" -H "$JSON" \
  -H "Authorization: Bearer $TOK" -d '{"organization_id":"acme","product":"opm","agent_key":"run-implementation"}' 2>/dev/null \
  | tr -d '\r' | grep -ci '^cache-control: no-store')"
[[ "$nostore" == 1 ]] && ok "response is Cache-Control: no-store" || bad "no-store header" "not found"

expect_code "unknown agent_key still resolves" 200 POST "$OAM/api/agents/resolve" -H "$JSON" \
  -H "Authorization: Bearer $TOK" -d '{"organization_id":"acme","product":"opm","agent_key":"never-published-agent"}'
expect_field "flagged as catalog drift" agent_key_known false

########################################################################
sec "7. Model binding precedence (org binding, then per-task override)"
expect_code "set acme org binding" 200 POST "$OAM/api/models/bindings/set" -H "$JSON" \
  -H "X-Organization-ID: acme" \
  -d '{"product":"opm","agent_key":"run-implementation","scope":"org","provider":"cli_cursor","model":"acme-org-model"}'
expect_code "resolve after org binding" 200 POST "$OAM/api/agents/resolve" -H "$JSON" \
  -H "Authorization: Bearer $TOK" -d '{"organization_id":"acme","product":"opm","agent_key":"run-implementation"}'
expect_field "org binding wins over family default" model acme-org-model

expect_code "resolve with per-task override" 200 POST "$OAM/api/agents/resolve" -H "$JSON" \
  -H "Authorization: Bearer $TOK" \
  -d '{"organization_id":"acme","product":"opm","agent_key":"run-implementation","override":{"provider":"cli_cursor","model":"task-override-model"}}'
expect_field "override beats org binding" model task-override-model

########################################################################
sec "8. Resolve is org-scoped"
# globex has no credential of its own. If org scoping leaked, it would resolve
# acme's key instead of failing — so a 404 here is the isolation assertion.
expect_code "globex has no key -> fails closed" 404 POST "$OAM/api/agents/resolve" -H "$JSON" \
  -H "Authorization: Bearer $TOK" -d '{"organization_id":"globex","product":"opm","agent_key":"run-implementation"}'
if grep -q "crsr-acme-secret-key" "$BODY" 2>/dev/null; then bad "org isolation" "acme key appeared in globex response"; else ok "acme credential absent from globex resolve"; fi

PINNED="$(mint_svc acme)"
expect_code "org-pinned token, body says globex" 200 POST "$OAM/api/agents/resolve" -H "$JSON" \
  -H "Authorization: Bearer $PINNED" -d '{"organization_id":"globex","product":"opm","agent_key":"run-implementation"}'
expect_field "token org overrides body org (model)"   model acme-org-model
expect_field "token org overrides body org (key)"     api_key crsr-acme-secret-key

########################################################################
sec "9. Credentials are write-only and per-org"
expect_code "credential list" 200 GET "$OAM/api/credentials" -H "X-Organization-ID: acme"
if grep -q "crsr-acme-secret-key" "$BODY" 2>/dev/null; then bad "credential list leaks plaintext" "value present"; else ok "credential list withholds values"; fi

expect_code "store globex org credential" 200 POST "$OAM/api/credentials/set" -H "$JSON" \
  -H "X-Organization-ID: globex" -d '{"key":"cursor_api_key","value":"crsr-globex-secret-key","scope":"org"}'
expect_code "globex now resolves" 200 POST "$OAM/api/agents/resolve" -H "$JSON" \
  -H "Authorization: Bearer $TOK" -d '{"organization_id":"globex","product":"opm","agent_key":"run-implementation"}'
expect_field "globex gets its own key" api_key crsr-globex-secret-key
expect_field "globex keeps the family default model" model auto

expect_code "acme unchanged by globex write" 200 POST "$OAM/api/agents/resolve" -H "$JSON" \
  -H "Authorization: Bearer $TOK" -d '{"organization_id":"acme","product":"opm","agent_key":"run-implementation"}'
expect_field "acme still its own key" api_key crsr-acme-secret-key

########################################################################
sec "10. AI runtime present in job images"
for img in ora-api:smoke opm-api:smoke; do
  if docker image inspect "$img" >/dev/null 2>&1; then
    if docker run --rm --entrypoint sh "$img" -c 'command -v cursor-agent || command -v agent' >/dev/null 2>&1; then
      ok "$img carries the Cursor Agent CLI"
    else
      printf '  NOTE  %s has no cursor-agent on PATH (family default cli_cursor would need it at job time)\n' "$img"
    fi
  else
    bad "$img" "image missing"
  fi
done

########################################################################
printf '\n===== %d passed, %d failed =====\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
