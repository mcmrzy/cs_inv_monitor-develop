# 极光 SDK 配置差异分析报告

## 1. 文件概览

### 已分析的文件
- ✅ Demo AndroidManifest: `inv_app/android/jiguang_sdk/jiguang_sdk/jiguang-demo/src/main/AndroidManifest.xml`
- ✅ Jiguang 模块 AndroidManifest: `inv_app/android/jiguang_sdk/jiguang_sdk/jiguang/src/main/AndroidManifest.xml`
- ✅ Jiguang 模块 build.gradle: `inv_app/android/jiguang_sdk/jiguang_sdk/jiguang/build.gradle`
- ✅ Jiguang libs 目录: `inv_app/android/jiguang_sdk/jiguang_sdk/jiguang/libs/`
- ✅ jiguang_auth 插件 AndroidManifest: `C:\Users\29538\AppData\Local\Pub\Cache\hosted\pub.dev\jiguang_auth-3.0.3\android\src\main\AndroidManifest.xml`
- ✅ jiguang_auth 插件 build.gradle: `C:\Users\29538\AppData\Local\Pub\Cache\hosted\pub.dev\jiguang_auth-3.0.3\android\build.gradle`
- ✅ Flutter 项目 AndroidManifest: `inv_app/android/app/src/main/AndroidManifest.xml`

---

## 2. 原生 SDK 库文件（libs 目录）

### Jiguang 模块 libs 目录包含：

#### AAR/JAR 文件
```
jcore-android-5.5.0.aar              (1631.0KB) - 极光核心库
jpush-android-6.2.0.jar              (424.5KB)  - JPush 推送 SDK
jpush-android-plugin-fcm-v6.2.0.jar  (28.6KB)   - FCM 推送插件
jverification-android-not_support_dynamic-release-3.4.8.jar (813.8KB) - 一键登录验证 SDK
```

#### Native SO 库（分架构）
```
arm64-v8a/libCtaApiLib.so   (917.5KB) - CTA 认证库（64位 ARM）
armeabi-v7a/libCtaApiLib.so            - CTA 认证库（32位 ARM）
x86/libCtaApiLib.so                    - CTA 认证库（x86）
x86_64/libCtaApiLib.so                 - CTA 认证库（x86_64）
```

**⚠️ 重要发现**：jiguang_auth 插件的 build.gradle 使用 Maven 依赖
```gradle
implementation 'cn.jiguang.sdk:jverification:3.3.1'
```
而我们下载的 demo 使用的是本地 JAR 文件（版本 3.4.8）。

---

## 3. 权限配置差异

### 3.1 Demo 要求的权限

| 权限 | Demo | Jiguang 模块 | 我们的项目 | jiguang_auth | 状态 |
|------|------|--------------|------------|--------------|------|
| `JOPERATE_MESSAGE` (自定义) | ✅ | ❌ | ❌ | ❌ | 需要添加 |
| `JPUSH_MESSAGE` (自定义) | ❌ | ✅ | ❌ | ❌ | 需要添加 |
| `INTERNET` | ✅ | ✅ | ✅ | ❌ | 已配置 |
| `ACCESS_NETWORK_STATE` | ✅ | ✅ | ✅ | ❌ | 已配置 |
| `ACCESS_WIFI_STATE` | ✅ | ✅ | ✅ | ❌ | 已配置 |
| `CHANGE_NETWORK_STATE` | ✅ | ❌ | ✅ | ❌ | 已配置 |
| `ACCESS_COARSE_LOCATION` | ✅ | ✅ | ✅ | ❌ | 已配置 |
| `ACCESS_FINE_LOCATION` | ✅ | ✅ | ✅ | ❌ | 已配置 |
| `ACCESS_BACKGROUND_LOCATION` | ❌ | ✅ | ❌ | ❌ | 可选 |
| `READ_PHONE_STATE` | ❌ | ✅ | ❌ | ❌ | 需要添加 |
| `QUERY_ALL_PACKAGES` | ❌ | ✅ | ❌ | ❌ | 需要添加 |
| `GET_TASKS` | ❌ | ✅ | ❌ | ❌ | 需要添加 |
| `WRITE_EXTERNAL_STORAGE` | ❌ | ✅ | ✅ (max 32) | ❌ | 已配置 |
| `READ_EXTERNAL_STORAGE` | ❌ | ✅ | ✅ (max 28) | ❌ | 已配置 |
| `POST_NOTIFICATIONS` | ❌ | ✅ | ✅ | ❌ | 已配置 |
| `CAMERA` | ✅ | ✅ | ✅ | ❌ | 已配置 |
| `RECORD_AUDIO` | ❌ | ✅ | ❌ | ❌ | JMRTC 需要 |
| `MODIFY_AUDIO_SETTINGS` | ❌ | ✅ | ❌ | ❌ | JMRTC 需要 |
| `GET_ACCOUNTS` | ✅ | ❌ | ❌ | ❌ | 可选 |
| `READ_PROFILE` | ✅ | ❌ | ❌ | ❌ | 可选 |
| `READ_CONTACTS` | ✅ | ❌ | ❌ | ❌ | 可选 |
| `REQUEST_INSTALL_PACKAGES` | ✅ | ❌ | ✅ | ❌ | 已配置 |

