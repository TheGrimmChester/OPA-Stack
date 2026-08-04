# Family-root build for opl-api:nas
#   docker build -f OPA-Stack/harness/docker/opl-api.nas.Dockerfile -t opl-api:nas --target opl-api .
FROM golang:1.25-alpine AS builder
RUN apk --no-cache add git ca-certificates
WORKDIR /src
ENV GOPROXY=https://proxy.golang.org,direct
ENV GOSUMDB=sum.golang.org
COPY Open-Auth-Go /modules/Open-Auth-Go
COPY Open-Job-Go /modules/Open-Job-Go
COPY Open-Tenant-Go /modules/Open-Tenant-Go
COPY Open-ClickHouse-Go /modules/Open-ClickHouse-Go
COPY Open-HTTP-Go /modules/Open-HTTP-Go
COPY Open-Logger-Go /modules/Open-Logger-Go
COPY OPL-API/ /src/OPL-API/
WORKDIR /src/OPL-API
RUN sed -i \
  -e 's|=> ../Open-Auth-Go|=> /modules/Open-Auth-Go|' \
  -e 's|=> ../Open-Job-Go|=> /modules/Open-Job-Go|' \
  -e 's|=> ../Open-Tenant-Go|=> /modules/Open-Tenant-Go|' \
  -e 's|=> ../Open-ClickHouse-Go|=> /modules/Open-ClickHouse-Go|' \
  -e 's|=> ../Open-HTTP-Go|=> /modules/Open-HTTP-Go|' \
  -e 's|=> ../Open-Logger-Go|=> /modules/Open-Logger-Go|' \
  go.mod \
  && go mod download \
  && CGO_ENABLED=0 GOOS=linux go build -o /out/opl-api .

FROM docker:27-cli AS dockercli

FROM debian:bookworm-slim AS opl-api
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl wget bash \
 && rm -rf /var/lib/apt/lists/*
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
WORKDIR /root/
COPY --from=builder /out/opl-api /usr/local/bin/opl-api
COPY OPL-API/scripts/ /opt/opa/scripts/
RUN mkdir -p /opa-jmeter
ENV HTTP_ADDR=:8092
EXPOSE 8092
CMD ["opl-api"]

FROM eclipse-temurin:17-jre-jammy AS opl-runner-jmeter
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /opt/jmeter /home/opa \
 && chown -R 65532:65532 /home/opa
USER 65532:65532
WORKDIR /home/opa
CMD ["sleep", "infinity"]
