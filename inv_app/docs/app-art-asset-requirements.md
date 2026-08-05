# 光伏逆变器监控 App（inv_app）美术资源需求文档

> 版本：v1.0 ｜ 面向对象：UI/视觉设计师 ｜ 对应产品：辰烁科技 / CSERGY 光伏逆变器监控 App
> 本文档定义 App 所需的全部美术资源（图标、吉祥物、插画、产品图），供设计师按规格交付。

---

## 1. 项目背景与品牌基调

- **产品**：光伏逆变器物联网监控 App（Android 为主，Flutter 开发，包名 `com.csergy.app1` / `com.csinv.monitor`）
- **核心业务**：户用光伏电站监控 —— 电站管理、逆变器实时数据、告警、OTA 固件升级、WiFi 配网、本地直连
- **品牌名**：中文「辰烁科技」/ 英文「CSERGY」
- **品牌主色**（与 `app_theme.dart` 一致，必须沿用）：
  - 主色 `#1565C0`（品牌蓝）
  - 深蓝 `#0D47A1`、浅蓝 `#42A5F5`（渐变区间：`#0D47A1 → #1565C0 → #42A5F5`）
  - 辅助色：成功绿、告警橙 `#FF9800`、错误红（Material 标准色即可）
- **视觉关键词**：清洁能源、科技感、蓝天白云、阳光、可靠
- **整体风格**：扁平化 + 线性图标（描边 1.8dp）+ 浅蓝渐变氛围插画；深色模式需兼容（颜色建议用品牌蓝不同透明度适配）

## 2. 页面全貌（33 个路由）

### 2.1 认证区（未登录，5 页）

| 路由 | 页面 | 现有图形情况 |
|---|---|---|
| `/splash` | 启动页：蓝渐变背景 + 太阳放射光线装饰 + 圆形底座太阳能板图标 + 品牌名 + 副标语 | 有 `solar_panel.png`；装饰为代码绘制 |
| `/login` | 登录页：品牌渐变头 + 悬浮表单卡片 + 第三方登录（微信/Google） | 有 `brand_logo.png`、`brand_name.png`、`icons/google.svg`、`icons/wechat.svg` |
| `/jverify-login` | 一键登录授权页（自绘，勾选框 16dp） | 有 `jverify_checkbox_checked/unchecked.png` |
| `/register` | 注册页（复用登录页品牌头） | 同登录页 |
| `/forgot-password` | 忘记密码页 | 纯表单 |

### 2.2 主框架（登录后，底部 5 Tab 导航）

| 路由 | 页面 | 底部导航当前图标（Material 默认，需品牌化） |
|---|---|---|
| `/home` | 首页：电站卡片、搜索、添加菜单、空状态 | home |
| `/statistics` | 数据统计：能量趋势/设备分布图表、离线横幅 | dashboard |
| `/devices` | 设备列表：拖动排序、长按编辑 | devices |
| `/alarms` | 告警/通知中心 | notifications |
| `/profile` | 我的：头像、菜单列表 | person |

### 2.3 业务页面（25 页）

- **电站**：`/station/create` 新建、`/station/:id` 详情、`/station/:id/edit` 编辑
- **设备**：`/device/:sn` 实时数据、`/device/:sn/control` 控制、`/device/:sn/protocol` 协议、`/device/:sn/history` 历史曲线、`/device/:sn/settings` 设置、`/device/:sn/edit` 编辑、`/add-device` 添加
- **本地通信**：`/wifi-config` WiFi 配网、`/local-mode` 本地模式、`/local-ota` 本地 OTA
- **OTA**：`/ota` 升级 Tab、`/ota/:sn` 详情、`/ota/:sn/detail` 任务详情
- **告警**：`/alarm/:id` 告警详情
- **我的**：`/settings` 设置、`/change-password` 改密、`/edit-profile` 编辑资料、`/about` 关于、`/notify-settings` 通知设置

