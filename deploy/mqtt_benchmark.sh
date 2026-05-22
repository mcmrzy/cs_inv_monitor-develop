#!/bin/bash
# MQTT 压测脚本 — 模拟 N 台设备并发上报
# 用法: ./mqtt_benchmark.sh <设备数量> <上报间隔秒数> <运行时长秒数>
# 示例: ./mqtt_benchmark.sh 10000 5 300

DEVICE_COUNT="${1:-1000}"
INTERVAL="${2:-5}"
DURATION="${3:-60}"
BROKER="${MQTT_BROKER:-jiuxiaoyw.online}"
PORT="${MQTT_PORT:-8883}"
USERNAME="${MQTT_USERNAME:-CSKJ-INV-SERVER-DEVICE}"
PASSWORD="${MQTT_PASSWORD:-CSKJINVSERVERDEVICE}"

echo "========================================="
echo " MQTT Benchmark"
echo " Devices: ${DEVICE_COUNT}"
echo " Interval: ${INTERVAL}s"
echo " Duration: ${DURATION}s"
echo " Broker: ${BROKER}:${PORT}"
echo "========================================="

# 安装 mqtt-bench (如果没有)
if ! command -v mqtt-bench &> /dev/null; then
  echo "Installing mqtt-bench..."
  go install github.com/krylovsk/mqtt-bench@latest
fi

# 生成设备 SN 列表
DEVICE_SNS=$(seq -f "H1CNC%04g000001F" 1 ${DEVICE_COUNT} | tr '\n' ' ')

# 运行压测
mqtt-bench \
  -broker "ssl://${BROKER}:${PORT}" \
  -username "${USERNAME}" \
  -password "${PASSWORD}" \
  -count "${DEVICE_COUNT}" \
  -size 256 \
  -clients "${DEVICE_COUNT}" \
  -qos 0 \
  -topic "cs_inv/{clientid}/data/ac" \
  -message '{"voltage":230.5,"current":10.2,"power":2350,"frequency":50.0,"pf":0.98}' \
  -interval "${INTERVAL}" \
  -time "${DURATION}"s \
  -wait 3000

echo ""
echo "Benchmark completed."
echo "Check EMQX Dashboard for connection/message stats."
echo "Check inv-device-server metrics: curl http://localhost:8081/metrics"
