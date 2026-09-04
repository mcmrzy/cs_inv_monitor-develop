import 'package:flutter/foundation.dart';
import 'package:inv_app/core/entities/organization.dart';
import 'package:inv_app/core/services/api_service.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';

/// 组织上下文存储
/// 管理用户当前的组织上下文和可用的组织列表
class OrganizationContextStore extends ChangeNotifier {
  final ApiService _apiService;
  final StorageService _storageService;

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

  OrganizationContextStore({
    required ApiService apiService,
    required StorageService storageService,
  })  : _apiService = apiService,
        _storageService = storageService;

  /// 加载用户可用的所有组织
  Future<void> loadAvailableOrganizations() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final orgs = await _apiService.getOrganizations();
      _availableOrgs = orgs;

      // 只恢复已持久化的认证上下文；不能把列表首项当作已切换。
      final persistedId = await _storageService.getActiveOrgId();
      final persistedIndex = persistedId == null
          ? -1
          : _availableOrgs.indexWhere((org) => org.id == persistedId);
      if (persistedIndex >= 0) {
        final active = _availableOrgs[persistedIndex];
        _activeOrgId = active.id;
        _activeOrgName = active.name;
      } else {
        _activeOrgId = null;
        _activeOrgName = null;
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
  Future<void> switchContextToOrganization(
    int orgId,
    String orgName,
    AuthBloc authBloc,
  ) async {
    if (!isMemberOf(orgId)) {
      throw ArgumentError('Organization $orgId not found');
    }

    _error = null;
    final authState = authBloc.state;
    if (authState is AuthAuthenticated &&
        authState.activeOrganizationId == orgId) {
      _activeOrgId = orgId;
      _activeOrgName = orgName;
      notifyListeners();
      return;
    }

    try {
      // AuthBloc 先完成服务端令牌轮换、权限刷新和持久化事务。
      await authBloc.switchOrganizationContext(orgId, orgName);
      _activeOrgId = orgId;
      _activeOrgName = orgName;
      notifyListeners();
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      rethrow;
    }
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
