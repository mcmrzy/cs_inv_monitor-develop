import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:wifi_iot/wifi_iot.dart';

/// 逆变器连接监控器：连接设备热点后，基于"通信是否应答"判定设备是否失联。
///
/// 判定依据为轮询应答而非业务量（修复：光伏逆变器夜间/弱光时 AC 输出
/// 本就为 0，旧实现用 AC=0 判停机会在夜间误断开热点）：
/// - [feedRealtime]：轮询成功收到数据 → 通信正常，重置计数；
/// - [feedFailure]：轮询请求异常/超时 → 计一次无响应；
/// - 内部定时器兜底：长时间没有任何应答（轮询循环卡死/未喂数据）同样计无响应。
///
/// 连续 [_confirmCount] 次无响应后自动断开设备热点并恢复家用 WiFi。
class InverterConnectionMonitor {
  Timer? _graceTimer;
  Timer? _checkTimer;
  bool _isMonitoring = false;
  int _noResponseCount = 0;
  DateTime? _lastResponseAt;

  /// 连续 N 次无响应才触发断开（3 秒间隔 × 3 次 = 9 秒确认窗口）
  static const int _confirmCount = 3;

  /// 连接后等待多久开始检测（秒）
  static const int _gracePeriodSeconds = 30;

  /// 检测间隔（与轮询间隔一致，秒）
  static const int _checkIntervalSeconds = 3;

  /// 应答超时：超过该时长未收到任何轮询数据视为一次无响应（秒）
  static const int _responseTimeoutSeconds = 10;

  /// 自动断开后的回调（UI 可用于显示提示）
  VoidCallback? onAutoDisconnected;

  bool get isMonitoring => _isMonitoring;

  /// 开始监控。连接到设备热点后调用。
  /// [onAutoDisconnected] 在自动断开时触发。
  void start({VoidCallback? onAutoDisconnected}) {
    stop();
    this.onAutoDisconnected = onAutoDisconnected;
    _isMonitoring = true;
    _noResponseCount = 0;
    _lastResponseAt = null;

    // 30 秒宽限期后开始检测
    _graceTimer = Timer(const Duration(seconds: _gracePeriodSeconds), () {
      debugPrint(
        '[InverterMonitor] Grace period over, starting responsiveness check',
      );
      _lastResponseAt ??= DateTime.now();
      _checkTimer = Timer.periodic(
        const Duration(seconds: _checkIntervalSeconds),
        (_) => _performCheck(),
      );
    });
    debugPrint(
      '[InverterMonitor] Started, will check after ${_gracePeriodSeconds}s',
    );
  }

  /// 停止监控。断开连接或切换模式时调用。
  void stop() {
    _graceTimer?.cancel();
    _graceTimer = null;
    _checkTimer?.cancel();
    _checkTimer = null;
    _isMonitoring = false;
    _noResponseCount = 0;
    _lastResponseAt = null;
  }

  /// 每次轮询拿到实时数据后调用：视为设备通信应答正常
  void feedRealtime(InverterRealtime realtime) {
    _markResponded();
  }

  /// 轮询请求异常/超时时调用：计一次无响应。
  /// 旧实现吞掉轮询异常且不喂数据，导致设备真正无响应时监控恰好失效
  void feedFailure() {
    _markNoResponse();
  }

  void _markResponded() {
    if (!_isMonitoring || _graceTimer?.isActive == true) return;
    _lastResponseAt = DateTime.now();
    _noResponseCount = 0;
  }

  void _markNoResponse() {
    if (!_isMonitoring || _graceTimer?.isActive == true) return;
    _noResponseCount++;
    if (_noResponseCount >= _confirmCount) {
      debugPrint(
        '[InverterMonitor] Inverter not responding '
        '(no response x$_noResponseCount), auto-disconnecting',
      );
      final callback = onAutoDisconnected;
      stop();
      _autoDisconnect(callback);
    }
  }

  /// 内部定时器兜底：长时间没有轮询应答（feed 丢失/轮询循环停滞）
  /// 同样计一次无响应，保证监控在数据链路异常时仍然生效
  void _performCheck() {
    final last = _lastResponseAt;
    if (last == null) return;
    final silentSeconds = DateTime.now().difference(last).inSeconds;
    if (silentSeconds >= _responseTimeoutSeconds) {
      // 重置计时避免一个静默窗口被重复计数
      _lastResponseAt = DateTime.now();
      _markNoResponse();
    }
  }

  Future<void> _autoDisconnect(VoidCallback? callback) async {
    try {
      // 1. 断开设备热点连接
      await WiFiForIoTPlugin.disconnect();
      debugPrint('[InverterMonitor] WiFi disconnected from device AP');

      // 2. 取消强制 WiFi 使用，让系统自动切回家用 WiFi
      await WiFiForIoTPlugin.forceWifiUsage(false);
      debugPrint(
        '[InverterMonitor] forceWifiUsage(false) - OS will reconnect to home WiFi',
      );
    } catch (e) {
      debugPrint('[InverterMonitor] Auto-disconnect error: $e');
    }

    // 3. 通知 UI
    callback?.call();
  }

  void dispose() {
    stop();
    onAutoDisconnected = null;
  }
}
