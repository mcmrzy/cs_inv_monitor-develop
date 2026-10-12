# Hardware Compatible OTA Implementation Plan

> **For agentic workers:** REQUIRED: Use subagent-driven-development to implement independent tasks with review. Preserve pre-existing edits; no automatic commit, deployment, database migration against production, or device flashing.

**Goal:** 为相同型号的不同硬件提供准确的固件选择及防误刷检查。

**Architecture:** 标准硬件目录 + 固件显式兼容关联，后端所有执行路径统一校验，Web 用标准多选管理范围，App 缓存范围并在本地 OTA 检查真实 INFO。第一阶段保持签名 V1，设备端 V2 作为明确的后续协议。

**Tech Stack:** Go/Gin/pgx, PostgreSQL, React/Ant Design, Flutter/Dart.

## Chunk 1: 后端和数据库

- [x] 测试先行：硬件空值、不匹配、兼容多版本、强制操作不能绕过。
- [x] 新增 migration 129 和 schema：标准目录、固件关联、关联冲突约束、历史硬件快照；不自动给旧固件开放范围。
- [x] model/repository/service/handler 实现目录、兼容选择、范围补录及审计；注册受权限保护路由。
- [x] 将资源、最新版本、任务创建、重试、回退、实际下发接到统一检查，并记录任务硬件快照。
- [x] 独立 PostgreSQL 测试验证两个硬件相同软件版本文件、冲突、所有关键执行边界。

## Chunk 2: Web（独立 agent）

- [x] firmwareUpload.test.ts 先验证范围序列化，再实现多选上传和目录增加。
- [x] services/otaApi.ts、types、locales、pages/ota 实现硬件字段、筛选、发布展示、历史固件补录。
- [x] 设备详情/升级交互展示未知硬件或无兼容固件原因；批量设备选择只接受固件支持硬件。
- [x] npm run test:run -- src/pages/ota src/services/otaApi.test.ts；npm run build:check。

## Chunk 3: App（独立 agent）

- [x] 本地 OTA 测试先验证缺硬件/范围与不兼容被阻止。
- [x] 下载、缓存、元数据解析全链路传递 hardware_versions；缓存恢复后继续严格判断。
- [x] 设备概览与本地升级展示硬件状态和原因，并保留功能模块中文命名。
- [x] flutter test 定向 OTA/下载测试；flutter analyze --no-pub（零 error/warning，现有 info 未清理；默认退出码为 1）。

## Chunk 4: 集成和审查

- [x] 分别做规格合规与代码质量检查，修复实际发现的问题。
- [x] Go 所有服务 build/test/vet，Web build/typecheck，Flutter analyze/test（静态分析零 error/warning，既有 info 保留）。
- [x] 写明 migration/backfill 使用步骤、签名 V2 设备端改造契约及未完成的实机验收。

最后一轮验证已完成：四个 Go 服务各自 build/test/vet 退出码均为 0；升级包硬件元数据新增断言及 12 项 PostgreSQL 集成测试通过；Web 71 项及类型检查/构建通过；App 136 项及全项目 analyze（--no-fatal-infos）通过。日志保存于 `.tmp/hardware-ota-verification/`。尚未执行生产迁移、部署、刷写和实机验收。
