# 总览页面重构计划 V2

## 概述

在现有传统列表布局基础上，优化信息密度、增强交互性、添加实时数据更新。保持现有架构（Clean Architecture + BLoC），不添加个性化定制功能。

---

## 设计目标

1. **信息密度优化**：提升关键信息的可读性和视觉层次
2. **交互性增强**：添加卡片展开、图表交互、数据筛选
3. **实时数据更新**：实现SSE实时推送，自动刷新数据

---

## 页面布局优化

### 当前布局
```
┌─────────────────────────────────────┐
│  AppBar: "数据概览"                   │
├─────────────────────────────────────┤
│  [离线数据提示 Banner]                 │
├─────────────────────────────────────┤
│  ██ HeroEnergyCard (渐变蓝底) ██      │
│  今日发电    累计发电    设备总数       │
├─────────────────────────────────────┤
│  🟢在线 6   ⚫离线 1   🔴故障 1       │
├─────────────────────────────────────┤
│  📈 近7日趋势                         │
├─────────────────────────────────────┤
│  🍩 设备状态分布                      │
├─────────────────────────────────────┤
│  🏆 电站发电排行                      │
├─────────────────────────────────────┤
│  ⚠️ 最近告警          查看全部 >      │
└─────────────────────────────────────┘
```

### 优化后布局
```
┌─────────────────────────────────────┐
│  AppBar: "数据概览"  🟢实时更新中     │
├─────────────────────────────────────┤
│  [离线数据提示 Banner]                 │
├─────────────────────────────────────┤
│  ██ HeroEnergyCard (渐变蓝底) ██      │
│  今日发电    累计发电    设备总数       │
│  12.5kWh ↑  1234kWh    8台           │
│  较昨日+5.2%                         │
├─────────────────────────────────────┤
│  🟢在线 6   ⚫离线 1   🔴故障 1       │
│  ↑2         ↓1         →0           │
├─────────────────────────────────────┤
│  📈 近7日趋势           [日][周][月]   │
│  ┌───────────────────────────┐      │
│  │  ~~~~折线图(可缩放)~~~~    │      │
│  └───────────────────────────┘      │
├─────────────────────────────────────┤
│  🍩 设备状态分布        点击查看详情 > │
│  ┌──────────┐  🟢 在线  6           │
│  │  环形图   │  ⚫ 离线  1           │
│  │   8台    │  🔴 故障  1           │
│  └──────────┘                       │
├─────────────────────────────────────┤
│  🏆 电站发电排行        点击查看详情 > │
│  电站A  ████████████  5.2 kWh       │
│  电站B  ████████      3.8 kWh       │
│  电站C  █████         2.1 kWh       │
├─────────────────────────────────────┤
│  ⚠️ 最近告警          查看全部 >      │
│  · 设备SN001 过温告警  2分钟前        │
│  · 设备SN003 通信中断  15分钟前       │
│  · 暂无更多告警                       │
└─────────────────────────────────────┘
     底部留白 100h (避让导航栏)
```

---

## 详细设计

### 1. 信息密度优化

#### 1.1 HeroEnergyCard 优化
- **添加趋势指示器**：显示较昨日/上周的变化百分比
- **优化数字格式化**：支持万/亿单位自动转换
- **添加动画效果**：数字滚动动画（AnimatedValue组件）

#### 1.2 QuickStatsRow 优化
- **添加变化指示**：显示在线/离线/故障数量的变化
- **优化视觉层次**：使用更明显的颜色对比
- **添加交互**：点击跳转到设备列表筛选

#### 1.3 EnergyTrendChart 优化
- **添加时间范围选择**：支持日/周/月视图切换
- **优化图表交互**：支持双指缩放和拖拽
- **添加数据详情**：点击数据点显示详细信息

#### 1.4 DeviceDistributionChart 优化
- **添加交互**：点击环形图扇区筛选设备
- **优化图例**：显示具体数量和百分比

#### 1.5 StationRankingList 优化
- **添加交互**：点击电站跳转到详情页
- **优化显示**：显示更多电站（可展开）

