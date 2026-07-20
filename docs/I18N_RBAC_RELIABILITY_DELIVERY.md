# 多语言、权限与可靠性改造交付说明

最后更新：2026-07-20

## 1. 交付目标

本次改造面向逆变器监控平台的实际商用场景，覆盖以下目标：

- Web 与 App 的中英文文案保持一致，避免缺失 key、硬编码文案和占位符不匹配。
- 代理商、安装商、终端用户按组织层级、设备归属和显式授权访问数据。
- 工单形成可派单、可升级、可审计、可幂等重试的业务闭环。
- OTA、MQTT、Kafka 和告警链路在并发、失败和服务重启场景下保持可恢复。
- 网关与 API 采用服务端身份、权限和对象范围校验，客户端不能伪造身份头或角色。
- 部署配置不再内置生产密钥，并提供可执行的验证与回滚边界。

## 2. 角色与数据范围

角色编号沿用 `users.role`：

| 角色 | 数据可见范围 | 可操作范围 |
|---|---|---|
| 0：超级管理员 | 全局 | 全局；固件删除、全局发布、App 灰度等高危操作 |
| 1–3：代理体系 | 本人及组织树后代的设备、站点、人员、告警和工单 | 仅操作组织树或设备授权范围内的对象 |
| 4：安装商 | 本人拥有、安装指派或显式授权的设备；本人站点；参与工单 | 仅修改本人创建或当前指派给自己的工单及授权设备 |
| 5：终端用户 | 本人设备、站点、通知和本人创建的工单 | 仅操作本人对象；不能通过设备可见权修改他人工单 |

核心数据范围由以下视图统一提供：

- `v_user_hierarchy`：最多 32 层的用户组织树，并防止循环关系。
- `v_user_device_access`：代理层级、安装指派、设备所有者和显式授权的统一设备范围。
- `v_user_station_access`：按设备和用户归属推导站点范围。

对象级权限规则：

1. RBAC 只判断某角色是否具备某类能力。
2. Handler/Service 再判断具体设备、站点、工单、通知或 OTA 任务是否属于当前用户范围。
3. 批量操作采用“全部校验后执行”，请求中只要包含一个越权设备就整体拒绝。
4. 通知可以按设备业务范围查看，但删除和清空只能作用于当前用户自己的通知。

## 3. 请求与身份链路

```text
客户端
  -> API Gateway：限流、请求体限制、JWT、会话撤销、RBAC、身份头清理
  -> API Server：权限能力、对象级范围、参数校验、业务状态机
  -> PostgreSQL：层级视图、事务锁、幂等约束、审计数据
  -> Device Server：MQTT 命令队列、离线持久化、消息确认
  -> MQTT/Kafka：分片消费、背压、重试、DLQ、有序提交
```

安全约束：

- Access Token 与 Refresh Token 使用不同的 `token_type`，不能互换。
- JWT 必须包含合法的 `jti`、用户、角色、签发时间、过期时间和签发方。
- 刷新令牌采用单次使用策略，重复使用会被拒绝。
- 修改密码、角色、状态或删除用户后，同步写入会话撤销时间；旧 Access/Refresh Token 立即失效。
- 网关先删除客户端传入的 `X-User-*` 身份头，再注入已验证身份。
- 网关从 Redis/PostgreSQL 获取当前角色，不使用客户端 JWT 中的角色直接做最终授权。

## 4. 业务功能

### 4.1 工单

工单状态机：

```text
open -> in_progress | closed
in_progress -> open | resolved | closed
resolved -> in_progress | closed
closed -> 终态
```

业务规则：

- 设备报障优先分配给设备安装商。
- 安装商创建现场任务时默认分配给自己。
- 无设备的终端用户报障流转给直属上级。
- 升级工单优先转交当前处理人的上级。
- 创建、状态变化和升级支持 `Idempotency-Key`；同一键但请求内容不同返回冲突。
- 更新支持 `expectedVersion` 乐观锁，避免并发覆盖。
- 状态、派单、升级、附件和删除均写入时间线及审计记录。
- 附件最多累计 5 个，每个不超过 10 MB；校验实际图片类型、随机文件名和私有下载权限。

### 4.2 OTA

- 任务通过数据库条件更新从 `pending/scheduled` 原子切换到 `running`，重复执行只能成功一次。
- 执行和重试采用固定大小工作池，不按设备无限创建 goroutine。
- 运行中的任务不能被伪装为已取消或直接删除。
- 命令序列化、HTTP 创建、网络请求和非 2xx 响应失败都会写回设备升级记录。
- 只有任务仍为 `running` 时，才允许写入 `completed/partial_success/failed` 终态。
- `device_upgrades.task_id` 新增外键并使用 `ON DELETE CASCADE`；历史记录先以 `NOT VALID` 方式兼容上线。
- 升级包回滚只查询当前用户设备范围内的成功记录；动态授予 `ota:control` 不会扩大为全局回滚。

