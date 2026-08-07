# CSERGY 家庭光伏监控 App 美术资源需求（视觉升级 v2.0）

> 产品：inv_app Flutter 移动端
> 面向对象：品牌设计、UI 设计、插画、3D 与动效设计师
> 版本日期：2026-08-05
> 目标用户：普通家庭业主

本文定义视觉升级所需的美术资源、设计语言、交付规格、优先级和代码接入范围。

---

## 1. 结论摘要

本轮升级不是在现有页面中零散加入几张插画，而是建立一套完整的“家庭清洁能源视觉世界”。

- 品牌气质：家庭友好、科技现代、鲜明多彩、可靠可信。
- 素材语言：B3——强氛围插画与真实产品渲染并用。
- IP 角色：青年能源工程师“小烁”，3D 半写实、约 1:5 头身。
- 页面比例：约 40% 强 IP 场景页面 + 60% 多彩数据页面。
- 色彩策略：科技青蓝为主，荧光黄绿为品牌记忆色；太阳黄、能源绿、储能紫和珊瑚红承担业务语义。
- 资源策略：角色、场景、产品、状态、流程、图标和装饰组件形成同一体系；不把小烁作为贴纸塞进每张卡片。

最终效果应接近“IP 化科技生活产品”，而不是传统工业监控后台，也不是少儿教育或游戏产品。

---

## 2. 当前 App 与资源现状

### 2.1 当前产品范围

lib/core/router/app_router.dart 当前注册 33 个 GoRoute，覆盖：

| 区域 | 页面/流程 |
|---|---|
| 认证 | 启动页、登录、注册、一键登录、忘记密码 |
| 主导航 | 首页、统计、设备、告警/通知、我的 |
| 电站 | 创建、详情、编辑 |
| 设备 | 实时数据、控制、协议、历史、设置、编辑、添加 |
| 本地通信 | WiFi 配网、本地模式、本地 OTA |
| OTA | 升级入口、升级页、任务详情、本地升级 |
| 用户与设置 | 设置、密码、资料、通知设置、关于 |

应用已实现浅色和深色主题，但整体视觉仍以 Material 默认组件、白色卡片和品牌蓝为主。

### 2.2 当前素材盘点

assets 目前已经包含：

- brand_logo.png、brand_name.png
- solar_panel.png
- 5 组导航图标的 normal/active PNG，共 10 张
- 12 张功能图标 PNG
- ic_stat_notification.png
- Google、微信登录 SVG
- Noto Sans SC 字体和业务数据文件

旧文档中“底部导航和功能图标尚未制作”的结论已经失效。当前真实问题是：

1. 已有导航和功能图标是 96×96 PNG，尚未形成可扩展的正式 SVG 图标系统。
2. role_service.dart 的主导航当前仍使用 Material Icons，已有导航 PNG 尚未成为稳定接入方案。
3. 全 App 实际图片接入点很少，大部分页面仍由 Material 图标、纯色容器和代码绘制元素组成。
4. brand_logo.png 与 brand_name.png 为 RGB PNG，不是完整的透明底、多主题品牌资产包。
5. 现有产品参考图带 AI 水印、背景或伪透明棋盘格，品牌字标和绘制风格不统一，不能直接用于正式 App。
6. 当前素材存在本地改动，后续应逐项迁移，不应直接批量删除或覆盖。

### 2.3 现有资源处理建议

| 资源 | 处理建议 |
|---|---|
| assets/icons/google.svg | 保留，按第三方品牌规范使用 |
| assets/icons/wechat.svg | 保留，按第三方品牌规范使用 |
| brand_logo.png / brand_name.png | 用正式品牌资产包替换 |
| solar_panel.png | 仅作临时占位，后续由能源对象资源替换 |
| 10 张导航 PNG | 迁移为正式 SVG 双态图标后下线 |
| 12 张功能 PNG | 仅保留有业务识别度的部分；通用操作改用系统图标 |
| ic_stat_notification.png | 按 Android 单色通知图标规范重新校验或重绘 |

---

## 3. 视觉方向

### 3.1 关键词

清洁能源、家庭生活、现代科技、明亮鲜活、可信可靠、轻量陪伴、数据清晰。

### 3.2 页面视觉结构

#### 强 IP 页面（约 40%）

适用于开屏、登录、首次引导、关键空状态、WiFi 配网、本地直连、OTA 过程、操作成功和关于页。

这些页面允许使用大面积色块、3D 小烁、家庭光伏场景、透明亚克力造型和明显动效。

