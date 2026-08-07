# CSERGY Flutter 主题生产级审计报告

审计日期：2026-08-05  
审计范围：`inv_app` 的浅色/深色主题、`BottomNavBar`、`AppBar`、核心卡片、状态色和硬编码颜色。  
审计约束：本轮只新增本报告，不修改 Dart、SVG、`pubspec.yaml` 或其他文档。

## 结论

审计时判定主题体系**不具备商用发布条件**。经 2026-08-06 实施 10 项代码修复并验证后，**深色模式可读性相关的页面级阻塞项已解除**：页面级浅色 token 直落深色背景（AppBar、核心卡片、状态文字）、状态色字面量重复、未使用的导航主题死配置均已收敛为上下文感知 token。**但仍不具备商用发布条件**：主题入口自身仍保留 `Colors.white/black` 与深色字面量，`AppColors` 固定色在表单等页面仍广泛使用，且真机/模拟器浅色/深色截图、对比度、字体放大、低端机 SVG 解码验收均未执行。完成剩余修正与视觉发布门禁前，不能宣称“美术资源准备无瑕疵”或“App 设计可商用”。

## 验收总表

| 检查项 | 状态 | 证据 | 结论 |
|---|---|---|---|
| 全局主题入口 | **阻塞** | `lib/core/theme/app_theme.dart:5-34`、`299-329` | 主题入口仍直接使用 `Colors.white/black`、`0xFF1A1D24` 字面量；`ThemeData`/`AppColor`/`AppColors` 三套入口漂移风险未消除 |
| 浅色基础背景/卡片 | 部分通过 | `app_theme.dart:15-34`、`602-656` | 背景和圆角方向一致，但页面仍有局部白色硬编码（品牌渐变、按钮前景等） |
| 深色基础背景/卡片 | **✅ 已修复（2026-08-06）** | `status_grid_widget.dart:185/193`、`recent_alarms_card.dart:55/103/126/209/243-278`、`scrollable_data_cards.dart:100-146` | 页面直接使用浅色 `AppColors.text*` 的核心卡片已迁移为 `AppColor.text*(context)` 上下文 token，空状态 `_buildEmpty` 增加 context 参数，边框改 `AppColor.outline(context)` |
| `BottomNavBar` 实际渲染 | 通过（静态） | `core/router/app_router.dart:817-902` | 使用 `ColorScheme`、SafeArea、normal/active SVG 和 fallback，链路正确 |
| 底部导航主题配置 | **✅ 已修复（2026-08-06）** | `app_theme.dart` 全文件 | 已删除浅色/深色两处从未使用的 `NavigationBarThemeData` 死配置（全项目无 NavigationBar 组件），现仅保留权威的 `BottomNavigationBarThemeData`（`app_theme.dart:139`、`412`） |
| `AppBar` 一致性 | **✅ 已修复（2026-08-06）** | `dashboard_overview_page.dart:45-46`、`app_router.dart:1060/1071-1072`、`create_station_page.dart:200-201`、`auth_page.dart:69/100` | 页面级 `Colors.white` 覆盖已改为 `AppColor.surface/surfaceContainer/textPrimary(context)`，深色模式不再出现白色顶栏 |
| 核心卡片可读性 | **✅ 已修复（2026-08-06）** | `status_grid_widget.dart:185/193`、`recent_alarms_card.dart:55/103/126/209/243-278`、`scrollable_data_cards.dart:100-146` | 计数/标签、标题、空状态、故障文本、SN/时间/箭头图标、非选中卡片文字与边框全部改为上下文 token |
| 状态色统一性 | **✅ 已修复（2026-08-06）** | `core/widgets/status_indicator.dart:3/65-69`、`hero_energy_card.dart:31` | `StatusIndicator` 字面量 `0xFF4CAF50/0xFFF44336/0xFF9E9E9E` 已改为语义常量 `AppColors.online/fault/offline` 并补充 import；Hero 品牌渐变收敛为共享 `AppColor.heroCard(context)`（注意：`app_theme.dart` 中 success/successLight 等重复语义色仍未收敛） |
| 真实视觉验证 | **阻塞** | 现有工作区验证记录 | 尚未完成浅色/深色真机或模拟器截图、对比度和 SVG 低端机解码验收 |

## 已通过项

