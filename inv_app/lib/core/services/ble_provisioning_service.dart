import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// BLE配网状态枚举
enum BleProvisioningStatus {
  idle,
  scanning,
  connecting,
  discoveringServices,
  readingDeviceInfo,
  subscribingNotifications,
  bleConnected, // BLE连接成功，可以开始配网
  writingCredentials,
  waitingForResult,
  wifiConnected, // WiFi配网成功
  failed,
  timeout,
  error,
}

/// BLE设备信息
class BleDeviceInfo {
  final String sn;
  final String firmwareVersion;
  final String macAddress;
  final String deviceName;
  final int rssi;

  BleDeviceInfo({
    required this.sn,
    required this.firmwareVersion,
    required this.macAddress,
    required this.deviceName,
    required this.rssi,
  });
}

/// BLE配网结果
class BleProvisioningResult {
  final bool success;
  final String? message;
  final BleDeviceInfo? deviceInfo;

  BleProvisioningResult({
    required this.success,
    this.message,
    this.deviceInfo,
  });
}

/// BLE配网服务
class BleProvisioningService {
  // 协议定义的UUID
  static const String serviceUuid = '43534956-5052-1000-8000-00805f9b34fb';
  static const String snCharacteristicUuid =
      '43534956-534e-1000-8000-00805f9b34fb';
  static const String firmwareCharacteristicUuid =
      '43534956-4657-1000-8000-00805f9b34fb';
  static const String macCharacteristicUuid =
      '43534956-4d41-1000-8000-00805f9b34fb';
  static const String ssidCharacteristicUuid =
      '43534956-5353-1000-8000-00805f9b34fb';
  static const String passwordCharacteristicUuid =
      '43534956-5057-1000-8000-00805f9b34fb';
  static const String statusCharacteristicUuid =
      '43534956-5354-1000-8000-00805f9b34fb';

  // 扫描超时时间
  static const Duration scanTimeout = Duration(seconds: 10);
  // 连接超时时间
  static const Duration connectionTimeout = Duration(seconds: 10);
  // 配网超时时间
  static const Duration provisioningTimeout = Duration(seconds: 60);

  // 状态流控制器
  final StreamController<BleProvisioningStatus> _statusController =
      StreamController<BleProvisioningStatus>.broadcast();
  Stream<BleProvisioningStatus> get statusStream => _statusController.stream;

  // 设备信息流控制器
  final StreamController<List<BleDeviceInfo>> _devicesController =
      StreamController<List<BleDeviceInfo>>.broadcast();
  Stream<List<BleDeviceInfo>> get devicesStream => _devicesController.stream;

  // 配网结果流控制器
  final StreamController<String> _resultController =
      StreamController<String>.broadcast();
  Stream<String> get resultStream => _resultController.stream;

  // 当前状态
  BleProvisioningStatus _currentStatus = BleProvisioningStatus.idle;
  BleProvisioningStatus get currentStatus => _currentStatus;

  // 扫描到的设备列表
  List<BleDeviceInfo> _discoveredDevices = [];
  List<BleDeviceInfo> get discoveredDevices => _discoveredDevices;

  // 当前连接的设备
  BluetoothDevice? _connectedDevice;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  // 订阅状态通知的特征
  // 超时定时器
  Timer? _scanTimer;
  Timer? _connectionTimer;
  Timer? _provisioningTimer;

  // 是否正在运行
  bool _running = false;
  bool get isRunning => _running;

