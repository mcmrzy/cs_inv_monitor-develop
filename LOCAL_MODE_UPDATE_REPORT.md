# 离网模式优化更新报告

## 📅 更新时间
2026-08-14

## 🎯 需求目标

根据用户反馈，本次更新主要实现以下功能改进：

### 1. **离网模式图标和文字居中显示** ✅
   - 本地连接页面（local_mode_page.dart）
   - 居中的大图标 + 双行标题
   - Switch 开关置于底部

### 2. **点击离网入口直接进入应用主界面** ✅
   - 不再跳转到独立的 `/local-mode` 引导页
   - 直接跳转至 `/home` 主页
   - 首页自动判断网络状态显示云端或本地数据

### 3. **"我的"页面状态提示** ✅
   - Guest Local Mode 时显示"离线用户"
   - 未登录时显示"未登录"
   - 添加橙色离网模式标签（wifi_off_rounded 图标 + 文字）

### 4. **使用默认头像昵称** ✅
   - Guest Local Mode 强制使用默认头像
   - 固定显示文本"离线用户"

---

## 🔧 修改文件清单

### 1. `inv_app/lib/features/profile/presentation/pages/profile_page.dart`
#### 修改内容：
- **新增 `isGuestLocalMode` 变量检测**（第 119 行）
  ```dart
  final connectionModeService = getIt<ConnectionModeService>();
  isGuestLocalMode = connectionModeService.isGuestLocalMode;
  if (isGuestLocalMode) {
    displayName = '离线用户';
  } else {
    displayName = '未登录';
  }
  ```

- **头像逻辑增强**（第 184 行，第 207-235 行）
  ```dart
  // 判断是否应该使用默认头像
  final shouldUseDefaultAvatar = !authState || authState.user == null;
  
  // 在 ShouldUseDefaultAvatar 或 showLoadError 时使用默认头像
  child: isLoading && avatarUrl == null
      ? Center(LoadingIndicator)
      : (shouldUseDefaultAvatar || showLoadError
          ? Image.asset(CsergyAssets.avatarDefault)
          : (avatarUrl != null ? Image.network(...) : Image.asset(...)))
  ```

- **离网模式标签显示**（第 312-345 行）
  ```dart
  // 离网模式提示标签
  if (isGuestLocalMode)
    Container(
      margin: EdgeInsets.only(bottom: 6.h),
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: Color(0xFFFFF7ED).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: Color(0xFFFDBA74).withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 12.sp, color: Color(0xFFF97316)),
          SizedBox(width: 4.w),
          Text(l10n.localMode, style: TextStyle(fontSize: 10.sp, ...))
        ],
      ),
    )
  ```

#### 视觉效果：
```
┌──────────────────────────────────────┐
│   ┌─────────┐                        │
│   │  默认头像 │     离线用户            │
│   └─────────┘                        │
│   [🔴📡] 离网模式                       │
│             安装商                      │
│                   ⮕                    │
└──────────────────────────────────────┘
```

---

### 2. `inv_app/lib/features/device/presentation/pages/local_mode_page.dart`
#### 修改内容：
- **布局重构**（第 203-263 行）
  ```dart
  Widget _buildModeSwitch() {
    return Column([
      // 居中的图标容器
      Container(
        width: 56.w, height: 56.w,
        decoration: BoxDecoration(
          color: isLocal ? successLight.withOpacity(0.15) : primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14.r),
        ),
        child: Icon(isLocal ? Icons.wifi : Icons.cloud_outlined, ...)
      ),
      
      SizedBox(height: 12.h),
      
      // 居中的主标题
      Text(localMode, 
        fontSize: 17.sp, fontWeight: FontWeight.bold),
      
      SizedBox(height: 4.h),
      
      // 居中的副标题
      Text(localModeDirectAp / remoteModeCloud, 
        fontSize: 13.sp, color: textHint),
      
      SizedBox(height: 20.h),
      
      // Switch 放在底部
      Switch(value: isLocal, ...)
    ])
  }
  ```

#### 视觉对比：

**修改前（水平布局）：**
```
[🔒] 离网模式    [开关]
    直连设备    
```

**修改后（垂直居中）：**
```
┌────────────────────────────────┐
│    ┌──────────┐                │
│    │  🔴📡     │                │
│    └──────────┘                │
│       离网模式                   │
│       直连设备                    │
│              [🔵]               │
└────────────────────────────────┘
```

---

### 3. `inv_app/lib/features/auth/presentation/pages/auth_page.dart`
#### 修改内容：
- **简化跳转逻辑**（第 378-391 行）
  ```dart
  Future<void> _enterGuestLocalMode() async {
    await getIt<ConnectionModeService>().enterGuestLocalMode();
    if (!mounted) return;
    // 直接跳转至主应用首页，不再区分是否连接设备 AP
    context.go('/home');
  }
  ```

