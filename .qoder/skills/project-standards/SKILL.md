---
name: project-standards
description: 光伏逆变器物联网监控平台(cs-inv-monitor)全栈开发规范。涵盖Go后端(Handler-Service-Repository)、Flutter移动端、React管理后台的编码标准、错误处理模式、安全规范、命名约定和构建验证流程。在编辑本项目任何代码文件时自动应用，确保代码一致性、可维护性和安全性。
---

# 项目开发规范（cs-inv-monitor）

## 系统架构概览

| 服务 | 目录 | 技术栈 | 职责 |
|------|------|--------|------|
| inv-api-server | `inv_api_server/` | Go + Gin + PostgreSQL + Redis | REST API 服务 |
| inv-device-server | `inv_device_server/` | Go + Gin + MQTT + Kafka | 设备通信网关 |
| api-gateway | `api-gateway/` | Go + Gin | API 网关（JWT/限流/RBAC） |
| mqtt-kafka-bridge | `mqtt-kafka-bridge/` | Go | EMQX Webhook → Kafka |
| inv-admin-frontend | `inv-admin-frontend/` | React + TS + Vite + AntD | 管理后台 |
| inv_app | `inv_app/` | Flutter + Dart | 移动 App |

---

## Go 后端规范

### 分层架构（严格遵守）

```
cmd/main.go          → 入口：配置加载、DI、路由、优雅退出
internal/handler/    → HTTP 层：解析请求、调用 Service、返回响应
internal/service/    → 业务逻辑层：编排、校验、事务
internal/repository/ → 数据访问层：纯 SQL 查询，不含业务逻辑
internal/model/      → 数据模型（struct 对应数据库表）
internal/middleware/  → JWT、RBAC、CORS、限流
pkg/                 → 可复用公共包（apperr/response/logger/jwt/sn/timezone）
```

**关键规则**：
- Handler 只做请求解析和响应返回，**不写业务逻辑**
- Repository 只做数据访问，**不打印日志**（由上层决定）
- Service 返回 `error`，使用 `fmt.Errorf("context: %w", err)` 包装

### 错误处理（核心模式）

**所有 Handler 层错误必须使用 `apperr` + `response.HandleError`**：

```go
import (
    "inv-api-server/pkg/apperr"
    "inv-api-server/pkg/response"
)

// ✅ 正确：InternalError 传递原始 err
if err != nil {
    response.HandleError(c, apperr.Internal("创建电站失败", err))
    return
}

// ✅ 正确：BadRequest 无需 err
response.HandleError(c, apperr.BadRequest("invalid station id"))
return

// ✅ 正确：NotFound / Forbidden / Unauthorized
response.HandleError(c, apperr.NotFound("device not found"))
response.HandleError(c, apperr.Forbidden("permission denied"))
response.HandleError(c, apperr.Unauthorized("token expired"))

// ✅ 正确：自定义业务码
response.HandleError(c, apperr.BadRequest("phone already registered").WithBizCode(4004))

// ❌ 禁止：直接使用旧 API
response.InternalError(c, "msg")    // 禁止
response.BadRequest(c, "msg")       // 禁止
response.NotFound(c, "msg")         // 禁止
response.Forbidden(c, "msg")        // 禁止
response.Unauthorized(c, "msg")     // 禁止
```

**`response.Error(c, code, msg)`** 保留用于需要自定义业务码的场景（如登录失败的 4001/4002/4003）。

**`apperr` 构造函数速查**：
| 函数 | HTTP | 用途 |
|------|------|------|
| `apperr.BadRequest(msg)` | 400 | 参数校验失败 |
| `apperr.Unauthorized(msg)` | 401 | 未认证 |
| `apperr.Forbidden(msg)` | 403 | 无权限 |
| `apperr.NotFound(msg)` | 404 | 资源不存在 |
| `apperr.Conflict(msg)` | 409 | 资源冲突 |
| `apperr.Internal(msg, err)` | 500 | 内部错误（**必须传 err**） |

### Import 组织

```go
import (
    // 1. 标准库
    "context"
    "fmt"

    // 2. 项目内部包
    "inv-api-server/internal/middleware"
    "inv-api-server/internal/model"
    "inv-api-server/internal/service"
    "inv-api-server/pkg/apperr"
    "inv-api-server/pkg/response"

    // 3. 第三方包
    "github.com/gin-gonic/gin"
)
```

### 命名约定

| 场景 | 规范 | 示例 |
|------|------|------|
| struct 字段 | PascalCase | `FirmwareArm` |
| JSON tag | snake_case | `"firmware_arm"` |
| 数据库列 | snake_case | `created_at` |
| 文件名 | snake_case | `ota_handler.go` |
| 变量/函数 | camelCase | `getUserByID` |
| 常量 | PascalCase | `MaxPageSize` |
| API 路径 | kebab-case | `/api/v1/upgrade-packages` |