### 2.4 现有资源盘点（assets/ + Android res）

```
inv_app/assets/
├── images/brand_logo.png        # 品牌 Logo（约 194 行二进制，已存在）
├── images/brand_name.png        # 品牌名字标（已存在）
├── images/solar_panel.png       # 太阳能板图标（已存在，仅此一张业务图）
├── icons/google.svg             # Google 第三方登录
└── icons/wechat.svg             # 微信第三方登录
android/app/src/main/res/
├── mipmap-*/ic_launcher.png     # App 启动图标（5 密度，默认 Flutter 图标，需重绘）
├── drawable-*/splash_solar_panel.png  # 原生启动屏太阳能板
└── drawable-xxhdpi/jverify_checkbox_*.png  # 一键登录勾选框
```

**结论**：除品牌 logo 外全站使用 Material 内置图标，无吉祥物、无空状态插画、无产品图。本需求文档补齐全部缺口。

## 3. 资源需求清单

### A 组：品牌基础（6 项）—— 优先级最高

| # | 资源名 | 用途 | 规格 |
|---|---|---|---|
| A1 | **App 启动图标** `ic_launcher` | 桌面图标、任务切换器 | 1024×1024 源图（圆形或圆角方形，蓝底白太阳能板），导出 mipmap：mdpi 48 / hdpi 72 / xhdpi 96 / xxhdpi 144 / xxxhdpi 192 |
| A2 | **品牌 Logo 横版** `brand_logo_h.png` | 启动页、登录页品牌头、关于页 | 含中英文组合（"辰烁科技 CSERGY"），白色版 + 深色版各一份，SVG 源图 + 透明底 PNG（高度 160px 基准，按比例缩放） |
| A3 | **品牌 Logo 方形** `brand_logo_square.png` | 页面头部、更新弹窗、头像占位 | 无字标圆底版，1024×1024 源图，PNG 透明底 |
| A4 | **启动屏插画** `splash_bg.png` | 替代 `/splash` 代码绘制的装饰（太阳光线/圆环） | 全屏背景插画 1920×1080，光伏主题：蓝天 + 放射阳光 + 光伏电站剪影，深蓝渐变打底 |
| A5 | **推送通知小图标** `ic_stat_notification.png` | 状态栏推送图标（Android） | 24×24dp 纯白透明底，单色可识别（太阳能板/铃铛造型），导出 drawable 各密度 |
| A6 | **版本更新弹窗图标** `ic_update.png` | 更新弹窗头部 | 64×64dp 圆角图标（下载/升级箭头 + 芯片），PNG |

### B 组：底部导航图标（5 组 × 2 态 = 10 个）

统一 **24dp 基准线性描边风格**（stroke 1.8dp、圆角端点），normal（灰 `#9AA0A6`）+ active（品牌蓝 `#1565C0`）两态，导出 48/72/96px（2x/3x）。

| # | 名称 | 造型建议 | 命名 |
|---|---|---|---|
| B1 | 首页 | 房子 + 太阳 | `ic_nav_home.png` / `ic_nav_home_active.png` |
| B2 | 统计 | 仪表盘（半圆 + 指针） | `ic_nav_statistics.png` / `_active` |
| B3 | 设备 | 逆变器（机箱 + 散热片 + 指示灯） | `ic_nav_devices.png` / `_active` |
| B4 | 告警 | 铃铛 | `ic_nav_alarm.png` / `_active` |
| B5 | 我的 | 人形 | `ic_nav_profile.png` / `_active` |

### C 组：功能图标集（12 个）

与 B 组同风格（24dp 线性描边），单色，品牌蓝；供各业务页 AppBar、列表、表单使用。

