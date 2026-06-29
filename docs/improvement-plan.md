# 辰烁科技光伏逆变器管理后台 — 全面改进规划

## 一、问题总览

审查发现了 **8 大类 40+ 个具体问题**，按严重程度分为 P0（必须修）、P1（应该修）、P2（建议修）。

---

## 二、P0 — 必须修复（影响功能正确性）

### 2.1 告警级别标签冲突 ⚠️ BUG
- `alert-rules/index.tsx:47-51` 本地定义了 `ALARM_LEVEL_MAP`，与全局 `utils/constants.ts:18-26` **标签不一致**
- 全局：1=严重, 2=警告, 3=提示
- alert-rules 本地：1=信息, 2=警告, 3=严重 ← **严重性反转！**
- parallel 本地：1=严重, 2=重要, 3=次要, 4=警告 ← 又一套
- **修复**：删除所有本地定义，统一使用 `@/utils/constants` 中的全局常量

### 2.2 菜单标签 vs 页面标题不一致
| 菜单标签 | 页面实际标题 | 文件 |
|----------|-------------|------|
| 电站监控 | 实时监控 | monitoring/index.tsx |
| 操作记录 | 操作日志 | operation-logs/index.tsx |
| 告警中心 | (无标题) | alerts/index.tsx |

- **修复**：统一菜单和页面标题

### 2.3 Portal 页面日期格式化用了 `new Date()` 而非 `dayjs`
- `portal/AlertsPage.tsx:45` 和 `portal/DeviceMonitorPage.tsx:166` 使用 `new Date(t).toLocaleString('zh-CN')`
- 其他所有页面使用 `dayjs`
- **修复**：统一使用 `dayjs`

---

## 三、P1 — 应该修复（影响用户体验一致性）

### 3.1 页面标题缺失（6 个页面无标题）
| 页面 | 文件 |
|------|------|
| 告警中心 | alerts/index.tsx |
| 告警规则 | alert-rules/index.tsx |
| 工单管理 | work-orders/index.tsx |
| 用户管理 | users/index.tsx |
| OTA升级 | ota/index.tsx |
| 系统管理 | admin/index.tsx (用了 `<h3>` 而非 Typography) |

- **修复**：统一添加 `<Title level={4}><Icon /> 页面名</Title>`

### 3.2 Card 样式分裂
- **现代风格**（borderRadius:12 + bordered={false}）：dashboard, monitoring, analytics, remote-settings
- **旧风格**（默认 borderRadius:6 + bordered=true）：alerts, alert-rules, work-orders, users, admin, ota, parallel, stations, models, operation-logs, batch-settings, portal
- **修复**：统一为 `bordered={false} borderRadius={12}`

### 3.3 表格大小和分页不一致
| 属性 | 当前状态 |
|------|----------|
| `size` | 3 种：small / middle / 不设（大） |
| `pageSize` | 10 和 20 混用 |
| `showTotal` | `'共X条'` vs `'共X台设备'` vs 不设 |
| `scroll.x` | 从 500 到 1600 各不相同 |
| 空状态 | 部分用 `<Empty>`，部分用默认，部分用自定义 div |

- **修复**：统一 `size="small"`, `pageSize=20`, `showTotal={(t)=>\`共 ${t} 条\`}`, 统一空状态

### 3.4 统计卡片样式分裂（5 种风格）
| 风格 | 使用页面 |
|------|----------|
| 渐变背景 Hero 卡片 | dashboard, monitoring |
| 左边框彩色 + 阴影 | analytics |
| 普通 Card + Statistic | alerts, work-orders, stations |
| hoverable Card | stations |
| 无样式 | portal |

- **修复**：统一为一种风格，建议保留渐变 Hero 卡片用于顶层概览，普通 Card 用于子页面

