# 设备OTA升级功能整体重构方案

## Context

当前管理后台OTA升级功能存在明显混乱：
- **"升级管理"** 和 **"升级包管理"** 两套升级路径重叠，用户不知该用哪个
- "升级管理"推送即升级（`immediate` 默认 `true`），缺乏任务调度和确认环节
- 固件管理、升级管理、升级包管理三个概念交叉，信息架构不清晰

目标：统一升级流程，建立清晰的"创建任务 → 配置策略 → 执行升级"流程，消除二义性。

---

## 新页面结构（3 Tab 替代 4 Tab）

```
OTA管理
├── Tab 1: 升级任务         ← 统一操作入口（替代旧"升级管理"+"升级包管理"）
├── Tab 2: 固件库           ← 资产管理（合并旧"固件管理"+"升级包组合"）
└── Tab 3: App版本管理      ← 保持不变
```

### Tab 1: 升级任务

以"升级任务"为核心概念，统一所有升级操作。

**页面布局：**
- 顶部统计栏：待执行 / 进行中 / 今日完成 / 失败 任务数
- 任务列表表格：任务名称、升级类型（单芯片/升级包）、目标设备数、进度条、状态、创建人、时间
- 操作：创建升级任务（主按钮）、执行、取消、重试失败、删除

**创建升级任务 - 向导式表单（3步）：**

| 步骤 | 内容 |
|------|------|
| Step 1: 选择升级内容 | 升级类型（单芯片固件 / 升级包）→ 选型号 → 选具体固件或升级包 |
| Step 2: 选择目标设备 | 按型号筛选设备列表，全选/手动选择，显示当前版本vs目标版本对比 |
| Step 3: 执行策略 | 执行方式（立即/定时/手动）+ 灰度比例 + 确认汇总 |

**任务状态机：**
```
draft（草稿）→ pending（待执行）/ scheduled（定时等待）
pending/scheduled → running（执行中）
running → completed / partial_success / failed
任意非终态 → cancelled
failed → pending（重试）
```

### Tab 2: 固件库

合并"固件管理"和"升级包组合"为一个资产管理页，两个子区域：
- **区域A - 固件文件**：上传/删除各芯片固件（保持现有 FirmwareTab 功能）
- **区域B - 升级包组合**：创建/删除升级包（型号 + 各芯片固件组合模板，保持现有 PackagesTab 功能，但去掉推送按钮）

### Tab 3: App版本管理

保持现有功能不变。

---

## 数据库调整

### 新增 `upgrade_tasks` 表（migration 009）

```sql
CREATE TABLE upgrade_tasks (
    id              BIGSERIAL PRIMARY KEY,
    name            VARCHAR(200) NOT NULL DEFAULT '',
    task_type       VARCHAR(20) NOT NULL,        -- 'single' | 'package'
    firmware_id     BIGINT,                       -- 单芯片模式
    package_id      BIGINT,                       -- 升级包模式
    model           VARCHAR(100) NOT NULL,
    target_version  VARCHAR(50) NOT NULL DEFAULT '',
    status          VARCHAR(20) NOT NULL DEFAULT 'draft',
    execute_mode    VARCHAR(20) NOT NULL DEFAULT 'manual', -- 'immediate'|'scheduled'|'manual'
    scheduled_at    TIMESTAMP,
    rollout_percent INTEGER NOT NULL DEFAULT 100,
    total_devices   INTEGER NOT NULL DEFAULT 0,
    success_count   INTEGER NOT NULL DEFAULT 0,
    failed_count    INTEGER NOT NULL DEFAULT 0,
    created_by      BIGINT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    executed_at     TIMESTAMP,
    completed_at    TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);
```

### 修改 `device_upgrades` 表

```sql
ALTER TABLE device_upgrades ADD COLUMN task_id BIGINT;
CREATE INDEX idx_du_task_id ON device_upgrades(task_id);
```

### 保留的表

`firmware_versions`、`upgrade_packages`、`upgrade_package_items` 均保持不变。`device_upgrades` 的现有字段全部保留，新增 `task_id` 关联升级任务。

---

## 后端改动

### 新增 API 路由

| 方法 | 路由 | 说明 |
|------|------|------|
| GET | `/ota/tasks` | 升级任务列表（分页+状态筛选） |
| POST | `/ota/tasks` | 创建升级任务（统一入口） |
| GET | `/ota/tasks/:id` | 任务详情 |
| POST | `/ota/tasks/:id/execute` | 手动执行任务 |
| POST | `/ota/tasks/:id/cancel` | 取消任务 |
| POST | `/ota/tasks/:id/retry` | 重试失败设备 |
| DELETE | `/ota/tasks/:id` | 删除任务 |
| GET | `/ota/tasks/:id/devices` | 任务下设备升级详情 |

