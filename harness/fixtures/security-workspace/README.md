# Security scan workspace (Security runs)

Intentional fixture files for Orchestrator scanners (`OPA_SECURITY_WORKSPACE=/workspace`).

Contains fake credentials (lite regex + gitleaks-detectable tokens), eval/innerHTML JS,
unpinned Dockerfile, and a Terraform stub so `POST /api/security/runs` smoke produces
findings. Not production code.

Mounted read-write in compose on `opa_orchestrator`. Secrets path: gitleaks when the
binary is in the image/PATH (`OPA_GITLEAKS_BIN` override); otherwise embedded lite regex.

Smoke AppSec flags (OSV / IAST / gitleaks / SKIP_CURSOR_AI) are documented in
`harness/README.md`.
