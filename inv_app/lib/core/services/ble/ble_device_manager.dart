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
}

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
}

/// 基于 flutter_secure_storage 的 device_key 存储
class SecureStorageBleDeviceKeyStore implements BleDeviceKeyStore {
  final FlutterSecureStorage _storage;

  SecureStorageBleDeviceKeyStore(this._storage);

  static String _keyOf(String sn) => 'ble_device_key_$sn';

  @override
  Future<String?> read(String sn) => _storage.read(key: _keyOf(sn));

  @override
  Future<void> write(String sn, String keyBase64) =>
      _storage.write(key: _keyOf(sn), value: keyBase64);

  @override
  Future<void> delete(String sn) => _storage.delete(key: _keyOf(sn));
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
  final _pendingCommands = <String, Completer<Map<String, dynamic>>>{};
  Completer<Map<String, dynamic>>? _authCompleter;
  final _random = Random.secure();

  /// 断线自动重连
  bool _autoReconnect = false;
  bool _disposed = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;

  BleDeviceSession({
    required BleAdapter adapter,
    required this.macAddress,
    required BleDeviceKeyStore keyStore,
  })  : _adapter = adapter,
        _keyStore = keyStore;

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

  // ---------------------------------------------------------------------------
  // 鉴权（协议 §5：HMAC-SHA256(nonce:ts, device_key) challenge-response）
  // ---------------------------------------------------------------------------

  Future<void> authenticate(String deviceKeyBase64) async {
    final connection = _connection;
    if (connection == null) {
      throw const BleCommandException('UNAUTHENTICATED', 'not connected');
    }
    _setState(BleDeviceState.authenticating);
    try {
      final key = base64Decode(deviceKeyBase64);
      final nonce = List<int>.generate(16, (_) => _random.nextInt(256));
      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final expected =
          Hmac(sha256, key).convert([...nonce, ...utf8.encode(':$ts')]);

      final completer = Completer<Map<String, dynamic>>();
      _authCompleter = completer;
      await connection.write(
        BleCtProtocol.serviceUuid,
        BleCtProtocol.authCharUuid,
        utf8.encode(
          jsonEncode({
            'mode': 'auth',
            'nonce': base64Encode(nonce),
            'ts': ts,
          }),
        ),
      );

      final resp = await completer.future.timeout(BleCtProtocol.authTimeout);
      final digest = resp['digest'] as String?;
      if (digest == null ||
          !_constantTimeEquals(base64Decode(digest), expected.bytes)) {
        throw const BleCommandException(
          'UNAUTHENTICATED',
          'digest mismatch',
        );
      }
      _setState(BleDeviceState.ready);
    } catch (e) {
      // 鉴权失败不断开连接，交由上层决定（可重试或走绑定）
      _setState(BleDeviceState.connecting);
      rethrow;
    }
  }

  void _onAuthNotify(List<int> bytes) {
    final completer = _authCompleter;
    if (completer == null || completer.isCompleted) return;
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (json['mode'] == 'auth') {
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
    final completer = Completer<Map<String, dynamic>>();
    _pendingCommands[commandId] = completer;

    final payload = utf8.encode(
      jsonEncode({
        'command_id': commandId,
        'action': action,
        'params': params,
        'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
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
    final id = json['command_id'] as String?;
    final completer = _pendingCommands.remove(id);
    if (completer == null || completer.isCompleted) return;

    if (json['status'] == 'ok') {
      completer.complete(
        (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
    } else {
      final err = json['error'] as Map?;
      completer.completeError(
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

  // ---------------------------------------------------------------------------
  // 断线与重连（指数退避 1s/2s/5s/10s 封顶）
  // ---------------------------------------------------------------------------

  void _handleUnexpectedDisconnect() {
    _pendingCommands.forEach((_, c) {
      if (!c.isCompleted) {
        c.completeError(
          const BleCommandException('UNAUTHENTICATED', 'disconnected'),
        );
      }
    });
    _pendingCommands.clear();
    _authCompleter = null;
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

/// 多设备管理器
///
/// - `Map<macAddress, BleDeviceSession>` 多设备并发管理
/// - 自动连接：按服务 UUID 低功耗扫描 → 命中设备读 SN →
///   keyStore 存在 device_key（已绑定）则连接并鉴权
class BleDeviceManager {
  final BleAdapter _adapter;
  final BleDeviceKeyStore _keyStore;

  final Map<String, BleDeviceSession> _sessions = {};
  StreamSubscription<BleScanResult>? _scanSub;
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

  /// 启动自动连接（Android 后台场景建议配合 autoConnect=true 挂起直连）
  ///
  /// 扫描过滤 CSIV-PR 服务 UUID（现有固件广播即携带），命中后：
  /// 连接 → 读 SN → keyStore 有 device_key → 鉴权进入 ready；
  /// 无 device_key（未绑定设备）跳过，交由配网/绑定流程处理。
  Future<void> startAutoConnect() async {
    if (_autoConnectRunning) return;
    _autoConnectRunning = true;

    final status = await _adapter.status;
    if (status != BleAdapterStatus.on) {
      _autoConnectRunning = false;
      throw StateError('BLE adapter not on: $status');
    }

    _scanSub = _adapter
        .scan(serviceUuids: const [BleCtProtocol.provisioningServiceUuid])
        .listen((result) async {
      if (!_autoConnectRunning) return;
      final existing = _sessions[result.macAddress];
      if (existing != null && existing.state != BleDeviceState.disconnected) {
        return;
      }
      try {
        await connectDevice(result.macAddress, autoReconnect: true);
      } catch (e) {
        debugPrint('BleDeviceManager: auto-connect ${result.macAddress} '
            'failed: $e');
      }
    });
  }

  Future<void> stopAutoConnect() async {
    _autoConnectRunning = false;
    await _scanSub?.cancel();
    _scanSub = null;
    await _adapter.stopScan();
  }
}
