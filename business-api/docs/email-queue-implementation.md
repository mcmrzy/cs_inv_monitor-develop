# 邮件队列系统实施文档

## 概述

本文档描述了基于 Kafka 的生产级邮件队列系统的实现，用于替代原有的同步 goroutine 邮件发送方式。

## 架构设计

```
Handler → Kafka Topic "email-sent" → Consumer Workers → SMTP Service
                      ↓
              Dead Letter Queue (if max retries exceeded)
                      ↓
              Alert on Critical Failures
```

### 核心特性

1. **异步处理**: 邮件发送不再阻塞 HTTP 请求
2. **重试机制**: 失败邮件自动重试（指数退避）
3. **死信队列**: 超过最大重试次数的邮件进入 DLQ
4. **速率限制**: 防止 SMTP 提供商限流（令牌桶算法）
5. **监控指标**: 完整的邮件发送性能追踪
6. **优先级支持**: high/normal/low 三级优先级

## 快速开始

### 1. 配置更新

在 `config.docker.yaml` 中添加以下配置：

```yaml
email_queue:
  enabled: true
  kafka_brokers: ["kafka:9092"]
  topic: "email-sent"
  dlq_topic: "email-dead-letter-queue"
  workers: 5
  batch_size: 50
  batch_timeout: 5s
  max_retries: 3
  rate_limit: 10  # 每秒最大发送量
```

### 2. Kafka Topic 创建

在 Kafka 中创建必要的 topics：

```bash
# 进入 Kafka 容器
docker exec -it kafka bash

# 创建邮件发送主题
kafka-topics.sh --create \
  --bootstrap-server localhost:9092 \
  --replication-factor 1 \
  --partitions 3 \
  --topic email-sent

# 创建死信队列主题
kafka-topics.sh --create \
  --bootstrap-server localhost:9092 \
  --replication-factor 1 \
  --partitions 1 \
  --topic email-dead-letter-queue
```

### 3. 应用集成

#### 初始化邮件队列

在 `main.go` 中添加：

```go
import (
    "inv-api-server/internal/email"
    "inv-api-server/internal/config"
)

// 在依赖注入阶段
var emailQueue *email.EmailQueue

if cfg.EmailQueue.Enabled {
    var err error
    emailQueue, err = email.NewEmailQueue(
        cfg.EmailQueue.KafkaBrokers,
        cfg.EmailQueue.Topic,
        cfg.EmailQueue.DLQTopic,
        cfg.EmailQueue.Workers,
        cfg.EmailQueue.BatchSize,
        cfg.EmailQueue.MaxRetries,
        cfg.EmailQueue.RateLimit,
    )
    
    if err != nil {
        logger.Fatal("Failed to initialize email queue", zap.Error(err))
    }
    
    // 启动 Kafka 消费者
    if err := emailQueue.StartKafkaConsumer(); err != nil {
        logger.Fatal("Failed to start email consumer", zap.Error(err))
    }
    
    defer emailQueue.Shutdown()
    
    logger.Info("Email queue initialized and consumers started")
}
```

#### 修改 InvitationHandler

更新 `invitation_handler.go`：

```go
type InvitationHandler struct {
    // ... existing fields ...
    emailQueue *email.EmailQueue  // 新增
}

func NewInvitationHandler(
    // ... existing params ...
    emailQueue *email.EmailQueue,  // 新增
) *InvitationHandler {
    return &InvitationHandler{
        // ... existing assignments ...
        emailQueue: emailQueue,
    }
}

// 在 Create handler 中，替换原来的邮件发送逻辑
func (h *InvitationHandler) Create(c *gin.Context) {
    // ... existing creation logic ...
    
    // After committing transaction
    if h.emailQueue != nil {
        go func(invitation model.Invitation) {
            err := h.emailQueue.SendInvitation(
                invitation.Email,
                rawToken[:8],
                roleName,
                org.Name,
                req.ExpiresHours,
                "CSERGY Smart Energy Platform",
            )
            
            if err != nil {
                logger.Warn("Failed to queue invitation email",
                    zap.Int64("invitation_id", invitation.ID),
                    zap.String("email", invitation.Email),
                    zap.Error(err))
                // Don't rollback - email failures shouldn't affect DB transaction
            } else {
                logger.Info("Invitation email queued successfully",
                    zap.Int64("invitation_id", invitation.ID),
                    zap.String("email", invitation.Email))
            }
        }(invitation)
    } else if h.emailService != nil {
        // Fallback to original method if queue not configured
        go func() {
            err := h.emailService.SendInvitationEmail(...)
            if err != nil {
                logger.Warn("Failed to send email", zap.Error(err))
            }
        }()
    }
    
    response.Success(c, invitation)
}
```

## 使用示例

### 发送邀请邮件

```go
err := emailQueue.SendInvitation(
    "user@example.com",     // 收件人邮箱
    "TOKEN12",              // Token 提示（仅显示前8位）
    "admin",                // 角色名称
    "My Organization",      // 组织名称
    24,                     // 过期时间（小时）
    "CSERGY Smart Energy",  // 发送者名称
)
```

### 发送设备转移通知

