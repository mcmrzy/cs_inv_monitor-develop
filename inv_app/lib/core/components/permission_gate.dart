import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/core/stores/organization_context_store.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';

/// 权限资源类型
enum ResourceType {
  organization, // 组织管理
  device, // 设备管理
  alert, // 告警管理
  report, // 报表查看
  user, // 用户管理
  system, // 系统设置
}

/// 权限级别枚举
enum PermissionLevel {
  view, // 仅查看
  control, // 控制
  manage, // 管理
  admin, // 管理员
}

extension PermissionLevelExtension on PermissionLevel {
  String get displayName {
    switch (this) {
      case PermissionLevel.view:
        return '查看';
      case PermissionLevel.control:
        return '控制';
      case PermissionLevel.manage:
        return '管理';
      case PermissionLevel.admin:
        return '管理员';
    }
  }
}

/// 权限检查器
class PermChecker {
  /// 检查用户对某个资源的某个操作是否有权限
  static bool has(
    BuildContext context,
    String resource,
    String action, {
    int? requiredOrgId,
  }) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return false;

    final userRole = authState.role;

    // 超级管理员（role=1）拥有所有权限
    if (userRole == 1) return true;

    // 获取当前组织上下文
    final orgStore = context.read<OrganizationContextStore>();

    // 如果需要特定组织且不在该组织中，返回 false
    if (requiredOrgId != null && !orgStore.isMemberOf(requiredOrgId)) {
      return false;
    }

    // 组织所有者或管理员拥有该组织的完整权限
    if (orgStore.hasActiveOrg && orgStore.isOrgOwner(orgStore.activeOrgId!)) {
      return _checkRolePermission(userRole, resource, action);
    }

    // 普通成员权限限制
    return _checkMemberPermission(userRole, resource, action);
  }

  /// 检查角色级别的权限
  static bool _checkRolePermission(int role, String resource, String action) {
    // 超级管理员
    if (role == 1) return true;

    // 管理员（role=2）
    if (role == 2) {
      // 管理员可以管理大多数资源
      return !_isSystemAdminOnly(resource);
    }

    // 普通用户（role=3）只能查看
    if (action == 'view') return true;
    return false;
  }

  /// 检查普通成员的权限
  static bool _checkMemberPermission(int role, String resource, String action) {
    // 普通成员只能执行基本的查看和操作
    if (role < 2) {
      if (resource == 'device' && action == 'control') {
        return true; // 可以控制自己名下的设备
      }
      if (resource == 'alert' && action == 'view') {
        return true; // 可以查看告警
      }
      return false;
    }
    return true;
  }

  /// 是否是仅限系统管理员的操作
  static bool _isSystemAdminOnly(String resource) {
    // 系统级管理操作仅超级管理员可执行
    return resource == 'system' || resource == 'user';
  }

  /// 获取用户的权限等级
  static PermissionLevel getUserPermissionLevel(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return PermissionLevel.view;
    }

    final role = authState.role;
    if (role == 1) return PermissionLevel.admin;
    if (role == 2) return PermissionLevel.manage;
    return PermissionLevel.view;
  }
}

/// 权限门控组件
/// 根据用户的权限显示或隐藏子组件
class PermissionGate extends StatelessWidget {
  final String resource;
  final String action; // view, control, manage, admin
  final Widget child;
  final Widget? emptyWrapper; // 没有权限时显示的组件，默认为 SizedBox.shrink()
  final int? requiredOrgId; // 可选：指定所需的组织 ID

  const PermissionGate({
    super.key,
    required this.resource,
    required this.action,
    required this.child,
    this.emptyWrapper,
    this.requiredOrgId,
  });

  @override
  Widget build(BuildContext context) {
    final hasPermission = PermChecker.has(
      context,
      resource,
      action,
      requiredOrgId: requiredOrgId,
    );

    if (hasPermission) {
      return child;
    }

    return emptyWrapper ?? const SizedBox.shrink();
  }
}

/// 组织权限门控组件
/// 需要用户在指定的组织上下文中才有权限
class OrganizationPermissionGate extends StatelessWidget {
  final int requiredOrgId;
  final String resource;
  final String action;
  final Widget child;

  const OrganizationPermissionGate({
    super.key,
    required this.requiredOrgId,
    required this.resource,
    required this.action,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final orgStore = context.read<OrganizationContextStore>();

    // 检查用户是否在当前激活的组织中
    final hasAccess = orgStore.isMemberOf(requiredOrgId);

    if (!hasAccess) {
      return const SizedBox.shrink();
    }

    return PermissionGate(
      resource: resource,
      action: action,
      requiredOrgId: requiredOrgId,
      child: child,
    );
  }
}

/// 角色守卫组件
/// 只有特定角色的用户才能看到
class RoleGuard extends StatelessWidget {
  final List<int> allowedRoles;
  final Widget child;
  final Widget? placeholder;

  const RoleGuard({
    super.key,
    required this.allowedRoles,
    required this.child,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return placeholder ?? const SizedBox.shrink();
    }

    if (allowedRoles.contains(authState.role)) {
      return child;
    }

    return placeholder ?? const SizedBox.shrink();
  }
}

/// 扩展 BuildContext 方便使用
extension AuthContextExtensions on BuildContext {
  bool hasPermission(String resource, String action) {
    return PermChecker.has(this, resource, action);
  }

  bool canViewDevices() => hasPermission('device', 'view');
  bool canControlDevices() => hasPermission('device', 'control');
  bool canManageOrganizations() => hasPermission('organization', 'manage');
  bool canViewAlerts() => hasPermission('alert', 'view');
  bool canManageUsers() => hasPermission('user', 'manage');
  bool canConfigureSystem() => hasPermission('system', 'admin');
}