1. `BottomNavBar` 在 `core/router/app_router.dart:848-875` 通过 `Theme.of(context).colorScheme` 获取选中/未选中颜色，没有直接写死浅色或深色值。
2. `BottomNavBar` 在 `core/router/app_router.dart:852-864` 使用 `colorScheme.surface` 和阴影，且保留 `SafeArea(top: false)`，底部安全区处理正确。
3. `core/router/app_router.dart:884-895` 已区分 normal/active SVG，并通过 `ColorFilter.mode` 着色；SVG 失败时在 `1001-1033` 有 Material fallback 和语义标签。
4. `core/widgets/data_card.dart:51-102` 使用 `colorScheme.onSurface/onSurfaceVariant`，是当前卡片中较可靠的明暗模式实现，可作为其他卡片迁移样板。
5. `core/theme/app_theme.dart:300-356` 已提供深色 AppBar、Card、Dialog、BottomSheet 的基础表面色，说明主题基础能力存在，问题主要在页面绕过主题和 token 漂移。

## 阻塞项与可执行修正清单

### P0：先修复深色模式可读性

| 文件与行号 | 问题 | 影响 | 可执行修正 | 状态与验证（2026-08-06） |
|---|---|---|---|---|
| `inv_app/lib/core/theme/app_theme.dart:5-34`、`299-329` | AppBar/Card 同时使用 `Colors.white`、`Colors.black` 和深色字面量 | 主题入口与页面 token 不一致，后续页面容易绕过 `ColorScheme` | 以 `ColorScheme.surface/onSurface/surfaceContainer` 为唯一表面入口；只保留品牌渐变和语义色的固定常量 | **❌ 未修复**：主题入口 `Colors.white/black`、`0xFF1A1D24` 字面量仍存在，未改动 |
| `inv_app/lib/core/theme/app_theme.dart:597-649`、`708-756` | `AppColor` 是上下文感知色，`AppColors` 是浅色固定色，两者命名相近但语义不同 | `AppColors.textPrimary` 在深色背景上会变成深色文字，造成低对比 | 将文字、背景、边框、状态 badge 统一迁移到上下文感知 token；固定色只保留品牌/状态原色，并明确命名为 palette/semantic | **❌ 未修复**：全局迁移未完成，表单等页面仍使用 `AppColors.textPrimary` 等固定色（仅状态 badge 与 Hero 渐变已收敛，见下方两项） |
| `inv_app/lib/features/dashboard/presentation/pages/dashboard_overview_page.dart:33-47` | `Scaffold` 已使用 `AppColor.surface(context)`，AppBar 却强制 `Colors.white`，前景色为 `AppColors.textPrimary` | 深色模式下顶部栏与页面背景断裂，标题可能变暗 | 改为 `AppColor.surfaceContainer(context)` + `AppColor.textPrimary(context)`，或完全依赖全局 `appBarTheme` | **✅ 已修复（2026-08-06）**：`dashboard_overview_page.dart:45-46` 已改为 `AppColor.surfaceContainer(context)` + `AppColor.textPrimary(context)` |
| `inv_app/lib/core/router/app_router.dart:1059-1072` | 设备列表使用 `AppColors.background` 和 `Colors.white` | 深色模式会出现浅色页面/白色顶栏 | 改为 `AppColor.surface(context)`、`AppColor.surfaceContainer(context)` 和 `AppColor.textPrimary(context)` | **✅ 已修复（2026-08-06）**：`app_router.dart:1060/1071-1072` 已改为 `AppColor.surface(context)`、`surfaceContainer(context)`、`textPrimary(context)` |
| `inv_app/lib/features/station/presentation/pages/create_station_page.dart:190-202` | AppBar 前景色固定为 `AppColors.textPrimary` | 深色 AppBar 上标题/返回键对比度不足 | 使用 `AppColor.textPrimary(context)`，并与其他表单页统一 | **✅ 已修复（2026-08-06）**：`create_station_page.dart:200-201` 已改为 `AppColor.surfaceContainer(context)` + `AppColor.textPrimary(context)`（该页表单区 `AppColors.textPrimary` 未迁移，属剩余 AppColors 全局清理范畴） |
| `inv_app/lib/features/auth/presentation/pages/auth_page.dart:68-79` | 登录页根背景固定 `Colors.white` | 深色模式无法保持统一表面层级；错误提示色与表面未统一 | 若登录页明确只支持浅色，需在产品规范中声明并锁定 `ThemeMode.light`；否则改为上下文感知背景，并保留品牌头部的固定渐变 | **✅ 已修复（2026-08-06）**：`auth_page.dart:69/100` 根背景改 `AppColor.surface(context)`、悬浮卡片改 `AppColor.surfaceContainer(context)`；品牌头部白色渐变按修正建议保留（品牌渐变属允许范围） |
| `inv_app/lib/features/dashboard/presentation/widgets/status_grid_widget.dart:180-194` | 状态数值和标签固定使用 `AppColors.textPrimary/textSecondary` | 深色状态卡片上文字可能偏暗 | 改为 `AppColor.textPrimary(context)`、`AppColor.textSecondary(context)`；状态边框/背景继续使用语义色透明层 | **✅ 已修复（2026-08-06）**：`status_grid_widget.dart:185/193` 计数改 `AppColor.textPrimary(context)`、标签改 `AppColor.textSecondary(context)` |
| `inv_app/lib/features/dashboard/presentation/widgets/recent_alarms_card.dart:50-56`、`122-124`、`203-207`、`240-275` | 告警标题、空状态、故障文本和元信息大量使用浅色固定文字 token | 深色告警卡片可读性和层级不稳定 | 标题/故障文本使用 `AppColor.textPrimary(context)`，辅助信息使用 `AppColor.textHint(context)`；告警颜色只用于 icon、badge、边框和短标签 | **✅ 已修复（2026-08-06）**：标题 `textPrimary(context)`、空状态 `_buildEmpty(context, l10n)` 增加 context 参数、故障文本 `textPrimary(context)`、SN/时间/箭头图标 `textHint(context)` |
| `inv_app/lib/features/dashboard/presentation/widgets/scrollable_data_cards.dart:99-139` | 非选中卡片文字使用 `AppColors.textPrimary/textSecondary/textHint` | 深色横向数据卡片的数字和标签可能变暗 | 使用 `AppColor.surfaceContainer(context)`、`AppColor.textPrimary(context)`、`AppColor.textSecondary(context)` 和上下文边框 token | **✅ 已修复（2026-08-06）**：非选中文字改 `AppColor.textPrimary/textSecondary/textHint(context)`，卡片背景 `surfaceContainer(context)`，边框 `AppColors.divider` 改 `AppColor.outline(context)` |