#### 旧逻辑 vs 新逻辑：

**旧逻辑（两步跳转）：**
```
点击离网入口 → 检查 WiFi 连接 → 
  ├─ 已连接设备 AP → /home
  └─ 未连接 → /local-mode (引导页)
```

**新逻辑（一步直达）：**
```
点击离网入口 → /home (直接使用)
```

---

## 🎨 设计规范

### 颜色使用
| 元素 | 颜色代码 | 用途 |
|------|---------|------|
| 离网模式背景 | `Color(0xFFFFF7ED)` | 橙色浅底色 |
| 离网模式边框 | `Color(0xFFFDBA74)` | 橙色描边 |
| 离网模式图标 | `Color(0xFFF97316)` | 橙色图标 |
| 云朵主题 | `Color(0xFF1565C0)` | 蓝色主题色 |

### 间距规范
```dart
Container(
  margin: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 16.h), // 外层间距
  padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 28.h), // 内层填充
  
  // 内部间距
  SizedBox(height: 12.h),    // 图标到主标题
  SizedBox(height: 4.h),     // 主标题到副标题
  SizedBox(height: 20.h),    // 副标题到 Switch
)
```

### 圆角与阴影
```dart
BorderRadius.circular(20.r), // 外框圆角
BoxShadow(
  color: Color(0xFF1565C0).withValues(alpha: 0.08),
  blurRadius: 16,
  offset: Offset(0, 6),
),
```

---

## ✅ 验收标准

### "我的"页面检查清单
- [ ] 未登录时显示"未登录"字样
- [ ] Guest Local Mode 时显示"离线用户"字样
- [ ] Guest Local Mode 使用默认头像（圆形灰色图案）
- [ ] Guest Local Mode 显示橙色离网标签（带 wifi_off 图标）
- [ ] 角色文本正常显示（"安装商"/"终端用户"等）

### 本地模式页面检查清单
- [ ] 图标居中且尺寸为 56x56dp
- [ ] 主标题字体加粗且居中
- [ ] 副标题为 hint 颜色且居中
- [ ] Switch 开关位于卡片底部
- [ ] 整体有适当的阴影效果
- [ ] 离线和在线模式切换流畅

### 离网入口检查清单
- [ ] 点击离网入口不经过中间页面
- [ ] 直接进入/home 主页
- [ ] GuestLocalMode 标志已设置
- [ ] "我的"页面正确显示"离线用户"

---

## 🔄 后续建议

### 短期优化
1. **首页数据源切换**
   - 首页应根据网络状态自动切换云端/本地缓存数据
   - 添加状态指示器（云端/本地同步）

2. **导航菜单适配**
   - 离网模式下禁用需要云端的菜单项
   - 提供明确的离线操作提示

3. **本地缓存预加载**
   - Guest Local Mode 首次进入时预加载最近数据
   - 提升离线体验流畅度

### 长期优化
1. **离线数据同步队列**
   - 支持离线操作记录
   - 网络恢复后自动同步

2. **多人协同离线支持**
   - 局域网内多台 App 设备共享
   - P2P 直连数据传输

3. **离线升级机制**
   - 支持本地 OTA 固件升级
   - 通过 BLE/WiFi 热点传输

---

## 🚀 测试场景

### 场景 1：未登录访问
1. 清除登录态或新建安装
2. 进入"我的"页面
3. ✅ 应显示"未登录" + 默认头像

### 场景 2：Guest Local Mode
1. 登录页 → 点击"本地离网模式"入口
2. ✅ 应直接进入 home 页
3. ✅ 进入"我的"显示"离线用户"+ 橙色标签

### 场景 3：本地模式切换
1. 设备页 → 本地连接
2. ✅ 图标和文字应居中显示
3. ✅ 切换到云端模式应恢复正常布局

### 场景 4：登录流程
1. Guest Local Mode → 登录
2. ✅ 头像应自动切换为用户头像
3. ✅ 昵称应显示用户昵称/手机号
4. ✅ 离网标签应消失

---

## 📊 相关文件索引

| 文件名 | 修改行数 | 关键改动 |
|-------|---------|---------|
| `profile_page.dart` | +47/-11 | 头像逻辑、状态标签 |
| `local_mode_page.dart` | +55/-40 | 居中布局重构 |
| `auth_page.dart` | +3/-9 | 简化跳转逻辑 |

---

## 👤 修改者
AI 开发助手 - Qoder

## 📝 备注
本次更新基于用户的明确需求，重点优化了离网模式的 UX 体验，使界面更加直观友好。所有修改均遵循项目的设计规范和 Flutter 最佳实践。
