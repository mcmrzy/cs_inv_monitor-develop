# CSERGY App 页面级美术资源映射说明

> 收尾任务 F｜盘点日期：2026-08-05｜适用产品：`inv_app` Flutter 移动端
>
> 本文只定义页面级美术资源路由、正式目标路径、规格、浅深色要求、可复用组件和接入优先级；本任务不修改代码、SVG、`pubspec.yaml` 或其他文档。

## 1. 当前结论

当前美术资源**尚未达到可商用发布状态**。本文是生产接入蓝图，不把“文件存在”视为“资源完成”。

- `assets/icons/csergy/` 当前有 24 个 SVG，已完成静态 XML、`24×24 viewBox`、`currentColor` 检查；仍需完成 33 条路由的实际引用、浅深色截图、无障碍和真机性能验收。
- 正式品牌、角色、真实产品、状态、场景和流程资源的目标路径如下文登记；目标文件未交付时必须标记缺失，不能用泛化设备或临时图替代。
- 用户提供的实物图及生成图只用于设计核对，不能直接进入发布包。

## 2. 正式资源路径与规格

以下路径是正式运行时资源的目标命名。当前尚未交付的目标文件不得通过复制 reference 文件、改名或生成空文件伪装完成。

### 2.1 品牌、角色和产品

| 类别 | 正式路径 | 规格 | 当前状态 |
|---|---|---|---|
| 品牌图形 | `assets/brand/csergy-logo.svg` | SVG 矢量；透明安全区；浅色版 | 缺失 |
| 品牌字标 | `assets/brand/csergy-wordmark.svg` | SVG 矢量；最小显示宽度建议 `96dp` | 缺失 |
| 深色品牌 | `assets/brand/csergy-logo-on-dark.svg`、`csergy-wordmark-on-dark.svg` | SVG；不烘焙背景；深色背景对比度合格 | 缺失 |
| 中文品牌（条件） | `assets/brand/csergy-wordmark-zh.svg` | 仅企业信息/中文品牌页使用；不替代衣服上的 `CSERGY` | 未锁定源文件 |
| 小烁基础表情 | `assets/character/xiaoshuo/xiaoshuo-{welcome,success,reminder,curious,failure}-1024.webp` | 透明底；默认 `1024×1024`；胸前六边形固定使用正式 `CSERGY` | 缺失；当前只有 reference/generated |
| 小烁流程动作 | `assets/character/xiaoshuo/xiaoshuo-guide-{wifi,ota}-1536x1024.webp` | 透明或可控背景；`1536×1024`；不嵌入动态文案 | 缺失 |
| 逆变器母版 | `assets/products/csergy-inverter-product-master-2048.png` | `2048×2048`；真实 Alpha；sRGB；无水印 | 缺失/验收阻塞 |
| 逆变器卡片 | `assets/products/csergy-inverter-product-card-800.webp` | `800×800`；透明或指定卡片底色 | 缺失/验收阻塞 |
| 逆变器主题预览 | `assets/products/csergy-inverter-product-light-800.webp`、`...-dark-800.webp` | 各 `800×800`；白色箱体、黑色控制区和字标在两种背景可读 | 缺失 |
| 储能母版 | `assets/products/csergy-storage-product-master-2048.png` | `2048×2048`；真实 Alpha；保留橙/黑端子、中央指示灯、把手和脚轮 | 缺失/验收阻塞 |
| 储能卡片 | `assets/products/csergy-storage-product-card-800.webp` | `800×800`；保留真实端子、脚轮和 `CSERGY` 字标 | 缺失/验收阻塞 |
| 储能主题预览 | `assets/products/csergy-storage-product-light-800.webp`、`...-dark-800.webp` | 各 `800×800`；深色背景不吞掉白箱体和黑色指示灯 | 缺失 |

### 2.2 状态、场景和流程

