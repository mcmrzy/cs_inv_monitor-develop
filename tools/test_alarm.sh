#!/bin/sh
# 测试告警端点：未注册设备（应 404）
wget -q -S -O - \
  --post-data='{"sn":"E2EMQTT00154EE8626","topic":"alarm","received_at":"2026-08-03T01:18:07Z","envelope":{"t":1785719887,"v":1,"data":{"source":0,"code":101,"level":1,"state":1}}}' \
  --header='Content-Type: application/json' \
  --header='X-Internal-Key: test-internal-key-with-more-than-32-characters' \
  http://inv-api-server:8080/api/v1/internal/device-alarm 2>&1
echo ""
echo "--- registered device ---"
# 已注册设备（应 200）
wget -q -S -O - \
  --post-data='{"sn":"E2E-SN-MSCIU07M4NH","topic":"alarm","received_at":"2026-08-03T01:20:07Z","envelope":{"t":1785720007,"v":1,"data":{"source":0,"code":200,"level":1,"state":1}}}' \
  --header='Content-Type: application/json' \
  --header='X-Internal-Key: test-internal-key-with-more-than-32-characters' \
  http://inv-api-server:8080/api/v1/internal/device-alarm 2>&1
