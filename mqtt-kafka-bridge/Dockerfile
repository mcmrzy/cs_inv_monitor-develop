FROM docker.m.daocloud.io/library/golang:1.25-alpine AS builder
ENV GOPROXY=https://proxy.golang.org,direct
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o mqtt-kafka-bridge .

FROM docker.m.daocloud.io/library/alpine:3.19
RUN apk --no-cache add ca-certificates tzdata
WORKDIR /app
COPY --from=builder /app/mqtt-kafka-bridge .
COPY config.docker.yaml ./config.yaml
EXPOSE 18088
CMD ["./mqtt-kafka-bridge"]
