# Flutter 艺术素材接入审计

> 审计范围：`inv_app` 当前 Flutter 路由、`RoleService`、底部导航、`pubspec.yaml`、已有素材目录及 Dart 代码中的素材引用。
>
> 审计目标：为后续导航图标、状态插画、角色素材和 CSERGY 产品素材接入确定真实入口、现状与缺口。

## 1. 结论摘要

- 路由主框架已经存在：公开认证路由、带 `MainShell` 的五个主导航路由，以及设备、配网、本地模式、本地 OTA、告警、设置和 OTA 详情等业务路由。
- 底部导航的唯一运行时入口是 `inv_app/lib/core/router/app_router.dart` 中的 `BottomNavBar`；它由 `ShellRoute` 注入，当前已读取 `assets/icons/csergy/` 下的 SVG 双态资源。
- `RoleService.getNavItems()` 已接收角色和权限参数，但当前始终返回五个固定导航项，没有按权限过滤。`isSystemAdmin` 与 `permissions` 对导航图标及显示项目前不产生实际差异。
- `pubspec.yaml` 已声明 `assets/images/`、`assets/icons/`、`assets/data/` 三个目录，因此新增素材放入这些目录后具备打包入口；但当前 Dart 代码只显式引用 `solar_panel.png`。
- 已有 `ic_nav_*` 图片、设备/能源图标和品牌图片大多处于“文件存在但业务未接入”状态；`assets/icons/` 当前只有 Google/微信登录 SVG。
- 当前没有角色/吉祥物、状态插画、人物场景、真实 CSERGY 逆变器或储能产品素材的 Flutter 资源及代码引用。后续素材接入需要新增文件并绑定到具体页面，而不是只生成图片。

## 2. 路由与页面接入点

### 2.1 公开路由

定义位置：`inv_app/lib/core/router/app_router.dart:131-162`

- `/splash` → `SplashPage`
- `/login` → `AuthPage`
- `/jverify-login` → `JVerifyAuthPage`
- `/register` → `AuthPage`
- `/forgot-password` → `ForgotPasswordPage`

角色开屏、品牌 Logo、登录背景、空状态或登录辅助插画的首要接入点是 `SplashPage` 和认证页面。

### 2.2 主导航路由

定义位置：`inv_app/lib/core/router/app_router.dart:163-192`

`ShellRoute` 使用 `MainShell(child: child)` 包裹以下五个页面：

| 导航项 | 路径 | 页面 | 当前素材入口 |
|---|---|---|---|
| Home | `/home` | `HomePage` | 页面中使用 `assets/images/solar_panel.png` 作为站点卡片图 |
| Overview | `/statistics` | `DashboardOverviewPage` | 未发现图片/ SVG 素材引用 |
| Device | `/devices` | `DeviceListPage` | 未发现图片/ SVG 素材引用 |
| Alarm | `/alarms` | `NotificationCenterPage` | 未发现状态插画引用 |
| Profile | `/profile` | `ProfilePage` | 未发现角色/头像插画引用 |

`MainShell` 在 `app_router.dart:788-809` 统一渲染 `BottomNavBar`。因此导航图标只需要接入此组件，即可覆盖五个主导航页面；不应在每个页面重复实现底部导航。

### 2.3 其他素材相关路由

由 `app_router.dart` 中的路由表确认的后续业务落点包括：

- 设备/站点：`/station/create`、`/station/:id`、`/station/:id/edit`、`/device/:sn`、`/device/:sn/control`、`/device/:sn/protocol`、`/device/:sn/history`、`/device/:sn/settings`、`/device/:sn/edit`、`/add-device`
- 本地连接：`/wifi-config`、`/local-mode`、`/local-ota`
- 告警与设置：`/alarm/:id`、`/settings`、`/change-password`、`/edit-profile`、`/about`、`/notify-settings`
- OTA：`/ota`、`/ota/:sn`、`/ota/:sn/detail`、`/ota/:sn/local`

