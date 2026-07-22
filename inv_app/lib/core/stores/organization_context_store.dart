import 'package:flutter/foundation.dart';
import 'package:inv_app/core/entities/organization.dart';
import 'package:inv_app/core/services/api_service.dart';

/// 组织上下文存储
/// 管理用户当前的组织上下文和可用的组织列表
class OrganizationContextStore extends ChangeNotifier {
  final ApiService _apiService;

  /// 公开 API 服务访问器，供外部组件调用 API
  ApiService get apiService => _apiService;

  int? _activeOrgId;
  String? _activeOrgName;
  List<Organization> _availableOrgs = [];
  bool _isLoading = false;
  String? _error;

  // 当前激活的组织 ID
  int? get activeOrgId => _activeOrgId;

  // 当前激活的组织名称
  String? get activeOrgName => _activeOrgName;

  // 可用组织列表
  List<Organization> get availableOrgs => _availableOrgs;

  // 是否有激活的组织
  bool get hasActiveOrg => _activeOrgId != null;

  // 是否在加载中
  bool get isLoading => _isLoading;

  // 错误信息
  String? get error => _error;

  /// 是否属于指定组织
  bool isMemberOf(int orgId) {
    return _availableOrgs.any((org) => org.id == orgId);
  }

  /// 是否为组织拥有者
  bool isOrgOwner(int orgId) {
    // TODO: 需要从后端 API 获取用户的角色信息
    // 这里暂时返回 true
    return orgId == _activeOrgId;
  }

  OrganizationContextStore({required ApiService apiService})
      : _apiService = apiService;

  /// 设置激活的组织
  /// 切换上下文到指定的组织
  void setActiveOrganization(int orgId, [String? orgName]) {
    final org = _availableOrgs.firstWhere(
      (o) => o.id == orgId,
      orElse: () => throw ArgumentError('Organization $orgId not found'),
    );

    _activeOrgId = orgId;
    _activeOrgName = orgName ?? org.name;
    notifyListeners();
  }

  /// 加载用户可用的所有组织
  Future<void> loadAvailableOrganizations() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final orgs = await _apiService.getOrganizations();
      _availableOrgs = orgs;

      // 如果没有激活的组织，自动选择第一个
      if (_activeOrgId == null && _availableOrgs.isNotEmpty) {
        _activeOrgId = _availableOrgs.first.id;
        _activeOrgName = _availableOrgs.first.name;
      }

      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 切换上下文到指定组织
  /// 这是外部调用的主要接口
  Future<void> switchContextToOrganization(int orgId, String orgName) async {
    setActiveOrganization(orgId, orgName);

    // 通知其他 store 更新（如果它们依赖于组织上下文）
    // 例如：刷新设备列表、告警列表等
    notifyListeners();
  }

  /// 退出当前组织上下文
  void exitCurrentContext() {
    if (_activeOrgId != null) {
      _activeOrgId = null;
      _activeOrgName = null;
      notifyListeners();
    }
  }

  /// 清除所有组织上下文
  void clearAll() {
    _activeOrgId = null;
    _activeOrgName = null;
    _availableOrgs = [];
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  /// 添加组织到列表（通常在创建组织后调用）
  void addOrganization(Organization org) {
    if (!_availableOrgs.any((o) => o.id == org.id)) {
      _availableOrgs.add(org);
      notifyListeners();
    }
  }

  /// 更新组织信息
  void updateOrganization(Organization updatedOrg) {
    final index = _availableOrgs.indexWhere((o) => o.id == updatedOrg.id);
    if (index != -1) {
      _availableOrgs[index] = updatedOrg;

      // 如果正在查看的组织被更新，也同步更新显示的名称
      if (_activeOrgId == updatedOrg.id) {
        _activeOrgName = updatedOrg.name;
      }

      notifyListeners();
    }
  }

  /// 移除组织（从列表中隐藏，不真正删除）
  void removeOrganization(int orgId) {
    _availableOrgs.removeWhere((o) => o.id == orgId);

    // 如果移除的是当前激活的组织，切换到上一个或第一个
    if (_activeOrgId == orgId) {
      if (_availableOrgs.isNotEmpty) {
        _activeOrgId = _availableOrgs.first.id;
        _activeOrgName = _availableOrgs.first.name;
      } else {
        _activeOrgId = null;
        _activeOrgName = null;
      }
    }

    notifyListeners();
  }
}
