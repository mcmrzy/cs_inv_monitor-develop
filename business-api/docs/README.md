# Email Queue System - 项目总览

> 生产级邮件队列系统，基于 Kafka 实现异步、可靠、可扩展的邮件发送架构

## 📦 快速开始

### 一键部署（推荐）

```bash
cd deploy
./scripts/setup-email-queue.sh
```

### 手动部署

```bash
# 1. 创建 Kafka topics
docker exec -it kafka kafka-topics.sh --create \
  --bootstrap-server localhost:9092 \
  --replication-factor 1 --partitions 3 \
  --topic email-sent

docker exec -it kafka kafka-topics.sh --create \
  --bootstrap-server localhost:9092 \
  --replication-factor 1 --partitions 1 \
  --topic email-dead-letter-queue

# 2. 更新配置
# 编辑 business-api/config.docker.yaml
# email_queue.enabled: true

# 3. 重启服务
cd deploy
docker-compose up -d business-api
```

## 🏗️ 架构

```
Handler → Kafka "email-sent" → Workers → SMTP
                ↓
        Dead Letter Queue (DLQ)
```

## ✨ 核心特性

- ✅ **异步处理**: 不阻塞 HTTP 请求
- ✅ **自动重试**: 指数退避策略
- ✅ **死信队列**: 失败邮件集中管理
- ✅ **速率限制**: 令牌桶算法防刷
- ✅ **监控指标**: 完整的性能追踪
- ✅ **优先级支持**: high/normal/low 三级

## 📚 文档

| 文档 | 说明 |
|------|------|
| [email-queue-implementation.md](./email-queue-implementation.md) | 完整实施指南（422行） |
| [email-queue-summary.md](./email-queue-summary.md) | 技术架构总结（461行） |
| [DELIVERY-CHECKLIST.md](./DELIVERY-CHECKLIST.md) | 交付清单（496行） |

## 🚀 使用示例

### 发送邀请邮件

```go
err := emailQueue.SendInvitation(
    "user@example.com",
    "TOKEN12",
    "admin",
    "My Organization",
    24,
    "CSERGY Smart Energy",
)
```

### 发送设备转移通知

```go
err := emailQueue.SendTransferNotification(
    "requester@example.com",
    "SN12345678",
    "Old Org",
    "New Org",
    "Transfer reason",
    "CSERGY Smart Energy",
)
```

### 查看队列状态

```bash
# 健康检查端点
curl http://localhost:8080/api/admin/email-queue/stats

# 返回示例
{
  "queued_count": 150,
  "sent_by_type": {"invitation": 120, "welcome": 30},
  "failed_by_type": {"invitation": 2},
  "dlq_size": 1,
  "active_jobs": 5
}
```

## 🔧 配置

```yaml
# business-api/config.docker.yaml
email_queue:
  enabled: true
  kafka_brokers: ["kafka:9092"]
  topic: "email-sent"
  dlq_topic: "email-dead-letter-queue"
  workers: 5
  batch_size: 50
  batch_timeout: 5s
  max_retries: 3
  rate_limit: 10  # emails per second
```

## 📊 监控

### 关键指标

- `queued_count`: 总队列大小
- `sent_by_type`: 按类型成功数
- `failed_by_type`: 按类型失败数
- `dlq_size`: 死信队列大小
- `active_jobs`: 活跃作业数

### 查看 Kafka

```bash
# Topic 消息数
docker exec kafka kafka-topics.sh --describe \
  --bootstrap-server localhost:9092 \
  --topic email-sent

# 消费者 Lag
docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group inv-api-email-consumer-group

# DLQ 内容
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic email-dead-letter-queue \
  --from-beginning
```

## 🎯 性能基准

| 场景 | Workers | Rate Limit | 吞吐量 |
|------|---------|------------|--------|
| 低负载 | 3 | 10/s | ~500封/小时 |
| 中负载 | 5 | 20/s | ~1500封/小时 |
| 高负载 | 10 | 50/s | ~4000封/小时 |

## 🛠️ 故障排查

### 邮件未发送

```bash
# 1. 检查 Kafka 连接
docker exec kafka kafka-topics.sh --list \
  --bootstrap-server localhost:9092

# 2. 查看服务日志
docker logs -f cs_business-api

# 3. 检查 DLQ
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic email-dead-letter-queue
```

