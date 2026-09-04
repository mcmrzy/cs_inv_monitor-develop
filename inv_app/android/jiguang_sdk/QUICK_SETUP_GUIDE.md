# 极光 SDK 配置快速操作指南

## 🎯 核心发现

### ✅ 好消息
**jiguang_auth 插件已经包含了大部分必要配置！**

插件通过 Maven 依赖自动引入：
- ✅ 所有必需的 Activity（电信/移动认证页面）
- ✅ 所有 Service 和 Receiver
- ✅ 核心 SDK 库
- ✅ 资源文件（图标、样式等）

### ⚠️ 需要手动添加的内容

只需要在 `inv_app/android/app/src/main/AndroidManifest.xml` 中添加 **3个权限** 和 **1个自定义权限声明**。

---

## 📝 立即执行的修改

### 修改文件：`inv_app/android/app/src/main/AndroidManifest.xml`

#### 在 `<manifest>` 标签下添加（第 1 行之后）：

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- ========== 新增：极光推送自定义权限 ========== -->
    <permission
        android:name="${applicationId}.permission.JPUSH_MESSAGE"
        android:protectionLevel="signature" />
    <uses-permission android:name="${applicationId}.permission.JPUSH_MESSAGE" />
    
    <!-- 现有权限 -->
    <uses-permission android:name="android.permission.INTERNET"/>
    ...
```

#### 在权限列表中添加（在现有权限之后，`<application>` 之前）：

```xml
    <!-- ========== 新增：JVerification 一键登录所需权限 ========== -->
    <uses-permission android:name="android.permission.READ_PHONE_STATE" />
    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"/>
    <uses-permission android:name="android.permission.GET_TASKS" />

    <application
        android:label="辰烁光伏"
        ...
```

---

## 🔍 为什么不需要其他配置？

### 1. Activity 不需要手动声明
**原因**：jiguang_auth 插件的 Maven 依赖会自动合并 Manifest

```gradle
// jiguang_auth/android/build.gradle
dependencies {
    implementation 'cn.jiguang.sdk:jverification:3.3.1'
}
```

这个 Maven 依赖包含了：
- `com.cmic.gen.sdk.view.GenLoginAuthActivity`（移动认证）
- `cn.jiguang.verifysdk.CtLoginActivity`（电信认证）
- `com.cmic.sso.sdk.activity.OAuthActivity`（OAuth）

### 2. JPush Activity 也不需要手动声明
**原因**：jpush_flutter 插件会自动注册所有 JPush 核心 Activity

### 3. Service/Receiver 不需要手动声明
**原因**：jpush_flutter 插件通过自动注册机制处理

---

## 📦 原生 SDK 库文件清单

位于：`inv_app/android/jiguang_sdk/jiguang_sdk/jiguang/libs/`

```
✅ jcore-android-5.5.0.aar              (1.6MB) - 极光核心
✅ jpush-android-6.2.0.jar              (424KB) - JPush SDK
✅ jpush-android-plugin-fcm-v6.2.0.jar  (29KB)  - FCM 插件
✅ jverification-android-not_support_dynamic-release-3.4.8.jar (814KB) - 一键登录

Native SO 库 (libCtaApiLib.so):
  ✅ arm64-v8a   (918KB)
  ✅ armeabi-v7a
  ✅ x86
  ✅ x86_64
```

**注意**：这些文件目前未被 Flutter 项目直接使用，因为：
- jpush_flutter 使用自己的 JPush SDK 版本
- jiguang_auth 使用 Maven 版本的 JVerification (3.3.1 vs 本地 3.4.8)

---

## 🔧 可选优化（非必需）

### 如果需要升级到最新 JVerification 版本

1. **复制 JAR 到项目**
```bash
# 将 jverification-android-not_support_dynamic-release-3.4.8.jar 
# 复制到 inv_app/android/app/libs/
```

2. **修改 jiguang_auth 的 build.gradle**（不推荐，因为会修改缓存）

**建议**：保持 Maven 依赖，等待 jiguang_auth 插件更新

---

## ✅ 验证清单

修改完成后，验证以下内容：

### 1. AndroidManifest.xml 权限检查
```bash
# 在 Android 目录运行
./gradlew assembleDebug
# 查看 build 日志中是否有权限警告
```

### 2. 一键登录功能测试
```dart
// Flutter 代码
import 'package:jiguang_auth/jiguang_auth.dart';

// 初始化
JiguangAuth.setup(appKey: '你的appKey');

// 检查配置
bool result = await JiguangAuth.checkConfig();
print('配置检查: $result');
```

### 3. 推送功能测试
```dart
// Flutter 代码
import 'package:jpush_flutter/jpush_flutter.dart';

JPush jpush = JPush();
jpush.setup(
  appKey: "你的appKey",
  channel: "your_channel",
  production: false,
);
```

---

## 🐛 常见问题

### Q1: 为什么 READ_PHONE_STATE 权限重要？
**A**: JVerification 需要读取设备信息来识别运营商和 SIM 卡

### Q2: QUERY_ALL_PACKAGES 权限会被 Google Play 拒绝吗？
**A**: 可能会。如果发布到 Google Play，需要说明用途。可以考虑：
- 只在必要市场版本添加
- 在隐私政策中说明

### Q3: 如果权限添加后仍然无法使用一键登录？
**A**: 检查以下几点：
1. 运行时权限是否已请求（Android 6.0+）
2. 网络权限是否正常
3. 查看 logcat：`adb logcat | grep JVerification`
4. 确认运营商服务是否开通

---

## 📊 配置对比表

| 配置项 | Demo 需要 | Jiguang 模块 | jiguang_auth 插件 | 我们的项目 | 状态 |
|--------|-----------|--------------|-------------------|------------|------|
| JPUSH_MESSAGE 权限 | ❌ | ✅ | ❌ | ❌ | 需添加 |
| READ_PHONE_STATE | ❌ | ✅ | ❌ | ❌ | 需添加 |
| QUERY_ALL_PACKAGES | ❌ | ✅ | ❌ | ❌ | 需添加 |
| GET_TASKS | ❌ | ✅ | ❌ | ❌ | 需添加 |
| 认证 Activity | ✅ | ✅ | ✅(Maven) | ✅(自动) | OK |
| JPush Activity | ❌ | ✅ | ❌ | ✅(自动) | OK |
| JPUSH_APPKEY | ❌ | ✅ | ❌ | ✅ | OK |
| JPUSH_CHANNEL | ❌ | ✅ | ❌ | ✅ | OK |

---

## 🎬 下一步

1. ✅ 修改 AndroidManifest.xml（添加 4 个权限声明）
2. ⏸️ 运行 `flutter clean` 和 `flutter pub get`
3. ⏸️ 重新编译 APK
4. ⏸️ 测试一键登录功能
5. ⏸️ 测试推送功能

---

**最后更新**: 2026-07-29
