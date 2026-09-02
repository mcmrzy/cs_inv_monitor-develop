import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/features/ota/domain/repositories/local_communication_repository.dart';

/// BLE OTA 通信服务
///
/// 实现 [LocalCommunicationRepository] 接口，通过 BLE 替代 WiFi AP 进行本地 OTA 升级。
/// 使用项目已有的 [BleAdapter] 抽象层，与 flutter_blue_ultra 解耦。
///
/// BLE 传输协议设计：
/// - 固件分片写入（受 MTU 限制，每包 ~509 字节有效载荷）
/// - 通过 Notify 特征接收升级进度/设备信息
/// - 通过 Read 特征查询设备状态
///
/// UUID 来源：固件团队提供的 CSIV-PR 配网服务规范
class BleCommunicationService implements LocalCommunicationRepository {
  BleCommunicationService({
    required BleAdapter adapter,
  }) : _adapter = adapter;

  final BleAdapter _adapter;

  // ---------------------------------------------------------------------------
  // BLE OTA 服务 UUID 与特征 UUID
  // 挂在 CSIV-PR 配网服务（43534956-5052-...）下，OTA 三个特征前缀 43534F54
  // ---------------------------------------------------------------------------

  /// CSIV-PR 配网服务 UUID
  static const String _otaServiceUuid =
      '43534956-5052-1000-8000-00805f9b34fb';

  /// OTA STATUS 特征（Read/Notify）：设备信息 / 升级进度查询
  static const String _charReadUuid =
      '43534F54-5354-1000-8000-00805f9b34fb';

  /// OTA DATA 特征（Write/Notify）：固件数据写入 + 进度通知
  static const String _charWriteUuid =
      '43534F54-4441-1000-8000-00805f9b34fb';

  /// OTA DATA 特征（Notify）：升级进度推送 / 异步事件通知
  static const String _charNotifyUuid =
      '43534F54-4441-1000-8000-00805f9b34fb';

  // ---------------------------------------------------------------------------
  // 传输参数
  // ---------------------------------------------------------------------------

  /// BLE 有效载荷上限（协商 MTU 512 - 3 ATT 头字节）
  static const int _chunkSize = 509;

  /// 数据包偏移头长度（字节）
  static const int _offsetHeaderSize = 4;

  /// 每包固件数据上限：有效载荷减去偏移头，
  /// 保证 [4字节偏移 + 数据] 整包不超过 MTU 有效载荷
  static const int _dataChunkSize = _chunkSize - _offsetHeaderSize;

  /// 扫描超时
  static const Duration _scanTimeout = Duration(seconds: 15);

  /// 连接超时
  static const Duration _connectTimeout = Duration(seconds: 15);

  /// 命令响应超时
  static const Duration _commandTimeout = Duration(seconds: 10);

  /// 进度查询超时
  static const Duration _progressTimeout = Duration(seconds: 5);

  // ---------------------------------------------------------------------------
  // 内部状态
  // ---------------------------------------------------------------------------

  BleGattConnection? _connection;
  String? _connectedMacAddress;
  StreamSubscription<List<int>>? _notifySub;

  /// 通知数据缓冲（用于异步等待设备响应）
  final List<int> _notifyBuffer = [];
  Completer<List<int>>? _notifyCompleter;

  /// 当前已连接设备的 MAC 地址
  String? get connectedMacAddress => _connectedMacAddress;

  /// 是否已连接
  bool get isConnected =>
      _connection != null && _connectedMacAddress != null;

  // ---------------------------------------------------------------------------
  // 接口实现：连接设备
  // ---------------------------------------------------------------------------

