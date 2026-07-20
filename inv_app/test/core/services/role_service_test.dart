import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/role_service.dart';

void main() {
  test('role constants match backend role model', () {
    expect(RoleService.roleSuperAdmin, 0);
    expect(RoleService.roleGeneralAgent, 1);
    expect(RoleService.roleAgent, 2);
    expect(RoleService.roleDealer, 3);
    expect(RoleService.roleInstaller, 4);
    expect(RoleService.roleEndUser, 5);
  });

  test('agent hierarchy and leaf roles are classified correctly', () {
    expect(RoleService.isAgent(RoleService.roleGeneralAgent), isTrue);
    expect(RoleService.isAgent(RoleService.roleAgent), isTrue);
    expect(RoleService.isAgent(RoleService.roleDealer), isTrue);
    expect(RoleService.isAgent(RoleService.roleInstaller), isFalse);
    expect(RoleService.isInstaller(RoleService.roleInstaller), isTrue);
    expect(RoleService.isEndUser(RoleService.roleEndUser), isTrue);
  });
}
