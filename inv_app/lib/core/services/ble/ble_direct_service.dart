import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/ble/ble_polling_service.dart';
import 'package:inv_app/core/services/storage_service.dart';

/// 扫描发现的本地设备候选（场景 B，设计文档 §3.2）
class BleDiscoveredDevice {
  final String macAddress;
  final String name;

  /// 最近一次扫描到的时间（内存缓存用，可为空）
  final DateTime? lastSeen;

  const BleDiscoveredDevice({
    required this.macAddress,
    required this.name,
    this.lastSeen,
  });
}

/// BLE 直连总开关协调服务（设计文档 §3.1）
///
/// - setEnabled(true)：校验蓝牙开启 → 按自动连接开关连接已绑定设备 →
///   启动轮询 → 周期扫描发现本地设备（scanResults 缓存/流 + unboundDevices 流）
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
  bool _autoConnect = true;
  bool _suspended = false;
  Timer? _scanTimer;
  StreamSubscription<BleScanResult>? _scanSub;
  final _enabledController = StreamController<bool>.broadcast();
  final _unboundController = StreamController<BleDiscoveredDevice>.broadcast();

  /// 发现设备内存缓存（按 MAC 去重，会话内保留）
  final Map<String, BleDiscoveredDevice> _scanResults = {};
  final _scanResultsController =
      StreamController<List<BleDiscoveredDevice>>.broadcast();

  bool get enabled => _enabled;

  bool get autoConnect => _autoConnect;

  /// 是否处于挂起状态（配网/绑定流程占用 BLE 链路期间）
  bool get suspended => _suspended;

  Stream<bool> get enabledStream => _enabledController.stream;

  /// 未绑定设备发现流（场景 B：保留兼容，UI 已改用 [scanResults]）
  Stream<BleDiscoveredDevice> get unboundDevices => _unboundController.stream;

  /// 当前扫描到的本地设备快照（按最近发现时间倒序）
  List<BleDiscoveredDevice> get scanResults {
    final list = _scanResults.values.toList()
      ..sort((a, b) {
        final ta = a.lastSeen;
        final tb = b.lastSeen;
        if (ta == null || tb == null) return 0;
        return tb.compareTo(ta);
      });
    return list;
  }

  /// 发现设备列表变化流
  Stream<List<BleDiscoveredDevice>> get scanResultsStream =>
      _scanResultsController.stream;

  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    if (value) {
      await _start();
    } else {
      await _stop();
    }
  }

  /// 运行时切换自动连接（持久化由调用方负责）
  Future<void> setAutoConnect(bool value) async {
    if (value == _autoConnect) return;
    _autoConnect = value;
    if (!_enabled) return;
    if (value) {
      await manager.startAutoConnect();
    } else {
      await manager.stopAutoConnect();
    }
  }

  /// 手动触发一次扫描（UI「重新扫描」）
  void rescan() {
    if (_enabled && !_suspended) {
      _scanOnce();
    }
  }

  /// 为配网/绑定流程挂起直连：停止发现扫描/轮询/自动连接并释放全部连接，
  /// 确保目标设备恢复广播、可被配网流程扫描与连接。
  /// 不改变开关持久化状态，流程结束后调 [resumeAfterProvisioning] 恢复。
  Future<void> suspendForProvisioning() async {
    if (!_enabled || _suspended) return;
    _suspended = true;
    _scanTimer?.cancel();
    _scanTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    polling.stop();
    await manager.stopAutoConnect();
    await manager.disconnectAll();
  }

  /// 配网/绑定流程结束后恢复直连（未挂起时不动作）
  Future<void> resumeAfterProvisioning() async {
    if (!_suspended) return;
    _suspended = false;
    if (!_enabled) return;
    if (_autoConnect) {
      try {
        await manager.startAutoConnect();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[BleDirect] resume auto-connect failed: $e');
        }
      }
    }
    polling.start();
    _startScanLoop();
  }

  /// 强制释放所有 BLE 资源（不论 _enabled 标记状态）。
  ///
  /// 用于会话切换（登出/注册）时确保 BLE 适配器被完全释放，
  /// 防止上一账号残留的直连服务占用适配器导致新用户配网扫描失败。
  /// 与 [setEnabled(false)] 不同，本方法忽略 _enabled 守卫。
  Future<void> forceReleaseResources() async {
    _enabled = false;
    _suspended = false;
    _scanTimer?.cancel();
    _scanTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    polling.stop();
    await manager.stopAutoConnect();
    await manager.disconnectAll();
    // 不改持久化状态：调用方（登出清理）不需要修改用户的 BLE 直连开关偏好
  }

  Future<void> _start() async {
    final status = await adapter.status;
    if (status != BleAdapterStatus.on) {
      throw StateError('BLE adapter not on: $status');
    }
    _enabled = true;
    _enabledController.add(true);
    await storage.saveIsBleDirectEnabled(true);
    _autoConnect = await storage.getIsBleAutoConnect();

    if (_autoConnect) {
      await manager.startAutoConnect();
    }
    polling.start();
    _startScanLoop();
  }

  Future<void> _stop() async {
    _enabled = false;
    _suspended = false;
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

  /// 周期扫描 CSIV-CT 设备；全部候选进 [scanResults]，
  /// 无活跃会话的额外进 [unboundDevices] 流（场景 B）
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
        final device = BleDiscoveredDevice(
          macAddress: result.macAddress,
          name: result.name,
          lastSeen: DateTime.now(),
        );
        _scanResults[result.macAddress] = device;
        _scanResultsController.add(scanResults);
        // 已连接会话忽略；未绑定候选交由 UI 确认（场景 B）
        if (manager.sessionOf(result.macAddress) != null) return;
        _unboundController.add(device);
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
    await _scanResultsController.close();
  }
}
