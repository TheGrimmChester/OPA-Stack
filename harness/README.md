# OPA-stack harness

Local smoke helpers and fixtures for the compose stack (`docker-compose.yaml`).

## Security features enabled for smoke

Compose turns on practical AppSec knobs so Dashboard Security / OSV / IAST / scanners work without manual env edits:

| Where | Enabled |
|-------|---------|
| **agent** | `OPA_OSV=1` (`POST /api/security/osv/enrich`), `OPA_SECURITY_MIN_SEVERITY=high`, `OPA_SECURITY_FAIL_OBSERVED=1`. Ingest token / OIDC gate left unset (open local ingest). |
| **orchestrator** | `OPA_SECURITY_WORKSPACE=/workspace` (fixture mount), gitleaks via image + `OPA_GITLEAKS_CONFIG`, `SKIP_CURSOR_AI=0`, `CURSOR_API_KEY` passed from host when set. |
| **php-cli** | `OPA_IAST=1` / `opa.iast=1` + `OPA_IAST_BLOCK=1` / `opa.iast_block=1` (local smoke only — do not copy block to prod). |
| **node-app** | `OPA_IAST=1` (parity; opa-node IAST is API/`installHooks`-driven). |

Rebuild Agent from a current tip via `./harness/rebuild-smoke-images.sh` so OSV / AppSec code is in `opa-agent:smoke`.

Optional after recreate — seed SBOM then enrich:

```bash
curl -fsS -X POST http://127.0.0.1:8080/v1/sbom \
  -H 'Content-Type: application/json' \
  --data-binary @harness/fixtures/sbom.smoke.json
curl -fsS -X POST http://127.0.0.1:8080/api/security/osv/enrich \
  -H 'Content-Type: application/json' -d '{}'
```

See also `fixtures/security-workspace/README.md` and `iast-block-smoke.php`.
