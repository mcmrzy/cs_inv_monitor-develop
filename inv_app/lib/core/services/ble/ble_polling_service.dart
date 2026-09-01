import 'dart:async';

import 'package:inv_app/core/services/ble/ble_device_manager.dart';

/// 一次轮询得到的遥测快照
class BlePolledTelemetry {
  final String sn;
  final Map<String, dynamic> data;

  const BlePolledTelemetry({required this.sn, required this.data});
}

/// 定时轮询已就绪 BLE 会话的遥测快照（设计文档 §3.3）
///
/// 默认 180s；与设备 80s 节拍 notify 推送并存，轮询作为主动拉取兜底。
class BlePollingService {
  BlePollingService({
    required this.manager,
    this.interval = const Duration(seconds: 180),
  });

  final BleDeviceManager manager;
  Duration interval;

  Timer? _timer;
  final _controller = StreamController<BlePolledTelemetry>.broadcast();
  bool _pollInFlight = false;
  bool _disposed = false;
  int _generation = 0;

  bool get isRunning => _timer?.isActive ?? false;

  /// 轮询遥测流
  Stream<BlePolledTelemetry> get telemetry => _controller.stream;

  void start() {
    if (_disposed || isRunning) return;
    final generation = ++_generation;
    _timer = Timer.periodic(
      interval,
      (_) => unawaited(_pollOnce(generation)),
    );
  }

  void stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  void setInterval(Duration value) {
    interval = value;
    if (isRunning) {
      _timer?.cancel();
      final generation = ++_generation;
      _timer = Timer.periodic(
        interval,
        (_) => unawaited(_pollOnce(generation)),
      );
    }
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _generation && isRunning;

  Future<void> _pollOnce(int generation) async {
    if (_pollInFlight || !_isCurrent(generation)) return;
    _pollInFlight = true;
    try {
      for (final session in manager.sessions.values) {
        if (!_isCurrent(generation)) return;
        if (session.state != BleDeviceState.ready || session.sn == null) {
          continue;
        }
        try {
          final data = await session.readTelemetrySnapshot();
          if (!_isCurrent(generation)) return;
          _controller.add(
            BlePolledTelemetry(sn: session.sn!, data: data),
          );
        } catch (_) {
          // 单设备读取失败不影响其他设备与下一周期
        }
      }
    } finally {
      _pollInFlight = false;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
    _controller.close();
  }
}
