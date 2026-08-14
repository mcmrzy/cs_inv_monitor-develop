import 'dart:async';
import 'package:inv_app/core/services/network_status_service.dart';
import 'package:inv_app/core/services/storage_service.dart';

enum ConnectionMode { remote, local }

/// 连接模式服务（云端 / 本地直连）
///
/// 职责（Q4/Q7 融合）：
/// - 维护当前连接模式（云端 / 本地）并持久化（is_local_mode）
/// - guest 本地模式：登录页"本地模式"入口免登录进入本地数据链路（蓝牙/AP），
///   与已登录用户断网自动切换本地共用同一套本地链路
/// - 网络驱动的自动切换：订阅 NetworkStatusService.statusStream（其内部已有
///   连续多次确认阈值防瞬时误判），断网自动切本地、恢复在线自动切云端；
///   仅当用户未手动选择（_manualOverride=false）时生效，手动选择优先
class ConnectionModeService {
  final StorageService _storageService;
  final NetworkStatusService _networkStatusService;
  final StreamController<ConnectionMode> _modeController =
      StreamController<ConnectionMode>.broadcast();

  ConnectionMode _currentMode = ConnectionMode.remote;

  /// 是否处于 guest 本地模式（登录页免登录进入，持久化 is_guest_local_mode）
  bool _isGuestLocalMode = false;

  /// 手动模式锁：用户显式选择（登录页本地模式入口 / 本地模式页连接设备 /
  /// 设置页切换云端）后置 true；网络事件驱动的自动切换仅在 false 时生效，
  /// 避免自动切换覆盖用户的显式选择
  bool _manualOverride = false;

  StreamSubscription<bool>? _networkSub;

  ConnectionMode get currentMode => _currentMode;
  bool get isLocal => _currentMode == ConnectionMode.local;
  bool get isRemote => _currentMode == ConnectionMode.remote;
  bool get isGuestLocalMode => _isGuestLocalMode;

  Stream<ConnectionMode> get modeStream => _modeController.stream;

  ConnectionModeService(
    this._storageService, {
    required NetworkStatusService networkStatusService,
  }) : _networkStatusService = networkStatusService;

  Future<bool> isLocalMode() async {
    return _storageService.getIsLocalMode();
  }

  /// 手动设置模式（用户显式操作），同时置手动锁
  Future<void> setLocalMode(bool isLocal) async {
    _manualOverride = true;
    _currentMode = isLocal ? ConnectionMode.local : ConnectionMode.remote;
    _modeController.add(_currentMode);
    await _storageService.saveIsLocalMode(isLocal);
  }

  /// 手动切换到云端模式（置手动锁，之后不再自动切本地）
  Future<void> switchToRemote() async {
    _manualOverride = true;
    _currentMode = ConnectionMode.remote;
    _modeController.add(_currentMode);
    await _storageService.saveIsLocalMode(false);
    // 使用 API 轮询，无需重连 MQTT
  }

  /// 手动切换到本地模式（置手动锁，之后不再自动切云端）
  Future<void> switchToLocal() async {
    _manualOverride = true;
    _currentMode = ConnectionMode.local;
    _modeController.add(_currentMode);
    await _storageService.saveIsLocalMode(true);
  }

  /// 登录页"本地模式"入口：以 guest 身份进入本地模式（免登录），
  /// 数据链路与已登录用户断网自动切换本地共用同一套（蓝牙/AP/本地 OTA）
  Future<void> enterGuestLocalMode() async {
    _isGuestLocalMode = true;
    await _storageService.saveIsGuestLocalMode(true);
    await switchToLocal();
  }

  /// 退出 guest 本地模式（返回登录页 / 重新登录时调用）
  Future<void> exitGuestLocalMode() async {
    _isGuestLocalMode = false;
    await _storageService.saveIsGuestLocalMode(false);
  }

  Future<void> init() async {
    final isLocal = await _storageService.getIsLocalMode();
    _isGuestLocalMode = await _storageService.getIsGuestLocalMode();
    _currentMode = isLocal ? ConnectionMode.local : ConnectionMode.remote;
    _modeController.add(_currentMode);

    // Q7：订阅网络状态实现自动切换（复用 NetworkStatusService 的连续确认
    // 阈值，避免瞬时抖动横跳）；用户手动选择后不再自动覆盖
    _networkSub = _networkStatusService.statusStream.listen((online) {
      if (_manualOverride) return;
      final target = online ? ConnectionMode.remote : ConnectionMode.local;
      if (target != _currentMode) {
        _autoApplyMode(target);
      }
    });
  }

  /// 网络事件驱动的自动切换（不置手动锁、不改 guest 标志），
  /// 网络恢复后仍可自动切回
  void _autoApplyMode(ConnectionMode mode) {
    _currentMode = mode;
    _modeController.add(_currentMode);
    _storageService.saveIsLocalMode(mode == ConnectionMode.local);
  }

  void dispose() {
    _networkSub?.cancel();
    _modeController.close();
  }
}
