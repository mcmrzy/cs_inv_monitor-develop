#!/bin/bash
# Kafka Topic 初始化脚本
# 适用: 逆变器设备管理系统
# 用法: docker exec inv-kafka kafka-topics.sh --bootstrap-server localhost:9092 --create --topic device-telemetry --partitions 6 --replication-factor 1

echo "=== 创建逆变器系统 Kafka Topics ==="

BROKER="localhost:9092"

# 1. 设备遥测数据 Topic（高频，6 分区）
docker exec inv-kafka kafka-topics.sh \
  --bootstrap-server $BROKER \
  --create --topic device-telemetry \
  --partitions 6 --replication-factor 1 \
  --config retention.ms=604800000 \
  --config cleanup.policy=delete

# 2. 设备信息 Topic（低频）
docker exec inv-kafka kafka-topics.sh \
  --bootstrap-server $BROKER \
  --create --topic device-info \
  --partitions 3 --replication-factor 1 \
  --config retention.ms=2592000000 \
  --config cleanup.policy=delete

# 3. 告警事件 Topic（高优先级）
docker exec inv-kafka kafka-topics.sh \
  --bootstrap-server $BROKER \
  --create --topic device-alarm \
  --partitions 3 --replication-factor 1 \
  --config retention.ms=2592000000 \
  --config cleanup.policy=delete

# 4. 命令响应 Topic
docker exec inv-kafka kafka-topics.sh \
  --bootstrap-server $BROKER \
  --create --topic device-cmd-response \
  --partitions 3 --replication-factor 1 \
  --config retention.ms=86400000 \
  --config cleanup.policy=delete

# 5. 设备状态 Topic
docker exec inv-kafka kafka-topics.sh \
  --bootstrap-server $BROKER \
  --create --topic device-status \
  --partitions 3 --replication-factor 1 \
  --config retention.ms=86400000 \
  --config cleanup.policy=delete

echo ""
echo "=== Topic 创建完成 ==="
echo ""
echo "查看 Topic 列表:"
docker exec inv-kafka kafka-topics.sh --bootstrap-server $BROKER --list
