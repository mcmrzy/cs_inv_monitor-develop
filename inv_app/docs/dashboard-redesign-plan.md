# 总览页面重构计划

## 概述

删除原来的 5-tab 统计页面，新建一个单屏滚动的 Dashboard 总览页面，替换底部导航栏的「统计」tab。只保留概要数据，去掉设备列表、日志、对比功能（这些在其他入口已有）。

---

## 页面布局（从上到下，单页滚动）

```
┌─────────────────────────────────┐
│  AppBar: "数据概览"              │
│  2026年6月11日 周三               │
├─────────────────────────────────┤
│  ██ Hero Energy Card (渐变蓝) ██ │
│  今日发电    累计发电    设备总数   │
│  12.5 kWh   1,234 kWh   8 台    │
├─────────────────────────────────┤
│  🟢 在线 6   ⚫ 离线 1   🔴 故障 1│
├─────────────────────────────────┤
│  📈 近7日发电趋势                 │
│  ┌───────────────────────────┐  │
│  │  ~~~~折线图(面积填充)~~~~  │  │
│  └───────────────────────────┘  │
├─────────────────────────────────┤
│  🍩 设备状态分布                  │
│  ┌──────────┐  🟢 在线  6       │
│  │  环形图   │  ⚫ 离线  1       │
│  │   8台    │  🔴 故障  1       │
│  └──────────┘                   │
├─────────────────────────────────┤
│  🏆 电站发电排行                  │
│  电站A  ████████████  5.2 kWh   │
│  电站B  ████████      3.8 kWh   │
│  电站C  █████         2.1 kWh   │
├─────────────────────────────────┤
│  ⚠️ 最近告警          查看全部 >  │
│  · 设备SN001 过温告警  2分钟前    │
│  · 设备SN003 通信中断  15分钟前   │
│  · 暂无更多告警                   │
└─────────────────────────────────┘
     底部留白 100h (避让导航栏)
```

---

## 文件变更清单

### 新建文件（features/dashboard/ 下，共 14 个）

**Domain 层：**
| # | 文件 | 说明 |
|---|------|------|
| 1 | `domain/entities/dashboard_data.dart` | 组合实体，包含所有仪表盘数据 |
| 2 | `domain/entities/trend_data_point.dart` | 趋势图数据点 |
| 3 | `domain/entities/station_rank_item.dart` | 电站排行项 |
| 4 | `domain/repositories/dashboard_repository.dart` | 仓库抽象接口 |