#### 多彩数据页面（约 60%）

适用于首页核心数据、统计图表、电站详情、设备列表与实时数据、告警通知、设置和表单。

这些页面以白色或冷灰信息面为主，通过业务语义色、场景缩略图、产品渲染和局部渐变丰富画面。小烁只在需要解释、引导或反馈时出现。

### 3.3 配色体系

保留品牌蓝 #1565C0，并扩展：

| 色彩角色 | 建议色值 | 用途 |
|---|---:|---|
| 品牌蓝 | #1565C0 | 品牌识别、主按钮、选中态 |
| 科技青 | #20C4E8 | 数据流、连接、互动高光 |
| 能量荧光黄绿 | #C9F23B | 品牌记忆点、关键行动、活跃状态 |
| 深海黑蓝 | #101828 | 标题、深色按钮、强对比背景 |
| 太阳黄 | #FFC857 | 光伏、发电、收益 |
| 清洁能源绿 | #36C98F | 正常、自用、低碳、成功 |
| 储能紫 | #6C63E8 | 电池、储能、OTA |
| 告警橙 | #FF9F43 | 一般告警、注意事项 |
| 故障珊瑚红 | #F05252 | 严重故障、失败、危险操作 |
| 冷灰背景 | #F4F8FB | 页面背景 |
| 白色信息面 | #FFFFFF | 卡片、表单、数据承载面 |

约束：

- 荧光黄绿只占画面的 5%–10%，不铺满长列表或大段正文背景。
- 红色只表达错误和风险，不用于普通装饰。
- 同一数据模块最多使用 1 个主色和 1 个辅助色。
- 深色模式必须使用独立表面色和对比度校验，不能只降低透明度。

### 3.4 图形语言

- 大圆角、轻阴影、悬浮层次和高透亚克力元素。
- 大色块用于开屏、登录、Hero 和流程页，不用于所有卡片。
- 数据页使用白色/冷灰承载信息，以多彩语义条、图表和图标建立节奏。
- 装饰元素从能源轨道、数据网格、光点、点阵和透明圆环中提炼。
- 不照搬参考产品的企鹅、车辆、版式或专属图形，只吸收高饱和配色、IP 场景化和多彩信息层级等原则。

---

## 4. 小烁 IP 角色规范

### 4.1 定位

- 名称：小烁
- 身份：青年能源工程师 / 家庭能源管家
- 性格：专业、可靠、耐心、积极，不卖萌、不说教
- 造型：3D 半写实，约 1:5 头身
- 年龄感：青年，不是儿童、宇航员或超级英雄

### 4.2 相对现有概念稿的调整

- 缩小眼睛和头部，弱化儿童感。
- 保留自然黑发和亲和表情，减少夸张惊吓与过大手势。
- 服装改为现代能源工程师工装：米白、品牌蓝、少量科技青或荧光黄绿。
- 取消胸前大型发光核心，统一使用小型 `CSERGY` 品牌字标胸标；不再使用六边形占位徽章。
- 降低霓虹蓝发光和金属宇航服质感，使用哑光织物、塑料和少量金属。
- 护目镜、安全帽、平板和工具箱作为按场景启用的配件。
- 插画内不生成品牌文字、按钮文案和数据，由 Flutter 叠加真实文本。

### 4.3 角色母版

| 编号 | 交付项 | 要求 |
|---|---|---|
| M01 | 角色 3D 母版 | Blender/C4D 等可编辑工程 |
| M02 | 三视图 | 正面、侧面、背面 |
| M03 | 标准 45° 视角 | 全身、半身、头像构图基准 |
| M04 | 材质与颜色板 | 服装、皮肤、头发、配件、品牌色 |
| M05 | 表情规范 | 微笑、专注、关切、惊讶、安心 |
| M06 | 配件包 | 安全帽、护目镜、平板、工具箱 |
| M07 | 灯光和摄像机模板 | 保证后续动作和场景一致 |

### 4.4 首批 10 个动作

| 文件名 | 动作 | 使用场景 |
|---|---|---|
| xiaoshuo_welcome | 自然挥手 | 开屏、登录、首次进入 |
| xiaoshuo_guide | 手持平板进行说明 | 新手引导、功能介绍 |
| xiaoshuo_station | 展示家庭光伏模型 | 无电站、新建电站 |
| xiaoshuo_device | 检查逆变器 | 无设备、添加设备 |
| xiaoshuo_wifi | 手机连接设备热点 | WiFi 配网、本地模式 |
| xiaoshuo_ota | 查看升级进度 | OTA 升级中 |
| xiaoshuo_success | 自然确认或点赞 | 配网成功、升级成功 |
| xiaoshuo_warning | 关切提示、手持警示牌 | 一般告警、风险提示 |
| xiaoshuo_offline | 检查断开的连接 | 离线、网络失败 |
| xiaoshuo_empty | 手持空白记录板 | 无数据、无记录、搜索为空 |

