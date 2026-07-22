FROM golang:1.26.5-alpine AS builder
ARG GOPROXY=https://goproxy.cn,https://goproxy.io,direct
ENV GOPROXY=${GOPROXY}
WORKDIR /app
COPY business-api/go.mod business-api/go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY business-api/ .
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 GOOS=linux go build -p=1 -ldflags="-s -w" -o inv-api-server ./cmd

FROM alpine:3.23
ARG ALPINE_MIRROR=dl-cdn.alpinelinux.org
RUN sed -i "s/dl-cdn.alpinelinux.org/${ALPINE_MIRROR}/g" /etc/apk/repositories && \
    apk --no-cache add ca-certificates tzdata wget
WORKDIR /app
COPY --from=builder /app/inv-api-server ./main
COPY business-api/config.docker.yaml ./config.yaml
COPY database ./database
RUN addgroup -S app && adduser -S -G app app && \
    mkdir -p /data/firmware /app/logs && \
    chown -R app:app /data/firmware /app/logs

ENV TZ=UTC

USER app

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD wget -q -O /dev/null http://localhost:8080/health || exit 1

CMD ["./main", "-config", "config.yaml"]
