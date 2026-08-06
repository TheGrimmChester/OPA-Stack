# Family-root build for opm-api:nas
#   docker build -f OPA-Stack/harness/docker/opm-api.nas.Dockerfile -t opm-api:nas --target opm-api .
# Default final stage is opm-api (not the runner) so bare `docker build -t opm-api:nas` is safe.
FROM golang:1.22-alpine AS builder
RUN apk --no-cache add git ca-certificates
WORKDIR /src
ENV GOPROXY=https://proxy.golang.org,direct
ENV GOSUMDB=sum.golang.org
COPY Open-Auth-Go /modules/Open-Auth-Go
COPY Open-Client-Go /modules/Open-Client-Go
COPY Open-Job-Go /modules/Open-Job-Go
COPY Open-Tenant-Go /modules/Open-Tenant-Go
COPY Open-HTTP-Go /modules/Open-HTTP-Go
COPY Open-Logger-Go /modules/Open-Logger-Go
COPY Open-Cache-Go /modules/Open-Cache-Go
COPY Open-Crypto-Go /modules/Open-Crypto-Go
COPY Open-Job-Env-Go /modules/Open-Job-Env-Go
COPY OPM-API/ /src/OPM-API/
WORKDIR /src/OPM-API
RUN sed -i \
  -e 's|=> ../Open-Auth-Go|=> /modules/Open-Auth-Go|' \
  -e 's|=> ../Open-Client-Go|=> /modules/Open-Client-Go|' \
  -e 's|=> ../Open-Job-Go|=> /modules/Open-Job-Go|' \
  -e 's|=> ../Open-Tenant-Go|=> /modules/Open-Tenant-Go|' \
  -e 's|=> ../Open-HTTP-Go|=> /modules/Open-HTTP-Go|' \
  -e 's|=> ../Open-Logger-Go|=> /modules/Open-Logger-Go|' \
  go.mod \
  && go mod edit \
      -replace github.com/TheGrimmChester/open-cache-go=/modules/Open-Cache-Go \
      -replace github.com/TheGrimmChester/open-crypto-go=/modules/Open-Crypto-Go \
      -replace github.com/TheGrimmChester/open-job-env-go=/modules/Open-Job-Env-Go \
  && go mod download \
  && CGO_ENABLED=0 GOOS=linux go build -o /out/opm-api . \
  && CGO_ENABLED=0 GOOS=linux go build -o /out/opm-runner ./cmd/opm-runner

FROM debian:bookworm-slim AS opm-runner-task
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl bash \
 && rm -rf /var/lib/apt/lists/* \
 && (NO_COLOR=1 curl -fsS https://cursor.com/install | bash \
      && test -x /root/.local/bin/agent \
      && REAL="$(readlink -f /root/.local/bin/agent)" \
      && REL="${REAL#/root/.local/share/cursor-agent/}" \
      && mkdir -p /opt/cursor-agent \
      && cp -a /root/.local/share/cursor-agent/. /opt/cursor-agent/ \
      && test -x "/opt/cursor-agent/$REL" \
      && ln -sfn "/opt/cursor-agent/$REL" /usr/local/bin/agent \
      && ln -sfn "/opt/cursor-agent/$REL" /usr/local/bin/cursor-agent \
      && chmod -R a+rX /opt/cursor-agent \
      && find /opt/cursor-agent -type f \( -name 'cursor-agent' -o -name 'node' -o -name '*.so*' \) -exec chmod a+x {} +) \
    || echo "WARN: Cursor Agent CLI install skipped" \
 && (export QWEN_INSTALL_VERSION=0.21.6 \
     QWEN_INSTALL_ROOT=/opt/qwen \
     QWEN_INSTALL_LIB_PARENT=/opt/qwen/lib \
     QWEN_INSTALL_BIN_DIR=/usr/local/bin \
     QWEN_NO_MODIFY_PATH=1 \
     QWEN_INSTALL_METHOD=standalone \
     NO_COLOR=1 \
     && curl -fsS \
       https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen-standalone.sh \
     | bash -s -- --method standalone --no-modify-path \
     && test -x /usr/local/bin/qwen \
     && chmod -R a+rX /opt/qwen) \
    || echo "WARN: Qwen Code CLI install skipped" \
 && mkdir -p /home/opm \
 && chown -R 65532:65532 /home/opm \
 && rm -rf /root/.npm /root/.local /tmp/*
COPY --from=builder /out/opm-runner /usr/local/bin/opm-runner
ENV HOME=/home/opm \
    OPM_MODEL=auto \
    PATH="/usr/local/bin:/usr/bin:/bin"
USER 65532:65532
WORKDIR /home/opm
ENTRYPOINT ["/usr/local/bin/opm-runner"]

FROM docker:27-cli AS dockercli

FROM debian:bookworm-slim AS opm-api
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates git wget \
 && rm -rf /var/lib/apt/lists/*
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
WORKDIR /root/
COPY --from=builder /out/opm-api /usr/local/bin/opm-api
ENV LISTEN_ADDR=:8096 \
    OPM_RUNNER_TAG=nas
EXPOSE 8096
CMD ["opm-api"]