另交付 1 个 App 头像、5 个表情头像和 3 个动画：欢迎、扫描/加载、操作成功。

严重告警、OTA 失败和危险操作确认不使用夸张人物表情，应优先展示安全图标、明确说明和操作入口。

---

## 5. 美术资源完整清单

### A 组：品牌与平台基础

| 编号 | 资源 | 形式 | 要求 | 优先级 |
|---|---|---|---|---|
| A01 | App 自适应图标 | foreground/background/monochrome | 1024×1024 母版；兼容 Android Adaptive Icon | P0 |
| A02 | 横版品牌 Logo | brand_logo_horizontal_* | 蓝色、白色、深色；SVG + 透明 PNG | P0 |
| A03 | 方形品牌标 | brand_mark_square_* | 无字标；SVG + 1024 PNG | P0 |
| A04 | 通知状态栏图标 | ic_stat_notification | 24dp 单色白形、透明背景、各 Android 密度 | P0 |
| A05 | 版本更新图标 | ic_update.svg | 芯片/下载组合，双色 SVG | P1 |
| A06 | 默认用户头像 | avatar_default.webp | 小烁头像；512×512 | P1 |
| A07 | 视觉规范页 | Figma/PDF/源文件 | 色彩、字体、圆角、阴影、插画和图标示例 | P0 |

### B 组：科技装饰组件

优先交付 SVG 或可由代码复刻的参数规范：

- pattern_energy_orbit.svg：能源轨道圆环
- pattern_data_grid.svg：数据网格
- pattern_halftone.svg：点阵渐隐
- pattern_light_particles.svg：光点粒子
- pattern_flow_line.svg：流动能量线
- shape_acrylic_capsule.svg：透明亚克力胶囊
- shape_color_blob.svg：大色块底形
- shape_glow_ring.svg：高透发光环

装饰组件必须支持裁切和重新组合，不交付带固定文案的整页背景图。

### C 组：核心场景插画

| 文件名 | 内容 | 页面 | 规格 |
|---|---|---|---|
| scene_splash_energy_home | 小烁、家庭、光伏板、能源光轨 | /splash | 竖屏 1440×3200 母版，背景/环境/角色分层 |
| scene_auth_clean_energy | 小烁与透明能源装置 | 登录、注册、一键登录 | 1440×900，角色独立层 |
| scene_home_energy_world | 家庭、光伏、储能、阳光与能源流 | /home Hero | 1440×800，可横向裁切 |
| scene_wifi_connection | 手机、路由器、逆变器、小烁 | WiFi 配网、本地模式 | 1200×900，关键对象分层 |
| scene_about_csergy | 城市、家庭和清洁能源愿景 | /about | 1440×960 |

### D 组：产品与能源对象

#### 产品主对象

| 文件名 | 内容 | 规格 |
|---|---|---|
| product_inverter_front.webp | 逆变器正面 | 2048×2048 透明底母版 |
| product_inverter_angle.webp | 逆变器 30° 侧视 | 2048×2048 透明底母版 |
| product_inverter_card.webp | 列表卡片构图 | 800×800 透明底 |
| product_storage_front.webp | 储能设备正面 | 2048×2048 透明底母版 |
| product_storage_angle.webp | 储能设备 30° 侧视 | 2048×2048 透明底母版 |
| product_storage_card.webp | 列表卡片构图 | 800×800 透明底 |

重绘要求：

- `C:\Users\29538\Pictures\csergy\逆变器.png` 和 `C:\Users\29538\Pictures\csergy\储能.jpg` 是唯一产品外形基准；不得用泛化设备替代。
- 逆变器必须保留白色矩形柜体、顶部安装板与两个挂孔、黑色中央显示/控制区、按键排列、上下分体结构和正面 `CSERGY` 标识。
- 储能设备必须保留白色柜体、顶部橙色与黑色端子、顶部接口槽、中央黑色指示灯、侧面黑色把手、底部脚轮和正面 `CSERGY` 标识。
- 去除参考图中的 AI 水印和白底时，不得删除、改写或重构产品本体细节。
- 两类产品使用统一视角、焦距、自然光源、阴影方向和材质精度。
- 采用可信的半写实产品渲染，不做粗线稿卡通化或重新设计。

