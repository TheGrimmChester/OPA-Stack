# Distribution

| Channel | Status | Notes |
|---------|--------|-------|
| Docker / GHCR | primary | `ghcr.io/.../opa-agent`, dashboard images via CI |
| Helm chart | alpha | `OPA-stack/helm/opa` — publish as a Helm repo when ready |
| npm (`opa` / rum) | SDK | Provenance via npm trusted publishing (CI) |
| PyPI | SDK | Trusted publishing |
| PECL | PHP | Documented native build path independent of Docker |
| deb/rpm | planned | Package the agent binary + unit file |

## Native PHP extension (non-Docker)

Build against your PHP headers (`phpize && ./configure && make`). See `OPA-PHP-extension` README. The container entrypoint is **not** required for production installs.

## Helm repo (future)

```bash
helm repo add opa https://example.invalid/opa-helm   # replace when published
helm install opa opa/opa
```

Until then, install from the git tree: `helm upgrade --install opa ./helm/opa`.
