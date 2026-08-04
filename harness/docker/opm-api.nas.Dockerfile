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
  && go mod download \
  && CGO_ENABLED=0 GOOS=linux go build -o /out/opm-api .

FROM debian:bookworm-slim AS opm-runner-task
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY OPM-API/scripts/opm-runner-entrypoint.sh /usr/local/bin/opm-runner
RUN chmod 755 /usr/local/bin/opm-runner
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
