#!/bin/bash
# Email Queue System - Quick Setup Script
# 邮件队列系统快速部署脚本

set -e

echo "=========================================="
echo "Email Queue System - Quick Setup"
echo "邮件队列系统 - 快速部署"
echo "=========================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running in correct directory
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}Error: Please run this script from the deploy directory${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 1: Creating Kafka topics...${NC}"
echo "步骤 1: 创建 Kafka topics..."

# Create email-sent topic
docker exec kafka kafka-topics.sh --create \
  --bootstrap-server localhost:9092 \
  --replication-factor 1 \
  --partitions 3 \
  --topic email-sent \
  --if-not-exists 2>/dev/null || echo "Topic email-sent already exists"

# Create DLQ topic
docker exec kafka kafka-topics.sh --create \
  --bootstrap-server localhost:9092 \
  --replication-factor 1 \
  --partitions 1 \
  --topic email-dead-letter-queue \
  --if-not-exists 2>/dev/null || echo "Topic email-dead-letter-queue already exists"

echo -e "${GREEN}✓ Kafka topics created${NC}"
echo ""

echo -e "${YELLOW}Step 2: Verifying Kafka topics...${NC}"
echo "步骤 2: 验证 Kafka topics..."

docker exec kafka kafka-topics.sh --list \
  --bootstrap-server localhost:9092 | grep email

echo -e "${GREEN}✓ Topics verified${NC}"
echo ""

echo -e "${YELLOW}Step 3: Updating configuration...${NC}"
echo "步骤 3: 更新配置文件..."

CONFIG_FILE="../business-api/config.docker.yaml"

if grep -q "email_queue:" "$CONFIG_FILE"; then
    echo -e "${YELLOW}Email queue config already exists, updating...${NC}"
    # Backup existing config
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%Y%m%d%H%M%S)"
fi

# Enable email queue in config (simple sed replacement)
sed -i 's/enabled: false.*# 开发环境/enabled: true  # Production enabled/' "$CONFIG_FILE" 2>/dev/null || true

echo -e "${GREEN}✓ Configuration updated${NC}"
echo ""

echo -e "${YELLOW}Step 4: Rebuilding business-api service...${NC}"
echo "步骤 4: 重建 business-api 服务..."

docker-compose build business-api

echo -e "${GREEN}✓ Service rebuilt${NC}"
echo ""

echo -e "${YELLOW}Step 5: Restarting services...${NC}"
echo "步骤 5: 重启服务..."

docker-compose up -d business-api

echo -e "${GREEN}✓ Services restarted${NC}"
echo ""

echo -e "${YELLOW}Step 6: Verifying deployment...${NC}"
echo "步骤 6: 验证部署..."

sleep 5

# Check if service is running
if docker-compose ps business-api | grep -q "Up"; then
    echo -e "${GREEN}✓ Service is running${NC}"
else
    echo -e "${RED}✗ Service failed to start${NC}"
    echo "Checking logs..."
    docker-compose logs --tail=50 business-api
    exit 1
fi

echo ""

# Check for email queue initialization in logs
if docker-compose logs business-api | grep -q "EmailQueue initialized"; then
    echo -e "${GREEN}✓ Email queue initialized successfully${NC}"
else
    echo -e "${YELLOW}! Email queue not detected in logs (may be disabled in config)${NC}"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Setup Complete!${NC}"
echo "部署完成！"
echo "=========================================="
echo ""

echo "Next steps:"
echo "1. Check logs: docker-compose logs -f business-api"
echo "2. Test email sending via API"
echo "3. Monitor Kafka topics:"
echo "   docker exec kafka kafka-topics.sh --describe --bootstrap-server localhost:9092 --topic email-sent"
echo ""

echo "后续步骤："
echo "1. 查看日志：docker-compose logs -f business-api"
echo "2. 通过 API 测试邮件发送"
echo "3. 监控 Kafka topics："
echo "   docker exec kafka kafka-topics.sh --describe --bootstrap-server localhost:9092 --topic email-sent"
echo ""

# Show quick stats
echo -e "${YELLOW}Quick Stats:${NC}"
echo "快速统计："

docker exec kafka kafka-run-class.sh kafka.tools.GetOffsetShell \
  --broker-list localhost:9092 \
  --topic email-sent 2>/dev/null | awk -F: '{sum+=$3} END {print "Total messages in queue: " sum}' || echo "Unable to fetch stats"

echo ""
echo "For more information, see:"
echo "- business-api/docs/email-queue-implementation.md"
echo "- business-api/docs/email-queue-summary.md"
echo ""
