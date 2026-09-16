import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:inv_app/core/services/ble/ble_adapter.dart';

/// CSIV-CT 本地控制服务协议常量
/// 对应文档：《docs/BLE_Local_Communication_Protocol.md》
class BleCtProtocol {
  BleCtProtocol._();

  static const String serviceUuid = '43534956-4354-1000-8000-00805f9b34fb';
  static const String authCharUuid = '43534956-4155-1000-8000-00805f9b34fb';
  static const String telemetryCharUuid =
      '43534956-544c-1000-8000-00805f9b34fb';
  static const String commandCharUuid = '43534956-434d-1000-8000-00805f9b34fb';
  static const String cmdResultCharUuid =
      '43534956-4352-1000-8000-00805f9b34fb';
  static const String infoCharUuid = '43534956-494e-1000-8000-00805f9b34fb';

  /// 配网服务（CSIV-PR），自动连接扫描过滤用
  static const String provisioningServiceUuid =
      '43534956-5052-1000-8000-00805f9b34fb';
  static const String provisioningSnCharUuid =
      '43534956-534e-1000-8000-00805f9b34fb';
  static const String otaControlCharUuid =
      '43534f54-4354-1000-8000-00805f9b34fb';
  static const String otaDataCharUuid =
      '43534f54-4441-1000-8000-00805f9b34fb';
  static const String otaStatusCharUuid =
      '43534f54-5354-1000-8000-00805f9b34fb';

  /// 广播扫描过滤 UUID 列表。
  ///
  /// 现有固件 ADV 仅携带 CSIV-PR；协议规范建议同时携带 CSIV-CT。
  /// 只按 CSIV-CT 过滤会导致数据链路/本地 OTA 扫不到设备。
  /// 扫描时两个都传，兼容当前与后续固件。
  static const List<String> scanServiceUuids = [
    provisioningServiceUuid,
    serviceUuid,
  ];

  static const int preferredMtu = 512;
  static const Duration commandTimeout = Duration(seconds: 5);
  static const int commandMaxRetries = 2;
  static const Duration authTimeout = Duration(seconds: 8);

  /// 断线重连退避序列（1s/2s/5s/10s 封顶）
  static const List<Duration> reconnectBackoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  static List<int> computeAuthProof({
    required List<int> key,
    required BleAuthProofRole role,
    required String sessionId,
    required List<int> phoneNonce,
    required List<int> deviceNonce,
    required int deviceTimestamp,
  }) {
    final prefix = role == BleAuthProofRole.phone
        ? 'CSIV-CT/v2/app|'
        : 'CSIV-CT/v2/device|';
    final message = <int>[
      ...utf8.encode(prefix),
      ...utf8.encode(sessionId),
      0x7c,
      ...phoneNonce,
      0x7c,
      ...deviceNonce,
      0x7c,
      ...utf8.encode('$deviceTimestamp'),
    ];
    return Hmac(sha256, key).convert(message).bytes;
  }
}

enum BleAuthProofRole { phone, device }

/// 每设备连接状态机
enum BleDeviceState { disconnected, connecting, authenticating, ready }

/// 命令执行异常（含协议错误码：UNAUTHENTICATED/FORBIDDEN/OUT_OF_RANGE 等）
class BleCommandException implements Exception {
  final String code;
  final String message;

  const BleCommandException(this.code, this.message);

  @override
  String toString() => 'BleCommandException($code): $message';
}

/// device_key 存储抽象（便于单元测试替换为内存实现）
abstract class BleDeviceKeyStore {
  Future<String?> read(String sn);
  Future<void> write(String sn, String keyBase64);
  Future<void> delete(String sn);

  /// 清空全部设备绑定密钥（登出时调用，隐私：不残留上一账号的绑定关系）
  Future<void> clearAll();
}

/// 基于 flutter_secure_storage 的 device_key 存储
class SecureStorageBleDeviceKeyStore implements BleDeviceKeyStore {
  final FlutterSecureStorage _storage;

  SecureStorageBleDeviceKeyStore(this._storage);

