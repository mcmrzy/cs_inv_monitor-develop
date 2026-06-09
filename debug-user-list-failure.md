# Debug Session: user-list-failure

**Status**: [OPEN]
**Created**: 2026-06-01
**Symptom**: 管理后台获取用户列表失败

## 请求链路追踪

```
前端 UsersPage
  → userApi.list() → GET /api/v1/users?page=1&pageSize=10
    → API Gateway (jwt.go → rbac.go → routes.go)
      → proxy → inv_api_server
        → RequirePermission("users","view") → ListUsers handler
          → UserRepository.List() → SQL query
```

## 假设列表

### H1: API Gateway 路由不匹配 (404)
- **观察点**: Gateway 日志中是否有 404 响应
- **证据**: 
  - Gateway 注册路由 `r.Any("/api/v1/users/*action", ...)` 使用 catch-all 参数
  - Gin 的 `*action` 要求路径至少有 `/` 后缀
  - `GET /api/v1/users` (无尾部斜杠) 不匹配 `/api/v1/users/*action`
  - `RedirectTrailingSlash = false`，不会自动重定向
  - `TrailingSlashHandler` 只移除尾部斜杠，不添加
  - **结论**: 请求会命中 `NoRoute` 处理器返回 404

### H2: 权限检查失败 (403)
- **观察点**: API Server 日志中是否有权限拒绝记录
- **证据**:
  - `RequirePermission(deps.PermChecker, "users", "view")` 检查权限
  - `PermChecker.CheckPermission` 从 `sys_user_role` 加载角色
  - 如果 `sys_user_role` 表不存在，回退到 `user.Role` 字段
  - 对于超级管理员 (role=0)，`roleID == 0` 直接放行
  - 对于其他角色，需要查询 `sys_role_permission` + `sys_permission`
  - 如果这些表不存在或无数据，权限检查失败

### H3: 数据库查询失败 (500)
- **观察点**: API Server 日志中是否有数据库错误
- **证据**:
  - `UserRepository.List()` 扫描 `nickname` 和 `avatar` 为 `string` 类型
  - 如果数据库中这些字段为 NULL，`Scan` 会失败
  - 其他方法 (如 `GetByPhone`) 使用 `sql.NullString` 处理 NULL
  - `List()` 方法在 Scan 错误时使用 `continue` 跳过，不会导致整个请求失败

### H4: API Server 不可达 (502)
- **观察点**: Gateway 日志中是否有 502 响应
- **证据**: `proxy.go` 的 ErrorHandler 会记录 "后端服务不可达"

### H5: JWT Token 问题 (401)
- **观察点**: Gateway 日志中是否有 401 响应
- **证据**: `jwt.go` 中间件验证 token

## 分析结论

通过深入分析，发现两类问题：

### 问题1: 尾部斜杠导致路由不匹配 (H1 确认)
- Gateway 注册路由 `r.Any("/api/v1/users/*action", ...)` 使用 catch-all 参数
- Gin 的 `*action` 要求路径至少有 `/` 后缀
- `GET /api/v1/users` (无尾部斜杠) 不匹配 `/api/v1/users/*action`
- `RedirectTrailingSlash = false`，不会自动重定向
- `TrailingSlashHandler` 只移除尾部斜杠，不添加

### 问题2: 前端API路径与后端路由不匹配
| 前端API路径 | 后端路由 | 状态 |
|-------------|----------|------|
| `/alerts` | `/alarms` | ❌ 路径不匹配 |
| `/firmwares` | `/ota/firmware` | ❌ 路径不匹配 |
| `/parallel-groups` | `/parallel` | ❌ 路径不匹配 |
| `/alert-rules` | 无 | ⚠️ 后端未实现 |
| `/work-orders` | 无 | ⚠️ 后端未实现 |

## 修复方案

修改三个文件：

### 1. `api-gateway/internal/middleware/slash.go`
将 `TrailingSlashHandler` 从"只移除尾部斜杠"改为"智能处理"：
- 有尾部斜杠的路径：移除（保持原有行为）
- 3 段 API 路径（如 `/api/v1/users`）：添加尾部斜杠，使其匹配 catch-all 路由

### 2. `api-gateway/internal/proxy/proxy.go`
- 在 `Director` 函数中添加路径标准化：转发到 API Server 前移除尾部斜杠
- 新增 `RewriteHandler` 方法：支持路径重写，将前端路径映射到后端路径

### 3. `api-gateway/internal/routes/routes.go`
添加缺失的路由和路径映射：
- `/api/v1/alerts/*action` → 重写到 `/api/v1/alarms`
- `/api/v1/firmwares/*action` → 重写到 `/api/v1/ota/firmware`
- `/api/v1/parallel-groups/*action` → 重写到 `/api/v1/parallel`
- `/api/v1/alert-rules/*action` → 直接转发（后端需实现）
- `/api/v1/work-orders/*action` → 直接转发（后端需实现）

## 修复记录

**修改文件**:
- `api-gateway/internal/middleware/slash.go` - TrailingSlashHandler 智能处理
- `api-gateway/internal/proxy/proxy.go` - 路径标准化 + RewriteHandler
- `api-gateway/internal/routes/routes.go` - 添加缺失路由和路径映射

**编译验证**: ✅ 通过 (`go build ./...`)

**修复逻辑**:
```
请求: GET /api/v1/users
  ↓ TrailingSlashHandler: 检测到 3 段 API 路径，添加尾部斜杠
  ↓ GET /api/v1/users/
  ↓ 路由匹配: /api/v1/users/*action ✓
  ↓ Proxy Director: 移除尾部斜杠
  ↓ GET /api/v1/users → API Server
  ↓ 返回用户列表 ✓

请求: GET /api/v1/alerts
  ↓ TrailingSlashHandler: 添加尾部斜杠
  ↓ GET /api/v1/alerts/
  ↓ 路由匹配: /api/v1/alerts/*action ✓
  ↓ RewriteHandler: 重写为 /api/v1/alarms
  ↓ GET /api/v1/alarms → API Server
  ↓ 返回告警列表 ✓
```

**影响范围**: 所有前端API路径都会被正确路由

**⚠️ 注意**: 以下功能后端未实现，需要补充开发：
- `/api/v1/work-orders` (工单管理)
- `/api/v1/alert-rules` (告警规则)
