# 辰烁科技光伏逆变器管理后台 — 导航重构设计文档

## 一、现状问题总结

### 1.1 侧边栏导航结构（当前）

```
Admin 视角:
├── 概览
│   ├── 仪表盘        [5个内部tab: 总览/发电统计/设备数据/操作日志/数据对比]
│   └── 大屏监控
├── 实时监控
│   ├── 电站监控      [5个内部tab: 运行参数/曲线对比/发电统计/历史数据/历史事件]
│   └── 设备管理
├── 数据分析
│   └── 电量统计      ← 只有1个子项，分组无意义
├── 站点管理
│   ├── 电站管理
│   ├── 型号管理
│   ├── 用户管理      ← 与"站点"无关
│   └── 操作记录
├── 维护售后          ← 塞了7个不相关功能，成了垃圾桶
│   ├── 远程设置
│   ├── 批量设置
│   ├── OTA升级
│   ├── 告警管理      [3个内部tab: 告警记录/告警规则/工单管理]
│   ├── 告警规则      ← 与告警管理内部tab重复
│   ├── 工单管理      ← 与告警管理内部tab重复
│   └── 并机管理      ← 不属于"售后"
└── 系统管理          ← 独立顶级菜单，但内部6个tab混装
```

### 1.2 具体问题清单

| # | 问题 | 影响 |
|---|------|------|
| P1 | **「维护售后」过度膨胀** — 7个子项跨越设备配置、固件管理、告警、工单、并机5个业务域 | 用户找不到功能，认知负担高 |
| P2 | **页面功能重复** — `/alerts` 内嵌了告警规则和工单tab，侧边栏又有独立的 `/alert-rules` 和 `/work-orders` | 用户困惑"去哪里操作" |
| P3 | **仪表盘操作日志重复** — dashboard 内有"操作日志"tab，又有独立 `/operation-logs` 页面 | 两处日志，数据可能不一致 |
| P4 | **发电统计出现在3处** — dashboard、monitoring、analytics 都有"发电统计" | 入口混乱 |
| P5 | **「站点管理」混搭** — 用户管理和操作记录与站点无逻辑关系 | 分类不符合心智模型 |
| P6 | **「数据分析」只有1个子项** — 单独分组浪费空间 | 不必要的层级 |
| P7 | **「实时监控」混搭** — 电站监控(实时可视化)和设备管理(CRUD)是不同场景 | 监控和管理混淆 |
| P8 | **并机管理归类错误** — 放在"维护售后"下，但并机是设备组织方式 | 语义不匹配 |

---

## 二、重构目标

1. **按用户心智模型分组** — 每个分组对应一个明确的业务场景
2. **消除功能重复** — 每个功能只有一个入口
3. **控制分组粒度** — 每组 2-4 个子项，避免过大或过小
4. **保持向后兼容** — 路由路径不变，仅调整菜单结构和页面内部tab

---

## 三、新导航结构设计

### 3.1 Admin 菜单（SUPER_ADMIN / AGENT）

```
📊 概览 (Overview)                              [DashboardOutlined]
├── /dashboard        仪表盘                     [DashboardOutlined]
│   内部tab: 总览 / 发电统计 / 设备数据 / 数据对比
│   ❌ 删除"操作日志"tab → 统一到 /operation-logs
└── /big-screen       大屏监控                    [FundViewOutlined]

📡 监控中心 (Monitoring Center)                   [RadarChartOutlined]
├── /monitoring       电站监控                    [ThunderboltOutlined]
│   内部tab: 运行参数 / 曲线对比 / 历史数据 / 历史事件
│   ❌ 删除"发电统计"tab → 统一到 /analytics
└── /devices          设备管理                    [DesktopOutlined]

📈 数据分析 (Data Analytics)                      [BarChartOutlined]
├── /analytics        发电统计                    [LineChartOutlined]
└── /operation-logs   操作记录                    [UnorderedListOutlined]

🏗️ 站点管理 (Site Management)                    [EnvironmentOutlined]
├── /stations         电站管理                    [EnvironmentOutlined]
├── /models           型号管理                    [ExperimentOutlined]
└── /parallel         并机管理                    [ClusterOutlined]

⚠️ 告警工单 (Alerts & Orders)                     [AlertOutlined]
├── /alerts           告警中心                    [AlertOutlined]
│   内部tab: 仅保留"告警记录"
│   ❌ 删除"告警规则"和"工单管理"tab
├── /alert-rules      告警规则                    [SafetyOutlined]
└── /work-orders      工单管理                    [FileTextOutlined]

🔧 设备运维 (Device O&M)                          [ToolOutlined]
├── /remote-settings  远程设置                    [ControlOutlined]
├── /batch-settings   批量设置                    [EditOutlined]
└── /ota              OTA升级                     [CloudUploadOutlined]

⚙️ 系统管理 (System Admin)                        [SettingOutlined]  [仅SUPER_ADMIN]
├── /admin            系统配置                    [SettingOutlined]
│   内部tab: 系统健康 / 租户管理 / 系统配置 / 系统配额 / 权限配置
│   ❌ 删除"审计日志"tab → 统一到 /operation-logs
└── /users            用户管理                    [TeamOutlined]
```

### 3.2 User 菜单（INSTALLER / END_USER）

```
📊 概览 (Overview)
└── /dashboard        仪表盘

📡 监控中心 (Monitoring Center)
├── /monitoring       电站监控
└── /devices          设备管理

📈 数据分析 (Data Analytics)
├── /analytics        发电统计
└── /operation-logs   操作记录

🏗️ 站点管理 (Site Management)
└── /stations         电站管理

⚠️ 告警工单 (Alerts & Orders)
├── /alerts           告警中心
├── /alert-rules      告警规则
└── /work-orders      工单管理

🔧 设备运维 (Device O&M)
└── /remote-settings  远程设置

🏠 我的电站 (My Portal)                          [HomeOutlined]
└── /portal           电站概览
```

