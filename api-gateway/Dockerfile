FROM golang:1.21-alpine AS builder

ENV GOPROXY=https://goproxy.cn,direct
ENV GO111MODULE=on

RUN apk add --no-cache git ca-certificates tzdata

WORKDIR /build

COPY go.mod go.sum* ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-s -w" \
    -o /build/api-gateway \
    ./main.go

FROM alpine:3.19

RUN apk --no-cache add ca-certificates tzdata

ENV TZ=Asia/Shanghai

RUN adduser -D -g '' appuser

WORKDIR /app

COPY --from=builder /build/api-gateway .
COPY config.docker.yaml ./config.yaml

USER appuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget -q --spider http://localhost:8080/health || exit 1

CMD ["./api-gateway", "-config", "config.yaml"]