  @override
  Future<bool> connectToDevice({
    required String deviceSN,
    required String deviceIP,
    String? password,
  }) async {
    debugPrint('[BleOTA] connectToDevice: scanning for SN=$deviceSN');

    try {
      // 1. 检查蓝牙适配器状态
      final status = await _adapter.status;
      if (status != BleAdapterStatus.on) {
        debugPrint('[BleOTA] BLE adapter not on: $status');
        return false;
      }

      // 2. 扫描目标设备（按 OTA 服务 UUID 过滤）
      final scanResult = await _scanForDevice(deviceSN);
      if (scanResult == null) {
        debugPrint('[BleOTA] device not found: $deviceSN');
        return false;
      }

      // 3. 连接设备
      debugPrint(
        '[BleOTA] connecting to ${scanResult.macAddress} (${scanResult.name})',
      );
      _connection = await _adapter.connect(
        scanResult.macAddress,
        timeout: _connectTimeout,
      );
      _connectedMacAddress = scanResult.macAddress;

      // 4. 订阅通知特征
      _notifySub = _connection!
          .subscribe(_otaServiceUuid, _charNotifyUuid)
          .listen(_onNotifyData, onError: _onNotifyError);

      debugPrint('[BleOTA] connected to ${scanResult.macAddress}');
      return true;
    } catch (e) {
      debugPrint('[BleOTA] connectToDevice failed: $e');
      await _cleanupConnection();
      return false;
    }
  }

  /// 扫描指定 SN 的设备
  Future<BleScanResult?> _scanForDevice(String deviceSN) async {
    final targetSN = deviceSN.toUpperCase();
    final completer = Completer<BleScanResult?>();

    final sub = _adapter
        .scan(
      serviceUuids: const [_otaServiceUuid],
      timeout: _scanTimeout,
    )
        .listen(
      (result) {
        // 匹配设备名称（CS-INV-{SN} 或 CS_INV_{SN}）
        final name = result.name.toUpperCase();
        if (name.contains(targetSN) && !completer.isCompleted) {
          completer.complete(result);
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) {
          debugPrint('[BleOTA] scan error: $e');
          completer.complete(null);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      },
    );

    // 等待扫描结果或超时
    final result = await completer.future.timeout(
      _scanTimeout,
      onTimeout: () => null,
    );

    await sub.cancel();
    await _adapter.stopScan();

    return result;
  }

  // ---------------------------------------------------------------------------
  // 接口实现：断开连接
  // ---------------------------------------------------------------------------

  @override
  Future<void> disconnect() async {
    debugPrint('[BleOTA] disconnecting');
    await _cleanupConnection();
  }

  // ---------------------------------------------------------------------------
  // 接口实现：上传固件（分片写入）
  // ---------------------------------------------------------------------------

  @override
  Future<void> uploadFirmware({
    required String deviceIP,
    required String filePath,
    required LocalOtaManifest manifest,
    void Function(int sent, int total)? onProgress,
  }) async {
    _assertConnected();

    debugPrint('[BleOTA] uploadFirmware: $filePath');
    debugPrint('[BleOTA] manifest: target=${manifest.target} '
        'taskId=${manifest.taskId} version=${manifest.version}');

    // 1. 读取固件文件
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Firmware file not found', filePath);
    }
    final bytes = await file.readAsBytes();
    debugPrint('[BleOTA] firmware size: ${bytes.length} bytes');

    // 2. 构造 OTA 初始化命令（强类型 manifest 直取字段，
    // 与 WiFi 通道共用同一套元数据，避免键名不一致）
    final initCommand = utf8.encode(jsonEncode({
      'cmd': 'ota_init',
      'target': manifest.target,
      'task_id': manifest.taskId,
      'version': manifest.version,
      'size': bytes.length,
      'sha256': manifest.sha256,
      'signature': manifest.signature,
      'security_version': manifest.securityVersion,
    }));

    // 3. 发送初始化命令
    await _writeCharacteristic(initCommand);
    final initResp = await _waitNotifyResponse(timeout: _commandTimeout);
    final initResult = _parseJsonResponse(initResp);
    if (initResult['status'] != 'ready') {
      throw Exception(
        'OTA init rejected: ${initResult['error'] ?? 'unknown'}',
      );
    }

    // 4. 分片发送固件数据
    int offset = 0;
    while (offset < bytes.length) {
      final end = (offset + _dataChunkSize < bytes.length)
          ? offset + _dataChunkSize
          : bytes.length;
      final chunk = bytes.sublist(offset, end);

      // 构造带序号的数据包
      final packet = _buildDataPacket(offset, chunk);
      await _writeCharacteristic(packet);

      offset = end;
      onProgress?.call(offset, bytes.length);

      // 给 BLE 协议栈一点处理时间
      await Future.delayed(const Duration(milliseconds: 10));
    }

    // 5. 发送传输完成命令
    final completeCommand = utf8.encode(jsonEncode({
      'cmd': 'ota_complete',
      'total_bytes': bytes.length,
    }));
    await _writeCharacteristic(completeCommand);

    // 6. 等待设备确认接收完成
    final completeResp = await _waitNotifyResponse(timeout: _commandTimeout);
    final completeResult = _parseJsonResponse(completeResp);
    if (completeResult['status'] != 'accepted') {
      throw Exception(
        'OTA transfer rejected: ${completeResult['error'] ?? 'unknown'}',
      );
    }

    debugPrint('[BleOTA] firmware upload completed');
  }