| 类别 | 正式目标路径 | 规格/语义 |
|---|---|---|
| 状态插画 | `assets/illustrations/states/{empty-stations,empty-devices,empty-alarms,empty-search,offline,network-error,permission-denied,partial-failure,connecting,ota-success,ota-failure,ota-validation-failure,update-available,update-latest,update-download-failure,form-success}-640.webp` | 默认 `640×480`；全页空态可交付 `1024×768`；带背景状态需提供 `-light`/`-dark` |
| 场景插画 | `assets/illustrations/scenes/scene-{energy-home,auth,local-connect,ota,profile}-{light,dark}-1600.webp` | 各 `1600×900`；文字安全区至少 `24dp`；不能用场景图伪装真实产品结构 |
| 流程插画 | `assets/illustrations/flows/flow-{app-init,auth-recovery,station-create,station-edit,device-pair,device-control,device-protocol,device-history,device-settings,wifi-connect,local-mode,ota-remote,ota-local,alarm-resolve,account-settings,app-update}-1200.webp` | `1200×600`；步骤文字由 Flutter 渲染，不烘焙多语言或动态数值 |

### 2.3 业务图标

正式图标路径为 `assets/icons/csergy/`：

- 导航双态：`nav_home_*`、`nav_statistics_*`、`nav_devices_*`、`nav_alarms_*`、`nav_ota_*`、`nav_profile_*`，每组 normal/active。
- 业务图标：`solar.svg`、`grid.svg`、`battery.svg`、`load.svg`、`inverter.svg`、`storage.svg`、`power.svg`、`energy_flow.svg`、`monitoring.svg`、`warning.svg`、`wifi.svg`、`firmware.svg`。
- 统一要求：`24×24 viewBox`、`currentColor`、统一线宽和圆角端点；图标只表达语义，不替代真实产品图。

## 3. 33 条真实路由映射

每行按“品牌 / 角色 / 产品 / 状态 / 场景 / 业务图标 / 流程插画”顺序映射。路径引用上节正式目标；`—` 表示该页面不需要该类别的主视觉。

### 3.1 认证与品牌入口

| # | 路由 | 页面 | 资源映射 | 优先级 |
|---:|---|---|---|---|
| 1 | `/splash` | 开屏 | `csergy-logo/wordmark` / `xiaoshuo-welcome` / inverter+storage light card / network-error+connecting / energy-home light/dark / `solar`,`energy_flow` / `flow-app-init` | P0 |
| 2 | `/login` | 登录 | `csergy-logo/wordmark` + dark / `xiaoshuo-welcome` / — / network-error+form-success / auth light/dark / `wifi`+第三方登录图标 / `flow-auth-recovery` | P0 |
| 3 | `/jverify-login` | 一键登录 | `csergy-logo/wordmark` / `xiaoshuo-welcome` / — / connecting+network-error+form-success / auth light/dark / `monitoring`,`warning` / `flow-auth-recovery` | P0 |
| 4 | `/register` | 注册 | `csergy-logo/wordmark` / `xiaoshuo-welcome` / — / network-error+form-success / auth light/dark / `monitoring`,`warning` / `flow-auth-recovery` | P0 |
| 5 | `/forgot-password` | 忘记密码 | `csergy-logo/wordmark` / `xiaoshuo-reminder+success` / — / network-error+form-success / auth light/dark / `warning`,`monitoring` / `flow-auth-recovery` | P0 |

### 3.2 主导航与数据页面

| # | 路由 | 页面 | 资源映射 | 优先级 |
|---:|---|---|---|---|
| 6 | `/home` | 首页/电站 | `csergy-logo/wordmark` / welcome+curious+failure / inverter+storage card / empty-stations+empty-search+offline+network-error+partial-failure / energy-home light/dark / `solar`,`grid`,`battery`,`load`,`inverter`,`storage`,`power`,`energy_flow`,`monitoring`,`warning` / `flow-app-init` | P0 |
| 7 | `/statistics` | 统计 | `csergy-logo` / curious+failure / inverter+storage card（设备分布时） / empty-search+offline+network-error+partial-failure+connecting / energy-home 低密度裁切 / `solar`,`grid`,`battery`,`load`,`power`,`energy_flow`,`monitoring`,`warning` / `flow-app-init` | P0 |
| 8 | `/devices` | 设备列表 | `csergy-logo` / curious+failure / inverter+storage card / empty-devices+empty-search+offline+network-error+permission-denied / — / `inverter`,`storage`,`monitoring`,`wifi`,`firmware`,`warning` / `flow-device-pair` | P0 |
| 9 | `/alarms` | 告警中心 | `csergy-logo` / reminder+curious / inverter+storage card（绑定设备时） / empty-alarms+offline+network-error+permission-denied+partial-failure / — / `warning`,`monitoring` / `flow-alarm-resolve` | P0 |
| 10 | `/profile` | 个人中心 | `csergy-logo/wordmark` / welcome+reminder / — / network-error+permission-denied / profile light/dark / `monitoring`,`wifi`,`firmware` / `flow-account-settings` | P1 |

