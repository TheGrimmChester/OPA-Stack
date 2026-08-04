# Family-root build for ora-api:nas (default stage = ora-api; use --target for runners)
#   docker build -f OPA-Stack/harness/docker/ora-api.nas.Dockerfile -t ora-api:nas --target ora-api .
FROM golang:1.25-alpine AS builder
RUN apk --no-cache add git ca-certificates
WORKDIR /src
ENV GOPROXY=https://proxy.golang.org,direct
ENV GOSUMDB=sum.golang.org
COPY Open-Auth-Go /modules/Open-Auth-Go
COPY Open-Client-Go /modules/Open-Client-Go
COPY Open-Job-Go /modules/Open-Job-Go
COPY Open-Tenant-Go /modules/Open-Tenant-Go
COPY Open-ClickHouse-Go /modules/Open-ClickHouse-Go
COPY Open-HTTP-Go /modules/Open-HTTP-Go
COPY Open-Logger-Go /modules/Open-Logger-Go
COPY ORA-API/ /src/ORA-API/
WORKDIR /src/ORA-API
RUN sed -i \
  -e 's|=> ../Open-Auth-Go|=> /modules/Open-Auth-Go|' \
  -e 's|=> ../Open-Client-Go|=> /modules/Open-Client-Go|' \
  -e 's|=> ../Open-Job-Go|=> /modules/Open-Job-Go|' \
  -e 's|=> ../Open-Tenant-Go|=> /modules/Open-Tenant-Go|' \
  -e 's|=> ../Open-ClickHouse-Go|=> /modules/Open-ClickHouse-Go|' \
  -e 's|=> ../Open-HTTP-Go|=> /modules/Open-HTTP-Go|' \
  -e 's|=> ../Open-Logger-Go|=> /modules/Open-Logger-Go|' \
  go.mod \
  && go mod download \
  && CGO_ENABLED=0 GOOS=linux go build -o /out/ora-api .

FROM debian:bookworm-slim AS ora-api
ARG TARGETARCH
ARG GITLEAKS_VERSION=8.30.0
ARG PLAYWRIGHT_VERSION=1.50.1
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git bash \
      docker.io \
      nodejs npm \
      libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
      libdbus-1-3 libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 \
      libxrandr2 libgbm1 libasound2 libpango-1.0-0 libcairo2 libatspi2.0-0 \
      libx11-6 libx11-xcb1 libxcb1 libxext6 libglib2.0-0 libgtk-3-0 \
      libxcb-shm0 libxshmfence1 libegl1 libxcursor1 libxi6 libxtst6 \
      fonts-liberation fonts-noto-color-emoji \
 && rm -rf /var/lib/apt/lists/* \
 && arch="$TARGETARCH" \
 && case "$arch" in amd64|x86_64) gl_arch=x64 ;; arm64|aarch64) gl_arch=arm64 ;; *) gl_arch=x64 ;; esac \
 && wget -qO /tmp/gitleaks.tgz \
      "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${gl_arch}.tar.gz" \
 && tar -xzf /tmp/gitleaks.tgz -C /usr/local/bin gitleaks \
 && rm -f /tmp/gitleaks.tgz \
 && (NO_COLOR=1 curl -fsS https://cursor.com/install | bash \
      && test -x /root/.local/bin/agent \
      && ln -sf /root/.local/bin/agent /usr/local/bin/agent \
      && ln -sf /root/.local/bin/cursor-agent /usr/local/bin/cursor-agent) \
    || echo "WARN: Cursor Agent CLI install skipped" \
 && npx --yes "playwright@${PLAYWRIGHT_VERSION}" install-deps chromium \
 && npx --yes "playwright@${PLAYWRIGHT_VERSION}" install chromium \
 && rm -rf /root/.npm /tmp/*
WORKDIR /root/
COPY --from=builder /out/ora-api /usr/local/bin/ora-api
COPY ORA-API/gitleaks.toml /etc/opa/gitleaks.toml
COPY ORA-API/scripts/ /opt/opa/scripts/
ENV HTTP_ADDR=:8091 \
    OPA_REVIEW_BROWSER_MCP=1 \
    OPA_REVIEW_BROWSER_DEPS_OK=1 \
    PLAYWRIGHT_BROWSERS_PATH=/root/.cache/ms-playwright \
    OPA_JOB_SANDBOX=off
EXPOSE 8091
CMD ["ora-api"]

FROM debian:bookworm-slim AS ora-runner-git
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates git \
 && rm -rf /var/lib/apt/lists/*
USER 65532:65532
WORKDIR /home/opa
CMD ["sleep", "infinity"]
