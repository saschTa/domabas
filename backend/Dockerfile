FROM golang:1.27.1-trixie@sha256:9baa6b4187bbb98d240372a8a235ac0bb6b5ddd52bba1431dc2f7c0705862728 AS build
WORKDIR /src
COPY backend/go.mod backend/go.sum ./
RUN go mod download
COPY backend/ ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server && \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/workflow ./cmd/workflow && \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/adopt-legacy ./cmd/adopt-legacy && \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/bootstrap-admin ./cmd/bootstrap-admin

FROM debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /data/ingestion /data/documents && chmod 0700 /data/ingestion /data/documents && chown -R 65532:65532 /data
RUN mkdir -p /var/lib/domabas/secrets && chmod 0700 /var/lib/domabas/secrets && chown 65532:65532 /var/lib/domabas/secrets
WORKDIR /app
COPY --from=build /out/ /app/
COPY LICENSE /usr/share/doc/domabas/LICENSE
COPY third_party/ /usr/share/doc/domabas/third-party/
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/app/server"]
