# Family-root build for oam-api:nas
#   docker build -f OPA-Stack/harness/docker/oam-api.nas.Dockerfile -t oam-api:nas --target oam-api .
FROM golang:1.22-alpine AS builder
RUN apk --no-cache add git ca-certificates
WORKDIR /src
ENV GOPROXY=https://proxy.golang.org,direct
ENV GOSUMDB=sum.golang.org
COPY Open-Auth-Go /modules/Open-Auth-Go
COPY Open-Tenant-Go /modules/Open-Tenant-Go
COPY Open-ClickHouse-Go /modules/Open-ClickHouse-Go
COPY Open-HTTP-Go /modules/Open-HTTP-Go
COPY Open-Logger-Go /modules/Open-Logger-Go
COPY Open-Cache-Go /modules/Open-Cache-Go
COPY Open-Crypto-Go /modules/Open-Crypto-Go
COPY OAM-API/ /src/OAM-API/
WORKDIR /src/OAM-API
# OAM-API's committed go.mod resolves from the module proxy (so a single-repo CI
# checkout builds). The NAS image instead builds against the sibling checkouts in
# this repo tree, so a local change to a shared module is picked up. `go mod edit`
# rather than the sed-rewrite the older Dockerfiles use, because there are no
# filesystem replaces in the committed file to rewrite.
RUN go mod edit \
      -replace github.com/TheGrimmChester/open-auth-go=/modules/Open-Auth-Go \
      -replace github.com/TheGrimmChester/open-tenant-go=/modules/Open-Tenant-Go \
      -replace github.com/TheGrimmChester/open-clickhouse-go=/modules/Open-ClickHouse-Go \
      -replace github.com/TheGrimmChester/open-http-go=/modules/Open-HTTP-Go \
      -replace github.com/TheGrimmChester/open-logger-go=/modules/Open-Logger-Go \
      -replace github.com/TheGrimmChester/open-cache-go=/modules/Open-Cache-Go \
      -replace github.com/TheGrimmChester/open-crypto-go=/modules/Open-Crypto-Go \
 && go mod tidy \
 && CGO_ENABLED=0 GOOS=linux go build -o /out/oam-api .

FROM alpine:3.20 AS oam-api
# wget (busybox) is present in alpine and is what the compose healthcheck uses.
RUN apk --no-cache add ca-certificates
# This service holds every org's credentials. It runs unprivileged and carries no
# job sandbox or shell tooling: there is nothing here to exec.
RUN adduser -D -u 65532 oam
WORKDIR /home/oam
COPY --from=builder /out/oam-api /usr/local/bin/oam-api
USER 65532:65532
ENV LISTEN_ADDR=:8090
EXPOSE 8090
CMD ["/usr/local/bin/oam-api"]