  static const String _keyPrefix = 'ble_device_key_';

  static String _keyOf(String sn) => '$_keyPrefix$sn';

  @override
  Future<String?> read(String sn) => _storage.read(key: _keyOf(sn));

  @override
  Future<void> write(String sn, String keyBase64) =>
      _storage.write(key: _keyOf(sn), value: keyBase64);

  @override
  Future<void> delete(String sn) => _storage.delete(key: _keyOf(sn));

  @override
  Future<void> clearAll() async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(_keyPrefix)) {
        await _storage.delete(key: key);
      }
    }
  }
}

/// TELEMETRY 分帧重组器（协议 §6.3：统一 1 字节控制头）
class BleFrameReassembler {
  static const int maxFrames = 8;

  final List<int> _buffer = [];
  int? _nextIndex;

  /// 喂入一帧；消息完整时返回完整字节，否则返回 null
  List<int>? feed(List<int> chunk) {
    if (chunk.length < 2) return null;
    final header = chunk[0];
    final isFirst = (header & 0x80) != 0;
    final isLast = (header & 0x40) != 0;
    final index = header & 0x3F;

    if (isFirst) {
      _buffer
        ..clear()
        ..addAll(chunk.sublist(1));
      _nextIndex = 1;
    } else {
      // 未收到首帧而收到后续帧，或序号不连续：丢弃等待下一首帧
      if (_nextIndex == null || index != _nextIndex) {
        _buffer.clear();
        _nextIndex = null;
        return null;
      }
      _buffer.addAll(chunk.sublist(1));
      _nextIndex = index + 1;
    }

    if (_buffer.length > maxFrames * 509 || (_nextIndex ?? 0) > maxFrames) {
      _buffer.clear();
      _nextIndex = null;
      return null;
    }

    if (isLast) {
      final complete = List<int>.unmodifiable(_buffer);
      _buffer.clear();
      _nextIndex = null;
      return complete;
    }
    return null;
  }
}

/// 单设备会话：状态机 + 命令队列 + 鉴权 + 遥测 + 退避重连
class _PendingBleCommand {
  final Completer<Map<String, dynamic>> completer;
  final String messageId;
  final String sessionId;

  const _PendingBleCommand({
    required this.completer,
    required this.messageId,
    required this.sessionId,
  });
}

class BleDeviceSession {
  final BleAdapter _adapter;
  final String macAddress;
  final BleDeviceKeyStore _keyStore;

  /// 设备 SN（连接后读取，自动连接鉴权与遥测归属用）
  String? sn;

  BleGattConnection? _connection;
  StreamSubscription<BleLinkState>? _linkSub;
  StreamSubscription<List<int>>? _telemetrySub;
  StreamSubscription<List<int>>? _cmdResultSub;
  StreamSubscription<List<int>>? _authSub;

  final _stateController = StreamController<BleDeviceState>.broadcast();
  BleDeviceState _state = BleDeviceState.disconnected;

  final _telemetryController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _reassembler = BleFrameReassembler();

  /// 命令队列（Future 链串行化，防 GATT 并发冲突）
  Future<void> _commandChain = Future.value();
  final _pendingCommands = <String, _PendingBleCommand>{};
  var _commandSequence = 0;
  Completer<Map<String, dynamic>>? _authCompleter;
  String? _expectedAuthType;
  String? _expectedAuthReplyTo;
  final _random = Random.secure();
  final Duration authTimeout;
  int protocolVersion = 0;
  Set<String> capabilities = const {};
  String? connectionSessionId;
  bool _otaInProgress = false;

  /// 断线自动重连
  bool _autoReconnect = false;
  bool _disposed = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;

  BleDeviceSession({
    required BleAdapter adapter,
    required this.macAddress,
    required BleDeviceKeyStore keyStore,
    Duration? authTimeout,
  })  : _adapter = adapter,
        _keyStore = keyStore,
        authTimeout = authTimeout ?? BleCtProtocol.authTimeout;

  bool get supportsSecureDirectControl =>
      protocolVersion == 2 &&
      connectionSessionId != null &&
      capabilities.contains('control');

