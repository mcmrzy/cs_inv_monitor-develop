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
///
/// 注意：外部主动调用 [checkConnectivity] 不计入"离线确认"计数（避免多处
/// 并发/先后调用放大误判），离线确认仅由系统状态事件与定时重试驱动。
class NetworkStatusService {
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
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

  /// 检查当前网络状态（乐观：单次 none 不判离线，仅安排延迟重试）
  ///
  /// 页面/Bloc 加载前探活可放心并发调用：检测结果不参与"离线确认"计数，
  /// 不会因启动瞬间网络栈未就绪误报 none 而把确认计数打满导致误判离线。
  Future<bool> checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    if (!results.contains(ConnectivityResult.none)) {
      _handleOnline();
      return true;
    }
    // 检测到无网络：保持乐观在线并安排一次延迟重试确认
    _scheduleRecheck();
    return _isOnline;
  }

  /// 处理系统网络状态变化事件
  void _onStatusChanged(List<ConnectivityResult> results) {
    _confirm(results);
  }

  /// 确认检测结果：只有系统事件与定时重试参与，累计到阈值才判离线
  void _confirm(List<ConnectivityResult> results) {
    if (!results.contains(ConnectivityResult.none)) {
      _handleOnline();
      return;
    }
    _offlineStreak++;
    // 无论是否达到阈值都继续重试：判离线后也能在网络恢复时自动回到在线
    _scheduleRecheck();
    if (_offlineStreak >= _offlineConfirmThreshold) {
      _setOnline(false);
    }
  }

  /// 网络恢复：重置确认计数并广播在线
  void _handleOnline() {
    _offlineStreak = 0;
    _recheckTimer?.cancel();
    _recheckTimer = null;
    _setOnline(true);
  }

  /// 延迟重试确认（重试结果参与离线确认）
  void _scheduleRecheck() {
    _recheckTimer?.cancel();
    _recheckTimer = Timer(_recheckInterval, () async {
      final results = await _connectivity.checkConnectivity();
      _confirm(results);
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