#### 1.6 RecentAlarmsCard 优化
- **添加交互**：点击告警跳转到详情
- **优化显示**：显示告警级别和持续时间

### 2. 交互性增强

#### 2.1 卡片展开详情
- 每个卡片支持点击展开，显示更多详细信息
- 使用AnimatedContainer实现平滑展开动画
- 展开后显示更多数据维度和操作按钮

#### 2.2 图表交互增强
- **折线图**：支持双指缩放、单指拖拽、点击数据点
- **环形图**：支持点击扇区筛选、长按显示详情
- **条形图**：支持点击条形跳转、长按显示详情

#### 2.3 数据筛选功能
- **时间范围选择**：在趋势图上方添加日/周/月切换
- **设备状态筛选**：点击状态芯片筛选设备列表
- **电站筛选**：点击电站名称跳转到详情

#### 2.4 动画效果优化
- **数字滚动**：使用AnimatedValue组件实现数字变化动画
- **图表动画**：添加图表绘制动画，提升视觉体验
- **状态变化**：添加状态变化时的过渡动画

### 3. 实时数据更新

#### 3.1 SSE连接实现
```dart
// 新建文件：lib/features/dashboard/data/datasources/dashboard_sse_data_source.dart
class DashboardSSEDataSource {
  Stream<DashboardData> connectToSSE() {
    // 实现SSE连接
    // 自动重连机制
    // 心跳检测
  }
}
```

#### 3.2 BLoC扩展
```dart
// 修改文件：lib/features/dashboard/presentation/bloc/dashboard_bloc.dart
// 添加SSE相关事件和状态
class DashboardSSEConnected extends DashboardState {}
class DashboardSSEDataReceived extends DashboardState {}
class DashboardSSEError extends DashboardState {}
```

#### 3.3 UI更新提示
- **连接状态指示器**：AppBar右侧显示连接状态（🟢实时更新中/🔴连接断开）
- **数据更新提示**：数据更新时显示呼吸灯效果
- **手动刷新按钮**：保持现有下拉刷新功能

---

## 文件变更清单

### 新建文件（3个）

| # | 文件 | 说明 |
|---|------|------|
| 1 | `lib/features/dashboard/data/datasources/dashboard_sse_data_source.dart` | SSE数据源实现 |
| 2 | `lib/features/dashboard/presentation/widgets/trend_time_range_selector.dart` | 趋势图时间范围选择器 |
| 3 | `lib/features/dashboard/presentation/widgets/animated_value.dart` | 数字滚动动画组件 |

### 修改文件（8个）

| # | 文件 | 变更 |
|---|------|------|
| 1 | `lib/features/dashboard/presentation/pages/dashboard_overview_page.dart` | 添加SSE连接、优化布局 |
| 2 | `lib/features/dashboard/presentation/widgets/hero_energy_card.dart` | 添加趋势指示器、动画效果 |
| 3 | `lib/features/dashboard/presentation/widgets/quick_stats_row.dart` | 添加变化指示、交互跳转 |
| 4 | `lib/features/dashboard/presentation/widgets/energy_trend_chart.dart` | 添加时间范围选择、图表交互 |
| 5 | `lib/features/dashboard/presentation/widgets/device_distribution_chart.dart` | 添加点击交互、筛选功能 |
| 6 | `lib/features/dashboard/presentation/widgets/station_ranking_list.dart` | 添加点击交互、展开功能 |
| 7 | `lib/features/dashboard/presentation/widgets/recent_alarms_card.dart` | 添加点击交互、告警详情 |
| 8 | `lib/features/dashboard/presentation/bloc/dashboard_bloc.dart` | 添加SSE相关事件和状态 |

### 删除文件（0个）

无

---

## API映射

### 现有API（保持不变）
| 区域 | 后端端点 | 响应字段 |
|------|----------|----------|
| Hero卡片 | `GET /dashboard/statistics` | `todayEnergy`, `totalEnergy`, `deviceStats.total` |
| 状态芯片 | `GET /dashboard/statistics` | `deviceStats.online/offline/fault` |
| 趋势图 | `GET /dashboard/trend?type=day` | `[{date, energy, cumulative}]` |
| 环形图 | `GET /dashboard/device-distribution` | `{online, offline, fault}` |
| 电站排行 | `GET /dashboard/station-ranking?period=today&limit=5` | `[{stationId, stationName, energy, deviceCount}]` |
| 最近告警 | `GET /dashboard/statistics` | `recentAlarms[]` |

