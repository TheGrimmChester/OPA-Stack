# OPA-stack harness

Local smoke helpers and fixtures for the compose stack (`docker-compose.yaml`).

## Security features enabled for smoke

AppSec control plane is **OSA** (`osa-api` `:8093`). Smoke routing in `lib/smoke-common.sh`
sends `/api/security/*`, `/api/vulns/*`, `/api/iast/*` there. Perf Lab is **OPL** (`:8092`).
ORA (`:8091`) owns SCM/connectors/AI review protocol.

| Where | Enabled |
|-------|---------|
| **osa-api** | Security runs, findings, vulns/IAST, AppSec gate (`OSA_HTTP` / `:8093`) |
| **ora-api** | SCM connectors, review, optional gate wait on OSA; gitleaks workspace when used for review-local scans |
| **opl-api** | Perf scenarios/runs/JMeter (`PERF_LAB_HTTP` / `:8092`) |
| **php-cli** | `OPA_IAST=1` / `opa.iast=1` + `OPA_IAST_BLOCK=1` / `opa.iast_block=1` (local smoke only — do not copy block to prod). |
| **node-app** | `OPA_IAST=1` (parity; opa-node IAST is API/`installHooks`-driven). |

Optional after recreate — seed SBOM then enrich against **OSA**:

```bash
curl -fsS -X POST http://127.0.0.1:8093/v1/sbom \
  -H 'Content-Type: application/json' \
  --data-binary @harness/fixtures/sbom.smoke.json
curl -fsS -X POST http://127.0.0.1:8093/api/security/osv/enrich \
  -H 'Content-Type: application/json' -d '{}'
```

See also `fixtures/security-workspace/README.md` and `iast-block-smoke.php`.

## AI resolve + tenant scoping smoke

Covers the account plane: service health across all six APIs and six dashboards,
the OAM → hub → peer org/project directory, and `POST /api/agents/resolve` —
which had no smoke coverage at all.

```bash
docker compose -f compose.all.yaml up -d
HOST=127.0.0.1 ./harness/ai-resolve-smoke.sh
```

Asserts the parts of the resolve contract that are easy to regress silently:
model and credential returned together (never two calls that can disagree),
service-JWT-only auth (a user token must be rejected), fail-closed when no
credential is stored, `override > org binding > family default` precedence, and
that neither a key nor a model leaks between organizations.

Expects a freshly created stack — one case asserts resolve fails closed *before*
any credential exists, so `docker compose down -v && up -d` between runs.
Service JWTs are minted by `lib/mint_service_jwt.py` from
`OPEN_SERVICE_JWT_SECRET` (defaults match compose).
