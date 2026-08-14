# 本地开发环境配置说明

## 架构概览

本地开发环境和生产环境是**完全独立的两套系统**，各自有独立的数据库服务器，通过 Kafka 消费者组实现消息隔离。

```
┌─────────────────────────────────────────────────────────────┐
│                        生产服务器                            │
│                                                             │
│   PostgreSQL (生产)     Redis (生产)     Device Server      │
│   └── inv_mqtt          └── 缓存数据      └── 端口 8081     │
│                                            消费者组:         │
│                                            inv-device-       │
│                                            server-parser     │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ Kafka (共享消息队列)
                          │
┌─────────────────────────────────────────────────────────────┐
│                        本地开发机器                          │
│                                                             │
│   PostgreSQL (本地)     Redis (本地)      Device Server      │
│   └── inv_mqtt          └── 缓存数据      └── 端口 8081     │
│                                            消费者组:         │
│                                            inv-device-       │
│                                            server-local-dev  │
└─────────────────────────────────────────────────────────────┘
```

## 隔离机制

### 1. 数据库完全隔离

两个环境使用**独立的数据库服务器**：

| 环境 | 数据库服务器 | 数据库名称 |
|------|------------|-----------|
| 生产环境 | 远程生产服务器 | `inv_mqtt` |
| 本地开发 | localhost | `inv_mqtt` |

**优势**：
- ✅ 数据完全独立，互不影响
- ✅ 可以随意清理本地数据
- ✅ 开发测试不会影响生产数据

### 2. Kafka 消费者组隔离

两个环境使用**不同的消费者组**，独立消费相同的消息：

| 环境 | 消费者组 |
|------|---------|
| 生产环境 | `inv-device-server-parser` |
| 本地开发 | `inv-device-server-local-dev` |

**消息流向**：

```
设备发送遥测数据
        │
        ▼
┌─────────────────────────────────────────┐
│        Kafka Topic: inv-telemetry       │
└─────────────────────────────────────────┘
        │
        ├──→ 消费者组: inv-device-server-parser (生产)
        │           │
        │           ▼
        │    ┌─────────────────┐
        │    │ 生产 PostgreSQL │
        │    │ (远程服务器)    │
        │    └─────────────────┘
        │
        └──→ 消费者组: inv-device-server-local-dev (开发)
                    │
                    ▼
             ┌─────────────────┐
             │ 本地 PostgreSQL │
             │ (localhost)     │
             └─────────────────┘
```

### 3. MQTT 客户端隔离

两个环境使用**不同的客户端 ID** 连接 EMQX：

| 环境 | 客户端 ID |
|------|----------|
| 生产环境 | `CSKJ-INV-SERVER-DEVICE-<hash>` |
| 本地开发 | `CSKJ-INV-SERVER-DEVICE-LOCAL-DEV` |

## 配置文件说明

### `.env`（根目录）

本地开发环境变量：

```env
# 数据库配置（本地 PostgreSQL）
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=local-dev-password_STRONG_PASSWORD
DB_NAME=inv_mqtt

# Redis 配置（本地）
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=local-dev-password_STRONG_PASSWORD

# MQTT 配置（连接线上 EMQX）
MQTT_BROKER=jiuxiaoyw.online
MQTT_PORT=1883
MQTT_CLIENT_ID=CSKJ-INV-SERVER-DEVICE-LOCAL-DEV
MQTT_USERNAME=CSKJ-INV-DEVICE-SERVER
MQTT_PASSWORD=CSKJINVDEVICESERVER

# Kafka 配置（使用独立消费者组）
KAFKA_ENABLED=true
KAFKA_BROKER=broker.jiuxiaoyw.online:9092
KAFKA_CONSUMER_GROUP=inv-device-server-local-dev
```

### `device-communication/config.dev.yaml`

本地开发专用配置文件：
- 连接本地数据库和 Redis
- 使用非 TLS 连接 EMQX
- 使用独立的 Kafka 消费者组
- 启用 debug 日志级别

## 快速启动

### 前置条件

1. **本地 PostgreSQL 已启动**，并创建了 `inv_mqtt` 数据库
2. **本地 Redis 已启动**
3. **Go 1.21+ 已安装**

### 启动步骤

```powershell
# 1. 验证配置
.\verify-dev-config.ps1

# 2. 启动本地开发环境
.\dev-start.ps1
```

### 验证启动成功

检查日志输出，应该看到：

```
✓ Database connected: inv_mqtt @ localhost:5432
✓ Redis connected: localhost:6379
✓ MQTT connected: CSKJ-INV-SERVER-DEVICE-LOCAL-DEV @ jiuxiaoyw.online:1883
✓ Kafka consumer started, group: inv-device-server-local-dev
✓ Server listening on :8081
```

## 验证环境隔离

### 1. 检查数据库连接

```powershell
# 连接本地数据库
psql -U postgres -d inv_mqtt

# 查看设备数据
SELECT COUNT(*) FROM devices;
```

### 2. 检查 EMQX 连接

在 EMQX 控制台应该看到两个连接：

| 客户端 ID | 状态 | 说明 |
|-----------|------|------|
| `CSKJ-INV-SERVER-DEVICE-<hash>` | ✅ 已连接 | 生产环境 |
| `CSKJ-INV-SERVER-DEVICE-LOCAL-DEV` | ✅ 已连接 | 本地开发 |

### 3. 检查 Kafka 消费者

查看本地开发日志：

```
INFO  Kafka consumer started, group: inv-device-server-local-dev
INFO  Connected to broker: broker.jiuxiaoyw.online:9092
INFO  Subscribed to topic: inv-telemetry
INFO  Subscribed to topic: inv-alerts
```

## 常用命令

### 启动本地开发

```powershell
.\dev-start.ps1
```

### 停止本地开发服务

```powershell
# 在运行服务的终端按 Ctrl+C
```

### 验证配置

```powershell
.\verify-dev-config.ps1
```

### 清理本地数据

```sql
-- 连接到本地数据库
psql -U postgres -d inv_mqtt

-- 清理旧的遥测数据（保留最近 7 天）
DELETE FROM device_telemetry WHERE time < NOW() - INTERVAL '7 days';

-- 清理测试设备
DELETE FROM devices WHERE sn LIKE 'TEST-%';
```

## 常见问题

### Q1: 数据库连接失败

**检查**：
```powershell
# 测试 PostgreSQL 连接
pg_isready -h localhost -p 5432

# 测试数据库是否存在
psql -U postgres -d inv_mqtt -c "SELECT 1;"
```

**解决**：
```powershell
# 如果数据库不存在，创建它
psql -U postgres -c "CREATE DATABASE inv_mqtt;"
```

### Q2: Kafka 消费失败

**检查**：
```powershell
# 测试 Kafka 连通性
Test-NetConnection -ComputerName broker.jiuxiaoyw.online -Port 9092
```

**解决**：
- 确认网络可以访问 Kafka broker
- 检查防火墙设置
- 如果不需要 Kafka，可以在 `.env` 中设置 `KAFKA_ENABLED=false`

### Q3: MQTT 连接失败

**检查**：
```powershell
# 测试 EMQX 连通性
Test-NetConnection -ComputerName jiuxiaoyw.online -Port 1883
```

**解决**：
- 确认网络可以访问 EMQX broker
- 检查用户名密码是否正确
- 查看服务日志获取详细错误信息

## 相关文档

- [本地开发环境指南](DEV_ENV_GUIDE.md)
- [生产环境部署指南](deploy/DEPLOY_GUIDE.md)
- [MQTT 配置说明](docs/mqtt_connection.md)