### 3.2 需要添加到 Flutter 项目的权限

```xml
<!-- 极光推送核心权限 -->
<permission
    android:name="${applicationId}.permission.JPUSH_MESSAGE"
    android:protectionLevel="signature" />
<uses-permission android:name="${applicationId}.permission.JPUSH_MESSAGE" />

<!-- JVerification 一键登录所需 -->
<uses-permission android:name="android.permission.READ_PHONE_STATE" />
<uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"/>
<uses-permission android:name="android.permission.GET_TASKS" />
```

---

## 4. Activity 配置差异

### 4.1 Jiguang 模块声明的 Activity（核心）

#### JPush 推送相关（✅ 已在 jiguang 模块中声明）

| Activity | 作用 | 是否必须 |
|----------|------|----------|
| `cn.jpush.android.ui.PopWinActivity` | Rich Push 弹窗 | ✅ 必须 |
| `cn.jpush.android.ui.PushActivity` | 推送核心 Activity | ✅ 必须 |
| `cn.jpush.android.service.JNotifyActivity` | 通知栏展示 (since 3.3.0) | ✅ 必须 |
| `cn.android.service.JTransitActivity` | 核心功能 (since 4.6.0) | ✅ 必须 |

#### JVerification 一键登录相关（⚠️ 需要关注）

| Activity | 作用 | Jiguang 模块 | jiguang_auth 插件 |
|----------|------|--------------|-------------------|
| `com.cmic.gen.sdk.view.GenLoginAuthActivity` | 移动认证授权页 | ✅ | ❌ (Maven 自动处理) |
| `cn.jiguang.verifysdk.CtLoginActivity` | 电信登录页 | ✅ | ❌ (Maven 自动处理) |
| `com.cmic.sso.sdk.activity.OAuthActivity` | OAuth 授权 | ✅ (Demo) | ❌ (Maven 自动处理) |

**✅ 好消息**：jiguang_auth 插件通过 Maven 依赖自动引入了这些 Activity，无需手动声明。

### 4.2 需要在 Flutter 项目添加的 Activity

**❌ 无需添加 Activity**
- jiguang_auth 插件通过 Maven 依赖 (`cn.jiguang.sdk:jverification:3.3.1`) 自动包含所有必要的 Activity
- JPush 相关 Activity 由 jpush_flutter 插件自动处理

---

## 5. Meta-data 配置差异

### 5.1 必需的 Meta-data

| Meta-data | Demo | Jiguang 模块 | 我们的项目 | 状态 |
|-----------|------|--------------|------------|------|
| `JPUSH_APPKEY` | ❌ | ✅ | ✅ | 已配置 |
| `JPUSH_CHANNEL` | ❌ | ✅ | ✅ | 已配置 |

### 5.2 我们项目的 Meta-data 配置（当前）

```xml
<!-- JPush AppKey -->
<meta-data
    android:name="JPUSH_APPKEY"
    android:value="${JPUSH_APPKEY}" />
<!-- JPush 渠道名 -->
<meta-data
    android:name="JPUSH_CHANNEL"
    android:value="${JPUSH_CHANNEL}" />
```

**✅ 状态**：Meta-data 配置完整

---

## 6. Service/Receiver/Provider 配置

### 6.1 Jiguang 模块声明的组件

#### Service
- `cn.jpush.android.service.PushService` (推送核心服务)
- `cn.jpush.android.service.PluginFCMMessagingService` (FCM 服务)

#### Receiver
- `cn.jpush.android.service.PushReceiver` (推送接收)
- `cn.jpush.android.service.AlarmReceiver` (定时任务)
- `cn.jpush.android.service.SchedulerReceiver` (调度器)
- `cn.jpush.android.asus.AsusPushMessageReceiver` (华硕推送)

#### Provider
- `cn.jpush.android.service.DataProvider` (数据提供)
- `cn.jpush.android.service.InitProvider` (初始化)

