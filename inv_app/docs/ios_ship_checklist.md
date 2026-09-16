# iOS 真机编译与上架清单

> 适用：`inv_app`（辰烁光伏逆变）。当前工程脚手架已存在，**尚未配置签名与 Team**。
> 本清单按「能在真机跑起来 → 功能降级可用 → 上架」三阶段排列。

---

## 0. 现状速览（基于代码库）

| 项 | 现状 |
|----|------|
| `ios/` 工程 | 有，`AppDelegate` 仅注册插件 |
| Bundle ID | `com.csergy.app1` |
| 最低系统 | iOS 13.0 |
| 签名 | Automatic，**无 DEVELOPMENT_TEAM** |
| Podfile | 无（首次在 Mac 上 `pod install` 会生成） |
| Info.plist 权限 | 相机 / 蓝牙 / 定位 / 局域网已写好 |
| URL Scheme | `csinv://` 已配 |
| 平台能力层 | 已就位（`lib/core/platform/`），WiFi 扫描/热点/小组件在 iOS 自动降级 |

---

## Phase 1 — 让 App 在真机跑起来（约 1 天）

### 1.1 硬件与账号

- [ ] Mac（macOS 13+，能装当前稳定版 Xcode）
- [ ] Xcode + Command Line Tools
- [ ] Flutter 稳定版（与团队 Android 开发用的版本对齐，建议先 `flutter --version` 记录）
- [ ] Apple Developer 账号（个人 $99 / 公司 $99，公司账号需 D-U-N-S）
- [ ] iPhone 真机（iOS 13+，建议 iOS 16+ 做主测机）
- [ ] 真机与 Mac 同一 Wi-Fi（无线调试）或 USB 线

### 1.2 仓库准备（Windows 侧可先做）

- [ ] 确认 `inv_app/ios/` 已提交（含 `Runner.xcodeproj`、`Info.plist`、Assets）
- [ ] 确认 `.gitignore` 未忽略 `ios/` 源文件（`Pods/`、`Flutter/ephemeral/` 可忽略）
- [ ] 把 `inv_app` 拷到 Mac，或 `git clone` 后切到同一分支

### 1.3 Mac 上首次构建

```bash
cd inv_app
flutter clean
flutter pub get
cd ios && pod install && cd ..   # 首次会生成 Podfile 并拉 CocoaPods
flutter devices                  # 应能看到 iPhone
```

- [ ] `flutter build ios --debug` 能跑通（可先 simulator）
- [ ] 连上真机后 `flutter devices` 出现设备 UDID
- [ ] `flutter run -d <device-id>` 首次会报签名/权限类错误，进入 1.4

### 1.4 签名配置（Xcode）

打开 `ios/Runner.xcworkspace`（**不是** `.xcodeproj`）：

1. Target `Runner` → **Signing & Capabilities**
2. Team：选择你的 Apple Developer 团队
3. Bundle Identifier：保持 `com.csergy.app1`，或改成公司正式 ID（上架后不可随意改）
4. Automatically manage signing：勾选
5. 若 Bundle ID 被占用：改唯一 ID，例如 `com.csergy.csinv`

- [ ] Team 已选，无红色报错
- [ ] 真机信任证书：iPhone → 设置 → 通用 → VPN 与设备管理 → 信任开发者
- [ ] 再次 `flutter run` 能进首页

### 1.5 首次真机冒烟（允许功能残缺）

| 检查 | 预期 | 优先级 |
|------|------|--------|
| 启动进闪屏/登录 | 不闪退 | P0 |
| 账号密码登录 | 能进主页 | P0 |
| 设备列表加载 | 云端接口通 | P0 |
| 电站/仪表盘 | 数据可展示 | P0 |
| 通知中心（站内） | 可打开 | P1 |
| 扫码添加设备 | 相机权限 + 扫码 | P1 |
| BLE 配网/本地升级 | 若有 BLE 设备可测 | P1 |
| WiFi 配网 / 本地 OTA | **iOS 默认不可用**，见 Phase 2 | P2 |
| 桌面小组件 | iOS 未做，跳过 | P2 |
| 一键登录 | 蜂窝下可试，失败则账号登录 | P1 |

---

