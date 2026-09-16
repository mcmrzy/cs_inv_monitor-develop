import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/features/ota/domain/repositories/local_communication_repository.dart';

/// BLE OTA 通信服务
///
/// 复用已鉴权的 [BleDeviceSession]，通过 [BleOtaLease] 独占链路，
/// 按固件 v2 协议完成 ota.ctrl / ota.data / ota.query。
/// 不再另建未鉴权连接，避免与轮询/控制抢适配器。
class BleCommunicationService implements LocalCommunicationRepository {
  BleCommunicationService({
    required BleAdapter adapter,
    required BleDeviceManager manager,
  })  : _adapter = adapter,
        _manager = manager;

  final BleAdapter _adapter;
  final BleDeviceManager _manager;

  /// 固件 OTA JSON 上限 512B；Base64 后 payload 需留信封余量。
  static const int _dataChunkSize = 128;

  static const Duration _scanTimeout = Duration(seconds: 15);
  static const Duration _commandTimeout = Duration(seconds: 10);
  static const Duration _progressTimeout = Duration(seconds: 5);

  BleDeviceSession? _session;
  BleOtaLease? _otaLease;
  StreamSubscription<Map<String, dynamic>>? _statusSub;
  String? _connectedMacAddress;

  final Random _random = Random.secure();
  final List<Map<String, dynamic>> _statusLog = [];
  final List<_OtaStatusWaiter> _statusWaiters = [];

  String? get connectedMacAddress => _connectedMacAddress;

  bool get isConnected =>
      _session != null && _session!.state == BleDeviceState.ready;

  @override
  Future<bool> connectToDevice({
    required String deviceSN,
    required String deviceIP,
    String? password,
  }) async {
    debugPrint('[BleOTA] connectToDevice: SN=$deviceSN');
    try {
      final status = await _adapter.status;
      if (status != BleAdapterStatus.on) {
        debugPrint('[BleOTA] BLE adapter not on: $status');
        return false;
      }

      final session = await _readySessionForSn(deviceSN);
      if (session == null) {
        debugPrint('[BleOTA] no authenticated session for $deviceSN');
        return false;
      }
      if (session.isOtaInProgress) {
        debugPrint('[BleOTA] session already has OTA lease');
        return false;
      }

      _session = session;
      _connectedMacAddress = session.macAddress;
      return true;
    } catch (e) {
      debugPrint('[BleOTA] connectToDevice failed: $e');
      await _cleanupLease();
      return false;
    }
  }

  /// 优先复用 manager 中已就绪且 SN 匹配的会话；否则扫描后接入已有会话。
  Future<BleDeviceSession?> _readySessionForSn(String deviceSN) async {
    final target = deviceSN.toUpperCase();
    for (final session in _manager.sessions.values) {
      if (session.state == BleDeviceState.ready &&
          (session.sn ?? '').toUpperCase() == target) {
        return session;
      }
    }

    final scanResult = await _scanForDevice(deviceSN);
    if (scanResult == null) return null;

    final session = await _manager.connectDevice(
      scanResult.macAddress,
      autoReconnect: false,
    );
    if (session.state != BleDeviceState.ready) {
      throw const BleCommandException(
        'UNAUTHENTICATED',
        'device must be bound and authenticated before BLE OTA',
      );
    }
    return session;
  }

