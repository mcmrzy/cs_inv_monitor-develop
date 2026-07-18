FROM golang:1.26.5-alpine AS builder
ARG GOPROXY=https://proxy.golang.org,direct
ENV GOPROXY=${GOPROXY}
WORKDIR /app
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY *.go ./
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o mqtt-kafka-bridge .

FROM alpine:3.23
ARG ALPINE_MIRROR=dl-cdn.alpinelinux.org
RUN sed -i "s/dl-cdn.alpinelinux.org/${ALPINE_MIRROR}/g" /etc/apk/repositories && \
    apk --no-cache add ca-certificates tzdata
WORKDIR /app
COPY --from=builder /app/mqtt-kafka-bridge .
COPY config.docker.yaml ./config.yaml
RUN addgroup -S app && adduser -S -G app app && chown -R app:app /app
USER app
EXPOSE 18088
CMD ["./mqtt-kafka-bridge"]
