import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_ultra/flutter_blue_ultra.dart' as fbu;

/// BLE 适配器抽象层
///
/// 隔离具体 BLE 栈（当前为 flutter_blue_ultra）。上层（BleDeviceManager 等）
/// 只依赖本文件的抽象类型；未来更换 BLE 栈（如 universal_ble）时，
/// 仅需在本文件新增/替换实现类，上层零改动。

/// BLE 适配器状态（与具体栈解耦）
enum BleAdapterStatus { unknown, unsupported, unauthorized, off, on }

/// 扫描结果（与具体栈解耦）
@immutable
class BleScanResult {
  final String macAddress;
  final String name;
  final int rssi;
  final List<String> serviceUuids;

  const BleScanResult({
    required this.macAddress,
    required this.name,
    required this.rssi,
    this.serviceUuids = const [],
  });
}

/// 单设备链路状态
enum BleLinkState { disconnected, connecting, connected, disconnecting }

/// GATT 连接抽象
abstract class BleGattConnection {
  String get macAddress;

  /// 链路状态流（广播流，可多处订阅）
  Stream<BleLinkState> get linkState;

  /// 当前实际协商 MTU，未协商时为 23。
  int get mtuNow;

  /// 协商 MTU，返回实际生效值
  Future<int> requestMtu(int mtu);

  Future<List<int>> read(
    String serviceUuid,
    String characteristicUuid, {
    int timeout = 15,
  });

  /// 写入特征值。
  ///
  /// [allowLongWrite] 打开 BLE 长写（prepare/execute）子过程：单次 ATT 写上限是
  /// MTU-3（本设备 NimBLE 协商 256 → 253），而 OTA 的 JSON 报文约 455 字节，
  /// 不开长写会被平台直接拒（PlatformException: data longer than allowed）。
  /// 上限 512 字节，且必须与响应一起用（不能和 withoutResponse 组合）。
  Future<void> write(
    String serviceUuid,
    String characteristicUuid,
    List<int> value, {
    bool withoutResponse = false,
    bool allowLongWrite = false,
    int timeout = 15,
  });

  /// 订阅特征通知。返回流仅推送订阅期间实际收到的值（不重放历史值），
  /// 取消订阅时自动关闭该特征的 notify。
  Stream<List<int>> subscribe(String serviceUuid, String characteristicUuid);

  Future<void> disconnect();
}

/// BLE 适配器抽象
abstract class BleAdapter {
  Future<BleAdapterStatus> get status;

  Stream<BleAdapterStatus> get statusStream;

  /// 扫描（可按服务 UUID 过滤）。每个新结果推送一次；
  /// 到达 [timeout] 后底层扫描停止，流保持可再次发起扫描。
  Stream<BleScanResult> scan({
    List<String> serviceUuids = const [],
    Duration timeout = const Duration(seconds: 15),
  });

  Future<void> stopScan();

  /// 连接设备。
  /// [autoConnect]（Android 有效）：挂起直连，设备出现在范围内时系统自动回连；
  /// 注意 autoConnect 模式下不能在 connect 时协商 MTU，需连接后自行 requestMtu。
  Future<BleGattConnection> connect(
    String macAddress, {
    bool autoConnect = false,
    Duration timeout = const Duration(seconds: 15),
  });
}

/// flutter_blue_ultra 实现
class FlutterBlueUltraAdapter implements BleAdapter {
  static BleAdapterStatus _mapAdapterState(fbu.BluetoothAdapterState s) {
    switch (s) {
      case fbu.BluetoothAdapterState.on:
        return BleAdapterStatus.on;
      case fbu.BluetoothAdapterState.off:
        return BleAdapterStatus.off;
      case fbu.BluetoothAdapterState.unauthorized:
        return BleAdapterStatus.unauthorized;
      case fbu.BluetoothAdapterState.unavailable:
        return BleAdapterStatus.unsupported;
      case fbu.BluetoothAdapterState.unknown:
      case fbu.BluetoothAdapterState.turningOn:
      case fbu.BluetoothAdapterState.turningOff:
        return BleAdapterStatus.unknown;
    }
  }