### 3.5 两种消息 API 混用
- `message.error()` — alerts, alert-rules, users, admin, ota, work-orders
- `messageApi.error()` (来自 `App.useApp()`) — devices, stations, parallel, models, batch-settings, operation-logs
- **修复**：统一使用 `App.useApp()` 的 `messageApi`（Ant Design 推荐方式）

### 3.6 列名不一致（同一概念不同名称）
| 概念 | 变体 |
|------|------|
| 设备序列号 | SN / 设备SN / 设备序列号 / 序列号 |
| 告警级别 | 告警级别 / 级别 / 等级 |
| 最后通信 | 最后通信时间 / 最后通信 / 最后上线 / 最近上线 |
| 故障信息 | 故障信息 / 故障描述 / 消息 |
| 额定功率 | 额定功率 / 额定功率(W) / 额定功率(kW) |

- **修复**：统一列名

---

## 四、P2 — 建议修复（影响代码质量和可维护性）

### 4.1 工具函数重复定义
| 函数 | 重复位置 |
|------|----------|
| `safeNum` | dashboard:67, monitoring:139, analytics:68（已有 utils/format.ts） |
| `CHART_COLORS` | dashboard:63, monitoring:98 |
| `HERO_GRADIENTS` | dashboard:54, monitoring:100 |

- **修复**：提取到 `utils/constants.ts` 或 `utils/format.ts`

### 4.2 数据获取模式混用
- **React Query**：dashboard, devices, stations, monitoring, models, analytics
- **手动 useState+useEffect**：alerts, users, admin, ota, work-orders, alert-rules, operation-logs

- **修复**：逐步迁移手动 fetch 到 React Query

### 4.3 Query Key 不一致
- 同一个 stations 列表，用了 3 种 key：`['stations']`, `['stations', 'list']`, `['stations', 'all']`
- **修复**：创建 `queryKeys` 工厂文件

### 4.4 Service API 方法重复
| Service | 重复方法 |
|---------|----------|
| alertApi | `getAlerts` == `list`, `acknowledge` == `handle` |
| otaApi | `getFirmwares` == `listFirmware`, `getTasks` == `listTasks` |
| userApi | `getUsers` == `list`, `createUser` == `create`, `deleteUser` == `delete` |
| workOrderApi | `getWorkOrders` == `list`, `createWorkOrder` == `create` |

- **修复**：保留一套命名规范的方法，删除重复

### 4.5 N+1 实时数据请求
- `dashboard/index.tsx:493-510` 和 `stations/index.tsx:161-178` 对每台设备单独调用 `getRealtime(sn)`
- 20 台设备 = 每 15 秒发 20 个请求
- **修复**：后端提供批量接口，或前端使用 `useQueries`

### 4.6 ErrorBoundary 体验差
- `components/ErrorBoundary.tsx` 出错时用 `alert()` 显示错误并跳转 `/login`
- **修复**：改为友好的错误页面 + 重试按钮

### 4.7 缺少全局 QueryClient 错误处理
- `main.tsx` 中 QueryClient 只设了 `retry: 1`，无全局 `onError`
- **修复**：添加全局错误处理

---

## 五、实施计划

### 阶段一：紧急修复（1-2 天）
1. 修复 ALARM_LEVEL_MAP 标签冲突
2. 统一菜单标签与页面标题
3. 修复 Portal 日期格式化

### 阶段二：UI 统一（2-3 天）
1. 统一 Card 样式（bordered={false}, borderRadius=12）
2. 添加缺失的页面标题
3. 统一表格 size/pageSize/showTotal
4. 统一列名
5. 统一消息 API

### 阶段三：代码质量（3-5 天）
1. 提取重复工具函数
2. 清理重复 Service API 方法
3. 创建 queryKeys 工厂
4. 迁移手动 fetch 到 React Query（alerts → users → admin → ota → work-orders → alert-rules → operation-logs）
5. 改善 ErrorBoundary

### 阶段四：性能优化（可选）
1. 后端批量实时数据接口
2. 统一 staleTime/refetchInterval 策略
3. 添加全局 QueryClient 错误处理