**Data 层：**
| # | 文件 | 说明 |
|---|------|------|
| 5 | `data/datasources/dashboard_remote_data_source.dart` | 4个 /dashboard/* API 调用 |
| 6 | `data/repositories/dashboard_repository_impl.dart` | 仓库实现 |

**Presentation 层 - BLoC：**
| # | 文件 | 说明 |
|---|------|------|
| 7 | `presentation/bloc/dashboard_event.dart` | 仅 1 个事件: DashboardLoadRequested |
| 8 | `presentation/bloc/dashboard_state.dart` | 4 个状态: Initial/Loading/Loaded/Error |
| 9 | `presentation/bloc/dashboard_bloc.dart` | 并行加载 4 个 API，缓存回退 |

**Presentation 层 - Widgets：**
| # | 文件 | 说明 |
|---|------|------|
| 10 | `presentation/widgets/hero_energy_card.dart` | 渐变英雄卡：今日/累计发电 + 设备数 |
| 11 | `presentation/widgets/quick_stats_row.dart` | 在线/离线/故障 3 个状态芯片 |
| 12 | `presentation/widgets/energy_trend_chart.dart` | fl_chart 折线图，7 日发电趋势 |
| 13 | `presentation/widgets/device_distribution_chart.dart` | fl_chart 环形图，设备状态分布 |
| 14 | `presentation/widgets/station_ranking_list.dart` | 水平条形图，Top5 电站排行 |
| 15 | `presentation/widgets/recent_alarms_card.dart` | 最近 3-5 条告警，带"查看全部"链接 |
| 16 | `presentation/widgets/dashboard_skeleton.dart` | 全页骨架屏加载态 |

**Presentation 层 - Page：**
| # | 文件 | 说明 |
|---|------|------|
| 17 | `presentation/pages/dashboard_overview_page.dart` | 主页面，CustomScrollView + 下拉刷新 |

### 移动文件（1 个）

| 文件 | 操作 | 原因 |
|------|------|------|
| `features/statistics/presentation/widgets/energy_statistics_tab.dart` | 移动到 `core/widgets/energy_statistics_tab.dart` | 被 station_detail_page.dart 引用，不能删除 |

### 修改文件（5 个）

| 文件 | 变更 |
|------|------|
| `lib/core/router/app_router.dart` | import 改为 DashboardOverviewPage，/statistics 路由改指向新页面 |
| `lib/core/services/service_locator.dart` | 删除 StatisticsBloc/Repo/DataSource 注册，新增 Dashboard 系列注册 |
| `lib/main.dart` | StatisticsBloc → DashboardBloc |
| `lib/core/services/role_service.dart` | nav label '统计' → '概览'（可选） |
| `lib/features/station/presentation/pages/station_detail_page.dart` | 更新 EnergyStatisticsTab 的 import 路径 |

### 删除文件（15 个，整个 statistics 目录）

```
features/statistics/
  data/datasources/statistics_remote_data_source.dart    ✗
  data/repositories/statistics_repository_impl.dart      ✗
  domain/entities/device_summary.dart                    ✗
  domain/entities/energy_data_point.dart                 ✗
  domain/entities/log_entry.dart                         ✗
  domain/repositories/statistics_repository.dart         ✗
  presentation/bloc/statistics_bloc.dart                 ✗
  presentation/bloc/statistics_event.dart                ✗
  presentation/bloc/statistics_state.dart                ✗
  presentation/pages/statistics_page.dart                ✗
  presentation/widgets/comparison_tab.dart               ✗
  presentation/widgets/device_data_tab.dart              ✗
  presentation/widgets/operation_logs_tab.dart           ✗
  presentation/widgets/overview_tab.dart                 ✗
  presentation/widgets/station_selector.dart             ✗
```

---

## API 映射

| 区域 | 后端端点 | 响应字段 |
|------|----------|----------|
| Hero 卡片 | `GET /dashboard/statistics` | `todayEnergy`, `totalEnergy`, `deviceStats.total` |
| 状态芯片 | `GET /dashboard/statistics` | `deviceStats.online/offline/fault` |
| 趋势图 | `GET /dashboard/trend?type=day` | `[{date, energy, cumulative}]` |
| 环形图 | `GET /dashboard/device-distribution` | `{online, offline, fault}` |
| 电站排行 | `GET /dashboard/station-ranking?period=today&limit=5` | `[{stationId, stationName, energy, deviceCount}]` |
| 最近告警 | `GET /dashboard/statistics` | `recentAlarms[]` |

BLoC 内部用 `Future.wait` 并行调用 4 个端点，总耗时 = 最慢单个请求。

---

## BLoC 设计（极简）

```dart
// Event - 仅 1 个
class DashboardLoadRequested extends DashboardEvent {}

// States - 4 个
class DashboardInitial extends DashboardState {}
class DashboardLoading extends DashboardState {}
class DashboardLoaded extends DashboardState {
  final int todayEnergy;
  final int totalEnergy;
  final int deviceTotal;
  final int onlineCount;
  final int offlineCount;
  final int faultCount;
  final List<TrendDataPoint> trendData;
  final List<StationRankItem> stationRanking;
  final List<Map<String, dynamic>> recentAlarms;
  final bool isFromCache;
}
class DashboardError extends DashboardState {
  final String message;
}
```

缓存策略：加载失败时尝试从 DataCacheService 读取缓存数据，显示 OfflineDataBanner。

---

## 视觉规范

- **卡片**: `AppColor.card(context)` 白色/暗色表面，16r 圆角
- **Hero 卡**: `AppColor.heroCard(context)` 主色渐变，20r 圆角
- **间距**: 卡片间 16h，内边距 16w
- **图表**: fl_chart 库，折线图带曲线+渐变面积填充，环形图 3 段
- **颜色**: 主蓝 1565C0、在线绿 2E7D32、离线灰 9E9E9E、故障红 C62828
- **字体**: 14sp 标题 w600，22sp 数值 w800，11sp 标签 w500
- **骨架屏**: ShimmerSkeleton + SkeletonBox/SkeletonCard
- **下拉刷新**: StyledRefreshIndicator
- **数字动画**: AnimatedValue 组件

---

## 实施顺序

1. **Domain 层** — 实体 + 仓库接口（4 文件）
2. **Data 层** — 数据源 + 仓库实现（2 文件）
3. **BLoC** — 事件/状态/BLoC（3 文件）
4. **移动** EnergyStatisticsTab → core/widgets/
5. **Widgets** — 7 个组件（从底向上）
6. **Page** — 主页面
7. **集成** — 修改 router / service_locator / main.dart
8. **清理** — 删除 statistics 目录
9. **测试** — 编译验证