### Service 层核心改动

新增 `CreateUpgradeTask` 统一方法：
- 选择单芯片固件 → 内部创建 `task_type='single'` 任务
- 选择升级包 → 内部创建 `task_type='package'` 任务
- 如果 `execute_mode='immediate'` → 创建后自动调用 ExecuteTask
- 如果 `execute_mode='scheduled'` → 创建定时任务
- 如果 `execute_mode='manual'` → 等待手动触发

新增 `ExecuteTask` 方法：
- 将 pending 任务转为 running
- 单芯片模式：复用现有 `PushUpgrade` 逻辑
- 升级包模式：复用现有 `PushPackageUpgrade` 逻辑（逐芯片链式升级 + `OnChipUpgradeComplete`）

保留：`OnChipUpgradeComplete`、`RollbackPackageUpgrade`、`SendUpgradeCommand` 等核心逻辑不变。

旧接口（`/ota/upgrades/push`、`/ota/packages/push`）保留兼容但标记 deprecated。

---

## 需要修改的文件清单

### 后端

| 文件 | 改动 |
|------|------|
| `database/migrations/009_upgrade_tasks.up.sql` | **新建**：创建 upgrade_tasks 表，device_upgrades 新增 task_id |
| `inv_api_server/internal/model/models.go` | 新增 UpgradeTask 结构体，DeviceUpgrade 新增 TaskID |
| `inv_api_server/internal/repository/ota_repository.go` | 新增 upgrade_tasks CRUD，修改 Upsert 支持 task_id |
| `inv_api_server/internal/service/ota_service.go` | 新增 CreateUpgradeTask + ExecuteTask 统一方法 |
| `inv_api_server/internal/handler/ota_handler.go` | 新增任务相关 handler |
| `inv_api_server/cmd/main.go` | 新增 `/ota/tasks` 路由 |

### 前端

| 文件 | 改动 |
|------|------|
| `inv-admin-frontend/src/pages/ota/index.tsx` | **重写**：3 Tab + 升级任务向导 + 任务列表 |
| `inv-admin-frontend/src/services/otaApi.ts` | 新增任务相关 API 方法 |
| `inv-admin-frontend/src/locales/ota.ts` | 新增任务相关国际化文案 |
| `inv-admin-frontend/src/types/index.ts` | 新增 UpgradeTask 类型 |

### 移动端（Flutter App）

**无需改动**。App 调用的 `/ota/check/:sn` 和 `/ota/trigger` 接口保持兼容。

---

## 实施计划

### Task 1: 数据库 migration
- 新建 `009_upgrade_tasks.up.sql`
- 创建 upgrade_tasks 表，device_upgrades 新增 task_id 列

### Task 2: 后端 Model + Repository
- 新增 UpgradeTask 结构体
- 新增 Repository 层 CRUD 方法

### Task 3: 后端 Service 层
- 新增 CreateUpgradeTask 统一创建方法
- 新增 ExecuteTask 执行方法（复用现有推送逻辑）
- 新增 ListUpgradeTasks / GetUpgradeTaskDetails 查询方法

### Task 4: 后端 Handler + 路由
- 新增任务相关 HTTP handler
- 注册新路由

### Task 5: 前端重写
- 重写 OTA 页面为 3 Tab 结构
- 实现升级任务创建向导（Steps 组件）
- 实现任务列表 + 详情抽屉
- 固件库 Tab 合并固件管理 + 升级包组合

### Task 6: 前端 API + 国际化
- 新增 otaApi 任务方法
- 补充国际化文案

### Task 7: 验证测试
- 创建单芯片升级任务 → 手动执行 → 确认设备收到命令
- 创建升级包任务 → 立即执行 → 确认逐芯片链式升级
- 灰度推送 → 确认只推送到选定比例的设备
- 取消/重试任务

---

## 关键设计决策

| 决策 | 理由 |
|------|------|
| 升级包作为"模板"而非"任务" | 升级包只定义固件组合，可被多个任务复用 |
| 保留 device_upgrades 表 | 是设备升级状态的真实来源，新增 task_id 关联即可 |
| execute_mode 三种模式 | 覆盖立即升级、定时升级、审批后手动升级等场景 |
| 旧接口保留兼容 | App 端和现有调用方无需修改 |
| MQTT 命令格式不变 | 设备端固件无需任何改动 |
