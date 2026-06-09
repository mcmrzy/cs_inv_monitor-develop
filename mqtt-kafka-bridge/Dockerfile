FROM golang:1.21-alpine AS builder
ENV GOPROXY=https://goproxy.cn,direct
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o mqtt-kafka-bridge .

FROM alpine:3.19
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories && \
    apk --no-cache add ca-certificates tzdata
WORKDIR /app
COPY --from=builder /app/mqtt-kafka-bridge .
COPY config.docker.yaml ./config.yaml
EXPOSE 18088
CMD ["./mqtt-kafka-bridge"]
