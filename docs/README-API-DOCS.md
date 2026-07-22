# Inv-MQTT Multi-Level Channel Platform API Documentation

完整的 API 文档套件，支持多级渠道平台的所有 33 个新端点。

## 📚 文档结构

```
docs/
├── openapi.yaml                    # OpenAPI 3.0 完整规范 (~2400 行)
├── swagger/
│   └── index.html                  # 交互式 Swagger UI
├── validate-api-docs.ps1          # 本地验证脚本
├── postman/                        # Postman 集合 (自动生成)
│   └── collection.json
└── README-API-DOCS.md              # 本文件

business-api/internal/docs/swagger/
└── doc.go                          # Go Swagger 注解

.github/workflows/
└── api-docs-validation.yml         # CI 验证工作流
```

## 🚀 快速开始

### 1. 查看交互式文档

打开浏览器访问 Swagger UI：

```bash
# 方式 1: 直接打开 HTML 文件
docs/swagger/index.html

# 方式 2: 通过 api-gateway (需要启动服务)
http://localhost:8080/api/swagger/
```

### 2. 验证文档

运行本地验证脚本：

```powershell
.\docs\validate-api-docs.ps1
```

该脚本会：
- ✓ 使用 Spectral 验证 OpenAPI 规范
- ✓ 使用 Redocly CLI 打包和验证
- ✓ 统计端点数量
- ✓ 验证必需的标签
- ✓ 生成 Postman 集合

### 3. 生成 Postman 集合

```bash
# 安装工具
npm install -g openapi-to-postman

# 生成集合
openapi2postmanv2 --spec docs/openapi.yaml --output docs/postman/collection.json

# 导入到 Postman
# Postman → Import → File → 选择 collection.json
```

## 📋 端点概览 (33 个端点)

### Organizations (8 个端点)

| 方法 | 路径 | 描述 | 认证 |
|------|------|------|------|
| POST | `/api/v1/organizations` | 创建组织单元 | JWT |
| GET | `/api/v1/organizations` | 列出组织 (分页) | JWT |
| GET | `/api/v1/organizations/:id` | 获取组织详情 | JWT |
| PUT | `/api/v1/organizations/:id` | 更新组织信息 | JWT |
| DELETE | `/api/v1/organizations/:id` | 软删除组织 | JWT |
| POST | `/api/v1/organizations/:id/move` | 移动到新父级 | JWT |
| PATCH | `/api/v1/organizations/:id/status` | 切换状态 | JWT |
| GET | `/api/v1/organizations/:id/tree` | 获取树形结构 | JWT |

### Invitations (5 个端点)

| 方法 | 路径 | 描述 | 认证 |
|------|------|------|------|
| POST | `/api/v1/invitations/create` | 发送邀请 | JWT |
| GET | `/api/v1/invitations/list` | 列出待处理邀请 | JWT |
| DELETE | `/api/v1/invitations/:id/revoke` | 撤销邀请 | JWT |
| GET | `/api/v1/invitations/:id/details` | 获取邀请详情 | JWT |
| POST | `/api/v1/invitations/accept` | 接受邀请并注册 | **公开** |

### Devices - Claim & Transfer (8 个端点)

| 方法 | 路径 | 描述 | 认证 |
|------|------|------|------|
| POST | `/api/v1/devices/claim-code/generate` | 生成认领码 | JWT |
| POST | `/api/v1/devices/claim-code/verify` | 验证认领码 | JWT |
| POST | `/api/v1/devices/:sn/claim` | 认领设备 | JWT |
| POST | `/api/v1/devices/:sn/request-transfer` | 发起转移 | JWT |
| GET | `/api/v1/devices/transfers/list` | 列出转移请求 | JWT |
| POST | `/api/v1/devices/transfers/:id/approve` | 批准转移 | JWT |
| POST | `/api/v1/devices/transfers/:id/reject` | 拒绝转移 | JWT |
| POST | `/api/v1/devices/transfers/:id/cancel` | 取消转移 | JWT |

