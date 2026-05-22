FROM alpine:latest

RUN apk --no-cache add ca-certificates tzdata wget

WORKDIR /app

COPY inv_device_server_linux ./main
COPY config.docker.yaml ./config.yaml
COPY web/ ./web/

ENV TZ=Asia/Shanghai

EXPOSE 8081

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget -q --spider http://localhost:8081/health || exit 1

CMD ["./main", "-config", "config.yaml"]
