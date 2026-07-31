# Security scan workspace (Wave 33)

Intentional fixture files for Agent scanners (`OPA_SECURITY_WORKSPACE=/workspace`).

Contains fake credentials (lite regex + gitleaks-detectable tokens), eval/innerHTML JS,
unpinned Dockerfile, and a Terraform stub so `POST /api/security/runs` smoke produces
findings. Not production code.

Secrets path: Agent prefers `gitleaks detect` when the binary is in the image/PATH
(`OPA_GITLEAKS_BIN` override); otherwise embedded lite regex.