这些页面是 WiFi 配网插画、设备连接插画、OTA 进度/完成/失败状态插画、告警空状态和关于页场景素材的真实接入候选点。

## 3. RoleService 与权限审计

文件：`inv_app/lib/core/services/role_service.dart`

### 3.1 当前模型

`NavItem` 在 `role_service.dart:5-17` 的字段为：

- `path`
- `label`
- `String iconAsset`
- `String activeIconAsset`

导航模型现在使用资源路径标识，`BottomNavBar` 通过 `SvgPicture.asset` 渲染普通态和选中态。

`RoleService.getNavItems()` 在 `role_service.dart:29-68` 固定返回 Home、Overview、Device、Alarm、Profile 五项。虽然函数接收 `isSystemAdmin` 和 `permissions`，但函数体没有根据二者筛选导航项。

### 3.2 权限常量与页面能力

已定义权限常量：

- `devices:view`
- `devices:manage`
- `device_control:basic`
- `ota:manage`
- `statistics:view`
- `alarms:view`
- `admin:manage`

`hasPermission`、`hasOtaAccess`、`hasStatisticsAccess`、`canManageDevices`、`canControlDevices` 已提供能力判断，但没有被用于构造差异化底部导航。

### 3.3 底部导航运行方式

`BottomNavBar` 在 `app_router.dart:817-889`：

1. 从 `AuthBloc` 读取 `isSystemAdmin` 和 `permissions`。
2. 调用 `RoleService.getNavItems()` 传入上述信息及本地化标签。
3. 根据当前路径计算选中索引。
4. 将 `NavItem.iconAsset` / `activeIconAsset` 包装为 `SvgPicture.asset(...)`。

因此自定义导航图标已经具备集中接入点；后续只需继续做主题、无障碍和真机验收，不应再回退到旧 PNG 或 Material 图标。

## 4. 已有素材清单与实际使用情况

### 4.1 Flutter 打包配置

文件：`inv_app/pubspec.yaml:82-88`

当前声明：

```yaml
assets:
  - assets/images/
  - assets/icons/
  - assets/data/
```

目录级声明已经覆盖后续新增 PNG、JPG、WebP、SVG 和 JSON 文件的打包入口。当前没有发现按文件逐项声明的遗漏，也没有发现素材命名常量或集中资源映射文件。

### 4.2 现有 `assets/images/`

| 素材组 | 文件 | 当前状态 |
|---|---|---|
| 品牌 | `brand_logo.png`、`brand_name.png` | 文件存在；未发现 Dart 代码显式引用 |
| 主导航 | `assets/icons/csergy/nav_*.svg` | 5 组 normal/active SVG 已接入 `BottomNavBar`；旧 PNG 仅作为待清理历史资源 |
| 设备/能源 | `ic_solar_panel.png`、`ic_inverter.png`、`ic_battery.png`、`ic_station.png` | 文件存在；未发现 Dart 代码显式引用 |
| 操作/辅助 | `ic_add.png`、`ic_edit.png`、`ic_location.png`、`ic_more.png`、`ic_ota.png`、`ic_search.png`、`ic_sort.png`、`ic_wifi.png`、`ic_stat_notification.png` | 文件存在；未发现 Dart 代码显式引用 |
| 通用图片 | `solar_panel.png` | 当前由 `SplashPage` 和 `HomePage` 显式引用 |

### 4.3 现有 `assets/icons/`

- `google.svg`
- `wechat.svg`

这两个 SVG 是登录方式图标，不是主导航图标，也不是状态插画或产品素材。

### 4.4 现有 `assets/data/`

- `alarm_codes.json`：告警码数据，不属于视觉素材。

### 4.5 真实 Dart 引用

当前搜索到的显式图片引用只有两处：

- `inv_app/lib/features/auth/presentation/pages/splash_page.dart:227-229`：开屏圆形容器内使用 `solar_panel.png`。
- `inv_app/lib/features/station/presentation/pages/home_page.dart:1152-1157`：站点卡片左侧使用 `solar_panel.png`。