### 3.3 OTA 与升级

| # | 路由 | 页面 | 资源映射 | 优先级 |
|---:|---|---|---|---|
| 11 | `/ota` | OTA 总入口 | `csergy-logo/wordmark` / reminder+curious / inverter+storage card / empty-devices+offline+network-error+permission-denied+partial-failure / ota light/dark / `firmware`,`inverter`,`storage`,`warning` / `flow-ota-remote` | P0 |
| 12 | `/ota/:sn` | 设备 OTA | `csergy-logo` / reminder+failure / inverter 或 storage card / offline+network-error+connecting+ota-failure / ota light/dark / `firmware`,`monitoring`,`warning` / `flow-ota-remote` | P0 |
| 13 | `/ota/:sn/detail` | OTA 详情 | `csergy-logo` / reminder+success+failure / inverter 或 storage card / connecting+ota-success+ota-failure+ota-validation-failure / ota light/dark / `firmware`,`power`,`warning` / `flow-ota-remote` | P0 |
| 14 | `/ota/:sn/local` | 设备本地 OTA | `csergy-logo` / guide-ota+success+failure / inverter 或 storage card / connecting+ota-success+ota-failure+ota-validation-failure / local-connect 与 ota light/dark / `firmware`,`wifi`,`warning` / `flow-ota-local` | P0 |

### 3.4 电站

| # | 路由 | 页面 | 资源映射 | 优先级 |
|---:|---|---|---|---|
| 15 | `/station/create` | 新建电站 | `csergy-logo/wordmark` / welcome+curious / inverter+storage card（选择类型时） / network-error+form-success / energy-home 低密度裁切 / `solar`,`grid`,`monitoring`,`warning` / `flow-station-create` | P1 |
| 16 | `/station/:id` | 电站详情 | `csergy-logo` / welcome+curious+failure / inverter+storage card / empty-search+offline+network-error+partial-failure / energy-home light/dark / `solar`,`grid`,`battery`,`load`,`power`,`energy_flow`,`monitoring`,`warning` / `flow-app-init` | P0 |
| 17 | `/station/:id/edit` | 编辑电站 | `csergy-logo` / reminder+success / inverter+storage card（摘要） / network-error+form-success / — / `monitoring`,`warning` / `flow-station-edit` | P1 |

### 3.5 设备与本地连接