---

## 四、变更明细

### 4.1 侧边栏菜单变更 (`MainLayout.tsx`)

| 变更类型 | 具体操作 |
|----------|----------|
| **移动** | `用户管理` 从「站点管理」→「系统管理」 |
| **移动** | `并机管理` 从「维护售后」→「站点管理」 |
| **移动** | `操作记录` 从「站点管理」→「数据分析」 |
| **拆分** | 「维护售后」拆为「告警工单」(告警/告警规则/工单) + 「设备运维」(远程设置/批量设置/OTA) |
| **删除分组** | 「数据分析」改为1级菜单组，不再是只有1个子项的空壳 |
| **重命名** | `告警管理` → `告警中心` (因为不再包含规则和工单) |
| **重命名** | `系统管理` 菜单项 → `系统配置` (区分菜单组名和页面名) |

### 4.2 页面内部tab清理

#### `/alerts` 告警页面
- **当前**: 3个tab (告警记录 / 告警规则 / 工单管理)
- **改为**: 只保留「告警记录」，删除嵌入的 `AlertRulesPage` 和 `WorkOrderTab`
- **涉及文件**: `inv-admin-frontend/src/pages/alerts/index.tsx`
- **删除**: Lines 79-80 中的 rules 和 workorders tab 项
- **删除**: 导入 `AlertRulesPage` 和 `WorkOrderTab` 组件

#### `/dashboard` 仪表盘
- **当前**: 5个tab (总览 / 发电统计 / 设备数据 / 操作日志 / 数据对比)
- **改为**: 4个tab (总览 / 发电统计 / 设备数据 / 数据对比)
- **涉及文件**: `inv-admin-frontend/src/pages/dashboard/index.tsx`
- **删除**: Line 980 中的 logs tab 项及 `renderLogs()` 函数

#### `/monitoring` 电站监控
- **当前**: 5个tab (运行参数 / 曲线对比 / 发电统计 / 历史数据 / 历史事件)
- **改为**: 4个tab (运行参数 / 曲线对比 / 历史数据 / 历史事件)
- **涉及文件**: `inv-admin-frontend/src/pages/monitoring/index.tsx`
- **删除**: Line 1126 中的 energy tab 项及 `renderEnergyStats()` 函数

#### `/admin` 系统管理
- **当前**: 6个tab (审计日志 / 系统健康 / 租户管理 / 系统配置 / 系统配额 / 权限配置)
- **改为**: 5个tab (系统健康 / 租户管理 / 系统配置 / 系统配额 / 权限配置)
- **涉及文件**: `inv-admin-frontend/src/pages/admin/index.tsx`
- **删除**: Line 72 中的 audit tab 项及 `AuditLogTab` 组件

### 4.3 不变的部分

| 项目 | 说明 |
|------|------|
| 路由路径 | 所有 `/xxx` 路径保持不变 |
| 页面组件 | 不移动、不重命名组件文件 |
| 权限系统 | permission 字段不变 |
| Portal 页面 | `/portal/*` 路由和页面不变 |
| 移动端 | Flutter App 导航不受影响 |

---

## 五、实施步骤

### Step 1: 修改 `MainLayout.tsx` — 菜单结构
重写 `adminMenuItems` 和 `userMenuItems` 数组

### Step 2: 清理 `/alerts` 页面
移除嵌入的告警规则和工单tab，只保留告警记录

### Step 3: 清理 `/dashboard` 页面
移除操作日志tab和 `renderLogs()` 函数

### Step 4: 清理 `/monitoring` 页面
移除发电统计tab和 `renderEnergyStats()` 函数

### Step 5: 清理 `/admin` 页面
移除审计日志tab和 `AuditLogTab` 组件

### Step 6: 验证
- 检查所有菜单项路由可达
- 检查权限过滤正常
- 确认删除的tab功能在对应独立页面中完整存在

---

## 六、新旧对照表

| 功能 | 旧位置 | 新位置 |
|------|--------|--------|
| 仪表盘 | 概览 > 仪表盘 | 概览 > 仪表盘 ✅ 不变 |
| 大屏监控 | 概览 > 大屏监控 | 概览 > 大屏监控 ✅ 不变 |
| 电站监控 | 实时监控 > 电站监控 | 监控中心 > 电站监控 |
| 设备管理 | 实时监控 > 设备管理 | 监控中心 > 设备管理 |
| 发电统计 | 数据分析 > 电量统计 | 数据分析 > 发电统计 |
| 操作记录 | 站点管理 > 操作记录 | 数据分析 > 操作记录 |
| 电站管理 | 站点管理 > 电站管理 | 站点管理 > 电站管理 ✅ 不变 |
| 型号管理 | 站点管理 > 型号管理 | 站点管理 > 型号管理 ✅ 不变 |
| 并机管理 | 维护售后 > 并机管理 | 站点管理 > 并机管理 |
| 告警管理 | 维护售后 > 告警管理 | 告警工单 > 告警中心 |
| 告警规则 | 维护售后 > 告警规则 | 告警工单 > 告警规则 |
| 工单管理 | 维护售后 > 工单管理 | 告警工单 > 工单管理 |
| 远程设置 | 维护售后 > 远程设置 | 设备运维 > 远程设置 |
| 批量设置 | 维护售后 > 批量设置 | 设备运维 > 批量设置 |
| OTA升级 | 维护售后 > OTA升级 | 设备运维 > OTA升级 |
| 用户管理 | 站点管理 > 用户管理 | 系统管理 > 用户管理 |
| 系统管理 | 系统管理 (顶级) | 系统管理 > 系统配置 |