### P1：统一导航、卡片和状态语义

| 文件与行号 | 问题 | 可执行修正 | 状态与验证（2026-08-06） |
|---|---|---|---|
| `inv_app/lib/core/theme/app_theme.dart:139-147`、`435-444` | 旧版 `BottomNavigationBarThemeData` 与 `core/router/app_router.dart:848-875` 的显式颜色重复 | 保留一处权威配置；推荐让 `BottomNavBar` 只读取 `ColorScheme`，主题文件只提供默认字号、类型和 elevation | **❌ 未修复**：未收敛为单一权威配置（本轮仅删除了 NavigationBar 死配置） |
| `inv_app/lib/core/theme/app_theme.dart:246-268`、`542-564` | 同时配置 `NavigationBarThemeData`，但实际组件是 `BottomNavigationBar` | 删除未使用的配置或切换组件后再保留，避免设计验收时误以为两套导航均已生效 | **✅ 已修复（2026-08-06）**：浅色/深色两处 `NavigationBarThemeData` 死配置已删除（全项目 grep 无 NavigationBar 组件），现仅保留 `BottomNavigationBarThemeData` |
| `inv_app/lib/core/widgets/status_indicator.dart:61-69` | 在线/故障/离线直接使用 `#4CAF50/#F44336/#9E9E9E` | 改为统一语义 token，例如 `AppColors.online/fault/offline`；状态值映射集中到一个 helper，避免与 `recent_alarms_card.dart:295-306` 产生漂移 | **✅ 已修复（2026-08-06）**：`status_indicator.dart:65-69` 已改用 `AppColors.online/fault/offline` 并补充 `app_theme.dart` import（状态值映射集中 helper 未做，风险已降） |
| `inv_app/lib/core/theme/app_theme.dart:719-730` | `success`、`successLight`、`online`、`error`、`errorLight`、`fault` 重复表达相近语义但颜色不同 | 定义状态矩阵：`online`、`offline`、`warning`、`fault`、`info`；每个状态明确 foreground、softBackground、border 三种用途 | **❌ 未修复**：`success/successLight/error/errorLight` 等重复语义色仍在 `AppColors` 中，状态矩阵未建立 |
| `inv_app/lib/features/dashboard/presentation/widgets/hero_energy_card.dart:31-45` | Hero 渐变重复了 `AppColor.heroCard` 的颜色和阴影定义 | 使用共享 hero decoration，避免品牌蓝渐变在主题文件和页面继续分叉；白色文字可保留，但需截图验证小字号对比度 | **✅ 已修复（2026-08-06）**：页面重复的品牌渐变+阴影已收敛为共享 `AppColor.heroCard(context)`（定义于 `app_theme.dart:628`）；小字号对比度截图验证仍属未执行门禁 |
| `inv_app/lib/core/widgets/data_card.dart:30-43` | 业务色直接作为背景透明层，依赖传入颜色的亮度 | 保留现有模式，但对传入色建立允许列表；避免将黄色/浅青色直接用于小字号文字或低对比背景 | **❌ 未修复**：本轮未改动 |