  bool get isOtaInProgress => _otaInProgress;

  BleDeviceState get state => _state;

  Stream<BleDeviceState> get stateStream => _stateController.stream;

  /// 遥测 JSON 流（已完成分帧重组与 JSON 解码）
  Stream<Map<String, dynamic>> get telemetry => _telemetryController.stream;

  void _setState(BleDeviceState next) {
    if (_state == next) return;
    _state = next;
    _stateController.add(next);
  }

  /// 连接并进入鉴权就绪流程
  /// [autoConnect]：Android 挂起直连（设备进入范围时系统回连）
  /// [autoReconnect]：意外断开后按指数退避自动重连
  Future<void> connect({
    bool autoConnect = false,
    bool autoReconnect = true,
  }) async {
    if (_state != BleDeviceState.disconnected) return;
    _autoReconnect = autoReconnect;
    _setState(BleDeviceState.connecting);

    try {
      final connection = await _adapter.connect(
        macAddress,
        autoConnect: autoConnect,
      );
      _connection = connection;
      _watchLink(connection);
      // autoConnect 模式 connect 时未协商 MTU，补协商
      if (autoConnect) {
        try {
          await connection.requestMtu(BleCtProtocol.preferredMtu);
        } catch (_) {
          // 部分设备/栈不支持时以默认 MTU 继续
        }
      }
      await _afterConnected();
    } catch (e) {
      _setState(BleDeviceState.disconnected);
      rethrow;
    }
  }

  void _watchLink(BleGattConnection connection) {
    _linkSub?.cancel();
    _linkSub = connection.linkState.listen((link) {
      if (link == BleLinkState.disconnected && !_disposed) {
        _handleUnexpectedDisconnect();
      }
    });
  }

  /// 连接成功后：读 SN → 订阅通知 → 若已有 device_key 则直接鉴权
  Future<void> _afterConnected() async {
    sn ??= await _readSn();
    await _loadProtocolInfo();

    _cmdResultSub = _connection!
        .subscribe(BleCtProtocol.serviceUuid, BleCtProtocol.cmdResultCharUuid)
        .listen(_onCmdResult, onError: (_) {});
    _authSub = _connection!
        .subscribe(BleCtProtocol.serviceUuid, BleCtProtocol.authCharUuid)
        .listen(_onAuthNotify, onError: (_) {});
    _telemetrySub = _connection!
        .subscribe(BleCtProtocol.serviceUuid, BleCtProtocol.telemetryCharUuid)
        .listen(_onTelemetry, onError: (_) {});

    final deviceKey = await _keyStore.read(sn!);
    if (deviceKey != null) {
      await authenticate(deviceKey);
      _reconnectAttempt = 0;
    } else {
      // 未绑定设备：保持连接等待上层走绑定流程（配网页/绑定页）
      _setState(BleDeviceState.authenticating);
    }
  }

  Future<void> _loadProtocolInfo() async {
    try {
      final info = await readInfo();
      if (info['v'] == 2 && info['type'] == 'info' && info['body'] is Map) {
        final body = (info['body'] as Map).cast<String, dynamic>();
        protocolVersion = (body['proto_version'] as num?)?.toInt() ?? 0;
        connectionSessionId = info['session_id'] as String?;
        capabilities = ((body['capabilities'] as List?) ?? const [])
            .whereType<String>()
            .toSet();
        final infoSn = body['device_sn'] as String?;
        if (infoSn != null && infoSn.isNotEmpty) sn = infoSn;
        return;
      }
      protocolVersion = 1;
      capabilities = const {};
      connectionSessionId = null;
    } catch (_) {
      protocolVersion = 1;
      capabilities = const {};
      connectionSessionId = null;
    }
  }

  Future<String> _readSn() async {
    try {
      final bytes = await _connection!.read(
        BleCtProtocol.provisioningServiceUuid,
        BleCtProtocol.provisioningSnCharUuid,
      );
      return utf8.decode(bytes).trim();
    } catch (_) {
      // 固件未实现 CSIV-PR 时退回 INFO 特征
      final bytes = await _connection!.read(
        BleCtProtocol.serviceUuid,
        BleCtProtocol.infoCharUuid,
      );
      final info = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return (info['sn'] as String?) ?? '';
    }
  }