  /// 发射状态更新
  void _emitStatus(BleProvisioningStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  /// 请求蓝牙权限
  Future<bool> requestBluetoothPermissions() async {
    // Android 12+ 需要蓝牙权限
    if (await Permission.bluetooth.isDenied) {
      final status = await Permission.bluetooth.request();
      if (!status.isGranted) return false;
    }

    // Android 12+ 需要蓝牙扫描权限
    if (await Permission.bluetoothScan.isDenied) {
      final status = await Permission.bluetoothScan.request();
      if (!status.isGranted) return false;
    }

    // Android 12+ 需要蓝牙连接权限
    if (await Permission.bluetoothConnect.isDenied) {
      final status = await Permission.bluetoothConnect.request();
      if (!status.isGranted) return false;
    }

    // Android 需要位置权限用于蓝牙扫描
    if (await Permission.location.isDenied) {
      final status = await Permission.location.request();
      if (!status.isGranted) return false;
    }

    return true;
  }

  /// 检查蓝牙是否可用
  Future<bool> isBluetoothAvailable() async {
    try {
      final adapterState = await FlutterBluePlus.adapterState.first;
      return adapterState == BluetoothAdapterState.on;
    } catch (e) {
      return false;
    }
  }

  /// 开始扫描BLE设备
  Future<void> startScan() async {
    if (_running) return;
    _running = true;
    _discoveredDevices = [];
    _connectedDevice = null;
    _scanTimer?.cancel();
    _connectionTimer?.cancel();
    _provisioningTimer?.cancel();
    _emitStatus(BleProvisioningStatus.scanning);

    try {
      // 请求权限
      final hasPermissions = await requestBluetoothPermissions();
      if (!hasPermissions) {
        _emitStatus(BleProvisioningStatus.error);
        _running = false;
        return;
      }

      // 检查蓝牙是否可用
      final isAvailable = await isBluetoothAvailable();
      if (!isAvailable) {
        _emitStatus(BleProvisioningStatus.error);
        _running = false;
        return;
      }

      // 开始扫描，过滤服务UUID
      await FlutterBluePlus.startScan(
        withServices: [Guid(serviceUuid)],
        timeout: scanTimeout,
      );

      // 监听扫描结果
      FlutterBluePlus.scanResults.listen((results) {
        _discoveredDevices = results.map((result) {
          // 协议说明：广播名是 CS_INV_完整SN，GAP Device Name也是完整SN
          final advName = result.advertisementData.advName;
          String deviceName;
          String sn = '';

          if (advName.isNotEmpty) {
            // 使用获取到的设备名
            deviceName = advName;
            // 从设备名中提取SN（去掉CS_INV_前缀）
            if (advName.startsWith('CS_INV_')) {
              sn = advName.substring(7); // 'CS_INV_'.length = 7
            }
          } else {
            // 如果没有设备名，用MAC地址后6位生成
            final mac = result.device.remoteId.toString();
            deviceName =
                'CS_INV_${mac.substring(mac.length - 6).replaceAll(':', '')}';
          }

          return BleDeviceInfo(
            sn: sn,
            firmwareVersion: '',
            macAddress: result.device.remoteId.toString(),
            deviceName: deviceName,
            rssi: result.rssi,
          );
        }).toList();

        // 发现设备后，取消超时定时器，避免显示“配网超时”
        if (_discoveredDevices.isNotEmpty) {
          _scanTimer?.cancel();
        }

        _devicesController.add(_discoveredDevices);
      });

      // 设置扫描超时
      _scanTimer = Timer(scanTimeout, () {
        if (_running && _currentStatus == BleProvisioningStatus.scanning) {
          stopScan();
          _emitStatus(BleProvisioningStatus.timeout);
        }
      });
    } catch (e) {
      _emitStatus(BleProvisioningStatus.error);
      _running = false;
    }
  }

  /// 停止扫描
  void stopScan() {
    FlutterBluePlus.stopScan();
    _scanTimer?.cancel();
    _running = false; // 重置运行标志
    if (_currentStatus == BleProvisioningStatus.scanning) {
      _emitStatus(BleProvisioningStatus.idle);
    }
  }

  /// 连接到BLE设备
  Future<BleProvisioningResult> connectToDevice(
      BleDeviceInfo deviceInfo) async {
    // 先停止扫描
    stopScan();

    if (_connectedDevice != null) {
      await disconnectFromDevice();
    }

    _emitStatus(BleProvisioningStatus.connecting);

    try {
      // 查找设备
      final device = BluetoothDevice.fromId(deviceInfo.macAddress);
      _connectedDevice = device;

      // 连接设备
      await device.connect(
        timeout: connectionTimeout,
        autoConnect: false,
      );

      _emitStatus(BleProvisioningStatus.discoveringServices);

      // 发现服务
      final services = await device.discoverServices();

      // 查找目标服务
      final targetService = services.firstWhere(
        (service) => service.uuid == Guid(serviceUuid),
        orElse: () => throw Exception('未找到配网服务'),
      );

      _emitStatus(BleProvisioningStatus.readingDeviceInfo);

      // 读取设备信息
      final deviceInfoResult = await _readDeviceInfo(targetService);

      _emitStatus(BleProvisioningStatus.subscribingNotifications);

      // 订阅状态通知
      await _subscribeToStatusNotifications(targetService);

      // 更新已发现设备列表中的设备信息（SN等）
      _updateDiscoveredDeviceInfo(deviceInfoResult);

      // 订阅成功后，立即标记为BLE已连接状态
      _emitStatus(BleProvisioningStatus.bleConnected);

      return BleProvisioningResult(
        success: true,
        deviceInfo: deviceInfoResult,
      );
    } catch (e) {
      _emitStatus(BleProvisioningStatus.error);
      return BleProvisioningResult(
        success: false,
        message: 'ble_connect_failed',
      );
    }
  }

  /// 读取设备信息
  Future<BleDeviceInfo> _readDeviceInfo(BluetoothService service) async {
    String sn = '';
    String firmwareVersion = '';
    String macAddress = '';

    for (final characteristic in service.characteristics) {
      if (characteristic.uuid == Guid(snCharacteristicUuid)) {
        final value = await characteristic.read();
        sn = String.fromCharCodes(value);
      } else if (characteristic.uuid == Guid(firmwareCharacteristicUuid)) {
        final value = await characteristic.read();
        firmwareVersion = String.fromCharCodes(value);
      } else if (characteristic.uuid == Guid(macCharacteristicUuid)) {
        final value = await characteristic.read();
        macAddress = String.fromCharCodes(value);
      }
    }

    // 从已发现设备列表中获取设备名
    final existingDevice = _discoveredDevices.firstWhere(
      (d) => d.macAddress == (_connectedDevice?.remoteId.toString() ?? ''),
      orElse: () => BleDeviceInfo(
          sn: '',
          firmwareVersion: '',
          macAddress: '',
          deviceName: 'CS_INV Device',
          rssi: 0),
    );

    // 使用读取到的SN更新设备名
    String deviceName = existingDevice.deviceName;
    if (sn.isNotEmpty) {
      // 如果读取到SN，使用完整SN作为设备名
      deviceName = 'CS_INV_$sn';
    } else if (deviceName.isEmpty) {
      deviceName = _connectedDevice?.platformName ?? 'CS_INV Device';
    }

    return BleDeviceInfo(
      sn: sn,
      firmwareVersion: firmwareVersion,
      macAddress: macAddress.isNotEmpty
          ? macAddress
          : (_connectedDevice?.remoteId.toString() ?? ''),
      deviceName: deviceName,
      rssi: 0,
    );
  }

  /// 订阅状态通知
  Future<void> _subscribeToStatusNotifications(BluetoothService service) async {
    for (final characteristic in service.characteristics) {
      if (characteristic.uuid == Guid(statusCharacteristicUuid)) {
        // 先启用通知（必须在监听之前）
        await characteristic.setNotifyValue(true);
        debugPrint(
            '[BLE] Subscribed to status notifications, characteristic UUID: ${characteristic.uuid}');

        // 监听状态变化
        characteristic.lastValueStream.listen((value) {
          if (value.isNotEmpty) {
            final status = String.fromCharCodes(value);
            debugPrint('[BLE] Received status notification: $status');
            _handleStatusUpdate(status);
          } else {
            debugPrint('[BLE] Received empty status notification');
          }
        });

        break;
      }
    }
  }

  /// 更新已发现设备列表中的设备信息
  void _updateDiscoveredDeviceInfo(BleDeviceInfo deviceInfo) {
    final index = _discoveredDevices.indexWhere(
      (d) => d.macAddress == deviceInfo.macAddress,
    );
    if (index >= 0) {
      _discoveredDevices[index] = deviceInfo;
      _devicesController.add(_discoveredDevices);
    }
  }

  /// Processing status update
  void _handleStatusUpdate(String status) {
    debugPrint(
        '[BLE] Processing status update: $status (length: ${status.length})');
    // 去除空白字符和空字符
    final cleanStatus = status.replaceAll(RegExp(r'[\s\x00]+'), '');
    debugPrint('[BLE] Cleaned status: $cleanStatus');

    if (!_resultController.isClosed) {
      switch (cleanStatus) {
        case 'waiting':
          _resultController.add('ble_waiting_credentials');
          break;
        case 'connecting':
          _resultController.add('ble_connecting_wifi');
          _emitStatus(BleProvisioningStatus.waitingForResult);
          break;
        case 'connected':
          _resultController.add('ble_wifi_connected');
          _emitStatus(BleProvisioningStatus.wifiConnected);
          break;
        case 'failed':
        case 'not_found':
          // 配网失败后，回到bleConnected状态，允许重新输入凭据
          _resultController.add(cleanStatus == 'not_found'
              ? 'ble_wifi_not_found'
              : 'ble_wifi_password_failed');
          _emitStatus(BleProvisioningStatus.bleConnected);
          break;
        default:
          debugPrint('[BLE] Unknown status: $cleanStatus');
          break;
      }
    } else {
      debugPrint('[BLE] Result stream closed, ignoring status update');
    }
  }

  /// 写入WiFi凭据
  Future<BleProvisioningResult> writeWiFiCredentials({
    required String ssid,
    required String password,
  }) async {
    if (_connectedDevice == null) {
      return BleProvisioningResult(
        success: false,
        message: 'ble_device_not_connected',
      );
    }

    _emitStatus(BleProvisioningStatus.writingCredentials);

    try {
      // 发现服务
      final services = await _connectedDevice!.discoverServices();
      final targetService = services.firstWhere(
        (service) => service.uuid == Guid(serviceUuid),
        orElse: () => throw Exception('未找到配网服务'),
      );

      // 查找SSID和密码特征
      BluetoothCharacteristic? ssidCharacteristic;
      BluetoothCharacteristic? passwordCharacteristic;

      for (final characteristic in targetService.characteristics) {
        if (characteristic.uuid == Guid(ssidCharacteristicUuid)) {
          ssidCharacteristic = characteristic;
        } else if (characteristic.uuid == Guid(passwordCharacteristicUuid)) {
          passwordCharacteristic = characteristic;
        }
      }

      if (ssidCharacteristic == null || passwordCharacteristic == null) {
        throw Exception('未找到WiFi配置特征');
      }

      // 先写入SSID
      await ssidCharacteristic.write(ssid.codeUnits, withoutResponse: false);
      debugPrint('[BLE] Written SSID: $ssid');

      // 写入密码（触发配网）
      await passwordCharacteristic.write(password.codeUnits,
          withoutResponse: false);
      debugPrint('[BLE] Written password, waiting for device response...');

      _emitStatus(BleProvisioningStatus.waitingForResult);

      // 设置配网超时
      _provisioningTimer = Timer(provisioningTimeout, () {
        if (_currentStatus == BleProvisioningStatus.waitingForResult) {
          _emitStatus(BleProvisioningStatus.timeout);
          _resultController.add('ble_timeout');
        }
      });

      return BleProvisioningResult(
        success: true,
        message: 'ble_credentials_sent',
      );
    } catch (e) {
      _emitStatus(BleProvisioningStatus.error);
      return BleProvisioningResult(
        success: false,
        message: 'ble_write_failed',
      );
    }
  }

  /// 断开设备连接
  Future<void> disconnectFromDevice() async {
    _provisioningTimer?.cancel();
    _connectionTimer?.cancel();

    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (e) {
        // 忽略断开连接时的错误
      }
      _connectedDevice = null;
    }

    _emitStatus(BleProvisioningStatus.idle);
  }

  /// 重置服务
  void reset() {
    stopScan();
    disconnectFromDevice();
    _discoveredDevices = [];
    _emitStatus(BleProvisioningStatus.idle);
  }

  /// 释放资源
  void dispose() {
    reset();
    _statusController.close();
    _devicesController.close();
    _resultController.close();
  }
}
