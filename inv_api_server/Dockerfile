FROM golang:1.25-alpine AS builder
ENV GOPROXY=https://goproxy.cn,direct
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o inv-api-server ./cmd/main.go

FROM golang:1.25-alpine
WORKDIR /app
COPY --from=builder /app/inv-api-server ./main
COPY config.docker.yaml ./config.yaml

ENV TZ=UTC

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD wget -q -O /dev/null http://localhost:8080/health || exit 1

CMD ["./main", "-config", "config.yaml"]