  /// 读取 INFO 特征（协议 §8：{sn,model,firmware,mac,bound,proto_ver}）
  Future<Map<String, dynamic>> readInfo() async {
    final connection = _connection;
    if (connection == null) {
      throw const BleCommandException('UNAUTHENTICATED', 'not connected');
    }
    final bytes = await connection.read(
      BleCtProtocol.serviceUuid,
      BleCtProtocol.infoCharUuid,
    );
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  /// 读取最新遥测快照（协议修订①：TELEMETRY 支持 Read，App 轮询用）
  Future<Map<String, dynamic>> readTelemetrySnapshot() async {
    if (_otaInProgress) {
      throw const BleCommandException('OTA_IN_PROGRESS', 'OTA owns BLE link');
    }
    final connection = _connection;
    if (connection == null) {
      throw const BleCommandException('UNAUTHENTICATED', 'not connected');
    }
    final bytes = await connection.read(
      BleCtProtocol.serviceUuid,
      BleCtProtocol.telemetryCharUuid,
    );
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  /// 校验设备 PIN（附录 B：配网写凭据前 pin_check）。
  /// 设备 notify 返回 {mode:'pin_check', result:'ok'|'rejected', error?:'invalid_pin'|'locked'}。
  Future<void> checkPin(String pin) async {
    final connection = _connection;
    if (connection == null) {
      throw const BleCommandException('UNAUTHENTICATED', 'not connected');
    }
    final completer = Completer<Map<String, dynamic>>();
    _authCompleter = completer;
    await connection.write(
      BleCtProtocol.serviceUuid,
      BleCtProtocol.authCharUuid,
      utf8.encode(jsonEncode({'mode': 'pin_check', 'pin': pin})),
    );
    final resp = await completer.future.timeout(BleCtProtocol.authTimeout);
    if (resp['mode'] != 'pin_check' || resp['result'] != 'ok') {
      final err = (resp['error'] as String?) ?? 'pin rejected';
      throw BleCommandException(
          err == 'locked' ? 'PIN_LOCKED' : 'PIN_REJECTED', err);
    }
  }

  /// 绑定（协议 §4.1 + 附录 B）：设备未绑定时写入 bind 消息，设备 notify 返回结果。
  /// [deviceKeyBase64] App 本地生成的 32B Base64 key；[pin] 场景 B 必传（设备端校验），
  /// 场景 A 配网已验证可不传；[issuedAt] 设备时钟校准用（缺省当前时间）。
  Future<void> bind(String deviceKeyBase64,
      {String? pin, DateTime? issuedAt}) async {
    final connection = _connection;
    if (connection == null) {
      throw const BleCommandException('UNAUTHENTICATED', 'not connected');
    }
    final ts = (issuedAt ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final completer = Completer<Map<String, dynamic>>();
    _authCompleter = completer;
    await connection.write(
      BleCtProtocol.serviceUuid,
      BleCtProtocol.authCharUuid,
      utf8.encode(
        jsonEncode({
          'mode': 'bind',
          'device_key': deviceKeyBase64,
          'issued_at': ts,
          if (pin != null) 'pin': pin,
        }),
      ),
    );
    final resp = await completer.future.timeout(BleCtProtocol.authTimeout);
    if (resp['mode'] != 'bind' || resp['result'] != 'ok') {
      throw BleCommandException(
        'BIND_REJECTED',
        (resp['error'] as String?) ?? 'bind rejected',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 鉴权（协议 §5：HMAC-SHA256(nonce:ts, device_key) challenge-response）
  // ---------------------------------------------------------------------------

  Future<void> authenticate(String deviceKeyBase64) async {
    final connection = _connection;
    if (connection == null) {
      throw const BleCommandException('UNAUTHENTICATED', 'not connected');
    }
    if (!supportsSecureDirectControl) {
      throw const BleCommandException(
        'UNSUPPORTED_SECURE_DIRECT_CONTROL',
        'device does not support CSIV-CT v2 secure control',
      );
    }
    _setState(BleDeviceState.authenticating);
    try {
      final key = base64Decode(deviceKeyBase64);
      if (key.length != 32) {
        throw const BleCommandException(
            'UNAUTHENTICATED', 'invalid device key');
      }
      final phoneNonce = List<int>.generate(16, (_) => _random.nextInt(256));
      final initId = _generateMessageId();
      final challengeFuture = _waitForAuth('auth.challenge', initId);
      await connection.write(
        BleCtProtocol.serviceUuid,
        BleCtProtocol.authCharUuid,
        utf8.encode(
          jsonEncode({
            'v': 2,
            'type': 'auth.init',
            'message_id': initId,
            'session_id': connectionSessionId,
            'body': {'phone_nonce': base64Encode(phoneNonce)},
          }),
        ),
      );
      final challenge = await challengeFuture.timeout(authTimeout);
      final challengeBody = (challenge['body'] as Map).cast<String, dynamic>();
      final deviceNonce = base64Decode(challengeBody['device_nonce'] as String);
      final deviceTimestamp = (challengeBody['device_ts'] as num).toInt();
      if (deviceNonce.length != 16) {
        throw const BleCommandException('UNAUTHENTICATED', 'invalid challenge');
      }
      final phoneProof = BleCtProtocol.computeAuthProof(
        key: key,
        role: BleAuthProofRole.phone,
        sessionId: connectionSessionId!,
        phoneNonce: phoneNonce,
        deviceNonce: deviceNonce,
        deviceTimestamp: deviceTimestamp,
      );
      final proofId = _generateMessageId();
      final resultFuture = _waitForAuth('auth.result', proofId);
      await connection.write(
        BleCtProtocol.serviceUuid,
        BleCtProtocol.authCharUuid,
        utf8.encode(jsonEncode({
          'v': 2,
          'type': 'auth.proof',
          'message_id': proofId,
          'session_id': connectionSessionId,
          'body': {'phone_proof': base64Encode(phoneProof)},
        })),
      );
      final result = await resultFuture.timeout(authTimeout);
      final body = (result['body'] as Map).cast<String, dynamic>();
      final expected = BleCtProtocol.computeAuthProof(
        key: key,
        role: BleAuthProofRole.device,
        sessionId: connectionSessionId!,
        phoneNonce: phoneNonce,
        deviceNonce: deviceNonce,
        deviceTimestamp: deviceTimestamp,
      );
      if (body['result'] != 'ok' ||
          body['device_proof'] is! String ||
          !_constantTimeEquals(
              base64Decode(body['device_proof'] as String), expected)) {
        throw const BleCommandException(
          'UNAUTHENTICATED',
          'digest mismatch',
        );
      }
      _setState(BleDeviceState.ready);
    } on TimeoutException catch (_) {
      if (_state != BleDeviceState.disconnected) {
        _setState(BleDeviceState.connecting);
      }
      throw const BleCommandException(
          'AUTH_TIMEOUT', 'authentication timed out');
    } catch (e) {
      // 鉴权失败不断开连接，交由上层决定（可重试或走绑定）
      if (_state != BleDeviceState.disconnected) {
        _setState(BleDeviceState.connecting);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _waitForAuth(String type, String replyTo) {
    final completer = Completer<Map<String, dynamic>>();
    _authCompleter = completer;
    _expectedAuthType = type;
    _expectedAuthReplyTo = replyTo;
    return completer.future;
  }

  void _onAuthNotify(List<int> bytes) {
    final completer = _authCompleter;
    if (completer == null || completer.isCompleted) return;
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (_expectedAuthType != null &&
          json['v'] == 2 &&
          json['type'] == _expectedAuthType &&
          json['session_id'] == connectionSessionId &&
          json['in_reply_to'] == _expectedAuthReplyTo) {
        _expectedAuthType = null;
        _expectedAuthReplyTo = null;
        completer.complete(json);
      } else if (_expectedAuthType == null &&
          (json['mode'] == 'bind' || json['mode'] == 'pin_check')) {
        completer.complete(json);
      }
    } catch (e) {
      completer.completeError(e);
    }
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  // ---------------------------------------------------------------------------
  // 命令下发（协议 §7：commandId 配对 + 5s 超时 + 2 次重试，串行队列）
  // ---------------------------------------------------------------------------

  /// 下发控制命令，返回设备回报的 data 字段
  Future<Map<String, dynamic>> sendCommand(
    String action, [
    Map<String, dynamic> params = const {},
  ]) {
    if (_otaInProgress) {
      return Future.error(
        const BleCommandException('OTA_IN_PROGRESS', 'OTA owns BLE link'),
      );
    }
    return _enqueue(() => _sendCommandInternal(action, params));
  }

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final result = _commandChain.then((_) => task());
    // 单个命令失败不中断后续队列
    _commandChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Map<String, dynamic>> _sendCommandInternal(
    String action,
    Map<String, dynamic> params,
  ) async {
    final connection = _connection;
    if (connection == null || _state != BleDeviceState.ready) {
      throw const BleCommandException('UNAUTHENTICATED', 'session not ready');
    }

    final commandId = _generateCommandId();
    final operationId = _generateMessageId();
    final messageId = _generateMessageId();
    final sessionId = connectionSessionId;
    if (sessionId == null) {
      throw const BleCommandException('UNAUTHENTICATED', 'missing session id');
    }
    final completer = Completer<Map<String, dynamic>>();
    _pendingCommands[commandId] = _PendingBleCommand(
      completer: completer,
      messageId: messageId,
      sessionId: sessionId,
    );

    final payload = utf8.encode(
      jsonEncode({
        'v': 2,
        'type': 'control.request',
        'message_id': messageId,
        'session_id': sessionId,
        'body': {
          'operation_id': operationId,
          'command_id': commandId,
          'session_id': sessionId,
          'sequence': ++_commandSequence,
          'action': action,
          'params': params,
        },
      }),
    );

    try {
      for (var attempt = 0;
          attempt <= BleCtProtocol.commandMaxRetries;
          attempt++) {
        await connection.write(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.commandCharUuid,
          payload,
        );
        try {
          // 重试沿用原 commandId，设备端幂等；迟到的首次回报同样可完成配对
          return await completer.future.timeout(BleCtProtocol.commandTimeout);
        } on TimeoutException {
          if (attempt == BleCtProtocol.commandMaxRetries) rethrow;
        }
      }
      throw TimeoutException('unreachable');
    } finally {
      _pendingCommands.remove(commandId);
    }
  }

  void _onCmdResult(List<int> bytes) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (json['v'] != 2 || json['type'] != 'control.result') return;
    final body = json['body'];
    if (body is! Map) return;
    final result = body.cast<String, dynamic>();
    final id = result['command_id'] as String?;
    final pending = _pendingCommands[id];
    if (pending == null || pending.completer.isCompleted) return;
    if (json['session_id'] != pending.sessionId ||
        json['in_reply_to'] != pending.messageId) {
      return;
    }

    final status = result['status'] as String?;
    if (status == 'accepted' || status == 'executing') return;
    _pendingCommands.remove(id);
    if (status == 'applied') {
      pending.completer.complete(
        (result['actual'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
    } else {
      final err = result['error'] as Map?;
      pending.completer.completeError(
        BleCommandException(
          (err?['code'] as String?) ?? 'INTERNAL',
          (err?['message'] as String?) ?? 'unknown error',
        ),
      );
    }
  }

  String _generateCommandId() => List.generate(4, (_) => _random.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  String _generateMessageId() => List.generate(12, (_) => _random.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  // ---------------------------------------------------------------------------
  // 遥测（协议 §6：分帧重组 + JSON 解码）
  // ---------------------------------------------------------------------------

  void _onTelemetry(List<int> bytes) {
    final complete = _reassembler.feed(bytes);
    if (complete == null) return;
    try {
      final json = jsonDecode(utf8.decode(complete)) as Map<String, dynamic>;
      _telemetryController.add(json);
    } catch (e) {
      debugPrint('BleDeviceSession: telemetry JSON decode failed: $e');
    }
  }

  Future<BleOtaLease> acquireOtaLease() async {
    if (_connection == null || _state != BleDeviceState.ready) {
      throw const BleCommandException('UNAUTHENTICATED', 'session not ready');
    }
    if (_otaInProgress) {
      throw const BleCommandException('OTA_IN_PROGRESS', 'OTA already active');
    }
    _otaInProgress = true;
    final status = _connection!
        .subscribe(
          BleCtProtocol.provisioningServiceUuid,
          BleCtProtocol.otaStatusCharUuid,
        )
        .map((bytes) =>
            jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
    return BleOtaLease._(this, status);
  }

  Future<void> _writeOta(
    String characteristicUuid,
    Map<String, dynamic> value,
  ) async {
    if (!_otaInProgress || _connection == null) {
      throw const BleCommandException('OTA_NOT_ACTIVE', 'OTA lease missing');
    }
    await _connection!.write(
      BleCtProtocol.provisioningServiceUuid,
      characteristicUuid,
      utf8.encode(jsonEncode(value)),
    );
  }

  Future<Map<String, dynamic>> _readOtaStatus() async {
    if (!_otaInProgress || _connection == null) {
      throw const BleCommandException('OTA_NOT_ACTIVE', 'OTA lease missing');
    }
    final bytes = await _connection!.read(
      BleCtProtocol.provisioningServiceUuid,
      BleCtProtocol.otaStatusCharUuid,
    );
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  void _releaseOtaLease() => _otaInProgress = false;

  // ---------------------------------------------------------------------------
  // 断线与重连（指数退避 1s/2s/5s/10s 封顶）
  // ---------------------------------------------------------------------------

  void _handleUnexpectedDisconnect() {
    _pendingCommands.forEach((_, pending) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          const BleCommandException('UNAUTHENTICATED', 'disconnected'),
        );
      }
    });
    _pendingCommands.clear();
    final auth = _authCompleter;
    if (auth != null && !auth.isCompleted) {
      auth.completeError(
        const BleCommandException('UNAUTHENTICATED', 'disconnected'),
      );
    }
    _authCompleter = null;
    _expectedAuthType = null;
    _expectedAuthReplyTo = null;
    connectionSessionId = null;
    protocolVersion = 0;
    capabilities = const {};
    _otaInProgress = false;
    _setState(BleDeviceState.disconnected);
    _connection = null;

    if (!_autoReconnect || _disposed) return;
    final backoff = BleCtProtocol.reconnectBackoff[
        _reconnectAttempt.clamp(0, BleCtProtocol.reconnectBackoff.length - 1)];
    _reconnectAttempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(backoff, () async {
      if (_disposed || _state != BleDeviceState.disconnected) return;
      try {
        await connect(autoReconnect: true);
      } catch (_) {
        // 失败由 linkState/下一次退避继续处理
      }
    });
  }

  /// 主动断开（不触发自动重连）
  Future<void> disconnect() async {
    _autoReconnect = false;
    _reconnectTimer?.cancel();
    await _teardown();
    _setState(BleDeviceState.disconnected);
  }

  Future<void> _teardown() async {
    await _telemetrySub?.cancel();
    await _cmdResultSub?.cancel();
    await _authSub?.cancel();
    await _linkSub?.cancel();
    _telemetrySub = null;
    _cmdResultSub = null;
    _authSub = null;
    _linkSub = null;
    final connection = _connection;
    _connection = null;
    try {
      await connection?.disconnect();
    } catch (_) {}
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _stateController.close();
    await _telemetryController.close();
  }
}

class BleOtaLease {
  BleOtaLease._(this._session, this.statuses);

  final BleDeviceSession _session;
  final Stream<Map<String, dynamic>> statuses;
  bool _released = false;

  Future<void> writeControl(Map<String, dynamic> value) =>
      _session._writeOta(BleCtProtocol.otaControlCharUuid, value);

  Future<void> writeData(Map<String, dynamic> value) =>
      _session._writeOta(BleCtProtocol.otaDataCharUuid, value);

  Future<Map<String, dynamic>> readStatus() => _session._readOtaStatus();

  void release() {
    if (_released) return;
    _released = true;
    _session._releaseOtaLease();
  }
}

/// 多设备管理器
///
/// - `Map<macAddress, BleDeviceSession>` 多设备并发管理
/// - 自动连接：由外部发现扫描驱动 → 命中设备读 SN →
///   keyStore 存在 device_key（已绑定）则连接并鉴权
class BleDeviceManager {
  final BleAdapter _adapter;
  final BleDeviceKeyStore _keyStore;

  final Map<String, BleDeviceSession> _sessions = {};
  bool _autoConnectRunning = false;

  BleDeviceManager({
    required BleAdapter adapter,
    required BleDeviceKeyStore keyStore,
  })  : _adapter = adapter,
        _keyStore = keyStore;

  /// 当前全部会话（mac → session，只读视图）
  Map<String, BleDeviceSession> get sessions => Map.unmodifiable(_sessions);

  BleDeviceSession? sessionOf(String macAddress) => _sessions[macAddress];

  /// 连接（或复用）指定设备会话
  Future<BleDeviceSession> connectDevice(
    String macAddress, {
    bool autoConnect = false,
    bool autoReconnect = true,
  }) async {
    final existing = _sessions[macAddress];
    if (existing != null && existing.state != BleDeviceState.disconnected) {
      return existing;
    }
    final session = existing ??
        BleDeviceSession(
          adapter: _adapter,
          macAddress: macAddress,
          keyStore: _keyStore,
        );
    _sessions[macAddress] = session;
    await session.connect(
      autoConnect: autoConnect,
      autoReconnect: autoReconnect,
    );
    return session;
  }

  Future<void> disconnectDevice(String macAddress) async {
    final session = _sessions.remove(macAddress);
    await session?.dispose();
  }

  Future<void> disconnectAll() async {
    await stopAutoConnect();
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    for (final s in sessions) {
      await s.dispose();
    }
  }

  /// 启动自动连接。
  ///
  /// 仅置位，不独立发起扫描：由 [BleDirectService] 的发现扫描统一驱动
  /// [tryAutoConnect]，避免两路 startScan 互相抢占（后一次会 stop 前一次）。
  Future<void> startAutoConnect() async {
    final status = await _adapter.status;
    if (status != BleAdapterStatus.on) {
      throw StateError('BLE adapter not on: $status');
    }
    _autoConnectRunning = true;
  }

  /// 外部发现扫描命中设备时调用；已绑定才连接并鉴权。
  Future<void> tryAutoConnect(BleScanResult result) async {
    if (!_autoConnectRunning) return;
    final existing = _sessions[result.macAddress];
    if (existing != null && existing.state != BleDeviceState.disconnected) {
      return;
    }
    // 仅自动连接已绑定设备：广播名解析 SN → keyStore 校验 device_key
    final sn = parseSnFromAdvName(result.name);
    if (sn.isEmpty) return;
    String? deviceKey;
    try {
      deviceKey = await _keyStore.read(sn);
    } catch (e) {
      debugPrint('BleDeviceManager: keyStore read $sn failed: $e');
      return;
    }
    if (deviceKey == null || !_autoConnectRunning) return;
    try {
      await connectDevice(result.macAddress, autoReconnect: true);
    } catch (e) {
      debugPrint('BleDeviceManager: auto-connect ${result.macAddress} '
          'failed: $e');
    }
  }

  /// 从广播名解析 SN（广播名形如 CS_INV_<SN> / CS-INV-<SN>）；
  /// 无法解析时返回空串
  static String parseSnFromAdvName(String name) {
    return name
        .replaceFirst(RegExp(r'^CS[-_]INV[-_]', caseSensitive: false), '')
        .trim();
  }

  Future<void> stopAutoConnect() async {
    _autoConnectRunning = false;
  }
}