### 变量作用域安全

```go
// ✅ 正确：err 在外层声明，if 块内使用同一个 err
result, err := service.DoSomething(ctx)
if err != nil {
    response.HandleError(c, apperr.Internal("operation failed", err))
    return
}

// ❌ 禁止：err 在 if 内被 := 遮蔽，传给 apperr 的是内层 err
result, err := service.DoSomething(ctx)
if err := other(); err != nil {  // err 被遮蔽！
    response.HandleError(c, apperr.Internal("failed", err))  // 这里传的是 other() 的 err
    return
}
```

### 构建验证

每次修改 Go 代码后**必须**验证编译：

```bash
cd inv_api_server && go build ./...
cd inv_device_server && go build ./...
cd api-gateway && go build ./main.go
cd mqtt-kafka-bridge && go build ./main.go
```

**Go 路径**：`C:\Users\29538\sdk\go1.26.2\bin\go.exe`（如 `go` 不在 PATH 中）

---

## 安全规范

### 认证与权限

- **JWT Bearer Token**：所有受保护路由必须校验 `Authorization` Header
- **角色**：0=超级管理员, 1=代理商, 2=安装商, 3=终端用户
- **内部调用**：服务间通信使用 `X-Internal-Key` Header
- **密码**：必须使用 `bcrypt` 哈希，禁止明文存储
- **Token 存储**：前端使用 httpOnly cookie（防 XSS）

### 输入校验

```go
// ✅ 必须校验所有用户输入
var req CreateStationRequest
if err := c.ShouldBindJSON(&req); err != nil {
    response.HandleError(c, apperr.BadRequest("invalid request"))
    return
}

// ✅ 校验 ID 参数
stationID, err := strconv.ParseInt(c.Param("id"), 10, 64)
if err != nil {
    response.HandleError(c, apperr.BadRequest("invalid station id"))
    return
}
```

### SQL 安全

- **禁止字符串拼接 SQL**，使用参数化查询（`$1`, `$2`）
- Repository 层使用 `pgx` 的参数化查询，禁止 `fmt.Sprintf` 拼接用户输入

### 敏感信息

- 禁止在代码中硬编码密码、密钥、Token
- 配置通过 `config.yaml` 或环境变量加载
- 日志中禁止打印用户密码、完整 Token

---

## Flutter 移动端规范

### 架构（Clean Architecture + BLoC）

```
lib/features/<feature>/
├── data/           # DataSource + Repository 实现
├── domain/         # Entity + Repository 接口
└── presentation/   # BLoC + Page + Widget
```

### 命名

- 文件名：`snake_case.dart`
- 类名：`PascalCase`
- 变量/方法：`camelCase`
- JSON 字段：`snake_case`

### 状态管理

- 使用 `flutter_bloc`（Bloc/Cubit）
- 全局服务使用 `get_it` 依赖注入（`service_locator.dart`）

---

## React 管理后台规范

### 架构

```
src/
├── pages/<module>/index.tsx    # 页面组件
├── services/<module>Api.ts     # API 调用
├── locales/<module>.ts         # 国际化
├── stores/<module>Store.ts     # Zustand 状态
└── types/index.ts              # TypeScript 类型
```

### 规范

- 使用 TypeScript 严格类型，禁止 `any`
- API 调用统一通过 `services/api.ts` 的 Axios 实例
- 国际化使用 `useTranslation` Hook，禁止硬编码中文字符串
- 状态管理使用 Zustand（`stores/`）
- 构建验证：`cd inv-admin-frontend && npx tsc --noEmit`

---

## 数据库规范

### 表命名

- 表名：`snake_case` 复数（`devices`, `firmware_versions`）
- 主键：`id BIGSERIAL PRIMARY KEY`
- 时间字段：`created_at TIMESTAMPTZ DEFAULT NOW()`
- 软删除：`deleted_at TIMESTAMPTZ`（可为 NULL）

### 迁移

- 迁移文件：`database/migrations/NNN_description.up.sql`
- 每次修改表结构必须创建新迁移，**禁止修改已有迁移**

---

## 变更检查清单

每次代码变更后，按顺序检查：

1. **编译**：`使用docker`（Go）/ `使用docker`（TS）/ `flutter analyze`（Dart）
2. **错误处理**：所有 Handler 错误使用 `apperr` + `response.HandleError`
3. **输入校验**：用户输入均已校验
4. **SQL 安全**：无字符串拼接 SQL
5. **命名一致**：遵循各层命名约定
6. **日志规范**：使用 `pkg/logger`（zap），禁止 `fmt.Println` / `log.Printf`
7. **Import 有序**：标准库 → 项目包 → 第三方
