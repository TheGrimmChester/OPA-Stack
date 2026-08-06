# Family-root build for opa-hub:nas
#   docker build -f OPA-Stack/harness/docker/opa-hub.nas.Dockerfile -t opa-hub:nas .
# Context: ~/Documents/repos (sibling Open-* + OPA-Hub checkouts)
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY Open-Auth-Go /modules/Open-Auth-Go
COPY Open-ClickHouse-Go /modules/Open-ClickHouse-Go
COPY Open-HTTP-Go /modules/Open-HTTP-Go
COPY Open-Logger-Go /modules/Open-Logger-Go
COPY Open-Cache-Go /modules/Open-Cache-Go
COPY Open-Crypto-Go /modules/Open-Crypto-Go
COPY Open-Tenant-Go /modules/Open-Tenant-Go
COPY OPA-Hub/ /src/OPA-Hub/
WORKDIR /src/OPA-Hub
RUN sed -i \
  -e 's|=> ../Open-Auth-Go|=> /modules/Open-Auth-Go|' \
  -e 's|=> ../Open-ClickHouse-Go|=> /modules/Open-ClickHouse-Go|' \
  -e 's|=> ../Open-HTTP-Go|=> /modules/Open-HTTP-Go|' \
  -e 's|=> ../Open-Logger-Go|=> /modules/Open-Logger-Go|' \
  -e 's|=> ../Open-Tenant-Go|=> /modules/Open-Tenant-Go|' \
  go.mod \
  && go mod edit \
      -replace github.com/TheGrimmChester/open-cache-go=/modules/Open-Cache-Go \
      -replace github.com/TheGrimmChester/open-crypto-go=/modules/Open-Crypto-Go \
  && CGO_ENABLED=0 go build -o /out/opa-hub .

FROM alpine:3.20
RUN apk --no-cache add ca-certificates wget \
 && adduser -D -H -u 10001 app
USER app
COPY --from=build /out/opa-hub /usr/local/bin/opa-hub
EXPOSE 8080
ENTRYPOINT ["opa-hub"]
