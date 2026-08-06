# Family-root build for osa-api:nas
#   docker build -f OPA-Stack/harness/docker/osa-api.nas.Dockerfile -t osa-api:nas --target osa-api .
FROM golang:1.22-alpine AS builder
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
COPY Open-Cache-Go /modules/Open-Cache-Go
COPY Open-Crypto-Go /modules/Open-Crypto-Go
COPY Open-Job-Env-Go /modules/Open-Job-Env-Go
COPY OSA-API/ /src/OSA-API/
WORKDIR /src/OSA-API
RUN sed -i \
  -e 's|=> ../Open-Auth-Go|=> /modules/Open-Auth-Go|' \
  -e 's|=> ../Open-Client-Go|=> /modules/Open-Client-Go|' \
  -e 's|=> ../Open-Job-Go|=> /modules/Open-Job-Go|' \
  -e 's|=> ../Open-Tenant-Go|=> /modules/Open-Tenant-Go|' \
  -e 's|=> ../Open-ClickHouse-Go|=> /modules/Open-ClickHouse-Go|' \
  -e 's|=> ../Open-HTTP-Go|=> /modules/Open-HTTP-Go|' \
  -e 's|=> ../Open-Logger-Go|=> /modules/Open-Logger-Go|' \
  go.mod \
  && go mod edit \
      -replace github.com/TheGrimmChester/open-cache-go=/modules/Open-Cache-Go \
      -replace github.com/TheGrimmChester/open-crypto-go=/modules/Open-Crypto-Go \
      -replace github.com/TheGrimmChester/open-job-env-go=/modules/Open-Job-Env-Go \
  && go mod download \
  && CGO_ENABLED=0 GOOS=linux go build -o /out/osa-api .

FROM debian:bookworm-slim AS osa-api
ARG TARGETARCH
ARG GITLEAKS_VERSION=8.30.0
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget \
 && rm -rf /var/lib/apt/lists/* \
 && arch="$TARGETARCH" \
 && case "$arch" in amd64|x86_64) gl_arch=x64 ;; arm64|aarch64) gl_arch=arm64 ;; *) gl_arch=x64 ;; esac \
 && wget -qO /tmp/gitleaks.tgz \
      "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${gl_arch}.tar.gz" \
 && tar -xzf /tmp/gitleaks.tgz -C /usr/local/bin gitleaks \
 && rm -f /tmp/gitleaks.tgz
WORKDIR /root/
COPY --from=builder /out/osa-api /usr/local/bin/osa-api
COPY OSA-API/gitleaks.toml /etc/opa/gitleaks.toml
COPY OSA-API/scripts/ /opt/osa/scripts/
ENV LISTEN_ADDR=:8093 \
    OPA_JOB_SANDBOX=off \
    OSA_RUNNER_TAG=nas
EXPOSE 8093
CMD ["osa-api"]

FROM debian:bookworm-slim AS osa-runner-scan
ARG TARGETARCH
ARG GITLEAKS_VERSION=8.30.0
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget \
 && rm -rf /var/lib/apt/lists/* \
 && arch="$TARGETARCH" \
 && case "$arch" in amd64|x86_64) gl_arch=x64 ;; arm64|aarch64) gl_arch=arm64 ;; *) gl_arch=x64 ;; esac \
 && wget -qO /tmp/gitleaks.tgz \
      "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${gl_arch}.tar.gz" \
 && tar -xzf /tmp/gitleaks.tgz -C /usr/local/bin gitleaks \
 && rm -f /tmp/gitleaks.tgz
COPY OSA-API/gitleaks.toml /etc/opa/gitleaks.toml
USER 65532:65532
WORKDIR /home/opa
CMD ["sleep", "infinity"]