#### 辅助对象

- object_solar_panel
- object_energy_home
- object_router
- object_mobile_phone
- object_power_grid

#### 能源流节点

- node_pv.svg
- node_inverter.svg
- node_storage.svg
- node_home_load.svg
- node_power_grid.svg

能源流节点应有统一视角或统一双色矢量风格，不与 Material Icon 混用。

### E 组：状态插画

| 文件名 | 场景 | 推荐构成 | 接入位置 |
|---|---|---|---|
| state_empty_station | 无电站 | 小烁 + 家庭光伏模型 | 首页 |
| state_empty_device | 无设备 | 小烁 + 逆变器轮廓 | 设备列表、电站详情 |
| state_empty_message | 无告警/通知 | 小烁 + 安心盾牌 | 告警/通知中心、最近告警 |
| state_empty_chart | 图表无数据 | 空数据面板 + 能源光点 | 统计、历史曲线 |
| state_empty_search | 搜索无结果 | 小烁 + 搜索设备 | 搜索结果 |
| state_empty_ota | 无升级记录 | 版本卡片 + 对勾 | OTA 页面 |
| state_offline_network | 网络离线 | 小烁检查断开的连接 | 全局离线、设备离线 |
| state_load_failed | 加载失败 | 数据模块断开 + 重试 | 页面级错误 |
| state_no_nearby_device | 未发现附近设备 | 雷达扫描 + 手机 | 本地模式、配网扫描 |
| state_permission_required | 未开启权限 | 手机权限卡片 + 提示 | 蓝牙、WiFi、定位权限 |

状态插画母版为 720×720 透明底，主体占画布 70%–82%。角色、道具和装饰需能独立导出，图片内不嵌入标题、说明或按钮。

### F 组：流程插画

WiFi / 本地通信：

- flow_wifi_select_device
- flow_wifi_connect_hotspot
- flow_wifi_configure_network
- flow_local_direct_connection

OTA：

- flow_ota_available
- flow_ota_downloading
- flow_ota_installing
- flow_ota_success

失败状态使用统一错误组件，不单独制作“哭泣、惊吓”的角色插画。

### G 组：导航与业务图标

#### 底部导航（5 组 × 2 态）

| 文件 | 造型 |
|---|---|
| nav_home_outline.svg / nav_home_active.svg | 家庭 + 能源光点 |
| nav_statistics_outline.svg / nav_statistics_active.svg | 数据图表/能量环 |
| nav_devices_outline.svg / nav_devices_active.svg | 逆变器设备 |
| nav_alarm_outline.svg / nav_alarm_active.svg | 铃铛/告警 |
| nav_profile_outline.svg / nav_profile_active.svg | 用户/家庭账户 |

未选中态为清晰线性图标；选中态使用科技青蓝和少量荧光黄绿的双色设计。普通禁用态由代码控制透明度。

#### 业务领域图标（12 个）

电站、逆变器、光伏板、储能、家庭负载、电网、WiFi 配网、本地连接、蓝牙扫描、OTA、收益、碳减排。

#### 不需要定制的通用图标

搜索、添加、编辑、删除、返回、关闭、更多、排序、分享、刷新、日历、帮助等通用操作统一使用 Material Symbols 或同一系统图标库，不再交付 PNG。

### H 组：动效资源

| 文件名 | 动效 | 建议时长 |
|---|---|---|
| anim_xiaoshuo_welcome | 自然挥手、能源光点经过 | 1.5–2.5 秒循环 |
| anim_xiaoshuo_scan | 查看平板、扫描光环移动 | 1.0–1.8 秒循环 |
| anim_xiaoshuo_success | 确认手势、能量粒子收束 | 0.8–1.2 秒单次 |
| anim_energy_flow | 能源节点间光点流动 | 持续循环 |
| anim_ota_progress | 升级环和数据粒子 | 持续循环 |

交付 3D 源工程、动画时间线和 MP4 预览。App 候选格式为透明动画 WebP 或帧序列，最终格式由开发结合包体和性能验证确定。Lottie 仅用于轨道、粒子和进度等矢量动效。

---

## 6. 页面接入矩阵

