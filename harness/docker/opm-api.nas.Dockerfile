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
COPY OPM-API/ /src/OPM-API/
WORKDIR /src/OPM-API
RUN sed -i \
  -e 's|=> ../Open-Auth-Go|=> /modules/Open-Auth-Go|' \
  -e 's|=> ../Open-Client-Go|=> /modules/Open-Client-Go|' \
  -e 's|=> ../Open-Job-Go|=> /modules/Open-Job-Go|' \
  go.mod \
  && go mod download \
  && CGO_ENABLED=0 GOOS=linux go build -o /out/opm-api .

FROM debian:bookworm-slim AS opm-runner-task
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
USER 65532:65532
WORKDIR /home/opm
CMD ["sleep", "infinity"]

FROM debian:bookworm-slim AS opm-api
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /root/
COPY --from=builder /out/opm-api /usr/local/bin/opm-api
ENV LISTEN_ADDR=:8096 \
    OPM_RUNNER_TAG=nas
EXPOSE 8096
CMD ["opm-api"]