### Members - Lifecycle (12 个端点)

| 方法 | 路径 | 描述 | 认证 |
|------|------|------|------|
| POST | `/api/v1/members/add` | 添加成员 | JWT |
| PUT | `/api/v1/memberships/:id/update` | 更新成员关系 | JWT |
| DELETE | `/api/v1/memberships/:id/remove` | 移除成员 | JWT |
| PATCH | `/api/v1/memberships/:id/deactivate` | 停用成员 | JWT |
| PATCH | `/api/v1/memberships/:id/reactivate` | 恢复成员 | JWT |
| POST | `/api/v1/members/transfer/initiate` | 发起转移 | JWT |
| POST | `/api/v1/members/transfer/accept` | 接受转移 | JWT |
| POST | `/api/v1/members/transfer/reject` | 拒绝转移 | JWT |
| GET | `/api/v1/members/transfers/list` | 列出待处理转移 | JWT |
| POST | `/api/v1/members/bulk-add` | 批量添加 | JWT |
| POST | `/api/v1/members/bulk-transfer` | 批量转移 | JWT |

## 🔐 认证

所有端点 (除 `/api/v1/invitations/accept`) 都需要 JWT Bearer Token 认证：

```yaml
Authorization: Bearer <jwt_token>
```

Token 通过登录接口获取，有效期 15 分钟。

### 在 Swagger UI 中使用

1. 点击 "Authorize" 按钮
2. 输入：`Bearer <your_jwt_token>`
3. 点击 "Authorize"
4. Token 会自动保存到 localStorage

## 📝 请求/响应示例

### 创建组织

**请求：**
```json
POST /api/v1/organizations
{
  "name": "华南分公司",
  "type": "distributor",
  "parent_id": null
}
```

**响应：**
```json
{
  "id": 123,
  "root_tenant_id": 100,
  "parent_id": null,
  "type": "distributor",
  "name": "华南分公司",
  "status": "active",
  "version": 1,
  "children_count": 0,
  "created_at": "2024-07-22T10:30:00Z",
  "updated_at": "2024-07-22T10:30:00Z"
}
```

### 发送邀请

**请求：**
```json
POST /api/v1/invitations/create
{
  "email": "newuser@example.com",
  "role_id": 3,
  "organization_id": 123,
  "expires_hours": 168
}
```

**响应：**
```json
{
  "id": 456,
  "email": "newuser@example.com",
  "role_name": "Distributor",
  "token_hint": "ABC12345****",
  "expires_at": "2024-07-29T10:30:00Z",
  "created_by": "张三",
  "status": "pending"
}
```

### 生成设备认领码

**请求：**
```json
POST /api/v1/devices/claim-code/generate
{
  "sn": "SN202407220001",
  "expires_hours": 168
}
```

**响应：**
```json
{
  "claim_code": "A1B2C3D4E5F6G7H8",
  "expires_at": "2024-07-29T10:30:00Z",
  "note": "请将此代码告知安装商，有效期 168 小时",
  "sn": "SN202407220001"
}
```

## 🛠 开发指南

### 添加新端点

1. **在 handler 中实现端点**
   ```go
   // business-api/internal/handler/organization_handler.go
   func (h *OrganizationHandler) Create(c *gin.Context) {
       // 实现逻辑
   }
   ```

2. **添加 Swagger 注解**
   ```go
   // business-api/internal/docs/swagger/doc.go
   // @Summary 创建组织单元
   // @Tags Organizations
   // @Accept json
   // @Produce json
   // @Security BearerAuth
   // @Param CreateOrganizationRequest body CreateOrganizationRequest true "Organization data"
   // @Success 201 {object} OrganizationWithChildren
   // @Router /organizations [post]
   func CreateOrganization() {}
   ```

