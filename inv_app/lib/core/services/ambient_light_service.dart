import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 环境光传感器服务（Android 自研通道 csergy/ambient_light）
///
/// 提供环境光照度（lux）流，供扫码页「暗光补光」按真实亮度判断。
/// iOS / 无环境光传感器的机型：[supported] 为 false，
/// 调用方应回退「持续扫不到码」启发式判据。
class AmbientLightService {
  AmbientLightService._();

  static const EventChannel _channel = EventChannel('csergy/ambient_light');

  static StreamSubscription<dynamic>? _sub;
  static final _luxController = StreamController<double>.broadcast();
  static bool _supported = false;
  static bool _started = false;
  static double _lastLux = -1;

  /// 设备是否具备环境光传感器（start() 后首个事件起有效）
  static bool get supported => _supported;

  /// 最近一次光照度（lux，负数表示尚未获取）
  static double get lastLux => _lastLux;

  /// 光照度流（lux）
  static Stream<double> get luxStream => _luxController.stream;

  /// 开始监听（幂等）
  static void start() {
    if (_started) return;
    _started = true;
    try {
      _sub = _channel.receiveBroadcastStream().listen(
        (event) {
          if (event == null) {
            // 原生侧明确告知无传感器
            _supported = false;
            return;
          }
          final lux = (event as num).toDouble();
          _supported = true;
          _lastLux = lux;
          if (!_luxController.isClosed) {
            _luxController.add(lux);
          }
        },
        onError: (Object e) {
          // 平台不支持（如 iOS）：回退启发式
          _supported = false;
          if (kDebugMode) {
            debugPrint('[AmbientLight] stream error: $e');
          }
        },
      );
    } catch (e) {
      _supported = false;
      if (kDebugMode) {
        debugPrint('[AmbientLight] start failed: $e');
      }
    }
  }

  /// 停止监听并重置状态
  static void stop() {
    _sub?.cancel();
    _sub = null;
    _started = false;
    _supported = false;
    _lastLux = -1;
  }
}