### 4.3 设备、告警与消息链路

- MQTT 入站消息按主题分片，使用有界队列和手动确认。
- 离线命令写入 Redis，恢复连接后重放。
- Kafka 桥按分区维护有界队列，失败进入重试或 DLQ，成功后再提交 offset。
- 告警消费失败不确认消息；告警事件使用数据库唯一约束避免重复写入。
- 设备控制、告警确认、通知、天气、Dashboard 和统计接口均使用服务端设备范围。

## 5. 多语言

Web 端：

- 中英文目录 key 集合一致。
- 插值变量集合一致。
- 生产代码中的字面量 `t()` key 必须存在。
- 英文目录不能混入中文用户文案。
- 登录页覆盖真实英文渲染，并同步切换 Ant Design locale。

App 端：

- 补齐告警、通知、OTA、Wi-Fi 配网、设备实时数据和设置页文案。
- Locale 与角色服务在启动时注册，并持久化用户语言选择。
- 中英文资源增加 parity 测试。

## 6. 数据库迁移

| 版本 | 内容 |
|---|---|
| 059 | 基于 develop 现有表结构建立用户层级、设备范围和站点范围视图 |
| 060 | 在对象级范围校验基础上增补安装商、终端用户业务操作权限 |
| 061 | 扩展 UUID 工单模型的乐观锁、幂等键、升级时间和持久化模板 |
| 062 | OTA 任务与设备升级记录外键（先以 `NOT VALID` 接入） |

每个版本均提供 `.up.sql` 和 `.down.sql`。迁移器按数字版本排序，并通过 `schema_migrations` 防止重复执行。

## 7. 配置与部署

### 7.1 上线前

1. 备份 PostgreSQL 和 Redis。
2. 在部署环境配置 `DB_PASSWORD`、`REDIS_PASSWORD`、`JWT_SECRET`、`INTERNAL_KEY`、MQTT、短信和推送密钥。
3. 不要把真实密钥写入 `deploy/.env` 或镜像。
4. 确认 PostgreSQL 中不存在需要人工保留的历史 OTA 孤儿记录，再择机执行：

```sql
ALTER TABLE device_upgrades VALIDATE CONSTRAINT fk_device_upgrades_task;
```

### 7.2 推荐顺序

```text
数据库迁移
  -> Redis / MQTT / Kafka
  -> Device Server / MQTT-Kafka Bridge
  -> API Server
  -> API Gateway
  -> Web / App
```

### 7.3 健康检查

- Gateway、API、Device Server 的健康接口必须返回成功。
- API 依赖异常时健康接口返回 503，不能只报告进程存活。
- 使用代理商、安装商、终端用户测试账号分别验证设备列表、站点、工单和越权请求。
- 验证旧令牌在角色或密码变化后返回 401。
- 验证包含一个越权设备的批量操作整体返回 403。

## 8. 验证记录

合并前门禁使用以下命令：

```powershell
# 四个 Go 模块
go test ./...
go vet ./...

# Web
node node_modules/vitest/vitest.mjs run
node node_modules/typescript/bin/tsc -b
node node_modules/vite/bin/vite.js build

# 部署配置
docker compose -f deploy/docker-compose.test.yml config --quiet
```

已覆盖：

- API、Gateway、Device Server、MQTT-Kafka Bridge 全量测试。
- Go 静态检查。
- Web 多语言、权限 UI、工单和服务调用测试。
- TypeScript 编译及 Vite 生产构建。
- 并发、背压和 JWT/SN 基准测试。
- Compose 配置解析和补丁格式检查。

未覆盖：

- 真实 PostgreSQL 迁移和容器化端到端测试。
- 真实 MQTT 设备压力测试。
- Windows 环境的 Go race detector（缺少 CGO/C 编译器）。
- App 的本轮 Flutter/Dart 复测（当前环境无 Flutter/Dart 命令）。

## 9. 回滚

1. 先回滚应用镜像，避免旧代码继续写入新状态。
2. 按 `062 -> 059` 的顺序评估并执行 `.down.sql`。
3. 工单、告警规则等迁移包含业务数据，执行 down 前必须单独备份相关表。
4. 回滚 JWT/会话机制后，建议清空登录会话并要求用户重新登录。
5. 回滚 MQTT/Kafka 消费逻辑前，确认队列、重试主题和 DLQ 中没有未处理消息。

## 10. 本次合并边界

本次 develop 集成以其现有 UUID 工单、Timescale 告警、签名 OTA 和设备协议实现为基线，只移植本轮多语言、权限与归属、工单可靠性、网关安全和相应文档/测试改动；没有用 main 的旧架构覆盖 develop 后续能力。

合并采用独立提交的 cherry-pick 方式，不合并当前工作树基线上的其他历史提交；目标主分支中已有的商业发布改造和未跟踪资源文件保持不变。
