# Multi-Level Platform Migration Guide

> Flutter App 从 MQTT 轮询架构到 REST API 多级渠道平台的迁移指南

## 目录

- [迁移概述](#迁移概述)
- [架构变更](#架构变更)
- [新增状态管理](#新增状态管理)
  - [OrganizationContextStore](#organizationcontextstore)
- [权限驱动 UI 组件](#权限驱动-ui-组件)
  - [PermissionGate](#permissiongate)
  - [OrganizationPermissionGate](#organizationpermissiongate)
  - [RoleGuard](#roleguard)
- [JWT Token 刷新机制](#jwt-token-刷新机制)
- [API 服务层方法](#api-服务层方法)
- [数据实体](#数据实体)
- [存储层变更](#存储层变更)
- [现有用户迁移清单](#现有用户迁移清单)
- [向后兼容性说明](#向后兼容性说明)
- [测试指南](#测试指南)
- [故障排除](#故障排除)
- [相关文档](#相关文档)

---

## 迁移概述

### 背景

原有的 `inv_app` 采用 **MQTT 直连轮询**架构，App 直接订阅 MQTT Broker 获取设备数据。这种架构在单租户场景下运行良好，但随着多级渠道（制造商 → 经销商 → 安装商 → 终端用户）商业模式的引入，需要更精细的组织隔离和权限控制。

### 迁移目标

| 方面 | 旧架构 | 新架构 |
|------|--------|--------|
| 数据获取 | MQTT 直连轮询 | REST API + MQTT 混合 |
| 组织模型 | 单租户 | 多级组织树 |
| 权限控制 | 无/简单 | RBAC 三维权限模型 |
| 设备归属 | 全局设备池 | 组织级隔离 |
| 成员管理 | 无 | 邀请/转移/角色 |

### 核心决策：混合架构

```
┌─────────────────────────────────────────────────────┐
│                    Flutter App                       │
│                                                     │
│  ┌──────────────┐         ┌──────────────────────┐  │
│  │  MQTT Client  │         │   REST API Client    │  │
│  │  (实时数据)   │         │   (业务逻辑)         │  │
│  └──────┬───────┘         └──────────┬───────────┘  │
└─────────┼────────────────────────────┼──────────────┘
          │                            │
    ┌─────▼─────┐              ┌──────▼──────┐
    │  MQTT     │              │  inv-api-   │
    │  Broker   │              │  server     │
    │  (遥测)   │              │  (CRUD/权限)│
    └───────────┘              └─────────────┘
```

**保留 MQTT 用于：**
- 设备实时遥测数据推送
- 设备状态变更通知
- 低延迟控制命令响应

**迁移到 REST API 用于：**
- 组织/成员/邀请等 CRUD 操作
- 权限验证和角色管理
- 设备转移审批流程
- 用户认证和 Token 管理

---

## 架构变更

### 分层架构

```
┌─────────────────────────────────────┐
│         Presentation Layer          │
│  - OrganizationBrowserScreen        │
│  - OrgInvitationScreen              │
│  - PermissionGate widgets           │
│  - OrgSelectorDialog                │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│         State Management            │
│  - OrganizationContextStore         │
│  - AuthBloc                         │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│         Service Layer               │
│  - ApiService (28+ new methods)     │
│  - JwtInterceptor                   │
│  - StorageService                   │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│       Backend API Endpoints         │
│  /api/v1/organizations/*            │
│  /api/v1/invitations/*              │
│  /api/v1/devices/transfers/*        │
└─────────────────────────────────────┘
```

### 关键文件清单

| 文件 | 行数 | 说明 |
|------|------|------|
| `lib/core/entities/organization.dart` | 299 | 组织相关实体定义 |
| `lib/core/stores/organization_context_store.dart` | 156 | 组织上下文状态管理 |
| `lib/core/services/api_service.dart` | +283 | API 服务层扩展 |
| `lib/core/components/permission_gate.dart` | 238 | 权限门控组件 |
| `lib/core/services/storage_service.dart` | +43 | 存储层扩展 |
| `lib/core/interceptors/jwt_interceptor.dart` | 112 | JWT 拦截器 |
| `lib/core/widgets/org_selector_dialog.dart` | 183 | 组织选择对话框 |
| `lib/core/screens/organization_browser_screen.dart` | 546 | 组织浏览器 |
| `lib/core/screens/org_invitation_screen.dart` | 566 | 邀请管理 |

---

## 新增状态管理

### OrganizationContextStore

`OrganizationContextStore` 是新增的核心状态管理组件，负责管理用户当前的组织上下文。

**文件路径：** `lib/core/stores/organization_context_store.dart`

**核心职责：**

- 管理当前激活的组织上下文（activeOrgId / activeOrgName）
- 加载用户可用的所有组织列表
- 切换组织上下文并通知 UI 更新
- 持久化组织选择到本地存储

**API 接口：**

```dart
class OrganizationContextStore extends ChangeNotifier {
  // 状态
  int? get activeOrgId;
  String? get activeOrgName;
  List<Organization> get availableOrgs;
  bool get isLoading;

  // 操作
  Future<void> loadAvailableOrganizations();
  Future<void> switchContextToOrganization(int orgId, String orgName);
  Future<void> refreshOrganizations();
  ApiService get apiService;
}
```

**使用方式：**

```dart
// 在 Provider 中注册
MultiProvider(
  providers: [
    ChangeNotifierProvider(
      create: (_) => OrganizationContextStore(apiService: apiService),
    ),
  ],
)

// 在组件中使用
final orgStore = context.read<OrganizationContextStore>();

// 获取当前组织
int? currentOrgId = orgStore.activeOrgId;

// 切换组织
await orgStore.switchContextToOrganization(1, '企业A');

// 监听变化
context.watch<OrganizationContextStore>().activeOrgId;
```

**状态流转：**

```
App 启动
  → loadAvailableOrganizations()
  → 检查本地存储的上次选择
  → 恢复上次组织上下文 OR 提示选择
  → 用户可切换 → switchContextToOrganization()
  → UI 自动更新
```

---

## 权限驱动 UI 组件

### PermissionGate

通用权限检查组件，根据用户的 RBAC 权限显示或隐藏子组件。

**文件路径：** `lib/core/components/permission_gate.dart`

```dart
PermissionGate(
  resource: 'organization',  // 资源类型
  action: 'manage',          // 操作类型：view / control / manage / admin
  child: ElevatedButton(
    onPressed: () {},
    child: Text('管理组织'),
  ),
)
```

**权限级别：**

| Action | 说明 | 包含 |
|--------|------|------|
| `view` | 仅查看 | — |
| `control` | 控制 | view |
| `manage` | 管理 | view + control |
| `admin` | 管理员 | view + control + manage |

### OrganizationPermissionGate

在 `PermissionGate` 基础上增加组织级别约束，要求用户必须在指定组织上下文中。

```dart
OrganizationPermissionGate(
  requiredOrgId: 42,
  resource: 'device',
  action: 'control',
  child: DeviceControlPanel(),
)
```

### RoleGuard

基于角色 ID 的简单守卫组件，适用于按角色过滤的场景。

```dart
RoleGuard(
  allowedRoles: [1, 2], // 1=超级管理员, 2=管理员
  child: AdminSettings(),
)
```

**fallback 参数：** 当权限不满足时，可显示替代组件：

```dart
PermissionGate(
  resource: 'device',
  action: 'manage',
  fallback: Text('您没有管理设备的权限'),
  child: DeviceManager(),
)
```

---

## JWT Token 刷新机制

**文件路径：** `lib/core/interceptors/jwt_interceptor.dart`

JWT 拦截器实现了自动 Token 管理，确保请求链不中断。

### 工作流程

```
发起 HTTP 请求
  → JwtInterceptor 添加 Authorization Header
  → 请求成功 → 返回响应
  → 请求返回 401
    → 调用 /api/v1/auth/refresh
    → 获取新 Token 对
    → 保存到 StorageService
    → 重试原始请求
    → 刷新也返回 401
      → 触发 onTokenExpired 回调
      → 退出登录
```

### 配置方式

```dart
final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
  ..interceptors.add(
    JwtInterceptor(
      storageService: storageService,
      onTokenExpired: () {
        // Token 完全过期，强制退出
        authBloc.add(ForceLogoutEvent());
      },
    ),
  );
```

### Token 存储

| Token | 存储方式 | 说明 |
|-------|----------|------|
| Access Token | `flutter_secure_storage` | iOS Keychain / Android Keystore 加密存储 |
| Refresh Token | `flutter_secure_storage` | 同上 |
| Active Org ID | `shared_preferences` | 非敏感数据，普通存储 |

---

## API 服务层方法

**文件路径：** `lib/core/services/api_service.dart`

新增 18+ 个 API 方法，覆盖完整的组织管理功能：

### 组织管理（6 个方法）

```dart
Future<List<Organization>> getOrganizations();
Future<Organization> createOrganization({
  required String name,
  String? description,
  String? type,  // manufacturer / distributor / dealer / installer / end_user
});
Future<Organization> getOrganization(int orgId);
Future<Organization> updateOrganization({
  required int orgId,
  String? name,
  String? description,
});
Future<void> deleteOrganization(int orgId);
Future<List<Organization>> getOrganizationTree(int orgId);
```

### 成员管理（4 个方法）

```dart
Future<List<OrganizationMember>> getOrganizationMembers(int orgId, {
  int page = 1,
  int pageSize = 20,
});
Future<OrganizationMember> addOrganizationMember({
  required int orgId,
  required int userId,
  required int roleId,
});
Future<OrganizationMember> updateMemberRole({
  required int orgId,
  required int userId,
  required int newRoleId,
});
Future<void> removeOrganizationMember(int orgId, int userId);
```

### 邀请系统（4 个方法）

```dart
Future<OrganizationInvitation> sendInvitation({
  required int orgId,
  required String email,
  required int roleId,
  int expiresHours = 168,  // 默认 7 天
});
Future<List<OrganizationInvitation>> listInvitations(int orgId, {
  int page = 1,
  int pageSize = 20,
  String? status,  // pending / accepted / revoked / expired
});
Future<void> revokeInvitation(int invitationId);
Future<String> copyInviteLink(int invitationId);
```

### 设备转移（4 个方法）

```dart
Future<void> requestDeviceTransfer({
  required String deviceSN,
  required int fromOrgId,
  required int toOrgId,
  String? reason,
});
Future<List<DeviceTransferRequest>> listTransferRequests({
  int page = 1,
  int pageSize = 20,
  String? status,  // pending / approved / rejected
});
Future<void> approveTransfer(int transferId, {String? note});
Future<void> rejectTransfer(int transferId, String reason);
```

### 错误处理

所有 API 方法统一抛出类型化异常：

```dart
try {
  final orgs = await apiService.getOrganizations();
} on UnauthorizedFailure catch (_) {
  // 401 - Token 过期，触发退出
} on ForbiddenFailure catch (_) {
  // 403 - 无权限操作
  showError('您没有执行此操作的权限');
} on NetworkFailure catch (_) {
  // 网络错误
  showError('网络连接失败，请检查网络');
}
```

---

## 数据实体

**文件路径：** `lib/core/entities/organization.dart`

```dart
// 组织
class Organization {
  final int id;
  final String name;
  final String? description;
  final String? type;
  final int memberCount;
  final int deviceCount;
  final DateTime createdAt;
}

// 组织成员
class OrganizationMember {
  final int userId;
  final String email;
  final String displayName;
  final int roleId;
  final String roleName;
  final DateTime joinedAt;
}

// 邀请记录
class OrganizationInvitation {
  final int id;
  final String email;
  final int roleId;
  final String roleName;
  final String status;  // pending / accepted / revoked / expired
  final String? token;
  final DateTime expiresAt;
  final String invitedBy;
}

// 设备转移请求
class DeviceTransferRequest {
  final int id;
  final String deviceSN;
  final int fromOrgId;
  final String fromOrgName;
  final int toOrgId;
  final String toOrgName;
  final String status;  // pending / approved / rejected
  final String? reason;
  final String requesterEmail;
  final DateTime createdAt;
}

// 成员角色枚举
enum OrgMemberRole {
  owner,    // 拥有者 - 完全权限
  admin,    // 管理员 - 管理成员和设备
  member,   // 成员 - 查看和控制
  viewer,   // 查看者 - 仅查看
}
```

---

## 存储层变更

**文件路径：** `lib/core/services/storage_service.dart`

新增组织上下文持久化方法：

```dart
// 新增方法
Future<int?> getActiveOrgId();
Future<void> saveActiveOrgId(int orgId);
Future<void> deleteActiveOrgId();

Future<String?> getActiveOrgName();
Future<void> saveActiveOrgName(String orgName);
Future<void> deleteActiveOrgName();
```

**持久化策略：**

| 数据类型 | 存储方式 | 安全级别 |
|----------|----------|----------|
| JWT Access Token | `flutter_secure_storage` | 高（加密） |
| JWT Refresh Token | `flutter_secure_storage` | 高（加密） |
| Active Org ID | `shared_preferences` | 低（明文） |
| Active Org Name | `shared_preferences` | 低（明文） |
| 用户信息 | `shared_preferences` | 低（明文） |

---

## 现有用户迁移清单

对于已有安装的用户，App 升级时需完成以下迁移：

### 自动迁移（App 内部处理）

1. **检测旧版本**：App 启动时检查是否存在组织上下文数据
2. **首次登录新版本**：
   - 自动调用 `getOrganizations()` 获取用户的组织列表
   - 如果用户属于多个组织，弹出组织选择对话框
   - 如果用户只属于一个组织，自动设置为当前上下文
3. **MQTT 订阅调整**：
   - 旧：`devices/#`（全局订阅）
   - 新：`devices/{orgId}/#`（组织隔离）
4. **本地数据清理**：清除旧版缓存的全局设备列表

### 手动操作（用户侧）

- 更新 App 至最新版本
- 首次打开时选择所属组织
- 如需管理多个组织，在「组织管理」页面切换

### 注意事项

- 旧版 App 仍可运行，但不会获得组织隔离功能
- 建议在升级引导页提示用户选择组织
- MQTT Topic 兼容层确保旧设备不受影响

---

## 向后兼容性说明

### API 兼容

| 接口 | 兼容性 | 说明 |
|------|--------|------|
| `/api/v1/auth/login` | 完全兼容 | 登录接口不变，返回结构扩展了 `orgId` 字段 |
| `/api/v1/devices` | 完全兼容 | 设备列表接口增加组织过滤，默认返回当前组织设备 |
| `/api/v1/telemetry` | 完全兼容 | 遥测数据接口不变 |
| `/api/v1/organizations` | 新增 | 新接口，旧版 App 不调用 |
| `/api/v1/invitations` | 新增 | 新接口，旧版 App 不调用 |

### MQTT Topic 兼容

| Topic 模式 | 版本 | 说明 |
|------------|------|------|
| `devices/{sn}/telemetry` | 旧 | 仍可用，无组织隔离 |
| `devices/{orgId}/{sn}/telemetry` | 新 | 组织隔离模式 |
| `alerts/{sn}` | 旧 | 仍可用 |
| `alerts/{orgId}/{sn}` | 新 | 组织隔离模式 |

> **过渡策略：** 新旧 Topic 格式并行运行，旧格式计划在 v2.0 后废弃。

### 数据迁移

- 数据库层面：所有现有设备和用户自动归属到默认组织（Root Org）
- 无需手动迁移数据，后端自动处理组织关联

---

## 测试指南

### 单元测试

```dart
// OrganizationContextStore 测试
test('switchContextToOrganization updates state correctly', () async {
  final mockApi = MockApiService();
  when(mockApi.getOrganizations())
    .thenAnswer((_) async => [
      Organization(id: 1, name: 'Org A', memberCount: 5, deviceCount: 10),
      Organization(id: 2, name: 'Org B', memberCount: 3, deviceCount: 20),
    ]);

  final store = OrganizationContextStore(apiService: mockApi);
  await store.loadAvailableOrganizations();

  expect(store.availableOrgs.length, 2);

  await store.switchContextToOrganization(1, 'Org A');
  expect(store.activeOrgId, 1);
  expect(store.activeOrgName, 'Org A');
});

// PermissionGate 测试
testWidgets('PermissionGate hides child without permission', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PermissionGate(
        resource: 'device',
        action: 'admin',
        child: Text('Admin Only'),
      ),
    ),
  );

  expect(find.text('Admin Only'), findsNothing);
});
```

### 集成测试

```dart
testWidgets('full organization workflow', (tester) async {
  // 1. 登录
  await tester.pumpWidget(App());
  await tester.enterText(find.byKey(Key('emailInput')), 'admin@test.com');
  await tester.enterText(find.byKey(Key('passwordInput')), 'password');
  await tester.tap(find.byKey(Key('loginBtn')));
  await tester.pumpAndSettle();

  // 2. 组织选择（多组织场景）
  expect(find.text('选择组织'), findsOneWidget);
  await tester.tap(find.text('企业A'));
  await tester.pumpAndSettle();

  // 3. 验证设备列表已按组织过滤
  expect(find.byKey(Key('deviceList')), findsOneWidget);

  // 4. 切换组织
  await tester.tap(find.byKey(Key('orgSwitchBtn')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('企业B'));
  await tester.pumpAndSettle();

  // 5. 验证设备列表已更新
  expect(find.byKey(Key('deviceList')), findsOneWidget);
});
```

### 手动测试检查项

- [ ] 登录后正确显示组织选择（多组织场景）
- [ ] 单组织自动选择，无弹出
- [ ] 组织切换后设备列表刷新
- [ ] 无权限操作按钮被隐藏
- [ ] Token 过期后自动刷新，请求不中断
- [ ] Refresh Token 过期后正确退出登录
- [ ] 邀请发送后邮件正常收到
- [ ] 设备转移审批流程完整

---

## 故障排除

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 登录后看不到设备 | 未选择组织上下文 | 在组织浏览器中选择组织 |
| 操作按钮不显示 | 权限不足 | 联系管理员提升角色权限 |
| Token 不断刷新 | Refresh Token 已过期 | 重新登录 |
| 组织列表为空 | API 返回空 | 确认用户已关联到至少一个组织 |
| 邀请邮件未发送 | SMTP 未配置 | 检查后端邮件服务配置 |
| 切换组织后数据不更新 | 缓存问题 | 下拉刷新或重启 App |
| MQTT 收不到数据 | Topic 不匹配 | 确认已切换到组织隔离 Topic |

---

## 相关文档

- [Flutter App 迁移实施记录](../../inv_app/MULTI_LEVEL_PLATFORM_MIGRATION.md) — 原始实施文档
- [Email Service Setup](../../business-api/docs/EMAIL_SERVICE_SETUP.md) — 邮件服务配置
- [Channel Management UI](../../inv-admin-frontend/docs/CHANNEL_MANAGEMENT_UI.md) — Web 管理台渠道管理
- [Key Rotation Scheduling](../../docs/KEY_ROTATION_SCHEDULING.md) — JWT 密钥轮换

---

*最后更新：2026-07-22*
*状态：Phase 1-2 已完成，Phase 3-4 进行中*
