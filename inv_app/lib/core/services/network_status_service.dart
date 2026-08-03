import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// 网络状态服务
///
/// 提供全局网络连接状态检测，支持：
/// - 检查当前网络连接状态（带"连续确认"机制，避免启动瞬间误判离线）
/// - 监听网络状态变化
/// - 提供离线/在线状态流
///
/// 默认乐观在线：单次检测到无网络不立即判离线，连续多次确认后才离线，
/// 解决 App 启动瞬间系统网络栈未就绪导致 checkConnectivity() 误返回 none 的问题。
class NetworkStatusService {
  final Connectivity _connectivity;
  StreamSubscription<ConnectivityResult>? _subscription;
  final _statusController = StreamController<bool>.broadcast();

  bool _isOnline = true;
  int _offlineStreak = 0;
  Timer? _recheckTimer;

  /// 连续检测到无网络的次数阈值，达到才确认离线
  static const int _offlineConfirmThreshold = 3;

  /// 确认重试间隔
  static const Duration _recheckInterval = Duration(seconds: 2);

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
    // 首次检查（乐观处理，不通知）
    await checkConnectivity();

    // 监听系统网络状态变化
    _subscription =
        _connectivity.onConnectivityChanged.listen(_onStatusChanged);
  }

  /// 检查当前网络状态（带连续确认：单次 none 不判离线）
  Future<bool> checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    return _handleResult(result);
  }

  /// 处理系统网络状态变化事件
  void _onStatusChanged(ConnectivityResult result) {
    _handleResult(result);
  }

  /// 处理检测结果：检测到网络立即在线；无网络需连续确认才离线
  bool _handleResult(ConnectivityResult result) {
    if (result != ConnectivityResult.none) {
      // 检测到网络：立即恢复在线并重置确认计数
      _offlineStreak = 0;
      _recheckTimer?.cancel();
      _recheckTimer = null;
      _setOnline(true);
      return true;
    }

    // 检测到无网络：不立即判离线，累计次数并延迟重试确认
    _offlineStreak++;
    if (_offlineStreak >= _offlineConfirmThreshold) {
      _setOnline(false);
    } else {
      _scheduleRecheck();
    }
    return _isOnline; // 确认期间保持乐观在线
  }

  /// 延迟重试确认
  void _scheduleRecheck() {
    _recheckTimer?.cancel();
    _recheckTimer = Timer(_recheckInterval, () {
      checkConnectivity();
    });
  }

  /// 更新状态并通知监听者
  void _setOnline(bool online) {
    final wasOnline = _isOnline;
    _isOnline = online;

    if (wasOnline != _isOnline) {
      if (kDebugMode) {
        debugPrint(
          '[NetworkStatus] Status changed: ${_isOnline ? "ONLINE" : "OFFLINE"}',
        );
      }
      _statusController.add(_isOnline);
    }
  }

  /// 释放资源
  void dispose() {
    _recheckTimer?.cancel();
    _subscription?.cancel();
    _statusController.close();
  }
}