| # | 路由 | 页面 | 资源映射 | 优先级 |
|---:|---|---|---|---|
| 18 | `/device/:sn` | 设备详情 | `csergy-logo` / welcome+curious+failure / inverter 或 storage hero/card / offline+network-error+partial-failure+connecting / energy-home 设备裁切 / `inverter`,`storage`,`power`,`energy_flow`,`monitoring`,`warning` / `flow-app-init` | P0 |
| 19 | `/device/:sn/control` | 设备控制 | `csergy-logo` / reminder+success+failure / inverter 或 storage hero / offline+network-error+permission-denied+connecting+form-success / energy-home 设备裁切 / `power`,`energy_flow`,`warning` / `flow-device-control` | P0 |
| 20 | `/device/:sn/protocol` | 协议配置 | `csergy-logo` / reminder+curious / inverter 或 storage card / network-error+permission-denied+form-success / — / `monitoring`,`wifi`,`firmware`,`warning` / `flow-device-protocol` | P1 |
| 21 | `/device/:sn/history` | 历史数据 | `csergy-logo` / curious+failure / inverter 或 storage card / empty-search+offline+network-error+partial-failure / — / `power`,`energy_flow`,`monitoring` / `flow-device-history` | P1 |
| 22 | `/device/:sn/settings` | 设备设置 | `csergy-logo` / reminder+success / inverter 或 storage card / offline+network-error+permission-denied+form-success / — / `monitoring`,`wifi`,`firmware`,`warning` / `flow-device-settings` | P1 |
| 23 | `/device/:sn/edit` | 编辑设备 | `csergy-logo` / reminder+success / inverter 或 storage card / network-error+permission-denied+form-success / — / `inverter`,`storage`,`monitoring`,`warning` / `flow-device-settings` | P1 |
| 24 | `/add-device` | 添加设备 | `csergy-logo/wordmark` / welcome+curious+guide-wifi / inverter+storage card / empty-devices+network-error+permission-denied+connecting+form-success / local-connect light/dark / `inverter`,`storage`,`wifi`,`monitoring`,`warning` / `flow-device-pair` | P0 |
| 25 | `/wifi-config` | WiFi 配网 | `csergy-logo` / guide-wifi+reminder+success+failure / inverter 或 storage card / offline+network-error+connecting+form-success / local-connect light/dark / `wifi`,`monitoring`,`warning` / `flow-wifi-connect` | P0 |
| 26 | `/local-mode` | 本地模式 | `csergy-logo` / guide-wifi+reminder+success+failure / inverter 或 storage card / offline+network-error+permission-denied+connecting / local-connect light/dark / `wifi`,`inverter`,`storage`,`monitoring`,`warning` / `flow-local-mode` | P0 |
| 27 | `/local-ota` | 本地 OTA 向导 | `csergy-logo` / guide-ota+success+failure / inverter 或 storage card / connecting+ota-success+ota-failure+ota-validation-failure / local-connect 与 ota light/dark / `wifi`,`firmware`,`warning` / `flow-ota-local` | P0 |

### 3.6 告警、用户与设置

| # | 路由 | 页面 | 资源映射 | 优先级 |
|---:|---|---|---|---|
| 28 | `/alarm/:id` | 告警详情 | `csergy-logo` / reminder+failure+success / inverter 或 storage card / offline+network-error+permission-denied+partial-failure+form-success / — / `warning`,`monitoring`,`inverter`,`storage` / `flow-alarm-resolve` | P0 |
| 29 | `/settings` | 设置 | `csergy-logo/wordmark` / reminder+curious / — / network-error+permission-denied+form-success / profile 低密度裁切 / `wifi`,`monitoring`,`firmware`,`warning` / `flow-account-settings` | P1 |
| 30 | `/change-password` | 修改密码 | `csergy-logo/wordmark` / reminder+success+failure / — / network-error+form-success / profile 低密度裁切 / `warning`,`monitoring` / `flow-auth-recovery` | P1 |
| 31 | `/edit-profile` | 编辑资料 | `csergy-logo/wordmark` / welcome+success+reminder / — / network-error+form-success / profile light/dark / `monitoring`,`warning` / `flow-account-settings` | P1 |
| 32 | `/about` | 关于页 | `csergy-logo/wordmark` + dark / welcome / inverter+storage light/dark card / update-available+update-latest+update-download-failure / profile light/dark / `firmware`,`inverter`,`storage`,`energy_flow` / `flow-app-update` | P0 |
| 33 | `/notify-settings` | 通知设置 | `csergy-logo/wordmark` / reminder+success / — / network-error+permission-denied+form-success / profile 低密度裁切 / `warning`,`monitoring`,`wifi` / `flow-account-settings` | P1 |

## 4. 可复用组件契约

页面接入应通过单一资源映射层，不再散落硬编码路径。推荐复用以下组件：

