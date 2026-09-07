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

  /// 协商 MTU，返回实际生效值
  Future<int> requestMtu(int mtu);

  Future<List<int>> read(String serviceUuid, String characteristicUuid);

  Future<void> write(
    String serviceUuid,
    String characteristicUuid,
    List<int> value, {
    bool withoutResponse = false,
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

    sub = fbu.FlutterBlueUltra.scanResults.listen(
      (results) {
        for (final r in results) {
          controller.add(
            BleScanResult(
              macAddress: r.device.remoteId.str,
              name: r.advertisementData.advName,
              rssi: r.rssi,
              serviceUuids: r.advertisementData.serviceUuids
                  .map((g) => g.str)
                  .toList(growable: false),
            ),
          );
        }
      },
      onError: controller.addError,
    );

    fbu.FlutterBlueUltra.startScan(
      withServices: serviceUuids.map(fbu.Guid.new).toList(growable: false),
      timeout: timeout,
    ).catchError((Object e) {
      controller.addError(e);
    });

    controller.onCancel = () => sub?.cancel();
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
  Future<List<int>> read(String serviceUuid, String characteristicUuid) async {
    final c = await _resolve(serviceUuid, characteristicUuid);
    return c.read();
  }

  @override
  Future<void> write(
    String serviceUuid,
    String characteristicUuid,
    List<int> value, {
    bool withoutResponse = false,
  }) async {
    final c = await _resolve(serviceUuid, characteristicUuid);
    await c.write(value, withoutResponse: withoutResponse);
  }

  @override
  Stream<List<int>> subscribe(String serviceUuid, String characteristicUuid) {
    final key =
        '${serviceUuid.toLowerCase()}/${characteristicUuid.toLowerCase()}';
    late StreamController<List<int>> controller;
    StreamSubscription<List<int>>? sub;

    controller = StreamController<List<int>>(
      onListen: () async {
        final c = await _resolve(serviceUuid, characteristicUuid);
        // onValueReceived：仅推送订阅期间实际收到的值，避免 lastValueStream 重放
        sub = c.onValueReceived.listen(
          controller.add,
          onError: controller.addError,
        );
        _notifyRefCount[key] = (_notifyRefCount[key] ?? 0) + 1;
        await c.setNotifyValue(true);
      },
      onCancel: () async {
        await sub?.cancel();
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