| # | 名称 | 造型建议 | 命名 |
|---|---|---|---|
| C1 | 电站 | 屋顶 + 太阳能板 | `ic_station.png` |
| C2 | 逆变器 | 同 B3 造型变体 | `ic_inverter.png` |
| C3 | 太阳能板 | 网格板 + 斜支架（重绘现有 `solar_panel.png`） | `ic_solar_panel.png` |
| C4 | 储能电池 | 电池 + 电量条 | `ic_battery.png` |
| C5 | WiFi 配网 | 三弧 WiFi 信号 | `ic_wifi.png` |
| C6 | 定位/地图 | 地图 pin | `ic_location.png` |
| C7 | OTA 升级 | 向上箭头 + 芯片 | `ic_ota.png` |
| C8 | 搜索 | 放大镜 | `ic_search.png` |
| C9 | 添加 | 加号 | `ic_add.png` |
| C10 | 排序 | 上下箭头 | `ic_sort.png` |
| C11 | 编辑 | 铅笔 | `ic_edit.png` |
| C12 | 更多 | 三个圆点 | `ic_more.png` |

### D 组：空状态插画（8 个）

**240×240dp 插画**，浅蓝底（品牌蓝 8% 透明度）+ 白色圆底 + 品牌蓝描边角色，风格与吉祥物统一（可让吉祥物入镜）。PNG 透明底，导出 2x/3x。

| # | 场景 | 内容建议 | 命名 | 使用页面 |
|---|---|---|---|---|
| D1 | 无电站 | 空场地 + 虚线轮廓屋顶 | `empty_stations.png` | 首页 `/home` |
| D2 | 无设备 | 空卡片 + 逆变器虚线轮廓 | `empty_devices.png` | 设备列表 `/devices` |
| D3 | 无告警 | 安心盾牌 + 对勾 | `empty_alarms.png` | 告警中心 `/alarms` |
| D4 | 无通知 | 空铃铛 | `empty_notifications.png` | 通知中心 |
| D5 | 图表无数据 | 空白折线图 + 太阳 | `empty_chart.png` | 统计页、历史曲线 |
| D6 | 搜索无结果 | 放大镜 + 问号 | `empty_search.png` | 首页搜索、设备搜索 |
| D7 | 网络离线/加载失败 | 断开的云 + 感叹号 | `empty_offline.png` | 全局加载失败态 |
| D8 | 无升级记录 | 空白版本历史 | `empty_ota.png` | OTA 页 `/ota` |

### E 组：吉祥物（6 个形态）—— 差异化记忆点

**设定建议**：光伏主题拟人化"太阳精灵"——暖黄色太阳脸 + 蓝色身体（太阳能板纹样），圆润可爱。
**规格**：每个形态 512×512px 源图（透明底 PNG），表情/手势变化，与 D 组插画共享角色设定。

| # | 形态 | 应用场景 | 命名 |
|---|---|---|---|
| E1 | 主形象（微笑招手） | 登录页欢迎区、关于页 | `mascot_main.png` |
| E2 | 告警形态（惊慌举旗） | 告警详情页头部、严重告警横幅 | `mascot_alarm.png` |
| E3 | 升级形态（背芯片/忙碌） | OTA 升级中页面 | `mascot_ota.png` |
| E4 | 离线形态（睡觉 Zzz） | 设备离线卡片、离线横幅 | `mascot_offline.png` |
| E5 | 成功形态（比赞） | OTA 升级成功、配网成功 | `mascot_success.png` |
| E6 | 加载形态（思考/转圈，可出 4 帧序列） | 骨架屏加载、下拉刷新 | `mascot_loading.png`（+帧） |

### F 组：页面专属插画（约 8 个）