## Phase 2 — 功能降级与插件补齐（1–2 周）

> 原则：**能进主流程 > 个别高级功能**。本地 OTA / WiFi 扫描在 iOS 上系统限制严格，优先做 BLE 通道。

### 2.1 平台能力（已实现，确认 UI 隐藏）

代码里 `PlatformCapabilities` 已把下列能力在非 Android 关掉：

- `canScanWifi` / `canJoinWifiAp` / `canLocalOtaWifiAp`
- `supportsHomeWidget` / `hasAmbientLight`

- [ ] iOS 真机上「WiFi 本地升级」入口不可用或引导到 BLE（若尚未隐藏，用 `PlatformCapabilities.canLocalOtaWifiAp` 过滤）
- [ ] 配网页：iOS 优先展示 **BLE 配网**；WiFi SoftAP 路径提示「请用 Android 或蓝牙」
- [ ] 扫码页：环境光自动补光仅 Android；iOS 走「连续扫不到」启发式（已有）

### 2.2 本地 OTA 策略（决策）

| 方案 | 说明 | 建议 |
|------|------|------|
| A. 仅 BLE 本地升级 | iOS 只走 `flutter_blue_ultra` 通道 | **一期推荐** |
| B. 引导用户手动连热点 | 文案引导「设置→Wi-Fi→连 CS-INV-xxx」，再回 App HTTP 升级 | 二期可选 |
| C. NEHotspotConfiguration | 可弹系统加入指定 SSID，但**不能扫周边列表** | 需原生开发 |

- [ ] 产品确认一期采用 **方案 A**
- [ ] OTA 页在 iOS 默认 channel = BLE
- [ ] 验证：BLE 连设备 → 传固件 → 进度 → 结果回传云端

### 2.3 推送（JPush iOS）

极光官方支持 iOS，但配置比 Android 重：

- [ ] Apple Developer → 证书：创建 **Apple Push Services** 证书（生产）+ 开发证书
- [ ] 导出 `.p8` / `.cer` + `.p12`，上传到极光控制台对应 AppKey
- [ ] Xcode：Runner → Capabilities → **Push Notifications** 打开
- [ ] Xcode：Capabilities → **Background Modes** → 勾选 Remote notifications
- [ ] Info.plist 补通知相关描述（若被审核要求）
- [ ] `AppDelegate.swift` 按极光文档补 APNs 注册回调（当前文件几乎为空，**需要改**）
- [ ] 真机：杀进程推送能到、点击能进 `/alarms`
- [ ] 代码已用 `PlatformCapabilities.supportsPush`，iOS 会 init；失败不闪退

### 2.4 一键登录（JVerify iOS）

- [ ] 极光控制台开通 iOS 一键登录，配置运营商素材
- [ ] 蜂窝数据 + 有 SIM 的 iPhone 上测试
- [ ] 失败降级：短信/账号密码（已有 `JVerifyCarrierException` 分支）
- [ ] 非蜂窝环境直接不展示一键登录按钮（`supportsOneTapLogin` 已开，但环境检查已有）

### 2.5 其它插件注意点

| 插件 | iOS 注意 |
|------|----------|
| `flutter_blue_ultra` | 需蓝牙权限文案（已写）；后台蓝牙需额外能力 |
| `wifi_iot` | iOS 能力极弱；业务已走 `WifiApController`，iOS 为 Unsupported |
| `mobile_scanner` | 相机权限（已写）；真机测扫码 |
| `home_widget` | 一期不做 WidgetKit |
| `image_cropper` / `image_picker` | 相册/相机权限，系统会弹 |
| `flutter_map` | OSM 瓦片；注意 App Privacy 声明位置数据 |
| `sqflite` | 无特殊 |
| `flutter_secure_storage` | Keychain，无特殊 |

### 2.6 必须补的原生代码

当前 `AppDelegate.swift` 只有：

```swift
GeneratedPluginRegistrant.register(with: self)
return super.application(...)
```

iOS 上线前通常还要：

- [ ] APNs：`didRegisterForRemoteNotifications` / `didFailToRegister` / `didReceiveRemoteNotification`（按 jpush_flutter 文档）
- [ ] 如需 Universal Links（扫码/邀请链接）：Associated Domains + AASA 文件
- [ ] 如需深链 `csinv://`：已配 URL Types，真机 Safari/备忘录测一次

