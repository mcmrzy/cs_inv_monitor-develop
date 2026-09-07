import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:inv_app/core/config/app_config.dart';

/// 网络状态服务
///
/// 提供全局网络连接状态检测，支持：
/// - 检查当前网络连接状态（带"连续确认"机制，避免启动瞬间误判离线）
/// - 监听网络状态变化
/// - 提供离线/在线状态流
/// - 主动互联网探活：覆盖"连着 WiFi 但无互联网"场景
///   （路由器断宽带/欠费、captive portal 等，链路层状态为已连接）
///
/// 对称滞回：判离线需连续多次确认，恢复在线同样需连续确认，
/// 避免网络抖动时状态横跳（banner/模式快速闪烁）。
///
/// 注意：外部主动调用 [checkConnectivity] 不计入"离线确认"计数（避免多处
/// 并发/先后调用放大误判），离线确认仅由系统状态事件与定时重试驱动。
class NetworkStatusService {
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final _statusController = StreamController<bool>.broadcast();

  bool _isOnline = true;
  int _offlineStreak = 0;
  int _onlineStreak = 0;
  Timer? _recheckTimer;

  /// 最近一次链路状态是否非 none（探活调度用：链路断开时无需探活）
  bool _linkUp = true;

  // ---- 互联网探活（覆盖"连 WiFi 无互联网"盲区）----
  Timer? _probeTimer;
  bool _probing = false;
  int _probeFailStreak = 0;

  /// 连续检测到无网络的次数阈值，达到才确认离线
  static const int _offlineConfirmThreshold = 3;

  /// 恢复在线的连续确认阈值（对称滞回，防抖动横跳）
  static const int _onlineConfirmThreshold = 2;

  /// 确认重试间隔
  static const Duration _recheckInterval = Duration(seconds: 2);

  /// 互联网探活周期
  static const Duration _probeInterval = Duration(seconds: 30);

  /// 探活连续失败阈值：链路正常但互联网连续不可达即判离线
  static const int _probeFailThreshold = 2;

  /// 单次探活超时
  static const Duration _probeTimeout = Duration(seconds: 3);

  NetworkStatusService({required Connectivity connectivity})
      : _connectivity = connectivity;

  /// 当前是否在线
  bool get isOnline => _isOnline;

  /// 当前是否离线
  bool get isOffline => !_isOnline;

  /// 网络状态变化流 (true=在线, false=离线)
  Stream<bool> get statusStream => _statusController.stream;

  /// 初始化服务，开始监听网络状态并启动周期性互联网探活
  Future<void> initialize() async {
    // 首次检查（乐观处理，不通知）
    await checkConnectivity();

    // 监听系统网络状态变化
    _subscription =
        _connectivity.onConnectivityChanged.listen(_onStatusChanged);

    // 周期性主动探活：检测"连着 WiFi 但无互联网"，并在探活恢复时回到在线
    _probeTimer?.cancel();
    _probeTimer = Timer.periodic(_probeInterval, (_) => _runInternetProbe());
  }

  /// 检查当前网络状态（乐观：单次 none 不判离线，仅安排延迟重试）
  ///
  /// 页面/Bloc 加载前探活可放心并发调用：检测结果不参与"离线确认"计数，
  /// 不会因启动瞬间网络栈未就绪误报 none 而把确认计数打满导致误判离线。
  Future<bool> checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    if (!results.contains(ConnectivityResult.none)) {
      _handleLinkUp(probeNow: true);
      return _isOnline;
    }
    // 检测到无网络：保持乐观在线并安排一次延迟重试确认
    _linkUp = false;
    _scheduleRecheck();
    return _isOnline;
  }

  /// 处理系统网络状态变化事件
  void _onStatusChanged(List<ConnectivityResult> results) {
    _confirm(results);
  }

  /// 确认检测结果：只有系统事件与定时重试参与，累计到阈值才判离线；
  /// 恢复在线同样需要连续确认（对称滞回）
  void _confirm(List<ConnectivityResult> results) {
    if (!results.contains(ConnectivityResult.none)) {
      _handleLinkUp();
      return;
    }
    _linkUp = false;
    _onlineStreak = 0;
    _offlineStreak++;
    // 无论是否达到阈值都继续重试：判离线后也能在网络恢复时自动回到在线
    _scheduleRecheck();
    if (_offlineStreak >= _offlineConfirmThreshold) {
      _setOnline(false);
    }
  }

  /// 链路恢复：对称滞回——连续确认达到阈值才广播在线，
  /// 避免 WiFi 抖动时状态横跳；在线后立即触发一次互联网探活
  void _handleLinkUp({bool probeNow = false}) {
    _linkUp = true;
    _offlineStreak = 0;
    _recheckTimer?.cancel();
    _recheckTimer = null;

    if (_isOnline) {
      if (probeNow) unawaited(_runInternetProbe());
      return;
    }

    _onlineStreak++;
    if (_onlineStreak >= _onlineConfirmThreshold) {
      _onlineStreak = 0;
      _setOnline(true);
      // 链路恢复后立即探活一次：若"连 WiFi 无互联网"会由探活纠正回离线
      unawaited(_runInternetProbe());
    }
  }

  /// 延迟重试确认（重试结果参与离线确认）
  void _scheduleRecheck() {
    _recheckTimer?.cancel();
    _recheckTimer = Timer(_recheckInterval, () async {
      final results = await _connectivity.checkConnectivity();
      _confirm(results);
    });
  }

  // ---- 互联网探活 ----

  /// 执行一次互联网探活并据此修正状态。
  /// 链路断开（飞行模式等）时跳过：探活必然失败且无意义。
  Future<void> _runInternetProbe() async {
    if (!_linkUp || _probing) return;
    _probing = true;
    bool reachable;
    try {
      reachable = await _probeInternet();
    } finally {
      _probing = false;
    }

    if (reachable) {
      _probeFailStreak = 0;
      // 曾因探活失败判离线、但链路一直正常：探活恢复即回到在线
      if (!_isOnline && _linkUp) {
        _offlineStreak = 0;
        _onlineStreak = 0;
        _setOnline(true);
      }
    } else {
      _probeFailStreak++;
      // 链路正常但互联网连续不可达（如欠费/光猫断网）：判离线
      if (_isOnline && _probeFailStreak >= _probeFailThreshold) {
        _setOnline(false);
        // 保持探活：互联网恢复后自动回到在线
      }
    }
  }

  /// 对 API 基址发起 HEAD 请求：任何 HTTP 响应（含 4xx）都视为互联网可达；
  /// 连接/握手/超时失败视为不可达
  Future<bool> _probeInternet() async {
    final uri = Uri.tryParse(AppConfig.apiBaseUrl);
    if (uri == null || uri.host.isEmpty) return true; // 无法探测时保持乐观

    final client = HttpClient()..connectionTimeout = _probeTimeout;
    try {
      final request = await client
          .headUrl(uri.replace(path: '/'))
          .timeout(_probeTimeout);
      final response = await request.close().timeout(_probeTimeout);
      await response.drain<void>();
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
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
    _probeTimer?.cancel();
    _subscription?.cancel();
    _statusController.close();
  }
}
