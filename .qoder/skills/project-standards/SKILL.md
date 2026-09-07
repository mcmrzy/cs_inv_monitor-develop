---
name: project-standards
description: 光伏逆变器物联网监控平台(cs-inv-monitor)全栈开发规范。涵盖Go后端(Handler-Service-Repository)、Flutter移动端、React管理后台的编码标准、错误处理模式、安全规范、命名约定和构建验证流程。在编辑本项目任何代码文件时自动应用，确保代码一致性、可维护性和安全性。
---

# 项目开发规范（cs-inv-monitor）

## 系统架构概览

> 参见 [AGENTS.md §子系统](../../AGENTS.md#子系统) 获取完整子系统表、基础设施和 MQTT 主题格式。

本 Skill 聚焦于**编辑时深度指引**（编码规范、错误处理模式、安全规范）。项目路由级信息（子系统、构建命令、变更边界、OTA 体系等）以 AGENTS.md 为单一事实来源。

---

## Go 后端规范

### 分层架构（严格遵守）

> 目录树结构参见 [AGENTS.md §目录结构约定](../../AGENTS.md#目录结构约定)。

**关键规则**（超出 AGENTS.md 的编辑时深度指引）：
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

> 参见 [AGENTS.md §命名约定](../../AGENTS.md#命名约定) 获取完整命名约定表（Go/TypeScript/Dart/数据库/API 路径）。
>
> 以下为本 Skill 补充的 Go 端额外约定：

| 场景 | 规范 | 示例 |
|------|------|------|
| 变量/函数 | camelCase | `getUserByID` |
| 常量 | PascalCase | `MaxPageSize` |

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
cd business-api && go build ./...
cd device-communication && go build ./...
cd api-gateway && go build ./main.go
cd mqtt-kafka-bridge && go build ./main.go
```

**Go 路径**：确保 `go` 在系统 PATH 中（使用 `go version` 验证）

---

## 安全规范

### 认证与权限

> 基础认证模型（JWT/角色/多租户/RBAC/内部调用）参见 [AGENTS.md §认证与权限](../../AGENTS.md#认证与权限)。
>
> 以下为编辑时的安全深度指引：

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

1. **编译**：`make build-go` 或 `go build ./...`（Go）/ `make type-check` 或 `npx tsc --noEmit`（TS）/ `flutter analyze --no-fatal-infos`（Dart）
2. **错误处理**：所有 Handler 错误使用 `apperr` + `response.HandleError`
3. **输入校验**：用户输入均已校验
4. **SQL 安全**：无字符串拼接 SQL
5. **命名一致**：遵循各层命名约定
6. **日志规范**：使用 `pkg/logger`（zap），禁止 `fmt.Println` / `log.Printf`
7. **Import 有序**：标准库 → 项目包 → 第三方
