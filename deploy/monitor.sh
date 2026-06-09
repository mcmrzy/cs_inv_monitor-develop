#!/bin/bash

# INV-MQTT 服务监控脚本
# 检查服务健康状态，自动重启失败的服务
# 配合 systemd timer 每分钟执行一次

set -e

LOG_FILE="/var/log/inv-mqtt/monitor.log"
ALERT_EMAIL="admin@example.com"  # 修改为你的告警邮箱

SERVICES=(
    "inv-api-server"
    "inv-device-server"
    "inv-api-gateway"
    "nginx"
)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_service() {
    local service=$1
    local status=$(systemctl is-active "$service" 2>/dev/null || echo "failed")

    if [ "$status" = "active" ]; then
        log "$service: OK"
        return 0
    else
        log "$service: FAILED - 尝试重启"
        systemctl restart "$service"
        sleep 5

        # 再次检查
        if systemctl is-active "$service" > /dev/null 2>&1; then
            log "$service: 重启成功"
            send_alert "$service 重启成功" "服务 $service 已自动重启"
            return 0
        else
            log "$service: 重启失败，需要人工干预"
            send_alert "$service 重启失败" "服务 $service 重启失败，请检查!"
            return 1
        fi
    fi
}

send_alert() {
    local subject=$1
    local message=$2

    # 邮件告警（需要配置邮件服务）
    # echo "$message" | mail -s "[INV-MQTT] $subject" "$ALERT_EMAIL"

    # 企业微信/钉钉告警（需要配置 webhook）
    # curl -X POST "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=YOUR_KEY" \
    #   -H 'Content-Type: application/json' \
    #   -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"[INV-MQTT] $message\"}}"

    log "ALERT: $subject - $message"
}

check_ports() {
    local failed=0

    # API Gateway (默认 8080)
    if ! nc -z localhost 8080 2>/dev/null; then
        log "警告: API Gateway 端口 8080 未监听"
        failed=1
    fi

    # API Server (默认 8088)
    if ! nc -z localhost 8088 2>/dev/null; then
        log "警告: API Server 端口 8088 未监听"
        failed=1
    fi

    return $failed
}

# 主流程
log "=== 开始服务监控 ==="

failed_count=0
for service in "${SERVICES[@]}"; do
    if ! check_service "$service"; then
        ((failed_count++))
    fi
done

# 检查端口
if ! check_ports; then
    ((failed_count++))
fi

# 检查资源使用
mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')
disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

log "资源使用 - 内存: ${mem_usage}%, 磁盘: ${disk_usage}%"

if [ "$mem_usage" -gt 90 ]; then
    log "警告: 内存使用率过高 (${mem_usage}%)"
    send_alert "内存使用率过高" "服务器内存使用率: ${mem_usage}%"
fi

if [ "$disk_usage" -gt 90 ]; then
    log "警告: 磁盘使用率过高 (${disk_usage}%)"
    send_alert "磁盘使用率过高" "服务器磁盘使用率: ${disk_usage}%"
fi

if [ "$failed_count" -eq 0 ]; then
    log "=== 所有服务正常 ==="
else
    log "=== 有 $failed_count 个服务异常 ==="
fi

exit $failed_count
