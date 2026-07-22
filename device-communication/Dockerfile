FROM golang:1.26.5-alpine AS builder
ARG GOPROXY=https://goproxy.cn,https://goproxy.io,direct
ENV GOPROXY=${GOPROXY}
WORKDIR /app
COPY go.mod ./
COPY go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 GOOS=linux go build -p=1 -ldflags="-s -w" -o inv-device-server ./cmd

FROM alpine:3.23
ARG ALPINE_MIRROR=dl-cdn.alpinelinux.org
RUN sed -i "s/dl-cdn.alpinelinux.org/${ALPINE_MIRROR}/g" /etc/apk/repositories && \
    apk --no-cache add ca-certificates tzdata wget
WORKDIR /app
COPY --from=builder /app/inv-device-server ./main
COPY config.docker.yaml ./config.yaml
RUN addgroup -S app && adduser -S -G app app && \
    mkdir -p /app/logs && chown -R app:app /app/logs

ENV TZ=UTC

USER app

EXPOSE 8081

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null http://localhost:8081/health || exit 1

CMD ["./main", "-config", "config.yaml"]