| 页面/模块 | 主资源 | 辅助资源 | 视觉策略 |
|---|---|---|---|
| /splash | 开屏场景、欢迎动画 | Logo、点阵、光轨 | 强 IP 全屏 |
| 登录/注册/一键登录 | 登录场景、小烁半身 | 亚克力胶囊、Logo | 上部强视觉，下部清晰表单 |
| /home | 家庭能源场景 | 电站缩略图、业务图标 | 多彩数据为主，场景 Hero 为辅 |
| /statistics | 图表配色与装饰规范 | 无数据插画 | 不放大角色，保证图表可读 |
| /devices | 产品卡片渲染 | 无设备插画 | 真实产品主体 + 多彩状态条 |
| /alarms | 无消息插画 | 告警图标、珊瑚红/橙 | 严重告警不用角色抢信息 |
| /profile | 小烁头像/默认头像 | 多彩业务入口图标 | 轻 IP，不使用大场景 |
| 电站详情 | 家庭、光伏、能源节点 | 图表和状态色 | 数据优先 |
| 设备实时页 | 产品渲染 | 能源流节点、状态图标 | 产品可信度优先 |
| WiFi 配网 | 通信流程插画、小烁 | 扫描/连接动效 | 强 IP 流程 |
| 本地模式 | 本地直连插画 | 未发现设备、权限状态 | 强引导 |
| OTA | OTA 流程插画、小烁 | 储能紫、进度动效 | 分阶段表达 |
| 设置/表单 | 业务图标 | 少量色块 | 保持安静 |
| /about | 品牌愿景场景 | Logo、品牌纹理 | 品牌故事页 |

主要代码接入点：

- lib/core/theme/app_theme.dart
- lib/core/services/role_service.dart
- lib/features/auth/presentation/pages/splash_page.dart
- lib/features/auth/presentation/pages/auth_page.dart
- lib/features/station/presentation/pages/home_page.dart
- lib/features/station/presentation/pages/station_detail_page.dart
- lib/features/dashboard/presentation/pages/dashboard_overview_page.dart
- lib/core/widgets/device_list_view.dart
- lib/features/device/presentation/pages/device_realtime_page.dart
- lib/features/device/presentation/pages/wifi_config_page.dart
- lib/features/device/presentation/pages/local_mode_page.dart
- lib/features/notification/presentation/pages/notification_center_page.dart
- lib/features/ota/presentation/pages/ota_page.dart
- lib/features/ota/presentation/pages/ota_detail_page.dart
- lib/features/ota/presentation/pages/local_ota_page.dart
- lib/core/widgets/offline_banner.dart

---

## 7. 文件与目录规范

建议目录：

    inv_app/assets/
    ├── images/
    │   ├── brand/
    │   ├── mascot/
    │   ├── scenes/
    │   ├── products/
    │   ├── states/
    │   └── flows/
    ├── icons/
    │   ├── nav/
    │   ├── domain/
    │   └── platform/
    └── animations/
        ├── mascot/
        └── energy/

若采用子目录，必须同步在 pubspec.yaml 中声明对应资源目录并完成打包验证。

### 7.1 命名

- 使用小写 snake_case。
- 文件名表达“类型 + 场景 + 状态”，不使用 final2、new、改版等名称。
- 浅色/深色变体使用 _light / _dark 后缀。
- 多倍图使用 Flutter 标准 2.0x/、3.0x/ 目录，不把倍率写入业务文件名。

### 7.2 格式

| 类型 | 首选格式 | 源文件 |
|---|---|---|
| 图标、装饰图形 | SVG | Figma/AI/SVG |
| 3D 角色和产品静态图 | WebP，必要时 PNG | Blender/C4D + 分层 PSD |
| 大场景插画 | WebP，角色和背景分层 | Blender/C4D/Figma/PSD |
| Android 平台图标 | PNG/XML 对应平台规范 | SVG/AI 母版 |
| 3D 动画 | 动画 WebP/帧序列，实施阶段确认 | 3D 源工程 + MP4 预览 |
| 矢量动效 | Lottie JSON | AE/Figma/Rive 等源工程 |

### 7.3 透明度、色彩与文本

- 透明资源必须具有真实 Alpha 通道，不能把棋盘格烘焙进图片。
- 全部使用 sRGB 色彩空间。
- 禁止水印、AI 平台标识和来源不明的版权素材。
- 图片内禁止嵌入产品文案、按钮、版本号、百分比或设备 SN。
- 品牌 Logo 使用正式矢量文件，不由 AI 重新生成文字。

### 7.4 尺寸与安全区

