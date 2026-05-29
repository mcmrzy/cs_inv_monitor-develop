FROM golang:1.21-alpine AS builder
ENV GOPROXY=https://goproxy.cn,direct
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o inv-device-server ./cmd/main.go

FROM alpine:3.19
RUN apk --no-cache add ca-certificates tzdata wget
WORKDIR /app
COPY --from=builder /app/inv-device-server ./main
COPY config.docker.yaml ./config.yaml
COPY web/ ./web/
RUN mkdir -p /app/logs

ENV TZ=Asia/Shanghai

EXPOSE 8081

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD wget -q --spider http://localhost:8081/health || exit 1

CMD ["./main", "-config", "config.yaml"]
