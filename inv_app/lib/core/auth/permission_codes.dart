/// Permission codes returned by the backend RBAC contract.
///
/// Keep these values aligned with
/// `business-api/internal/repository/role_default_grants.go`.
abstract final class PermissionCodes {
  static const _legacyResourceAliases = <String, String>{
    'device': 'devices',
    'organization': 'organizations',
    'alert': 'alerts',
    'user': 'users',
  };

  static const devicesView = 'devices:view';
  static const devicesControl = 'devices:control';
  static const devicesManage = 'devices:manage';

  static const organizationsManage = 'organizations:manage';
  static const organizationsInvite = 'organizations:invite';
  static const organizationsManageMembers = 'organizations:manage_members';

  static const alertsView = 'alerts:view';
  static const usersManage = 'users:manage';
  static const adminManage = 'admin:manage';

  /// Builds a permission code while supporting only known legacy aliases.
  /// Unknown and already canonical resource names are kept unchanged.
  static String build(String resource, String action) {
    final canonicalResource = _legacyResourceAliases[resource] ?? resource;
    return '$canonicalResource:$action';
  }
}