### 新增SSE端点
| 区域 | 后端端点 | 响应字段 |
|------|----------|----------|
| 实时数据 | `GET /dashboard/sse` | `Event: dashboard_update` |

---

## BLoC设计扩展

### 新增事件
```dart
class DashboardSSEConnectRequested extends DashboardEvent {}
class DashboardSSEDisconnectRequested extends DashboardEvent {}
class DashboardTimeRangeChanged extends DashboardEvent {
  final String range; // 'day', 'week', 'month'
}
```

### 新增状态
```dart
class DashboardSSEConnected extends DashboardState {}
class DashboardSSEDataReceived extends DashboardState {
  final DashboardData data;
}
class DashboardSSEError extends DashboardState {
  final String message;
}
```

---

## 视觉规范（补充）

### 新增颜色
- **趋势上升**：`AppColors.success` (#2E7D32)
- **趋势下降**：`AppColors.error` (#C62828)
- **趋势持平**：`AppColors.textHint` (#9CA3AF)
- **实时连接**：`AppColors.success` (#2E7D32)
- **连接断开**：`AppColors.error` (#C62828)

### 新增动画
- **数字滚动**：300ms ease-out
- **卡片展开**：250ms ease-in-out
- **图表绘制**：500ms ease-out
- **状态变化**：200ms ease-in-out

---

## 实施顺序

### 阶段1：信息密度优化（3天）
1. 优化HeroEnergyCard，添加趋势指示器
2. 优化QuickStatsRow，添加变化指示
3. 创建AnimatedValue组件，实现数字滚动动画
4. 优化图表标签和图例

### 阶段2：交互性增强（4天）
1. 实现卡片展开详情功能
2. 优化图表交互（缩放、拖拽、点击）
3. 添加时间范围选择器
4. 实现数据筛选和跳转功能

### 阶段3：实时数据更新（3天）
1. 实现SSE数据源
2. 扩展BLoC支持SSE
3. 添加连接状态指示器
4. 实现数据更新提示

### 阶段4：测试和优化（2天）
1. 功能测试
2. 性能优化
3. 用户体验优化
4. 文档更新

---

## 技术要点

### 1. SSE实现
- 使用`http`包的流式响应
- 实现自动重连机制（指数退避）
- 添加心跳检测（30秒间隔）
- 处理网络状态变化

### 2. 图表交互
- 使用`fl_chart`的内置交互支持
- 实现自定义手势识别器
- 优化触摸响应区域
- 添加交互反馈动画

### 3. 性能优化
- 使用`const`构造函数减少重建
- 实现 widget 缓存机制
- 优化图表绘制性能
- 使用`AutomaticKeepAliveClientMixin`保持状态

### 4. 错误处理
- 网络错误自动重试
- 数据解析错误降级处理
- 用户友好的错误提示
- 离线模式支持

---

## 测试计划

### 单元测试
- BLoC状态管理测试
- 数据源测试
- 工具函数测试

### 集成测试
- 页面加载流程测试
- 交互功能测试
- SSE连接测试

### 用户测试
- 信息可读性测试
- 交互流畅性测试
- 实时更新体验测试

---

## 风险评估

### 技术风险
1. **SSE连接稳定性**：需要处理网络波动和重连
2. **图表性能**：大数据量下的渲染性能
3. **内存管理**：长时间运行的内存泄漏

### 解决方案
1. 实现健壮的重连机制和错误处理
2. 优化图表渲染，支持数据采样
3. 定期检查内存使用，实现资源释放

---

## 成功指标

1. **信息密度**：关键信息一目了然，减少滚动次数
2. **交互响应**：所有交互响应时间 < 100ms
3. **实时性**：数据更新延迟 < 2秒
4. **稳定性**：SSE连接成功率 > 99%
5. **用户满意度**：用户反馈评分 > 4.5/5