### P2：完成视觉发布门禁

| 文件/范围 | 门禁动作 | 通过标准 | 状态与验证（2026-08-06） |
|---|---|---|---|
| `inv_app/lib/core/theme/app_theme.dart` 及全部主题消费点 | 执行浅色/深色截图巡检 | AppBar、卡片、底部导航、弹窗、输入框无白块/黑字异常，层级连续 | **❌ 未修复**：未执行截图巡检（静态 analyze 通过不等同于视觉验收） |
| `BottomNavBar`、所有 `AppBar` | 检查 normal/active、子路由选中、SVG fallback | 选中态使用 CSERGY 蓝，未选中态可读但弱化；SVG 和 fallback 视觉重量一致 | **❌ 未修复**：未执行截图验收 |
| `status_indicator.dart`、状态卡片、告警列表 | 建立状态色对照表 | 在线/正常、离线、告警、故障在首页、设备、统计、告警页颜色一致；不能只依赖颜色区分，必须同时有文字/图标 | **❌ 未修复**：对照表未建立（`StatusIndicator` 字面量已收敛为语义常量，属代码层部分收敛） |
| 全部 `inv_app/lib` 的 `Colors.white/black` 和 `Color(0x...)` | 按用途分类清理 | 允许品牌渐变、产品图/插画专用色和阴影透明色；表面、文字、边框和状态 badge 必须走 token | **❌ 未修复**：未执行全量分类清理 |
| Flutter 真机或模拟器 | 验收浅色/深色、中文/英文、小屏和系统字体放大 | 0.85x/1.0x/1.3x 字体下无截断；深浅色切换后无白屏、黑屏或文字消失 | **❌ 未修复**：未执行真机/模拟器验收 |

## 重点结论

- **BottomNavBar：静态实现通过，主题配置已收敛。** 实际使用 `ColorScheme` 和 CSERGY SVG；2026-08-06 已删除未使用的 `NavigationBarThemeData` 死配置；仍须补做浅色/深色截图验证（未执行）。
- **AppBar：已修复。** `dashboard_overview_page.dart:45-46`、`app_router.dart:1060/1071-1072`、`create_station_page.dart:200-201` 的页面级覆盖已改为上下文 token，深色模式不再出现白色顶栏；主题入口自身 `appBarTheme` 的 `Colors.white/black` 字面量仍未收敛。
- **卡片：已修复（页面级）。** `status_grid_widget.dart`、`recent_alarms_card.dart`、`scrollable_data_cards.dart` 的固定浅色文字 token 已全部迁移为上下文 token；`data_card.dart` 业务色允许列表与 `app_theme.dart` 表面字面量仍待处理。
- **状态色：部分修复。** `StatusIndicator` 字面量颜色已收敛为 `AppColors.online/fault/offline` 语义常量；`app_theme.dart` 中 `success/successLight/error/errorLight` 等重复语义色与状态矩阵仍未收敛。
- **商用判定：不通过。** P0 剩余项（主题入口字面量、`AppColors` 全局迁移）、P1 状态矩阵与业务色允许列表未完成，且真机/模拟器截图、对比度、字体放大、低端机 SVG 解码验收未执行，暂不能进入生产候选版本。

## 本轮未执行

- 未修改代码或资源文件。
- 未运行 Flutter 构建、分析、真机/模拟器截图；因此本报告的“通过”仅表示静态代码层面的通过，不代表运行时视觉验收通过。
