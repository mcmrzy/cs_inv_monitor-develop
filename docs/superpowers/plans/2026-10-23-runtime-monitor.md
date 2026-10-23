# Runtime Monitor Implementation Plan

**Goal:** 系统管理员可在系统监控查看脱敏业务 API 异常及实际数据库字段状态。

**Architecture:** Gin 捕获错误，Redis 有界保存；Handler → Service → Repository 查询并聚合，独立检查 PostgreSQL 实际字段；React 展示可筛选异常和结构检查。

**Tech Stack:** Go/Gin/pgx/Redis、React/TypeScript/Ant Design、miniredis/Vitest。

## 实施与验证

- [x] 新增 model/runtime_monitor.go、repository/runtime_monitor_repository.go 及测试：有界 Redis、过期、原子写入、字段存在/类型判定。
- [x] 新增 service/runtime_monitor_service.go 及测试：重复合并、样本计数、依赖不可用的 unknown 状态。
- [x] 新增 middleware/runtime_monitor.go 及测试：5xx/业务码/panic、脱敏、服务端 request ID、保存失败不影响响应。
- [x] 接入 response 错误原因、电站查询错误、启动中间件及管理员只读端点；新增 handler/runtime_monitor_handler.go 与鉴权测试；网关注册转发。
- [x] 新增 RuntimeErrorsTab.tsx 及行为测试；接入 API/国际化/系统监控页签，验证非系统管理员无入口、读取失败不显示零。
- [x] 执行 Go build/vet/test（四服务）、Web 类型/构建/定向 lint/测试；记录环境或既有工作区问题。
- [x] 检查差异、脱敏和改动边界，更新本文件验收状态；保留现有无关修改，生产不部署。

所有测试先运行失败用例，再实现。阶段交付需区分本地验证与生产发布；全量日志历史不会因新增采集自动补齐。

## 本地验证记录（2026-10-23）

- 四个 Go 模块分别执行 `go build ./...`、`go vet ./...`、`go test ./... -count=1 -timeout=120s`，全部退出 0。
- `go test -tags=integration ./internal/handler -run TestRuntimeMonitorPostgresMissingColumn -count=1` 通过：本机 PostgreSQL 17 隔离库重现实际 42703、请求 ID 与管理端记录对应；迁移已登记仍判定缺列；仅测试库补列后结构变为 ok。临时实例已停止。
- 专用 Redis 客户端多阶段延迟测试通过：每段 80ms 的握手/初始化/命令受共同 200ms 期限约束；持续写入时清除超过 24h 的旧数据；容量 1000。
- Web `tsc -b --pretty false`、Vite 生产构建、定向 ESLint 均退出 0。ESLint 有 4 条原有未使用变量警告；Vite 有现有大 chunk 提示。
- Vitest 线程池单 worker 执行 RuntimeErrorsTab 与 SystemPages 两个文件，13 项通过；包含普通组织管理员不请求接口、连接卡片正常仍显示结构异常。jsdom 存在既有 getComputedStyle 提示。
- 独立只读评审发现并修复网关注册、写出响应后 panic、Redis 总期限和按年龄清理四项，复核未发现新 P1/P2。
- 本轮行为验证与最小精简检查已完成：复用现有 API、认证、时区、日志和响应工具；未增加部署组件或数据库日志表。
- 将待提交索引导出到独立快照后，business-api 与 api-gateway 构建及相关监控/路由测试通过，前端类型检查通过；确认本次提交不依赖工作区其余未提交改动。

## 交付边界

首期仅采集 business-api 新发生的请求异常，数据库结构检查只覆盖当前电站读取依赖。尚未在浏览器与生产进行验收，不导入历史服务器日志，不修复生产缺列，不触发生产部署。保留工作区其余 App/OTA/设备通信等既有改动；未写入记忆。