  @override
  Future<BleAdapterStatus> get status async =>
      _mapAdapterState(await fbu.FlutterBlueUltra.adapterState.first);

  @override
  Stream<BleAdapterStatus> get statusStream =>
      fbu.FlutterBlueUltra.adapterState.map(_mapAdapterState);

  @override
  Stream<BleScanResult> scan({
    List<String> serviceUuids = const [],
    Duration timeout = const Duration(seconds: 15),
  }) {
    final controller = StreamController<BleScanResult>();
    StreamSubscription<List<fbu.ScanResult>>? sub;
    final seen = <String, BleScanResult>{};

    final wanted = serviceUuids.map((e) => e.toLowerCase()).toSet();

    bool accept(fbu.ScanResult r) {
      if (wanted.isEmpty) return true;
      final name = r.advertisementData.advName.toUpperCase();
      // 名称匹配兜底：部分机型/固件把服务 UUID 只放 SCAN_RSP，
      // 硬件 ScanFilter 会漏扫，调试助手无过滤所以能搜到。
      if (name.contains('CS_INV') || name.contains('CS-INV')) return true;
      final advertised = r.advertisementData.serviceUuids
          .map((g) => g.str.toLowerCase())
          .toSet();
      return wanted.any(advertised.contains);
    }

    sub = fbu.FlutterBlueUltra.scanResults.listen(
      (results) {
        for (final r in results) {
          if (!accept(r)) continue;
          final mapped = BleScanResult(
            macAddress: r.device.remoteId.str,
            name: r.advertisementData.advName,
            rssi: r.rssi,
            serviceUuids: r.advertisementData.serviceUuids
                .map((g) => g.str)
                .toList(growable: false),
          );
          final prev = seen[mapped.macAddress];
          if (prev != null &&
              prev.name == mapped.name &&
              prev.rssi == mapped.rssi) {
            continue;
          }
          seen[mapped.macAddress] = mapped;
          controller.add(mapped);
        }
      },
      onError: controller.addError,
    );

    // 不传硬件 UUID 过滤：Android ScanFilter 只匹配 ADV 包，
    // UUID 在 SCAN_RSP 或广播不稳定时会漏扫。androidLegacy
    // 走 1M PHY，兼容 ESP32 传统广播（调试助手同策略）。
    fbu.FlutterBlueUltra.startScan(
      withServices: const [],
      timeout: timeout,
      androidLegacy: true,
    ).catchError((Object e) {
      controller.addError(e);
    });

    controller.onCancel = () async {
      await sub?.cancel();
      await fbu.FlutterBlueUltra.stopScan();
    };
    return controller.stream;
  }

  @override
  Future<void> stopScan() => fbu.FlutterBlueUltra.stopScan();

  @override
  Future<BleGattConnection> connect(
    String macAddress, {
    bool autoConnect = false,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final device = fbu.BluetoothDevice.fromId(macAddress);
    // autoConnect 与 connect 时协商 MTU 互斥（flutter_blue_ultra 断言），
    // 挂起直连场景传 mtu: null，由调用方连接成功后自行 requestMtu。
    await device.connect(
      timeout: timeout,
      mtu: autoConnect ? null : 512,
      autoConnect: autoConnect,
    );
    return FbuGattConnection(device);
  }
}

/// flutter_blue_ultra 的 GATT 连接封装
class FbuGattConnection implements BleGattConnection {
  final fbu.BluetoothDevice _device;
  final Map<String, fbu.BluetoothCharacteristic> _charCache = {};

  @override
  int get mtuNow => _device.mtuNow;
  final Map<String, int> _notifyRefCount = {};
  List<fbu.BluetoothService>? _services;