| # | 资源 | 用途 | 规格 |
|---|---|---|---|
| F1 | 登录页头部插画 `login_header.png` | 登录/注册页品牌区（替代纯渐变），光伏场景氛围图 | 宽幅 1080×420，透明/深蓝底 |
| F2 | WiFi 配网流程插画 ×3 `wifi_step1/2/3.png` | `/wifi-config` 三步引导（连热点 → 输密码 → 成功） | 每张 320×240 |
| F3 | 本地模式插画 `local_mode.png` | `/local-mode` 页面头部（手机直连设备） | 320×240 |
| F4 | 本地 OTA 插画 `local_ota.png` | `/local-ota` 页面头部 | 320×240 |
| F5 | OTA 升级状态图 ×3 `ota_upgrading/success/failed.png` | `/ota/:sn` 升级中/成功/失败状态区 | 每张 240×240 |
| F6 | 设备卡片默认图 `device_placeholder.png` | 无图片设备的卡片占位（逆变器正面图） | 160×160 |
| F7 | 电站详情头图占位 `station_placeholder.png` | 电站详情头部（屋顶电站场景） | 宽幅 720×320 |
| F8 | 头像默认图 `avatar_default.png` | 用户未设置头像时 | 256×256（圆形裁切友好） |

### G 组：产品图（2 个）

| # | 资源 | 用途 | 规格 |
|---|---|---|---|
| G1 | 逆变器产品图 `inverter_product.png` | 设备详情/控制页展示（对应 CS-L10-6K2 等机型，正面斜 45° 或正视图，3D 渲染或高精插画） | 600×600 透明底 |
| G2 | 户用光伏电站场景图 `station_scene.png` | 登录页、关于页、分享图氛围图（屋顶 + 逆变器 + 电网 + 蓝天） | 1920×1080 或 1080×720 |

## 4. 规格与命名规范（交付硬性要求）

1. **源文件**：矢量资源保留 SVG/AI 源文件（或 1024px+ PNG 源图），交付时一并提供
2. **位图密度**：所有 PNG 按 1x/2x/3x 三档导出（基准 dp × 2/3 = px）；插画类至少提供 2x/3x
3. **命名**：全小写 snake_case（`ic_nav_home.png`、`empty_stations.png`、`mascot_alarm.png`）
4. **存放约定**（设计师交付后由开发放置）：
   - `inv_app/assets/images/` —— 全部 PNG（pubspec.yaml 已声明该目录）
   - `inv_app/assets/icons/` —— SVG
   - `android/app/src/main/res/mipmap-*/` —— App 图标
   - `android/app/src/main/res/drawable-*/` —— 原生启动屏、通知图标、勾选框
5. **颜色约束**：主色只用品牌蓝系（见 §1），导航 active 色 `#1565C0`，normal 灰 `#9AA0A6`；插画背景用品牌蓝 8% 透明度
6. **最小可读性**：24dp 图标在 2x 下（48px）轮廓清晰可辨，禁用 1px 以下细节

## 5. 接入点（供开发参考，设计师可忽略）

| 资源 | 代码位置 |
|---|---|
| B 组导航图标 | `lib/core/services/role_service.dart`（`NavItem.icon/activeIcon`，改用 `ImageIcon(AssetImage(...))`） |
| D 组空状态 | `lib/features/station/presentation/pages/home_page.dart`、`lib/features/dashboard/presentation/pages/dashboard_overview_page.dart`、设备列表/告警/OTA 各页空态分支 |
| A2/A4/F1 | `lib/features/auth/presentation/pages/splash_page.dart`、`auth_page.dart` |
| A5 | `android/.../res/drawable/`（推送配置） |
| C 组 | 各业务页 `Icon(Icons.xxx)` 替换为图片图标 |
| E 组 | OTA 页、告警页、离线横幅、登录页 |

## 6. 交付优先级建议

1. **第一批（P0）**：A1 App 图标、A2/A3 Logo、A4 启动屏、B 组导航 10 个
2. **第二批（P1）**：C 组功能图标 12 个、D 组空状态 8 个
3. **第三批（P2）**：E 组吉祥物 6 形态、F1 登录页插画
4. **第四批（P3）**：F 组其余页面插画、G 组产品图

每批交付即按 §5 接入点替换并真机走查（重点：图标清晰度、深色模式对比度、插画与页面留白协调）。
