import 'dart:async';

import 'package:inv_app/core/services/ble/ble_device_manager.dart';

/// 一次轮询得到的遥测快照
class BlePolledTelemetry {
  final String sn;
  final Map<String, dynamic> data;

  const BlePolledTelemetry({required this.sn, required this.data});
}

/// A single device read failure, kept observable without stopping the cycle.
class BlePollingError {
  final String sn;
  final Object error;
  final StackTrace stackTrace;

  const BlePollingError({
    required this.sn,
    required this.error,
    required this.stackTrace,
  });
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
  final _errorController = StreamController<BlePollingError>.broadcast();
  int? _pollInFlightGeneration;
  bool _disposed = false;
  int _generation = 0;

  bool get isRunning => _timer?.isActive ?? false;

  /// 轮询遥测流
  Stream<BlePolledTelemetry> get telemetry => _controller.stream;

  /// Per-device read failures. One failed device does not stop other reads.
  Stream<BlePollingError> get errors => _errorController.stream;

  void start() {
    if (_disposed || isRunning) return;
    final generation = ++_generation;
    _timer = Timer.periodic(
      interval,
      (_) => unawaited(_pollOnce(generation)),
    );
    unawaited(_pollOnce(generation));
  }

  void stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _pollInFlightGeneration = null;
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
    if (_pollInFlightGeneration != null || !_isCurrent(generation)) return;
    _pollInFlightGeneration = generation;
    try {
      for (final session in manager.sessions.values) {
        if (!_isCurrent(generation)) return;
        if (session.state != BleDeviceState.ready || session.sn == null) {
          continue;
        }
        if (session.isOtaInProgress) continue;
        try {
          final data = await session.readTelemetrySnapshot();
          if (!_isCurrent(generation)) return;
          _controller.add(
            BlePolledTelemetry(sn: session.sn!, data: data),
          );
        } catch (error, stackTrace) {
          if (_isCurrent(generation)) {
            _errorController.add(
              BlePollingError(
                sn: session.sn!,
                error: error,
                stackTrace: stackTrace,
              ),
            );
          }
        }
      }
    } finally {
      if (_pollInFlightGeneration == generation) {
        _pollInFlightGeneration = null;
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
    _controller.close();
    _errorController.close();
  }
}