---

## Phase 3 — 上架 App Store（3–5 个工作日 + 审核）

### 3.1 证书与描述文件

- [ ] App ID 与 Bundle ID 一致
- [ ] Distribution 证书
- [ ] App Store 描述文件
- [ ] 测试可用 TestFlight（推荐先内测）

### 3.2 打包

```bash
# 注入生产 API（与 Android 发版脚本对齐）
flutter build ipa --release \
  --dart-define=API_BASE_URL=https://api.jiuxiaoyw.online/api/v1 \
  --dart-define=APP_VERSION_NAME=1.0.4 \
  --dart-define=APP_VERSION_CODE=14
```

- [ ] `build/ios/ipa/*.ipa` 产出
- [ ] Xcode Organizer / Transporter / `xcrun altool` 上传
- [ ] App Store Connect 出现构建版本

### 3.3 元数据与合规

- [ ] 应用名称、副标题、关键词、截图（6.7" / 6.5" / 5.5"，至少 6.7"）
- [ ] 隐私政策 URL（仓库已有 `https://www.csinv.com/privacy`）
- [ ] **App 隐私**（Privacy Nutrition Labels）：
  - [ ] 联系信息（手机号登录）
  - [ ] 位置（配网/电站选址）
  - [ ] 蓝牙（设备配网）
  - [ ] 诊断/使用数据（按实际上报）
- [ ] 年龄分级问卷
- [ ] 出口合规（加密：一般勾选标准加密豁免；用了 HTTPS 即可走标准路径）
- [ ] 审核备注：说明需要蓝牙/Wi-Fi/相机用于光伏设备配网与监控

### 3.4 审核风险点（提前规避）

| 风险 | 原因 | 规避 |
|------|------|------|
| 未用功能权限 | Info.plist 写了用不到的权限 | 删除未用描述，或保证功能真实用到 |
| 一键登录失败进不去 | 无蜂窝/SIM | 保证账号密码登录始终可用 |
| 隐私政策打不开 | URL 失效 | 上线前 curl 验证 |
| 崩溃/启动黑屏 | 插件 iOS 未初始化 | TestFlight 至少 2 台不同机型过冒烟 |
| 热更新/自更新 | App 内下载 APK/IPA | iOS **禁止**自更新安装包；仅引导 App Store |

### 3.5 上线后

- [ ] TestFlight 外部测试 20–50 人
- [ ] 监控崩溃（Xcode Organizer / Firebase Crashlytics 等）
- [ ] 推送到达率抽查
- [ ] 版本号策略：`pubspec version` 与 `CFBundleShortVersionString` 同步（脚本 `build_release.bat` 思路可扩到 iOS）

---

## 推荐时间表（单人）

| 周次 | 目标 |
|------|------|
| 第 1 周 | 签名 + 真机跑通主流程 + 登录/列表/详情 |
| 第 2 周 | BLE 本地升级闭环 + 扫码/配网降级 + 推送证书 |
| 第 3 周 | TestFlight 内测修问题 + 隐私标签 + 提审 |
| 第 4 周 | 审核跟进、上架、灰度 |

---

## 与 Android 的差异备忘（给开发）

1. **不要**在 iOS 上期望 `WifiScanPlugin.kt` 等价能力；扫描周边 Wi-Fi 列表需特殊资质。
2. `forceWifiUsage` 是 Android 概念；iOS 流量绑定模型不同，走 `UnsupportedWifiApController`。
3. 极光一键登录/推送在 iOS 要独立证书与素材，不是 Android AppKey 一套通吃。
4. 桌面小组件要另开 WidgetKit Extension，属于独立工程目标。
5. 自更新下载 `.ipa` 会被拒；更新必须走 App Store。

---

## 命令速查

```bash
# 设备
flutter devices

# 调试运行
flutter run -d <ios-device-id>

# 分析 / 测试（Windows 上也可先跑）
flutter analyze
flutter test test/core/platform/

# 发布构建
flutter build ipa --release --dart-define=API_BASE_URL=...

# 强制清理
flutter clean && cd ios && pod install && cd ..
```