  FbuGattConnection(this._device);

  @override
  String get macAddress => _device.remoteId.str;

  @override
  Stream<BleLinkState> get linkState =>
      _device.connectionState.map(_mapLinkState);

  static BleLinkState _mapLinkState(fbu.BluetoothConnectionState s) {
    if (s == fbu.BluetoothConnectionState.connected) {
      return BleLinkState.connected;
    }
    if (s == fbu.BluetoothConnectionState.disconnected) {
      return BleLinkState.disconnected;
    }
    // Android/iOS 不流式推送 connecting/disconnecting（枚举值已废弃），兜底视为连接中
    return BleLinkState.connecting;
  }

  @override
  Future<int> requestMtu(int mtu) => _device.requestMtu(mtu);

  Future<fbu.BluetoothCharacteristic> _resolve(
    String serviceUuid,
    String characteristicUuid,
  ) async {
    final key =
        '${serviceUuid.toLowerCase()}/${characteristicUuid.toLowerCase()}';
    final cached = _charCache[key];
    if (cached != null) return cached;

    _services ??= await _device.discoverServices();
    for (final service in _services!) {
      if (service.uuid.str.toLowerCase() != serviceUuid.toLowerCase()) {
        continue;
      }
      for (final c in service.characteristics) {
        if (c.uuid.str.toLowerCase() == characteristicUuid.toLowerCase()) {
          _charCache[key] = c;
          return c;
        }
      }
    }
    throw StateError(
      'characteristic not found: $key（设备固件可能未实现 CSIV-CT 服务）',
    );
  }

  @override
  Future<List<int>> read(
    String serviceUuid,
    String characteristicUuid, {
    int timeout = 15,
  }) async {
    final c = await _resolve(serviceUuid, characteristicUuid);
    return c.read(timeout: timeout);
  }

  @override
  Future<void> write(
    String serviceUuid,
    String characteristicUuid,
    List<int> value, {
    bool withoutResponse = false,
    bool allowLongWrite = false,
    int timeout = 15,
  }) async {
    final c = await _resolve(serviceUuid, characteristicUuid);
    await c.write(
      value,
      withoutResponse: withoutResponse,
      allowLongWrite: allowLongWrite,
      timeout: timeout,
    );
  }

  @override
  Stream<List<int>> subscribe(String serviceUuid, String characteristicUuid) {
    final key =
        '${serviceUuid.toLowerCase()}/${characteristicUuid.toLowerCase()}';
    late StreamController<List<int>> controller;
    StreamSubscription<List<int>>? sub;
    bool cancelled = false;
    bool subscribed = false;

    controller = StreamController<List<int>>(
      onListen: () async {
        try {
          final c = await _resolve(serviceUuid, characteristicUuid);
          if (cancelled) return;
          // onValueReceived：仅推送订阅期间实际收到的值，避免 lastValueStream 重放
          sub = c.onValueReceived.listen(
            controller.add,
            onError: controller.addError,
          );
          await c.setNotifyValue(true);
          if (cancelled) {
            await sub?.cancel();
            await c.setNotifyValue(false);
            return;
          }
          _notifyRefCount[key] = (_notifyRefCount[key] ?? 0) + 1;
          subscribed = true;
        } catch (error, stackTrace) {
          await sub?.cancel();
          if (!cancelled) controller.addError(error, stackTrace);
        }
      },
      onCancel: () async {
        cancelled = true;
        await sub?.cancel();
        if (!subscribed) return;
        subscribed = false;
        final count = (_notifyRefCount[key] ?? 1) - 1;
        _notifyRefCount[key] = count;
        if (count <= 0) {
          _notifyRefCount.remove(key);
          try {
            final c = await _resolve(serviceUuid, characteristicUuid);
            await c.setNotifyValue(false);
          } catch (_) {
            // 连接已断开时忽略关闭失败
          }
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> disconnect() => _device.disconnect();
}