3. **更新 OpenAPI 规范**
   ```yaml
   # docs/openapi.yaml
   paths:
     /organizations:
       post:
         summary: 创建组织单元
         tags: [Organizations]
         # ... 完整定义
   ```

4. **运行验证**
   ```powershell
   .\docs\validate-api-docs.ps1
   ```

### 生成 Swagger 文档

```bash
# 安装 swag
go install github.com/swaggo/swag/cmd/swag@latest

# 生成文档
cd business-api
swag init --parseDependency --generalInfo cmd/main.go --output internal/docs/swagger
```

## 🔄 CI/CD 集成

GitHub Actions 工作流会在以下情况自动验证：

- **Push 到 main/develop 分支**
- **Pull Request 包含文档更改**
- **手动触发**

### 检查项

1. ✓ OpenAPI 规范语法验证 (Spectral)
2. ✓ 端点覆盖率检查
3. ✓ 必需标签验证
4. ✓ 示例完整性检查
5. ✓ Go Swagger 注解编译
6. ✓ Postman 集合生成

### 部署

合并到 `main` 分支后，文档会自动部署到 GitHub Pages：

```
https://<username>.github.io/<repository>/docs/swagger/
```

## 📊 Schema 定义

### OrganizationType

```yaml
type: string
enum:
  - manufacturer    # 制造商
  - agent           # 代理商
  - distributor     # 分销商
  - customer        # 客户
  - service_partner # 服务商
```

### MembershipStatus

```yaml
type: string
enum:
  - active      # 活跃
  - inactive    # 停用
  - suspended   # 暂停
  - revoked     # 已撤销
```

### InvitationStatus

```yaml
type: string
enum:
  - pending   # 待处理
  - used      # 已使用
  - expired   # 已过期
  - revoked   # 已撤销
```

### TransferStatus

```yaml
type: string
enum:
  - pending    # 待处理
  - approved   # 已批准
  - rejected   # 已拒绝
  - cancelled  # 已取消
```

## 🚨 错误响应

所有错误遵循统一格式：

```json
{
  "code": "ERROR_CODE",
  "message": "错误描述",
  "details": {}
}
```

### 常见错误码

| 状态码 | 错误码 | 描述 |
|--------|--------|------|
| 400 | `BAD_REQUEST` | 请求参数无效 |
| 401 | `UNAUTHORIZED` | 未认证或 Token 无效 |
| 403 | `FORBIDDEN` | 权限不足 |
| 404 | `NOT_FOUND` | 资源不存在 |
| 409 | `CONFLICT` | 冲突 (重复、配额、循环引用) |
| 500 | `INTERNAL_ERROR` | 服务器内部错误 |

## 📈 版本历史

### v1.0.0 (当前版本)

- ✓ 33 个多级渠道平台端点
- ✓ 完整的 OpenAPI 3.0 规范
- ✓ Swagger UI 交互式文档
- ✓ Postman 集合支持
- ✓ CI/CD 自动验证

### v2.0.0 (计划中)

- 增强批量操作
- 实时推送通知
- WebSocket 支持

## 🔗 相关资源

- [OpenAPI 规范](https://spec.openapis.org/oas/v3.0.3)
- [Swagger UI](https://swagger.io/tools/swagger-ui/)
- [Redocly CLI](https://redocly.com/docs/cli/)
- [Spectral Linter](https://stoplight.io/open-source/spectral)

## 💡 最佳实践

1. **始终提供示例** - 每个端点都应该有请求/响应示例
2. **使用统一错误格式** - 所有错误使用 ErrorResponse schema
3. **标注认证要求** - 明确哪些端点需要 JWT
4. **保持向后兼容** - 避免破坏性变更
5. **定期验证** - 每次提交前运行验证脚本

## 📞 支持

如有问题或建议，请联系：

- Email: support@csergy.com
- Documentation: https://csergy.com/docs

---

*最后更新：2024-07-22*