| 组件 | 资源 | 尺寸 | 主要页面 |
|---|---|---:|---|
| `CsergyBrandHeader` | 品牌 B1–B4 | AppBar `112×28dp`；认证 `160×40dp` | 认证、首页、OTA、设置、关于 |
| `XiaoshuoStatePanel` | C1–C7 + S1–S16 | 插画 `160–240dp` | 空态、错误、连接、OTA、表单结果 |
| `CsergyProductCard` | P2/P6；主题用 P3/P4/P7/P8 | 列表 `80–112dp` | 首页、设备、电站、OTA、关于 |
| `CsergyProductHero` | P1/P5 或 P3/P7 | `220–320dp` | 设备详情、控制、关于 |
| `EnergyFlowCard` | G1/G2 + 能源图标 | `160–260dp` | 首页、统计、电站详情 |
| `CsergyStatusEmptyState` | S1–S8 + C3/C4/C5 | 插画 `160–240dp` | 首页、设备、告警、统计、历史 |
| `CsergyConnectionStepper` | F5/F10/F11 + S9 | 步骤图 `72–120dp` | 添加设备、WiFi、本地模式 |
| `CsergyOtaStepper` | F12/F13 + C7 + S9–S12 | 步骤图 `72–120dp` | 远程/本地 OTA |
| `CsergyBusinessIcon` | 24 个 CSERGY SVG | `20–24dp`；点击区不小于 `48×48dp` | 导航、图表、标签、列表 |

## 5. 浅深色和发布门禁

- Logo、场景和带背景状态必须成对提供 `light/dark`；透明产品母版和透明角色必须在浅灰与深海蓝背景各检查一次。
- 图标使用 `currentColor`，不可在 SVG 内写死黑/白背景；同一语义在图标、图表、标签、插画中保持相同颜色。
- 白色逆变器/储能产品必须检查白边、黑边、透明毛刺、字标清晰度和深色背景可辨识度。
- 大图优先 WebP；列表只加载 `800×800` 卡片图，禁止滚动列表直接加载 `2048×2048` 母版。
- 状态和流程图不得烘焙步骤标题、按钮、版本号或动态数值；动态文字由 Flutter 渲染。

### 当前禁止进入发布包

| 当前路径 | 状态 | 原因 |
|---|---|---|
| `assets/reference/products/csergy-inverter-reference.png` | reference | RGB、无真实 Alpha、带水印，仅用于实物结构核对 |
| `assets/reference/products/csergy-storage-reference.jpg` | reference | JPEG、无 Alpha、带水印，仅用于实物结构核对 |
| `assets/reference/products/generated/*` | generated candidate | 未完成真实结构、字标、Alpha 和水印验收 |
| `assets/reference/characters/generated/*` | generated candidate | 未完成胸前 `CSERGY` 和生产规格验收 |
| `assets/images/solar_panel.png` | legacy temporary | 当前开屏/首页占位图，不能代表 CSERGY 真实产品 |
| `assets/images/brand_logo.png`、`brand_name.png` | brand candidate | 缺少正式源文件、主题版本和安全区验收 |
| `assets/images/ic_*.png` | legacy candidate | 历史 PNG，未完成统一风格和主题回归 |

`assets/icons/csergy/*.svg` 属于**生产候选**：静态门禁已通过，但必须完成页面实际引用、浅深色截图、无障碍、低端机解码和未使用文件决策后才可作为最终发布资源。`assets/icons/google.svg`、`wechat.svg` 也属于第三方候选，须完成实际接入和品牌/授权确认。

## 6. 接入优先级

### P0

完成 B1–B4、P1–P8、C1–C7、S1–S12；优先接入开屏、认证、首页、统计、设备、告警、远程/本地 OTA、设备详情/控制、添加设备、WiFi、本地模式、告警详情和关于页，并完成浅色、深色、加载、空态、错误、离线、权限和 360dp 小屏截图回归。

### P1

完成 S13–S16、G1–G10、F3–F11、F14–F16；接入电站编辑、协议、历史、设置、个人资料、密码和通知页面；清理 `solar_panel.png` 和未使用历史 PNG 的运行时引用。

### P2

补充产品多视角、动效、横屏和包体积优化；明确 `nav_ota_*` 是否作为一级入口；建立版本登记和自动化资源门禁。

**最终完成标准：** 33 条路由均能解析到正式资源或明确的系统 UI 回退；reference/generated/临时资源不进入发布集合；产品结构、品牌字标、浅深色、无障碍、真机截图、构建和资源加载全部通过验收后，才可标记为“完整、可商用”。