```go
err := emailQueue.SendTransferNotification(
    "requester@example.com",
    "SN12345678",
    "Old Organization",
    "New Organization",
    "Transfer reason here",
    "CSERGY Smart Energy",
)
```

### 发送欢迎邮件

```go
err := emailQueue.SendWelcomeEmail(
    "newuser@example.com",
    "username",
    "CSERGY Smart Energy",
)
```

### 发送密码重置邮件

```go
err := emailQueue.SendPasswordReset(
    "reset-token-here",
    "username",
    "user@example.com",
    "CSERGY Smart Energy",
)
```

### 发送验证码邮件

```go
err := emailQueue.SendVerificationCode(
    "user@example.com",
    "注册验证码",
    "<html>Verification code HTML body</html>",
)
```

## 监控与指标

### 内置指标

邮件队列系统提供以下指标（通过 `GetStats()` 方法访问）：

- `queued_count`: 总队列邮件数
- `sent_by_type`: 按类型分类的成功发送数
- `failed_by_type`: 按类型分类的失败数
- `dlq_size`: 死信队列大小
- `active_jobs`: 当前处理中的作业数
- `kafka_brokers`: Kafka broker 列表
- `max_retries`: 最大重试次数
- `worker_count`: 并发 worker 数量

### 健康检查端点

添加 HTTP 端点检查队列状态：

```go
router.GET("/api/admin/email-queue/stats", func(c *gin.Context) {
    if emailQueue != nil {
        stats := emailQueue.GetStats()
        c.JSON(200, stats)
    } else {
        c.JSON(200, gin.H{"status": "disabled"})
    }
})
```

## 故障排查

### 检查 Kafka 连接

```bash
# 查看 topic 详情
docker exec -it kafka kafka-topics.sh \
  --describe --bootstrap-server localhost:9092 \
  --topic email-sent

# 查看消费者组状态
docker exec -it kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group inv-api-email-consumer-group
```

### 检查死信队列

```bash
# 消费 DLQ 中的消息
docker exec -it kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic email-dead-letter-queue \
  --from-beginning
```

### 常见问题

1. **邮件未发送**
   - 检查 Kafka broker 连接
   - 确认 topic 已创建
   - 查看 worker 日志是否有错误

2. **速率限制触发**
   - 降低 `rate_limit` 配置
   - 增加 SMTP 提供商限额
   - 考虑使用多个 SMTP 账户

3. **邮件进入 DLQ**
   - 检查邮件内容格式
   - 验证 SMTP 凭据
   - 查看网络连通性

## 性能优化

### 调整 Worker 数量

根据 SMTP 服务器能力调整并发数：

```yaml
# 低负载（< 1000 封/小时）
workers: 3

# 中负载（1000-5000 封/小时）
workers: 5-10

# 高负载（> 5000 封/小时）
workers: 15-20
```

### 批量优化

对于大量邮件，增加批次大小：

```yaml
batch_size: 100      # 默认 50
batch_timeout: 10s   # 默认 5s
```

### Kafka 分区

根据 worker 数量设置分区：

```bash
# 3-5 workers: 3 partitions
# 5-10 workers: 6 partitions
# 10-20 workers: 12 partitions
```

## 安全考虑

1. **Kafka 认证**: 生产环境应启用 SASL/SSL
2. **邮件内容加密**: 敏感信息应在存储时加密
3. **DLQ 访问控制**: 限制死信队列的访问权限
4. **速率限制**: 防止滥用和垃圾邮件生成

## 测试策略

### 单元测试

```go
func TestEmailQueue_SendInvitation(t *testing.T) {
    queue, _ := NewEmailQueue(...)
    
    err := queue.SendInvitation(
        "test@example.com",
        "TOKEN",
        "admin",
        "Test Org",
        24,
        "Test Sender",
    )
    
    assert.NoError(t, err)
}
```

### 集成测试

使用 testcontainers 启动本地 Kafka：

```go
func TestEmailQueue_Integration(t *testing.T) {
    ctx := context.Background()
    kafkaC, _ := testcontainers.GenericContainer(ctx, 
        testcontainers.GenericContainerRequest{
            ContainerRequest: testcontainers.ContainerRequest{
                Image: "confluentinc/cp-kafka:latest",
                // ... kafka configuration
            },
        })
    
    // Run tests...
}
```

### 负载测试

模拟 1000 封/小时的负载：

```bash
# 使用 k6 或类似工具
for i in {1..1000}; do
    curl -X POST http://localhost:8080/api/invitations \
      -d '{"email": "user${i}@example.com"}' &
done
wait
```

## 迁移指南

### 从旧系统迁移

1. **并行运行**: 同时启用队列和旧方法一段时间
2. **逐步切换**: 先处理非关键邮件类型
3. **监控对比**: 确保新系统的可靠性
4. **完全切换**: 确认稳定后移除旧代码

## 版本历史

- **v1.0.0** (2026-07-22): 初始版本
  - Kafka 集成
  - 死信队列
  - 速率限制
  - 基础监控

## 参考资源

- [Apache Kafka 文档](https://kafka.apache.org/documentation/)
- [segmentio/kafka-go](https://github.com/segmentio/kafka-go)
- [Email Service 原始实现](./email_service.go)
