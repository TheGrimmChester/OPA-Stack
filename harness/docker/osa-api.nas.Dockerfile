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
COPY OSA-API/ /src/OSA-API/
WORKDIR /src/OSA-API
RUN sed -i \
  -e 's|=> ../Open-Auth-Go|=> /modules/Open-Auth-Go|' \
  -e 's|=> ../Open-Client-Go|=> /modules/Open-Client-Go|' \
  -e 's|=> ../Open-Job-Go|=> /modules/Open-Job-Go|' \
  go.mod \
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