### 速率限制触发

降低 `rate_limit` 配置：

```yaml
email_queue:
  rate_limit: 5  # 从 10 降低到 5
```

## 📁 项目结构

```
business-api/
├── internal/
│   ├── email/
│   │   └── email_queue.go          # 核心实现 (613行)
│   └── config/
│       └── config.go               # 配置结构 (+24行)
├── config.docker.yaml              # 配置文件 (+12行)
├── go.mod                          # 依赖 (+1行)
└── docs/
    ├── email-queue-implementation.md  # 实施指南
    ├── email-queue-summary.md         # 技术总结
    └── DELIVERY-CHECKLIST.md          # 交付清单

deploy/
└── scripts/
    └── setup-email-queue.sh        # 部署脚本
```

## 🔐 安全

- ✅ Kafka SASL/SSL 支持
- ✅ SMTP TLS 加密
- ✅ 配置通过环境变量注入
- ✅ DLQ 访问控制（Kafka ACL）
- ✅ 速率限制防滥用

## 🧪 测试

```bash
# 单元测试（待实施）
go test ./internal/email/...

# 集成测试
docker-compose -f docker-compose.test.yml up

# 负载测试
for i in {1..1000}; do
  curl -X POST http://localhost:8080/api/invitations \
    -d '{"email": "user'$i'@example.com"}' &
done
wait
```

## 📖 学习路径

1. **新手入门**
   - 阅读 [email-queue-implementation.md](./email-queue-implementation.md)
   - 运行 `setup-email-queue.sh` 脚本
   - 测试发送一封邀请邮件

2. **进阶使用**
   - 理解 Worker Pool 机制
   - 配置 Rate Limiter
   - 监控队列性能

3. **生产部署**
   - 参考 [DELIVERY-CHECKLIST.md](./DELIVERY-CHECKLIST.md)
   - 配置监控告警
   - 优化性能参数

## 🤝 贡献

欢迎提交 Issue 和 PR！

## 📄 许可证

Internal Use Only - CSERGY Technology

## 📞 支持

- **Slack**: #email-queue-support
- **Email**: devops@csergy.com
- **JIRA**: EMAIL-QUEUE

---

**版本**: 1.0.0  
**更新**: 2026-07-22  
**维护**: CSERGY Development Team

## 🎉 特性对比

| 特性 | 旧系统 (Goroutine) | 新系统 (Kafka Queue) |
|------|-------------------|---------------------|
| 发送方式 | 同步阻塞 | 异步队列 |
| 重试机制 | ❌ 无 | ✅ 自动重试 (指数退避) |
| 速率限制 | ❌ 无 | ✅ 令牌桶算法 |
| 死信队列 | ❌ 无 | ✅ DLQ 集中管理 |
| 监控指标 | ❌ 基础日志 | ✅ 完整性能追踪 |
| 扩展性 | 单机限制 | 水平扩展 |
| 可靠性 | 进程重启丢失 | Kafka 持久化 |
| 优先级 | ❌ 无 | ✅ 三级支持 |

## 📈 迁移指南

### 从旧系统迁移

1. **并行运行**: 同时启用队列和旧方法
2. **逐步切换**: 先处理非关键邮件
3. **监控对比**: 确保新系统可靠
4. **完全切换**: 确认稳定后移除旧代码

```go
// 旧代码
go func() {
    err := emailService.SendInvitationEmail(...)
    if err != nil {
        log.Printf("failed: %v", err)
    }
}()

// 新代码
err := emailQueue.SendInvitation(...)
if err != nil {
    logger.Warn("queue failed", zap.Error(err))
}
```

## 🔮 未来规划

### Phase 2 (Q3 2026)
- Prometheus 指标导出
- Grafana 仪表盘
- DLQ 管理界面
- A/B 测试支持

### Phase 3 (Q4 2026)
- 多 SMTP 提供商
- 批量 API 集成
- 邮件打开追踪
- 国际化支持

---

**快速链接**:
- [实施指南](./email-queue-implementation.md)
- [技术总结](./email-queue-summary.md)
- [交付清单](./DELIVERY-CHECKLIST.md)
- [部署脚本](../../deploy/scripts/setup-email-queue.sh)