  /// 构造带偏移量的数据包
  ///
  /// 格式: [4字节偏移量(大端)] [固件数据...]
  /// 数据段长度由调用方限制为 [_dataChunkSize]，
  /// 确保整包不超过 BLE 协商 MTU 有效载荷
  List<int> _buildDataPacket(int offset, List<int> data) {
    final packet = <int>[
      (offset >> 24) & 0xFF,
      (offset >> 16) & 0xFF,
      (offset >> 8) & 0xFF,
      offset & 0xFF,
      ...data,
    ];
    return packet;
  }

  // ---------------------------------------------------------------------------
  // 接口实现：触发升级
  // ---------------------------------------------------------------------------

  @override
  Future<void> triggerUpgrade(String deviceIP) async {
    _assertConnected();

    debugPrint('[BleOTA] triggerUpgrade');

    final command = utf8.encode(jsonEncode({
      'cmd': 'ota_start',
    }));

    await _writeCharacteristic(command);

    final resp = await _waitNotifyResponse(timeout: _commandTimeout);
    final result = _parseJsonResponse(resp);

    if (result['status'] != 'ok' && result['status'] != 'started') {
      throw Exception(
        'Trigger upgrade failed: ${result['error'] ?? 'unknown'}',
      );
    }

    debugPrint('[BleOTA] upgrade triggered');
  }

  // ---------------------------------------------------------------------------
  // 接口实现：查询升级进度
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, dynamic>> getProgress(String deviceIP) async {
    _assertConnected();

    debugPrint('[BleOTA] getProgress');

    // 发送进度查询命令
    final command = utf8.encode(jsonEncode({
      'cmd': 'ota_progress',
    }));
    await _writeCharacteristic(command);

    // 等待通知响应
    final resp = await _waitNotifyResponse(timeout: _progressTimeout);
    return _parseJsonResponse(resp);
  }

  // ---------------------------------------------------------------------------
  // 接口实现：获取设备信息
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, dynamic>> getDeviceInfo(String deviceIP) async {
    _assertConnected();

    debugPrint('[BleOTA] getDeviceInfo');

    // 通过 Read 特征读取设备信息
    final bytes = await _connection!.read(_otaServiceUuid, _charReadUuid);
    return _parseJsonResponse(bytes);
  }

  // ---------------------------------------------------------------------------
  // 接口实现：测试连接
  // ---------------------------------------------------------------------------

