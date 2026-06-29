# 概览页面智能家居风格重设计

## [S1] 设计目标

将概览页面从传统列表布局改为智能家居风格，提升视觉吸引力和用户体验。

## [S2] 核心变化

### 2.1 顶部发电功率仪表盘
- 大圆形进度环显示实时发电功率
- 中心显示当前功率数值（kW）
- 底部显示今日发电量和收益
- 渐变背景，视觉焦点

### 2.2 状态卡片网格
- 2列网格布局
- 在线/离线/故障/告警 4个状态卡片
- 每个卡片包含：图标、数量、趋势指示
- 点击可跳转到对应列表

### 2.3 横向滑动数据卡片
- 今日/本月/本年/累计 4个数据维度
- 可横向滑动切换
- 每个卡片显示：数值、单位、趋势

### 2.4 趋势图表区
- 时间范围选择器（日/周/月）
- 面积图显示发电趋势
- 支持交互（缩放、点击查看详情）

### 2.5 电站排行区
- 垂直列表，显示Top5电站
- 进度条显示发电量占比
- 点击跳转到电站详情

### 2.6 告警信息区
- 显示最近3-5条告警
- 颜色区分告警级别
- 点击跳转到告警详情

## [S3] 视觉规范

- **主色调**: 保持现有蓝色系
- **卡片样式**: 圆角16px，白色背景，轻微阴影
- **间距**: 卡片间16px，内边距16px
- **字体**: 标题16sp w600，数值24sp w800，标签12sp w500
- **图标**: 使用Material Icons，24px

## [S4] 交互规范

- **点击反馈**: 涟漪效果
- **滑动**: 横向滑动切换数据卡片
- **下拉刷新**: 保持现有刷新机制
- **动画**: 数字变化时使用滚动动画

## [S5] 文件变更

### 新建文件
- `lib/features/dashboard/presentation/widgets/power_gauge_widget.dart` - 发电功率仪表盘
- `lib/features/dashboard/presentation/widgets/status_grid_widget.dart` - 状态卡片网格
- `lib/features/dashboard/presentation/widgets/scrollable_data_cards.dart` - 横向滑动数据卡片

### 修改文件
- `lib/features/dashboard/presentation/pages/dashboard_overview_page.dart` - 主页面布局
- `lib/features/dashboard/presentation/widgets/hero_energy_card.dart` - 改为发电功率仪表盘
- `lib/features/dashboard/presentation/widgets/quick_stats_row.dart` - 改为状态卡片网格
- `lib/features/dashboard/presentation/widgets/energy_trend_chart.dart` - 优化图表样式
- `lib/features/dashboard/presentation/widgets/station_ranking_list.dart` - 优化列表样式
- `lib/features/dashboard/presentation/widgets/recent_alarms_card.dart` - 优化告警卡片样式

## [S6] 实施顺序

1. 创建发电功率仪表盘组件
2. 创建状态卡片网格组件
3. 创建横向滑动数据卡片组件
4. 修改主页面布局
5. 优化现有组件样式
6. 测试和调整
