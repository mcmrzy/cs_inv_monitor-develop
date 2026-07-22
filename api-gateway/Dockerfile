FROM golang:1.26.5-alpine AS builder

ARG GOPROXY=https://goproxy.cn,https://goproxy.io,direct
ENV GOPROXY=${GOPROXY}
ENV GO111MODULE=on

ARG ALPINE_MIRROR=dl-cdn.alpinelinux.org
RUN sed -i "s/dl-cdn.alpinelinux.org/${ALPINE_MIRROR}/g" /etc/apk/repositories && \
    apk add --no-cache git ca-certificates tzdata

WORKDIR /build

COPY go.mod go.sum* ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY . .

RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -p=1 \
    -ldflags="-s -w" \
    -o /build/api-gateway \
    ./main.go

FROM alpine:3.23

ARG ALPINE_MIRROR=dl-cdn.alpinelinux.org
RUN sed -i "s/dl-cdn.alpinelinux.org/${ALPINE_MIRROR}/g" /etc/apk/repositories && \
    apk --no-cache add ca-certificates tzdata wget

ENV TZ=UTC

RUN adduser -D -g '' appuser

WORKDIR /app

COPY --from=builder /build/api-gateway .
COPY config.docker.yaml ./config.yaml

USER appuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://localhost:8080/health || exit 1

CMD ["./api-gateway", "-config", "config.yaml"]