### 6.2 我们项目当前的组件

```xml
<!-- JPush 自定义 Receiver -->
<receiver
    android:name="cn.jpush.android.service.NotificationReceiver"
    android:enabled="true"
    android:exported="false">
    <intent-filter>
        <action android:name="cn.jpush.android.intent.RECEIVE_MESSAGE" />
        <category android:name="${applicationId}" />
    </intent-filter>
</receiver>
```

**⚠️ 注意**：jpush_flutter 插件会自动注册大部分必要的 Service/Receiver/Provider

---

## 7. jiguang_auth 插件分析

### 7.1 插件 AndroidManifest（几乎为空）

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
  package="com.jiguang.jverify">
</manifest>
```

**原因**：插件依赖通过 Maven 自动引入，Manifest 配置由 SDK 自动合并

### 7.2 插件 build.gradle 依赖

```gradle
dependencies {
    implementation 'cn.jiguang.sdk:jverification:3.3.1'
}
```

### 7.3 插件包含的资源文件
- 动画文件：`umcsdk_anim_loading.xml`
- Drawable：多个 umcsdk 相关图标和背景
- Values：`jverification_styles.xml` (样式定义)

---

## 8. 关键差异总结

### ✅ 已正确配置
1. ✅ JPUSH_APPKEY 和 JPUSH_CHANNEL meta-data
2. ✅ 基础网络权限 (INTERNET, ACCESS_NETWORK_STATE 等)
3. ✅ 位置权限 (ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION)
4. ✅ jpush_flutter 插件 (版本 3.4.6)
5. ✅ jiguang_auth 插件 (版本 3.0.3)
6. ✅ POST_NOTIFICATIONS 权限 (Android 13+)

### ⚠️ 需要补充的配置

#### 1. 权限（添加到 `<manifest>` 标签下）

```xml
<!-- 极光推送自定义权限 -->
<permission
    android:name="${applicationId}.permission.JPUSH_MESSAGE"
    android:protectionLevel="signature" />
<uses-permission android:name="${applicationId}.permission.JPUSH_MESSAGE" />

<!-- JVerification 一键登录必需 -->
<uses-permission android:name="android.permission.READ_PHONE_STATE" />
<uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"/>
<uses-permission android:name="android.permission.GET_TASKS" />
```

#### 2. Activity（无需添加）
- jiguang_auth 插件通过 Maven 自动引入所有必要的 Activity
- JPush Activity 由 jpush_flutter 插件自动注册

#### 3. Service/Receiver（无需添加）
- 由 jpush_flutter 插件自动注册

---

## 9. 版本差异

| 组件 | Demo 本地 JAR | jiguang_auth 插件 | 差异 |
|------|---------------|-------------------|------|
| JVerification | 3.4.8 (本地) | 3.3.1 (Maven) | Demo 版本更新 |
| JPush | 6.2.0 | - | Demo 包含 |
| JCore | 5.5.0 | - | Demo 包含 |

**建议**：如果需要最新版本，可以考虑替换 jiguang_auth 的 Maven 依赖为本地 JAR

---

## 10. 配置建议

### 立即需要做的

1. **添加权限到 AndroidManifest.xml**
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- 添加自定义权限声明 -->
    <permission
        android:name="${applicationId}.permission.JPUSH_MESSAGE"
        android:protectionLevel="signature" />
    <uses-permission android:name="${applicationId}.permission.JPUSH_MESSAGE" />
    
    <!-- 添加 JVerification 所需权限 -->
    <uses-permission android:name="android.permission.READ_PHONE_STATE" />
    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"/>
    <uses-permission android:name="android.permission.GET_TASKS" />
    
    <!-- ... 现有配置 ... -->
</manifest>
```

### 可选优化

1. 如需使用 FCM 推送，需要：
   - 添加 Google Services 配置
   - 在 jiguang 模块 build.gradle 中启用 FCM 依赖
   
2. 如需升级到最新 SDK 版本：
   - 替换 jiguang_auth 的 Maven 依赖为本地 JAR 3.4.8
   - 更新相关配置

---

## 11. 常见问题排查

### 如果一键登录不工作
1. 检查 READ_PHONE_STATE 权限是否授予
2. 确认网络权限正常
3. 查看 logcat 中 JVerification 相关日志

### 如果推送不工作
1. 确认 JPUSH_APPKEY 正确
2. 检查 JPUSH_MESSAGE 权限
3. 查看 JPush 控制台日志

---

**报告生成时间**: 2026-07-29
**分析基于**: jiguang_auth 3.0.3, jpush_flutter 3.4.6
