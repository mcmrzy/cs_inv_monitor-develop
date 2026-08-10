import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/ble/ble_polling_service.dart';
import 'package:inv_app/core/services/storage_service.dart';

/// 扫描发现的未绑定设备候选（场景 B，设计文档 §3.2）
class BleDiscoveredDevice {
  final String macAddress;
  final String name;

  const BleDiscoveredDevice({required this.macAddress, required this.name});
}

/// BLE 直连总开关协调服务（设计文档 §3.1）
///
/// - setEnabled(true)：校验蓝牙开启 → 自动连接已绑定设备 → 启动轮询 →
///   周期扫描发现未绑定设备（unboundDevices 流）
/// - setEnabled(false)：断开全部会话并停止轮询，恢复纯 HTTP
class BleDirectService {
  BleDirectService({
    required this.adapter,
    required this.manager,
    required this.polling,
    required this.storage,
  });

  final BleAdapter adapter;
  final BleDeviceManager manager;
  final BlePollingService polling;
  final StorageServiceLike storage;

  static const Duration _rescanInterval = Duration(seconds: 30);

  bool _enabled = false;
  Timer? _scanTimer;
  StreamSubscription<BleScanResult>? _scanSub;
  final _enabledController = StreamController<bool>.broadcast();
  final _unboundController = StreamController<BleDiscoveredDevice>.broadcast();

  bool get enabled => _enabled;

  Stream<bool> get enabledStream => _enabledController.stream;

  /// 未绑定设备发现流（场景 B：UI 弹一键确认）
  Stream<BleDiscoveredDevice> get unboundDevices => _unboundController.stream;

  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    if (value) {
      await _start();
    } else {
      await _stop();
    }
  }

  Future<void> _start() async {
    final status = await adapter.status;
    if (status != BleAdapterStatus.on) {
      throw StateError('BLE adapter not on: $status');
    }
    _enabled = true;
    _enabledController.add(true);
    await storage.saveIsBleDirectEnabled(true);

    await manager.startAutoConnect();
    polling.start();
    _startScanLoop();
  }

  Future<void> _stop() async {
    _enabled = false;
    _enabledController.add(false);
    _scanTimer?.cancel();
    _scanTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    polling.stop();
    await manager.stopAutoConnect();
    await manager.disconnectAll();
    await storage.saveIsBleDirectEnabled(false);
  }

  /// 周期扫描 CSIV-CT 设备，未在本地绑定（无 device_key）的作为候选上报
  void _startScanLoop() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(_rescanInterval, (_) => _scanOnce());
    _scanOnce();
  }

  Future<void> _scanOnce() async {
    if (!_enabled) return;
    await _scanSub?.cancel();
    _scanSub = adapter.scan(
      serviceUuids: const [BleCtProtocol.serviceUuid],
      timeout: const Duration(seconds: 15),
    ).listen(
      (result) {
        if (!_enabled) return;
        // 已连接会话忽略；未绑定候选交由 UI 确认（场景 B）
        if (manager.sessionOf(result.macAddress) != null) return;
        _unboundController.add(
          BleDiscoveredDevice(
            macAddress: result.macAddress,
            name: result.name,
          ),
        );
      },
      onError: (Object e) {
        if (kDebugMode) debugPrint('[BleDirect] scan error: $e');
      },
    );
  }

  /// 从持久化存储恢复开关状态（App 启动时调用）
  Future<void> restore() async {
    final saved = await storage.getIsBleDirectEnabled();
    if (saved && !_enabled) {
      try {
        await _start();
      } catch (e) {
        if (kDebugMode) debugPrint('[BleDirect] restore failed: $e');
      }
    }
  }

  Future<void> dispose() async {
    await _stop();
    await _enabledController.close();
    await _unboundController.close();
  }
}