- 图标以 24dp 网格绘制，保证 20dp–28dp 范围内清晰。
- 小图标避免 1px 以下细节、复杂渐变和细碎 3D 材质。
- 状态插画母版 720×720，主体周围至少保留 10% 安全留白。
- 产品母版 2048×2048，卡片版 800×800。
- 场景图按真实容器比例制作并分层交付，允许不同屏幕比例重新裁切。
- 开屏关键人物和 Logo 不进入状态栏、刘海、底部手势区和极端裁切区。

### 7.5 建议体积预算

| 资源 | 单文件建议上限 |
|---|---:|
| 普通 SVG 图标 | 20 KB |
| 导航双色 SVG | 30 KB |
| 状态 WebP | 180 KB |
| 产品卡片 WebP | 250 KB |
| 大场景 WebP | 500 KB |
| 单个 App 动画 | 1.5 MB |

体积上限需结合真机清晰度复核，不能为压缩体积造成明显色带、毛边或透明边缘发黑。

---

## 8. 不应制作的资源

- 不为每个页面制作固定全屏背景 PNG。
- 不为搜索、添加、编辑、返回、更多等通用操作重复制作位图图标。
- 不制作带固定中英文文案的场景插画。
- 不制作“睡觉加载”“夸张惊吓”“哭泣失败”等降低可信度的角色动作。
- 不在严重告警、安全确认和危险操作区域使用大面积吉祥物。
- 不为在线、离线、告警、升级分别重绘完整产品图；状态覆盖由代码和图标表达。
- 不直接使用带水印、AI 错字、伪透明背景或品牌不一致的参考图。

---

## 9. 分批交付优先级

### P0：视觉基线与第一印象

1. 视觉规范与配色系统。
2. 正式 Logo 和 App 自适应图标。
3. 小烁 3D 母版、标准视角和 4 个核心动作：欢迎、设备、WiFi、成功。
4. 开屏场景和登录场景。
5. 逆变器、储能两类产品主渲染。
6. 底部导航 5 组双态 SVG。
7. 4 个核心科技装饰：轨道、点阵、数据网格、光点。

### P1：主导航与高频页面

1. 首页家庭能源场景。
2. 小烁剩余 6 个动作和 5 个表情头像。
3. 10 个状态插画。
4. 12 个能源业务图标。
5. 产品卡片构图与 5 个能源流节点。
6. 首页、统计、设备、告警、我的的多彩视觉适配。

### P2：复杂流程与动效

1. WiFi、本地模式 4 组流程插画。
2. OTA 4 组流程插画。
3. 小烁 3 个动画与能源流/OTA 动效。
4. 关于页品牌场景。
5. 深色模式素材适配和低端机性能优化。

---

## 10. 验收清单

### 角色一致性

- 五官、发型、年龄感、头身比在所有动作中一致。
- 工装版型、Logo 位置、配件尺寸和材质一致。
- 动作符合青年工程师身份，不儿童化、英雄化或夸张卖萌。

### 产品可信度

- 逆变器与储能设备的结构、接口和品牌字标正确。
- 所有产品图视角、焦距、光源和阴影一致。
- 无水印、无伪透明背景、无 AI 错字和无意义结构。

### App 适配

- 在典型 360×800 与 430×932 逻辑布局下不遮挡文字和按钮。
- 浅色和深色背景下保持主体边缘、文字和状态对比度。
- 24dp 图标在真机上轮廓清楚。
- 中英文切换后插画与文本仍有足够空间。
- 资源体积、解码时间和首屏加载时间满足真机要求。

### 视觉一致性

- 角色、3D 场景、产品渲染、二维图标和数据图表属于同一配色体系。
- 多彩来源于业务语义和页面层级，不是随机给每张卡片换色。
- 强 IP 页面与数据页面有明显节奏差异，但导航、字体、圆角和间距连续。

---

## 11. 开发接入原则

1. 先落地主题 Token、SVG 图标组件和统一资源路径，再逐页替换。
2. 角色、场景和产品图使用独立图层，文案、数据、进度和按钮由 Flutter 渲染。
3. 空状态封装成统一组件，通过资源、标题、说明和操作按钮参数化复用。
4. 能源流、状态覆盖、渐变、阴影和背景色尽可能由代码实现，减少重复位图。
5. 每接入一批资源即进行 Android 真机走查，重点验证裁切、透明边缘、深色模式、包体和低端机性能。
6. 正式资源接入前保留当前占位资源，完成页面迁移后再逐项清理，避免一次性删除导致回归。