  @override
  Future<bool> testConnection(String deviceIP) async {
    if (!isConnected) return false;

    try {
      debugPrint('[BleOTA] testConnection');

      // 发送心跳命令
      final command = utf8.encode(jsonEncode({'cmd': 'ping'}));
      await _writeCharacteristic(command);

      final resp = await _waitNotifyResponse(timeout: _progressTimeout);
      final result = _parseJsonResponse(resp);

      return result['status'] == 'ok' || result['cmd'] == 'pong';
    } catch (e) {
      debugPrint('[BleOTA] testConnection failed: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 接口实现：检查是否已连接
  // ---------------------------------------------------------------------------

  @override
  Future<bool> isConnectedToDeviceAP() async {
    return isConnected;
  }

  // ---------------------------------------------------------------------------
  // BLE 内部工具方法
  // ---------------------------------------------------------------------------

  /// 向设备写入数据
  Future<void> _writeCharacteristic(List<int> value) async {
    final connection = _connection;
    if (connection == null) {
      throw StateError('BLE not connected');
    }
    await connection.write(
      _otaServiceUuid,
      _charWriteUuid,
      value,
    );
  }

  /// 处理通知数据
  void _onNotifyData(List<int> data) {
    _notifyBuffer.addAll(data);

    // 检查是否有等待中的响应
    final completer = _notifyCompleter;
    if (completer != null && !completer.isCompleted) {
      // 简单实现：收到数据即认为响应完成
      // TODO: 根据固件协议实现更精确的消息边界检测
      completer.complete(List<int>.from(_notifyBuffer));
      _notifyBuffer.clear();
    }
  }

  /// 处理通知错误
  void _onNotifyError(Object error) {
    debugPrint('[BleOTA] notify error: $error');
    final completer = _notifyCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
  }

  /// 等待设备通知响应
  Future<List<int>> _waitNotifyResponse({
    Duration timeout = _commandTimeout,
  }) async {
    _notifyBuffer.clear();
    _notifyCompleter = Completer<List<int>>();

    try {
      return await _notifyCompleter!.future.timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException(
            'BLE notify response timeout',
            timeout,
          );
        },
      );
    } finally {
      _notifyCompleter = null;
    }
  }

  /// 解析 JSON 响应
  Map<String, dynamic> _parseJsonResponse(List<int> data) {
    try {
      final str = utf8.decode(data).trim();
      if (str.isEmpty) return {};
      return jsonDecode(str) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[BleOTA] JSON parse error: $e (data: $data)');
      return {};
    }
  }

  /// 断言已连接
  void _assertConnected() {
    if (!isConnected) {
      throw StateError(
        'BLE not connected. Call connectToDevice() first.',
      );
    }
  }

  /// 清理连接资源
  Future<void> _cleanupConnection() async {
    await _notifySub?.cancel();
    _notifySub = null;
    _notifyBuffer.clear();
    _notifyCompleter = null;

    final connection = _connection;
    _connection = null;
    _connectedMacAddress = null;

    try {
      await connection?.disconnect();
    } catch (e) {
      debugPrint('[BleOTA] disconnect error (ignored): $e');
    }
  }

  /// 释放所有资源（页面销毁时调用）
  Future<void> dispose() async {
    await _cleanupConnection();
  }

  // ============ 参数读写 / 控制命令（BLE 通道不支持 HTTP 风格） ============

  @override
  Future<String> readParameter(String deviceIP, String paramName) {
    throw UnsupportedError(
      'BLE 通道不支持 HTTP 参数读取，请切换到 WiFi AP 通道',
    );
  }

  @override
  Future<bool> writeParameter(
    String deviceIP, String paramName, String value,
  ) {
    throw UnsupportedError(
      'BLE 通道不支持 HTTP 参数写入，请切换到 WiFi AP 通道',
    );
  }

  @override
  Future<Map<String, dynamic>> controlDevice(
    String deviceIP,
    String command, {
    Map<String, dynamic>? params,
  }) {
    throw UnsupportedError(
      'BLE 通道不支持 HTTP 控制命令，请切换到 WiFi AP 通道',
    );
  }
}