未发现 `Image.asset`、`AssetImage` 或 `SvgPicture.asset` 对其他现有图片的引用。

## 5. 角色、状态插画与产品素材缺口

### 5.1 角色/人物素材

- `assets/images/` 中没有角色、人物、吉祥物、表情或人物场景文件。
- `ProfilePage`、`AboutPage`、认证页面中未发现角色素材引用。
- “小烁”角色及人物服装胸前 `CSERGY` 六边形标记目前没有进入 `inv_app/assets/`，也没有页面接入点。
- 后续应至少准备：欢迎/成功/提醒/疑问/故障五表情，以及开屏、空状态、OTA 完成/失败等可复用角色姿态。

### 5.2 状态插画

- 当前没有空设备、断网、离线、无告警、加载失败、OTA 成功、OTA 失败等插画文件。
- `/alarms`、`/devices`、`/wifi-config`、`/local-mode`、`/local-ota`、OTA 详情页面是主要状态插画接入点。
- 现有 `ic_wifi.png`、`ic_ota.png`、`ic_stat_notification.png` 只能作为小图标候选，不能替代完整状态插画。

### 5.3 真实产品素材

- 当前资源目录没有用户提供的 CSERGY 真实逆变器和储能设备图片。
- `ic_inverter.png`、`ic_battery.png` 是通用小图标候选，不应直接作为真实产品渲染图或产品卡片主视觉。
- 后续首页能源流、设备卡片、关于页和场景图应使用以用户提供实物为基准的产品素材，并区分“真实产品图”和“业务图标”。

## 6. 关键缺口清单

### P0：影响已规划视觉落地

1. 底部导航已迁移到 CSERGY SVG；仍需完成真机视觉、无障碍和深色模式验收。
2. 角色/人物/表情素材尚未进入 `assets/`，因此无法在页面中复用。
3. 真实 CSERGY 逆变器、储能设备素材尚未进入 `assets/`，产品卡片只能继续使用通用图标或 `solar_panel.png`。
4. 状态插画目录和命名约定尚未建立。

### P1：影响权限和页面一致性

1. `RoleService.getNavItems()` 当前不按权限过滤；“角色差异化导航”尚未实际实现。
2. 所有 `ShellRoute` 子路由都会由 `MainShell` 提供底部导航，但页面是否属于主导航范围没有单独的显式配置。
3. 素材没有集中映射层，页面直接写字符串路径；后续批量更换 CSERGY 品牌素材时容易产生散落引用。

### P2：影响维护与交付质量

1. 同一素材目录同时承载品牌、导航、设备图标和大图，缺少子目录分层。
2. 没有发现素材尺寸、明暗主题、选中态、无障碍语义或 SVG 颜色策略的约定。
3. 目前只看到两处实际图片引用，无法证明所有既有素材都已通过构建或运行时验证。

## 7. 建议的后续接入顺序

1. 对 `assets/icons/csergy/` 的 5 组导航 SVG 做真机、深色模式和无障碍验收。
2. 清理旧的 `ic_nav_*` PNG 前，先完成页面截图回归并确认没有其他直接引用。
3. 将 CSERGY 真实逆变器和储能产品图放入独立产品素材目录，区分透明主视图、卡片缩略图和场景图。
4. 为 `/home`、`/devices`、`/alarms`、`/wifi-config`、`/local-ota` 和 OTA 详情页建立状态插画接入点。
5. 将小烁角色素材按 `character/`、`states/` 或等价目录整理，并统一使用 CSERGY 胸前标识。
6. 再处理权限差异化导航：明确每个导航项需要的权限，并让 `getNavItems()` 真正筛选，同时补充首页/设备/告警等无权限状态的视觉回退。
7. 最后运行 `flutter analyze`、资源加载测试和关键页面截图验证，确认素材路径、明暗主题和不同角色权限下的布局均正常。

## 8. 本次审计修改范围

本次只新增本报告文件，未修改 Flutter 业务代码、`pubspec.yaml`、资源文件或其他文档。
