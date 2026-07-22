import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:wifi_iot/wifi_iot.dart';

/// 逆变器连接监控器：连接到设备热点后，30秒检测一次逆变器是否有交流输出。
/// 如果 AC 电流和功率均 ≤ 0（逆变器已停机/无响应），自动断开设备热点并恢复家用 WiFi。
class InverterConnectionMonitor {
  Timer? _graceTimer;
  Timer? _checkTimer;
  bool _isMonitoring = false;
  int _zeroACCount = 0;

  /// 连续 N 次 AC=0 才触发断开（每次 3 秒轮询，2 次 = 6 秒确认窗口）
  static const int _confirmCount = 2;

  /// 连接后等待多久开始检测（秒）
  static const int _gracePeriodSeconds = 30;

  /// 检测间隔（与轮询间隔一致，秒）
  static const int _checkIntervalSeconds = 3;

  /// 自动断开后的回调（UI 可用于显示提示）
  VoidCallback? onAutoDisconnected;

  bool get isMonitoring => _isMonitoring;

  /// 开始监控。连接到设备热点后调用。
  /// [onAutoDisconnected] 在自动断开时触发。
  void start({VoidCallback? onAutoDisconnected}) {
    stop();
    this.onAutoDisconnected = onAutoDisconnected;
    _isMonitoring = true;
    _zeroACCount = 0;

    // 30 秒宽限期后开始检测
    _graceTimer = Timer(const Duration(seconds: _gracePeriodSeconds), () {
      debugPrint('[InverterMonitor] Grace period over, starting AC check');
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
    _zeroACCount = 0;
  }

  /// 每次轮询拿到实时数据后调用此方法传入 AC 数据。
  /// 也可不调用此方法，改用 [_performCheck] 由内部定时器主动拉取。
  void feedRealtime(InverterRealtime realtime) {
    if (!_isMonitoring || _graceTimer?.isActive == true) return;
    _evaluateAC(realtime.ac);
  }

  void _performCheck() {
    // 由外部通过 feedRealtime 注入数据；此处仅作为后备触发
    // 实际检测逻辑在 _evaluateAC 中
  }

  void _evaluateAC(ACData? ac) {
    if (ac == null) {
      _zeroACCount++;
    } else if (ac.current <= 0 && ac.power <= 0) {
      _zeroACCount++;
    } else {
      _zeroACCount = 0;
    }

    if (_zeroACCount >= _confirmCount) {
      debugPrint(
        '[InverterMonitor] Inverter not responding (AC=0 x$_zeroACCount), auto-disconnecting',
      );
      stop();
      _autoDisconnect();
    }
  }

  Future<void> _autoDisconnect() async {
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
    onAutoDisconnected?.call();
  }

  void dispose() {
    stop();
    onAutoDisconnected = null;
  }
}