  Future<BleScanResult?> _scanForDevice(String deviceSN) async {
    final targetSN = deviceSN.toUpperCase();
    final completer = Completer<BleScanResult?>();

    final sub = _adapter
        .scan(
          serviceUuids: BleCtProtocol.scanServiceUuids,
          timeout: _scanTimeout,
        )
        .listen(
      (result) {
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

    final result = await completer.future.timeout(
      _scanTimeout,
      onTimeout: () => null,
    );
    await sub.cancel();
    await _adapter.stopScan();
    return result;
  }

  /// 释放 OTA 独占；不断开共享 BLE 会话。
  @override
  Future<void> disconnect() async {
    debugPrint('[BleOTA] releasing OTA lease');
    await _cleanupLease();
  }

  @override
  Future<void> uploadFirmware({
    required String deviceIP,
    required String filePath,
    required LocalOtaManifest manifest,
    void Function(int sent, int total)? onProgress,
  }) async {
    _assertConnected();
    final session = _session!;
    final sessionId = session.connectionSessionId;
    if (sessionId == null) {
      throw const BleCommandException(
        'UNAUTHENTICATED',
        'missing session id',
      );
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Firmware file not found', filePath);
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw ArgumentError('Firmware file is empty');
    }
    manifest.validate();

    debugPrint(
      '[BleOTA] uploadFirmware size=${bytes.length} '
      'target=${manifest.target} task=${manifest.taskId}',
    );

    _otaLease = await session.acquireOtaLease();
    _statusLog.clear();
    _statusSub = _otaLease!.statuses.listen(
      _onOtaStatus,
      onError: (Object e) => debugPrint('[BleOTA] status error: $e'),
    );

    final transferId =
        '${manifest.taskId}-${DateTime.now().microsecondsSinceEpoch}';
    final infoBody = _flattenInfoBody(await session.readInfo());

    await _writeCtrl({
      'v': 2,
      'type': 'ota.ctrl',
      'message_id': _messageId(),
      'session_id': sessionId,
      'body': {
        'transfer_id': transferId,
        'task_id': manifest.taskId,
        'manifest_version': 1,
        'target': _wireTarget(manifest.target),
        'model': infoBody['model'] ?? '',
        'version': manifest.version,
        'size': bytes.length,
        'sha256': manifest.sha256,
        'signature': manifest.signature,
        'security_version': manifest.securityVersion,
        'timeout_seconds': manifest.timeoutSeconds,
      },
    });

    final accepted = await _waitForStatus(
      (s) {
        final body = _normalizeStatusEnvelope(s);
        return body['transfer_id'] == transferId &&
            const {'accepted', 'receiving', 'verifying', 'installing'}
                .contains(_stageOf(s));
      },
      timeout: _commandTimeout,
    );
    _throwIfFailed(accepted);

    var offset = 0;
    while (offset < bytes.length) {
      if (!_otaLeaseIsActive) {
        throw const BleCommandException('OTA_NOT_ACTIVE', 'lease released');
      }
      final end = min(offset + _dataChunkSize, bytes.length);
      final chunk = bytes.sublist(offset, end);

      await _writeData({
        'v': 2,
        'type': 'ota.data',
        'message_id': _messageId(),
        'session_id': sessionId,
        'body': {
          'transfer_id': transferId,
          'offset': offset,
          'payload': base64Encode(chunk),
        },
      });

      final ack = await _waitForStatus(
        (s) {
          final body = _normalizeStatusEnvelope(s);
          final acceptedOffset = (body['accepted_offset'] as num?)?.toInt();
          return body['transfer_id'] == transferId &&
              acceptedOffset != null &&
              acceptedOffset >= end;
        },
        timeout: _commandTimeout,
      );
      _throwIfFailed(ack);
      offset = end;
      onProgress?.call(offset, bytes.length);
    }

    // 写入成功不等于设备已持久接收；等待校验/烧写进入下一阶段。
    final after = await _waitForStatus(
      (s) {
        final body = _normalizeStatusEnvelope(s);
        return body['transfer_id'] == transferId &&
            const {'verifying', 'installing', 'rebooting', 'succeeded'}
                .contains(_stageOf(s));
      },
      timeout: _commandTimeout,
    );
    _throwIfFailed(after);
    debugPrint('[BleOTA] firmware bytes accepted: $offset/${bytes.length}');
  }

  @override
  Future<void> triggerUpgrade(String deviceIP) async {
    _assertConnected();
    // 固件在 ota.ctrl 后由 worker 自动安装；此处仅确认任务仍在推进。
    final status = await _queryStatus();
    final stage = _stageOf(status);
    if (stage == 'failed' || stage == 'rolled_back' || stage == 'cancelled') {
      _throwIfFailed(status);
    }
    debugPrint('[BleOTA] triggerUpgrade sees stage=$stage');
  }

  @override
  Future<Map<String, dynamic>> getProgress(String deviceIP) async {
    _assertConnected();
    final status = await _queryStatus();
    return _mapProgress(status);
  }

  @override
  Future<Map<String, dynamic>> getDeviceInfo(String deviceIP) async {
    _assertConnected();
    final info = await _session!.readInfo();
    return _flattenInfoBody(info);
  }

  @override
  Future<bool> testConnection(String deviceIP) async {
    if (!isConnected) return false;
    try {
      final info = await _session!.readInfo();
      return info['v'] == 2 && info['type'] == 'info';
    } catch (e) {
      debugPrint('[BleOTA] testConnection failed: $e');
      return false;
    }
  }

  @override
  Future<bool> isConnectedToDeviceAP() async => isConnected;

  @override
  Future<String> readParameter(String deviceIP, String paramName) {
    throw UnsupportedError(
      'BLE 通道不支持 HTTP 参数读取，请切换到 WiFi AP 通道',
    );
  }

  @override
  Future<bool> writeParameter(
    String deviceIP,
    String paramName,
    String value,
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

  Future<void> dispose() async {
    await _cleanupLease();
    _session = null;
    _connectedMacAddress = null;
  }

  // ---------------------------------------------------------------------------
  // 内部：协议与状态
  // ---------------------------------------------------------------------------

  bool get _otaLeaseIsActive => _otaLease != null && _session != null;

  Future<void> _writeCtrl(Map<String, dynamic> value) async {
    final lease = _otaLease;
    if (lease == null) {
      throw const BleCommandException('OTA_NOT_ACTIVE', 'lease missing');
    }
    await lease.writeControl(value);
  }

  Future<void> _writeData(Map<String, dynamic> value) async {
    final lease = _otaLease;
    if (lease == null) {
      throw const BleCommandException('OTA_NOT_ACTIVE', 'lease missing');
    }
    await lease.writeData(value);
  }

  Future<Map<String, dynamic>> _queryStatus() async {
    final session = _session;
    final lease = _otaLease;
    if (session == null || lease == null) {
      throw const BleCommandException('OTA_NOT_ACTIVE', 'lease missing');
    }
    final sessionId = session.connectionSessionId;
    if (sessionId == null) {
      throw const BleCommandException('UNAUTHENTICATED', 'missing session');
    }
    await lease.writeControl({
      'v': 2,
      'type': 'ota.query',
      'message_id': _messageId(),
      'session_id': sessionId,
      'body': const {'query': 'status'},
    });
    try {
      return await _waitForAnyStatus(
        (s) => s.containsKey('stage') || s.containsKey('body'),
        timeout: _progressTimeout,
      );
    } on TimeoutException {
      return await lease.readStatus();
    }
  }

  void _onOtaStatus(Map<String, dynamic> status) {
    _statusLog.add(status);
    if (_statusLog.length > 64) {
      _statusLog.removeAt(0);
    }
    for (final waiter in List<_OtaStatusWaiter>.from(_statusWaiters)) {
      if (!waiter.completer.isCompleted && waiter.predicate(status)) {
        waiter.completer.complete(status);
        _statusWaiters.remove(waiter);
      }
    }
  }

  Future<Map<String, dynamic>> _waitForStatus(
    bool Function(Map<String, dynamic> status) predicate, {
    Duration timeout = _commandTimeout,
  }) async {
    for (final cached in List<Map<String, dynamic>>.from(_statusLog)) {
      if (predicate(cached)) return cached;
    }
    final waiter = _OtaStatusWaiter(
      predicate: predicate,
      completer: Completer<Map<String, dynamic>>(),
    );
    _statusWaiters.add(waiter);
    try {
      return await waiter.completer.future.timeout(timeout);
    } on TimeoutException {
      rethrow;
    } finally {
      _statusWaiters.remove(waiter);
    }
  }

  Future<Map<String, dynamic>> _waitForAnyStatus(
    bool Function(Map<String, dynamic> status) predicate, {
    Duration timeout = _commandTimeout,
  }) {
    return _waitForStatus(predicate, timeout: timeout);
  }

  void _throwIfFailed(Map<String, dynamic> status) {
    final stage = _stageOf(status);
    final code = _resultCodeOf(status);
    final failedStage = stage == 'failed' ||
        stage == 'rolled_back' ||
        stage == 'cancelled';
    final failedCode = code.isNotEmpty && code != 'OK';
    if (!failedStage && !failedCode) return;
    final message = _messageOf(status);
    throw BleCommandException(
      failedCode ? code : 'OTA_FAILED',
      message.isEmpty ? 'BLE OTA failed at $stage' : message,
    );
  }

  String _messageId() => List.generate(12, (_) => _random.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  static String _wireTarget(String localTarget) {
    switch (localTarget.toLowerCase()) {
      case 'esp':
        return 'communication_module';
      case 'arm':
        return 'system_controller';
      default:
        return localTarget;
    }
  }

  static Map<String, dynamic> _normalizeStatusEnvelope(
    Map<String, dynamic> raw,
  ) {
    if (raw['body'] is Map) {
      final body = (raw['body'] as Map).cast<String, dynamic>();
      return {
        ...body,
        'session_id': raw['session_id'],
        'transfer_id': body['transfer_id'],
      };
    }
    return raw;
  }

  static String _stageOf(Map<String, dynamic> status) {
    final body = _normalizeStatusEnvelope(status);
    final stage =
        (body['stage'] as String? ?? body['state'] as String? ?? '').toLowerCase();
    return stage;
  }

  static String _resultCodeOf(Map<String, dynamic> status) {
    final body = _normalizeStatusEnvelope(status);
    return (body['result_code'] as String? ??
            body['error_code'] as String? ??
            body['code'] as String? ??
            '')
        .trim();
  }

  static String _messageOf(Map<String, dynamic> status) {
    final body = _normalizeStatusEnvelope(status);
    return (body['message'] as String? ?? '').trim();
  }

  static Map<String, dynamic> _mapProgress(Map<String, dynamic> raw) {
    final body = _normalizeStatusEnvelope(raw);
    final stage = _stageOf(raw);
    final percent = (body['progress'] as num?)?.toDouble() ?? 0.0;
    final version = (body['version'] as String? ?? '');
    final mapped = switch (stage) {
      'accepted' || 'receiving' => 'uploading',
      'verifying' => 'verifying',
      'installing' => 'installing',
      'rebooting' => 'rebooting',
      'succeeded' => 'done',
      'failed' || 'rolled_back' || 'cancelled' => 'failed',
      'cancelling' => 'cancelling',
      _ => stage.isEmpty ? 'unknown' : stage,
    };
    return {
      'status': mapped,
      'state': mapped,
      'progress': percent,
      'message': _messageOf(raw),
      'version': version,
      'transfer_id': body['transfer_id'],
      'accepted_offset': body['accepted_offset'],
      'result_code': _resultCodeOf(raw),
    };
  }

  static Map<String, dynamic> _flattenInfoBody(Map<String, dynamic> envelope) {
    final body = envelope['body'] is Map
        ? (envelope['body'] as Map).cast<String, dynamic>()
        : envelope;
    final firmware = (body['firmware_version'] as String? ??
            body['version'] as String? ??
            '')
        .trim();
    return {
      ...body,
      'sn': body['device_sn'] ?? body['sn'],
      'model': body['model'],
      'version': firmware,
      'firmware': firmware,
      if (firmware.isNotEmpty) 'firmware_esp': firmware,
      if (firmware.isNotEmpty) 'esp_version': firmware,
      if (firmware.isNotEmpty) 'firmware_arm': firmware,
      if (firmware.isNotEmpty) 'arm_version': firmware,
    };
  }

  void _assertConnected() {
    final session = _session;
    if (session == null || session.state != BleDeviceState.ready) {
      throw StateError(
        'BLE OTA session not ready. Call connectToDevice() first.',
      );
    }
  }

  Future<void> _cleanupLease() async {
    await _statusSub?.cancel();
    _statusSub = null;
    for (final waiter in List<_OtaStatusWaiter>.from(_statusWaiters)) {
      if (!waiter.completer.isCompleted) {
        waiter.completer.completeError(
          const BleCommandException('OTA_NOT_ACTIVE', 'OTA lease released'),
        );
      }
    }
    _statusWaiters.clear();
    _otaLease?.release();
    _otaLease = null;
    _statusLog.clear();
  }
}

class _OtaStatusWaiter {
  _OtaStatusWaiter({
    required this.predicate,
    required this.completer,
  });

  final bool Function(Map<String, dynamic> status) predicate;
  final Completer<Map<String, dynamic>> completer;
}
