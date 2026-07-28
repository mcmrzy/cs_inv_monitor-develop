import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// 网络状态服务
///
/// 提供全局网络连接状态检测，支持：
/// - 检查当前网络连接状态
/// - 监听网络状态变化
/// - 提供离线/在线状态流
class NetworkStatusService {
  final Connectivity _connectivity;
  StreamSubscription<ConnectivityResult>? _subscription;
  final _statusController = StreamController<bool>.broadcast();

  bool _isOnline = true;

  NetworkStatusService({required Connectivity connectivity})
      : _connectivity = connectivity;

  /// 当前是否在线
  bool get isOnline => _isOnline;

  /// 当前是否离线
  bool get isOffline => !_isOnline;

  /// 网络状态变化流 (true=在线, false=离线)
  Stream<bool> get statusStream => _statusController.stream;

  /// 初始化服务，开始监听网络状态
  Future<void> initialize() async {
    // 检查当前状态
    await _checkCurrentStatus();

    // 监听状态变化
    _subscription = _connectivity.onConnectivityChanged.listen(_onStatusChanged);
  }

  /// 检查当前网络状态
  Future<bool> checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    return _updateStatus(result);
  }

  /// 处理状态变化
  void _onStatusChanged(ConnectivityResult result) {
    _updateStatus(result);
  }

  /// 更新状态并通知监听者
  bool _updateStatus(ConnectivityResult result) {
    final wasOnline = _isOnline;
    _isOnline = result != ConnectivityResult.none;

    if (wasOnline != _isOnline) {
      if (kDebugMode) {
        debugPrint('[NetworkStatus] Status changed: ${_isOnline ? "ONLINE" : "OFFLINE"}');
      }
      _statusController.add(_isOnline);
    }

    return _isOnline;
  }

  /// 检查当前状态（不通知）
  Future<void> _checkCurrentStatus() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = result != ConnectivityResult.none;
  }

  /// 释放资源
  void dispose() {
    _subscription?.cancel();
    _statusController.close();
  }
}
