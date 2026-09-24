import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:inv_app/core/errors/ota_error_types.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/ble/ble_write_errors.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/features/ota/domain/repositories/local_communication_repository.dart';

/// BLE 通道连接失败原因（[BleCommunicationService.connectToDevice] 返回 false 时有效）。
///
/// 设备一旦被连接就会停止广播（固件仅在断开事件里重启广播），
/// 因此"连不上"必须区分是"没扫到"还是"已连上但未鉴权"，
/// 否则会把未绑定/鉴权失败误报成"扫描不到设备"。
enum BleConnectFailure {
  /// 蓝牙未开启或不可用
  adapterOff,

  /// 扫描不到目标设备（设备不在广播范围内）
  notFound,

  /// 已连接但本机没有该设备的 device_key（未在本机绑定）
  notBound,

  /// 已连接但鉴权失败（本机 device_key 与设备不匹配）
  authFailed,

  /// 设备固件未实现 CSIV-CT v2 安全控制/OTA，无法蓝牙本地升级
  unsupportedFirmware,

  /// 会话已被 OTA 独占，需等上一次任务收尾
  otaBusy,

  /// 其他异常
  unknown,
}

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

  static const int _binaryHeaderSize = 10;
  static const int _binaryPayloadMax = 496;
  static const int _binaryBatchSize = 1024;

  static const Duration _scanTimeout = Duration(seconds: 15);
  static const Duration _commandTimeout = Duration(seconds: 10);
  static const Duration _progressTimeout = Duration(seconds: 5);

  BleDeviceSession? _session;
  BleOtaLease? _otaLease;
  StreamSubscription<Map<String, dynamic>>? _statusSub;
  String? _connectedMacAddress;
  String? _targetMacAddress;
  BleConnectFailure? _lastConnectFailure;

  final Random _random = Random.secure();
  final List<Map<String, dynamic>> _statusLog = [];
  final List<_OtaStatusWaiter> _statusWaiters = [];
  int _statusSequence = 0;

  String? get connectedMacAddress => _connectedMacAddress;

  /// 本次连接目标设备 MAC：连接未成功但已知设备地址时也会填充，
  /// 供页面在"未绑定/鉴权失败"时对同一台设备执行绑定补救
  String? get targetMacAddress => _targetMacAddress;

  /// 最近一次 connectToDevice 失败原因（成功后为 null）
  BleConnectFailure? get lastConnectFailure => _lastConnectFailure;

  bool get isConnected =>
      _session != null && _session!.state == BleDeviceState.ready;

  @override
  Future<bool> connectToDevice({
    required String deviceSN,
    required String deviceIP,
    String? password,
    String? macAddress,
  }) async {
    debugPrint('[BleOTA] connectToDevice: SN=$deviceSN mac=$macAddress');
    _lastConnectFailure = null;
    _targetMacAddress = null;
    try {
      final status = await _adapter.status;
      if (status != BleAdapterStatus.on) {
        debugPrint('[BleOTA] BLE adapter not on: $status');
        _lastConnectFailure = BleConnectFailure.adapterOff;
        return false;
      }

      final session = await _acquireSession(deviceSN, macAddress);
      if (session == null) return false;
      if (session.isOtaInProgress) {
        debugPrint('[BleOTA] session already has OTA lease');
        _lastConnectFailure = BleConnectFailure.otaBusy;
        return false;
      }

      _session = session;
      _connectedMacAddress = session.macAddress;
      return true;
    } catch (e) {
      debugPrint('[BleOTA] connectToDevice failed: $e');
      _lastConnectFailure ??= BleConnectFailure.unknown;
      await _cleanupLease();
      return false;
    }
  }

  /// 获取可用于 OTA 的会话。
  ///
  /// 顺序：复用本机已就绪会话（MAC 优先、SN 兜底）→ 无活跃会话时按已知
  /// MAC 直连 → 最后才按 SN 扫描兜底。
  ///
  /// 关键约束：设备连上后停止广播，只要有活跃会话就绝不能改走扫描，
  /// 否则用户会看到"第二次连接扫描不到设备"。
  /// 2026-09-22 起会话连接即就绪（无绑定/鉴权前置），不再做鉴权重试归因。
  Future<BleDeviceSession?> _acquireSession(
    String deviceSN,
    String? macAddress,
  ) async {
    final live = _findLiveSession(deviceSN, macAddress);
    if (live != null && live.state == BleDeviceState.ready) {
      _targetMacAddress = live.macAddress;
      return live;
    }

    final mac = (macAddress ?? '').trim();
    if (mac.isNotEmpty) {
      return _connectByMac(mac, deviceSN);
    }

    final scanResult = await _scanForDevice(deviceSN);
    if (scanResult == null) {
      _lastConnectFailure = BleConnectFailure.notFound;
      return null;
    }
    return _connectByMac(scanResult.macAddress, deviceSN);
  }

  /// 直连已知 MAC（不扫描）。
  ///
  /// 直连失败按原因归因：连接层失败（设备不在范围/链路未建立）归
  /// "找不到设备"。
  Future<BleDeviceSession?> _connectByMac(
    String macAddress,
    String deviceSN,
  ) async {
    final BleDeviceSession session;
    try {
      session = await _manager.connectDevice(
        macAddress,
        autoReconnect: false,
      );
    } catch (e) {
      debugPrint('[BleOTA] direct connect $macAddress failed: $e');
      _targetMacAddress = macAddress;
      _lastConnectFailure = BleConnectFailure.notFound;
      return null;
    }
    _targetMacAddress = session.macAddress;
    return session;
  }

  /// 匹配本机活跃会话：MAC 精确匹配优先，其次 SN 匹配。
  BleDeviceSession? _findLiveSession(String deviceSN, String? macAddress) {
    final targetSn = deviceSN.trim().toUpperCase();
    final targetMac = (macAddress ?? '').trim().toUpperCase();
    BleDeviceSession? bySn;
    for (final session in _manager.sessions.values) {
      if (session.state == BleDeviceState.disconnected) continue;
      if (targetMac.isNotEmpty &&
          session.macAddress.toUpperCase() == targetMac) {
        return session;
      }
      if (targetSn.isNotEmpty &&
          (session.sn ?? '').trim().toUpperCase() == targetSn) {
        bySn = session;
      }
    }
    return bySn;
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
    // 设备端只在收到非空 SHA-256 时校验整个固件。旧版清单可能没有摘要，
    // 本地 BLE 传输仍应让设备验证最终写入内容。
    final firmwareSha = manifest.sha256.isEmpty
        ? sha256.convert(bytes).toString()
        : manifest.sha256;

    debugPrint(
      '[BleOTA] uploadFirmware size=${bytes.length} '
      'target=${manifest.target} task=${manifest.taskId}',
    );

    final lease = await _ensureOtaLease();

    final infoBody = _flattenInfoBody(await session.readInfo());
    final capabilities = (infoBody['capabilities'] as List?) ?? const [];
    if (!capabilities.contains('ota_binary_v1')) {
      throw const BleCommandException(
        'OTA_BINARY_UNSUPPORTED',
        '设备尚未支持二进制 BLE OTA，请先用云端、Wi-Fi 或旧版 App 升级 ESP',
      );
    }
    final mtu = session.negotiatedMtu;
    if (mtu < 256) {
      throw BleCommandException(
        'BLE_MTU_TOO_SMALL',
        '蓝牙 MTU=$mtu，至少需要 256；请改用 Wi-Fi 或更换手机重试',
      );
    }
    final maxPayload =
        min(_binaryPayloadMax, min(509, mtu - 3) - _binaryHeaderSize);
    final transferId = _messageId();
    final transferToken = int.parse(transferId.substring(0, 8), radix: 16);
    debugPrint('[BleOTA] binary OTA mtu=$mtu payload=$maxPayload');

    final ctrlAccepted = (Map<String, dynamic> s) {
      final body = _normalizeStatusEnvelope(s);
      return body['transfer_id'] == transferId &&
          (_isFailed(s) ||
              const {'accepted', 'receiving', 'verifying', 'installing'}
                  .contains(_stageOf(s)));
    };
    await _writeOtaMessage(
      control: true,
      what: 'ota.ctrl',
      message: {
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
          'sha256': firmwareSha,
          'signature': manifest.signature,
          'security_version': manifest.securityVersion,
          'timeout_seconds': max(manifest.timeoutSeconds, 1200),
        },
      },
      alreadyLanded: () => _statusLog.any(ctrlAccepted),
    );

    final accepted =
        await _waitForStatus(ctrlAccepted, timeout: _commandTimeout);
    _throwIfFailed(accepted);

    var offset = 0;
    while (offset < bytes.length) {
      if (!_otaLeaseIsActive) {
        throw const BleCommandException('OTA_NOT_ACTIVE', 'lease released');
      }
      final batchEnd = min(
        ((offset ~/ _binaryBatchSize) + 1) * _binaryBatchSize,
        bytes.length,
      );
      while (offset < batchEnd) {
        final payloadLength = min(maxPayload, batchEnd - offset);
        final frame = Uint8List(_binaryHeaderSize + payloadLength);
        final header = ByteData.view(frame.buffer);
        frame[0] = 0xb1;
        frame[1] = 1;
        header.setUint32(2, transferToken, Endian.little);
        header.setUint32(6, offset, Endian.little);
        frame.setRange(_binaryHeaderSize, frame.length,
            bytes.getRange(offset, offset + payloadLength));
        await _writeBinaryFrameWithRecovery(
          lease: lease,
          frame: frame,
          transferId: transferId,
          offset: offset,
          payloadLength: payloadLength,
        );
        offset += payloadLength;
      }

      final chunkAcked = (Map<String, dynamic> s) {
        final body = _normalizeStatusEnvelope(s);
        final acceptedOffset = (body['accepted_offset'] as num?)?.toInt();
        return body['transfer_id'] == transferId &&
            (_isFailed(s) ||
                (acceptedOffset != null && acceptedOffset >= batchEnd));
      };
      // 低 MTU 下 JSON 状态通知可能超过 ATT MTU-3，被设备栈丢弃。
      // 最后一帧的 write-with-response 返回后，直接读取状态，避免每 1 KB
      // 空等一次通知超时。
      Map<String, dynamic> ack;
      if (mtu < 512) {
        ack = await _readActiveOtaStatus(lease, transferId);
      } else {
        try {
          ack = await _waitForStatus(chunkAcked, timeout: _commandTimeout);
        } on TimeoutException {
          ack = await _readActiveOtaStatus(lease, transferId);
        }
      }
      _throwIfFailed(ack);
      final acceptedOffset =
          (_normalizeStatusEnvelope(ack)['accepted_offset'] as num?)?.toInt();
      if (acceptedOffset == null ||
          acceptedOffset < 0 ||
          acceptedOffset > bytes.length) {
        throw const BleCommandException(
          'OTA_STATUS_INVALID',
          '设备返回无效的已接收偏移量',
        );
      }
      if (acceptedOffset < batchEnd) {
        offset = acceptedOffset;
        continue;
      }
      offset = acceptedOffset;
      onProgress?.call(offset, bytes.length);
    }

    // 写入成功不等于设备已持久接收；等待校验/烧写进入下一阶段。
    final afterPredicate = (Map<String, dynamic> s) {
      final body = _normalizeStatusEnvelope(s);
      return body['transfer_id'] == transferId &&
          (_isFailed(s) ||
              const {'verifying', 'installing', 'rebooting', 'succeeded'}
                  .contains(_stageOf(s)));
    };
    late Map<String, dynamic> after;
    if (mtu < 512) {
      // 状态通知在低 MTU 下可能完全发不出；读状态直到 worker 离开 receiving。
      final deadline = Stopwatch()..start();
      while (true) {
        final status = await _readActiveOtaStatus(lease, transferId);
        if (afterPredicate(status)) {
          after = status;
          break;
        }
        if (deadline.elapsed >= _commandTimeout) {
          throw TimeoutException('BLE OTA verification status timed out');
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } else {
      after = await _waitForStatus(afterPredicate, timeout: _commandTimeout);
    }
    _throwIfFailed(after);
    debugPrint('[BleOTA] firmware bytes accepted: $offset/${bytes.length}');
  }

  @override
  Future<void> triggerUpgrade(String deviceIP) async {
    // BLE 固件收到完整 ota.ctrl/data 后会自动校验、刷写并重启，不存在额外的
    // “触发升级”命令。uploadFirmware 已确认设备至少进入 verifying/installing；
    // 此时再查询会与 ESP 重启断链竞争，并把正常重启误报为 OTA_NOT_ACTIVE。
    debugPrint('[BleOTA] triggerUpgrade: already started by ota.ctrl/data');
  }

  @override
  Future<Map<String, dynamic>> getProgress(String deviceIP) async {
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
    _targetMacAddress = null;
    _lastConnectFailure = null;
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

  /// 写一条 OTA 报文，对本地蓝牙协议栈的瞬时拒绝做有限次重试。
  ///
  /// 长写（prepare/execute）在 Android 上是多步序列，回调偶发带回
  /// GATT_BUSY(132)/GATT_ERROR(133)/GATT_CMD_STARTED(134)；但回调报错不代表
  /// 设备没收到。固件 handle_data 要求 offset 严格等于已收长度，盲目重发会被
  /// 设备当成坏帧拒掉，所以每次重试前先查状态流：上一发其实已经落地
  /// （accepted 阶段 / accepted_offset 达标）就直接当成功。
  Future<void> _writeOtaMessage({
    required bool control,
    required String what,
    required Map<String, dynamic> message,
    required bool Function() alreadyLanded,
  }) async {
    const maxAttempts = 4;
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1 && alreadyLanded()) return;
      try {
        if (control) {
          await _writeCtrl(message);
        } else {
          await _writeData(message);
        }
        return;
      } catch (e) {
        final attCode = deviceAttErrorCodeOf(e);
        if (attCode != null) {
          // 设备侧主动拒绝：重试无意义，直接给出可操作的原因。
          throw BleCommandException(
            'DEVICE_REFUSED',
            '$what 被设备拒绝：${deviceAttRefusalReason(attCode)}；'
                '请重启设备后重试。原始错误：$e',
          );
        }
        if (!isTransientBleWriteError(e)) rethrow;
        lastError = e;
        if (alreadyLanded()) return;
        if (attempt == maxAttempts) break;
        await Future<void>.delayed(Duration(milliseconds: 150 * attempt));
      }
    }
    throw BleCommandException(
      'BLE_WRITE_BUSY',
      '$what 连续 $maxAttempts 次被本地蓝牙协议栈拒绝'
          '（GATT_BUSY/GATT_ERROR/GATT_CMD_STARTED），最后一次：$lastError',
    );
  }

  Future<Map<String, dynamic>> _readActiveOtaStatus(
    BleOtaLease lease,
    String transferId,
  ) async {
    final status = await lease.readStatus(timeout: 5);
    final body = _normalizeStatusEnvelope(status);
    if (body['transfer_id'] != transferId) {
      throw const BleCommandException(
        'OTA_STATUS_MISMATCH',
        '设备返回的升级会话与当前传输不一致',
      );
    }
    return status;
  }

  Future<void> _writeBinaryFrameWithRecovery({
    required BleOtaLease lease,
    required List<int> frame,
    required String transferId,
    required int offset,
    required int payloadLength,
  }) async {
    final elapsed = Stopwatch()..start();
    while (true) {
      try {
        await lease.writeDataBytes(frame);
        return;
      } catch (error) {
        final attCode = deviceAttErrorCodeOf(error);
        if (attCode != null && attCode != 9) {
          throw BleCommandException(
            'DEVICE_REFUSED',
            'ota.data@$offset 被设备拒绝：${deviceAttRefusalReason(attCode)}；'
                '原始错误：$error',
          );
        }
        if (attCode != 9 && !isTransientBleWriteError(error)) rethrow;
        if (elapsed.elapsed >= const Duration(seconds: 20)) {
          throw BleCommandException(
            'BLE_WRITE_BUSY',
            'ota.data@$offset 在 20 秒内未获确认：$error',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final status = await _readActiveOtaStatus(lease, transferId);
        _throwIfFailed(status);
        final accepted =
            (_normalizeStatusEnvelope(status)['accepted_offset'] as num?)
                ?.toInt();
        if (accepted == offset + payloadLength) return;
        if (accepted != offset) {
          throw BleCommandException(
            'OTA_OFFSET_MISMATCH',
            '设备已接收偏移量 $accepted，当前帧为 $offset+$payloadLength',
          );
        }
      }
    }
  }

  Future<Map<String, dynamic>> _queryStatus() async {
    final session = _session;
    if (session == null) {
      throw const BleCommandException('UNAUTHENTICATED', 'session missing');
    }
    final lease = await _ensureOtaLease();
    final sessionId = session.connectionSessionId;
    if (sessionId == null) {
      throw const BleCommandException('UNAUTHENTICATED', 'missing session');
    }
    final statusStart = _statusSequence;
    await lease.writeControl({
      'v': 2,
      'type': 'ota.query',
      'message_id': _messageId(),
      'session_id': sessionId,
      'body': const {'query': 'status'},
    });
    try {
      return await _waitForStatus(
        (s) =>
            s['session_id'] == sessionId &&
            (s['type'] == 'ota.status' || s.containsKey('stage')),
        timeout: _progressTimeout,
        startIndex: statusStart,
      );
    } on TimeoutException {
      return await lease.readStatus();
    }
  }

  void _onOtaStatus(Map<String, dynamic> status) {
    _statusSequence++;
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
    int startIndex = 0,
  }) async {
    final firstSequence = _statusSequence - _statusLog.length + 1;
    for (var i = 0; i < _statusLog.length; i++) {
      if (firstSequence + i <= startIndex) continue;
      final cached = _statusLog[i];
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

  static bool _isFailed(Map<String, dynamic> status) {
    final stage = _stageOf(status);
    final code = _resultCodeOf(status);
    return const {'failed', 'rolled_back', 'cancelled'}.contains(stage) ||
        (code.isNotEmpty && code != 'OK');
  }

  void _throwIfFailed(Map<String, dynamic> status) {
    final stage = _stageOf(status);
    final code = _resultCodeOf(status);
    final failedStage =
        stage == 'failed' || stage == 'rolled_back' || stage == 'cancelled';
    final failedCode = code.isNotEmpty && code != 'OK';
    if (!failedStage && !failedCode) return;
    final message = _messageOf(status);
    if (code == 'INSUFFICIENT_STORAGE') {
      throw OtaInsufficientStorageException(message);
    }
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
      case 'dsp':
        return 'dsp_controller';
      case 'bms':
        return 'bms';
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
    final stage = (body['stage'] as String? ?? body['state'] as String? ?? '')
        .toLowerCase();
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

  /// 获取当前有效 OTA 租约；设备重启并重连后，旧租约已失效，此处为进度查询
  /// 重新订阅状态特征。上传期间会复用现有租约，不会抢占同一会话。
  Future<BleOtaLease> _ensureOtaLease() async {
    var session = _session;
    if (session == null) {
      throw const BleCommandException('UNAUTHENTICATED', 'session missing');
    }
    if (session.state == BleDeviceState.disconnected) {
      session = await _manager.connectDevice(
        session.macAddress,
        autoReconnect: false,
      );
      _session = session;
      _connectedMacAddress = session.macAddress;
    }
    if (session.state != BleDeviceState.ready) {
      throw const BleCommandException('UNAUTHENTICATED', 'session not ready');
    }
    final current = _otaLease;
    if (current != null && current.isActive) return current;

    final staleSub = _statusSub;
    final staleLease = _otaLease;
    _statusSub = null;
    _otaLease = null;
    await staleSub?.cancel();
    staleLease?.release();

    final lease = await session.acquireOtaLease();
    _otaLease = lease;
    _statusLog.clear();
    _statusSub = lease.statuses.listen(
      _onOtaStatus,
      onError: (Object e) => debugPrint('[BleOTA] status error: $e'),
    );
    return lease;
  }

  Future<void> _cleanupLease() async {
    final subscription = _statusSub;
    final lease = _otaLease;
    final waiters = List<_OtaStatusWaiter>.from(_statusWaiters);
    _statusSub = null;
    _otaLease = null;
    _statusWaiters.clear();
    _statusLog.clear();
    await subscription?.cancel();
    for (final waiter in waiters) {
      if (!waiter.completer.isCompleted) {
        waiter.completer.completeError(
          const BleCommandException('OTA_NOT_ACTIVE', 'OTA lease released'),
        );
      }
    }
    lease?.release();
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
