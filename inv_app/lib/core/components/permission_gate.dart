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

/// 权限检查器 (基于新组织权限体系)
class PermChecker {
  /// 构建 permission_code，如 'devices:view'
  static String _permCode(String resource, String action) => '$resource:$action';

  /// 检查用户对某个资源的某个操作是否有权限
  static bool has(
    BuildContext context,
    String resource,
    String action, {
    int? requiredOrgId,
  }) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return false;

    // 系统超级管理员绕过所有权限检查
    if (authState.isSystemAdmin) return true;

    // 获取当前组织上下文
    final orgStore = context.read<OrganizationContextStore>();

    // 如果需要特定组织且不在该组织中，返回 false
    if (requiredOrgId != null && !orgStore.isMemberOf(requiredOrgId)) {
      return false;
    }

    // 基于 permission_code 检查
    final code = _permCode(resource, action);
    return authState.permissions.contains(code);
  }

  /// 获取用户的权限等级
  static PermissionLevel getUserPermissionLevel(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return PermissionLevel.view;
    }

    if (authState.isSystemAdmin) return PermissionLevel.admin;
    if (authState.permissions.contains('admin:manage')) {
      return PermissionLevel.manage;
    }
    if (authState.permissions.any((p) => p.endsWith(':manage'))) {
      return PermissionLevel.control;
    }
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

/// 权限守卫组件
/// 只有拥有指定权限的用户才能看到
class RoleGuard extends StatelessWidget {
  final List<String> requiredPermissions;
  final bool requireSystemAdmin;
  final Widget child;
  final Widget? placeholder;

  const RoleGuard({
    super.key,
    this.requiredPermissions = const [],
    this.requireSystemAdmin = false,
    required this.child,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return placeholder ?? const SizedBox.shrink();
    }

    if (requireSystemAdmin && !authState.isSystemAdmin) {
      return placeholder ?? const SizedBox.shrink();
    }

    if (requiredPermissions.isNotEmpty && !authState.isSystemAdmin) {
      final hasAll = requiredPermissions.every(
        (p) => authState.permissions.contains(p),
      );
      if (!hasAll) {
        return placeholder ?? const SizedBox.shrink();
      }
    }

    return child;
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
