# BLE 直连设备模式（App 端）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 inv_app 中实现"通过 BLE 直连设备"能力：设置开关、配网后自动绑定、180s 遥测轮询（与 HTTP 并存）、离线操作日志本地存储与联网自动同步。

**Architecture:** 复用现有 BLE 协议层（BleDeviceManager/BleDeviceSession，已实现状态机、HMAC 鉴权、命令队列、分帧重组）。新增 5 个服务：`OfflineOpLogStore`（sqflite 本地日志）、`OfflineLogSyncService`（网络恢复自动同步+指数退避）、`BleBindingService`（配网后自动绑定编排）、`BlePollingService`（180s 轮询遥测）、`BleDirectService`（开关聚合：扫描/自动连接/轮询启停）。BleDeviceSession 扩展 3 个协议方法（readInfo / readTelemetrySnapshot / bind）。UI 改动：设置页开关+周期、配网页绑定触发、设备编辑页解绑副作用、设备设置页日志入口、新建操作日志页。

**Tech Stack:** Flutter + flutter_blue_ultra（BLE）+ sqflite（本地日志）+ get_it（DI）+ Dio（HTTP）+ mocktail（测试）

**依赖设计文档:** `docs/superpowers/specs/2026-08-10-ble-local-mode-design.md` §3、§7

**前置约定：** 协议层类已存在（`lib/core/services/ble/ble_adapter.dart`、`ble_device_manager.dart`）；`BleAdapter`/`BleGattConnection`/`BleDeviceKeyStore` 均为抽象类可 mocktail mock；后端接口见配套计划《2026-08-10-ble-backend-offline-logs.md》（bind 返回 device_key、POST /devices/offline-logs）。

---

### Task 1: 添加依赖（sqflite / uuid）

**Files:**
- Modify: `inv_app/pubspec.yaml`

- [ ] **Step 1: 修改 pubspec.yaml**

在 `pubspec.yaml` 的 `path_provider: ^2.1.2` 之后添加：

```yaml
  sqflite: ^2.4.2
  uuid: ^4.5.1
```

在 `dev_dependencies` 的 `mocktail: ^1.0.0` 之后添加：

```yaml
  sqflite_common_ffi: ^2.3.4
```

- [ ] **Step 2: 拉取依赖**

Run: `cd inv_app && flutter pub get`
Expected: `Got dependencies!` 无错误

- [ ] **Step 3: 提交**

```bash
git add inv_app/pubspec.yaml inv_app/pubspec.lock
git commit -m "chore(app): add sqflite and uuid dependencies for BLE local mode"
```

---

### Task 2: BleDeviceSession 协议扩展（readInfo / readTelemetrySnapshot / bind）

**Files:**
- Modify: `inv_app/lib/core/services/ble/ble_device_manager.dart`（BleDeviceSession 增加 3 个公开方法；`_onAuthNotify` 支持 bind 模式）
- Test: Create `inv_app/test/ble/ble_device_session_test.dart`

- [ ] **Step 1: 先写失败测试**

Create `inv_app/test/ble/ble_device_session_test.dart`：

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:mocktail/mocktail.dart';

class MockBleAdapter extends Mock implements BleAdapter {}

class MockBleGattConnection extends Mock implements BleGattConnection {}

class MockBleDeviceKeyStore extends Mock implements BleDeviceKeyStore {}

void main() {
  late MockBleAdapter adapter;
  late MockBleGattConnection connection;
  late MockBleDeviceKeyStore keyStore;
  late StreamController<List<int>> authNotify;

  const mac = 'AA:BB:CC:DD:EE:FF';

  setUp(() {
    adapter = MockBleAdapter();
    connection = MockBleGattConnection();
    keyStore = MockBleDeviceKeyStore();
    authNotify = StreamController<List<int>>.broadcast();

    when(() => adapter.connect(any(), autoConnect: any(named: 'autoConnect'), timeout: any(named: 'timeout')))
        .thenAnswer((_) async => connection);
    when(() => connection.linkState)
        .thenAnswer((_) => const Stream.empty());
    when(() => connection.read(
          BleCtProtocol.provisioningServiceUuid,
          BleCtProtocol.provisioningSnCharUuid,
        ))
        .thenAnswer((_) async => utf8.encode('H1CNA6K20001'));
    when(() => connection.subscribe(any(), any())).thenAnswer((_) => authNotify.stream);
    when(() => keyStore.read(any())).thenAnswer((_) async => null);
  });

  tearDown(() => authNotify.close());

  Future<BleDeviceSession> connectSession() async {
    final session = BleDeviceSession(
      adapter: adapter,
      macAddress: mac,
      keyStore: keyStore,
    );
    await session.connect();
    return session;
  }

  test('readInfo returns INFO json', () async {
    when(() => connection.read(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.infoCharUuid,
        ))
        .thenAnswer((_) async => utf8.encode(
              '{"sn":"H1CNA6K20001","bound":false,"proto_ver":"1.0"}',
            ));

    final session = await connectSession();
    final info = await session.readInfo();

    expect(info['sn'], 'H1CNA6K20001');
    expect(info['bound'], false);
  });

  test('readTelemetrySnapshot returns telemetry json', () async {
    when(() => connection.read(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.telemetryCharUuid,
        ))
        .thenAnswer((_) async => utf8.encode('{"power_w":3000,"status":1}'));

    final session = await connectSession();
    final data = await session.readTelemetrySnapshot();

    expect(data['power_w'], 3000);
  });

  test('bind writes bind message and completes on ok notify', () async {
    when(() => connection.write(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.authCharUuid,
          any(),
        ))
        .thenAnswer((_) async {});

    final session = await connectSession();
    // 未绑定设备：连接后停留在 authenticating
    expect(session.state, BleDeviceState.authenticating);

    final bindFuture = session.bind('a2V5LWJhc2U2NA==');
    // 设备 notify 返回 bind 结果
    authNotify.add(utf8.encode(jsonEncode({'mode': 'bind', 'result': 'ok'})));
    await bindFuture; // 不抛异常即通过
  });

  test('bind throws BleCommandException when rejected', () async {
    when(() => connection.write(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.authCharUuid,
          any(),
        ))
        .thenAnswer((_) async {});

    final session = await connectSession();
    final bindFuture = session.bind('a2V5LWJhc2U2NA==');
    authNotify.add(utf8.encode(jsonEncode({
      'mode': 'bind',
      'result': 'error',
      'error': 'already_bound',
    })));
    await expectLater(
      bindFuture,
      throwsA(isA<BleCommandException>()
          .having((e) => e.code, 'code', 'BIND_REJECTED')),
    );
  });

  test('readTelemetrySnapshot throws when not connected', () async {
    final session = BleDeviceSession(
      adapter: adapter,
      macAddress: mac,
      keyStore: keyStore,
    );
    await expectLater(
      session.readTelemetrySnapshot(),
      throwsA(isA<BleCommandException>()),
    );
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd inv_app && flutter test test/ble/ble_device_session_test.dart`
Expected: FAIL（`readInfo`/`readTelemetrySnapshot`/`bind` undefined）

- [ ] **Step 3: 实现三个协议方法**

在 `ble_device_manager.dart` 的 `BleDeviceSession` 类中、`_readSn()` 方法之后插入：

```dart
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

  /// 绑定（协议 §4.1）：设备未绑定时写入 bind 消息，设备 notify 返回结果。
  /// [deviceKeyBase64] 来自云端 `POST /devices/bind` 响应。
  Future<void> bind(String deviceKeyBase64) async {
    final connection = _connection;
    if (connection == null) {
      throw const BleCommandException('UNAUTHENTICATED', 'not connected');
    }
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
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
```

- [ ] **Step 4: 修改 _onAuthNotify 支持 bind 模式**

将 `_onAuthNotify` 中的 `if (json['mode'] == 'auth') {` 改为：

```dart
      if (json['mode'] == 'auth' || json['mode'] == 'bind') {
        completer.complete(json);
      }
```

- [ ] **Step 5: 运行测试确认通过**

Run: `cd inv_app && flutter test test/ble/ble_device_session_test.dart`
Expected: PASS（5 个用例全部通过）

- [ ] **Step 6: 提交**

```bash
git add inv_app/lib/core/services/ble/ble_device_manager.dart inv_app/test/ble/ble_device_session_test.dart
git commit -m "feat(app): add readInfo/readTelemetrySnapshot/bind to BleDeviceSession"
```

---

### Task 3: OfflineOpLogStore（sqflite 本地操作日志）

**Files:**
- Create: `inv_app/lib/core/services/offline/offline_op_log_store.dart`
- Test: Create `inv_app/test/offline/offline_op_log_store_test.dart`

- [ ] **Step 1: 先写失败测试**

Create `inv_app/test/offline/offline_op_log_store_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late OfflineOpLogStore store;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    store = OfflineOpLogStore(
      openDb: () async => databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: OfflineOpLogStore.onCreate,
        ),
      ),
    );
  });

  OfflineOpLog sample(int seq) => OfflineOpLog(
        logId: 'log-$seq',
        deviceSn: 'H1CNA6K20001',
        action: 'set_power',
        params: {'power_w': seq * 100},
        result: 'ok',
        channel: 'ble',
        opTime: DateTime.utc(2026, 8, 10, 0, 0, seq),
      );

  test('add then pending returns the log with pending status', () async {
    await store.add(sample(1));
    final pending = await store.pending(limit: 50);
    expect(pending, hasLength(1));
    expect(pending.first.logId, 'log-1');
    expect(pending.first.syncStatus, 'pending');
    expect(pending.first.action, 'set_power');
    expect(pending.first.params['power_w'], 100);
  });

  test('markSyncing/markSynced transitions status', () async {
    await store.add(sample(1));
    await store.markSyncing(['log-1']);
    expect((await store.pending(limit: 50)), isEmpty);

    await store.markSynced(['log-1']);
    expect(await store.pendingCount(), 0);

    // synced 的日志不再出现在 pending
    await store.add(sample(2));
    expect(await store.pendingCount(), 1);
  });

  test('pending respects limit and excludes synced', () async {
    for (var i = 1; i <= 60; i++) {
      await store.add(sample(i));
    }
    await store.markSynced(['log-1']);
    final pending = await store.pending(limit: 50);
    expect(pending, hasLength(50));
    expect(pending.every((l) => l.logId != 'log-1'), isTrue);
  });

  test('bumpAttempts increments and failed status stops retry', () async {
    await store.add(sample(1));
    await store.bumpAttempts(['log-1']);
    final pending = await store.pending(limit: 50);
    expect(pending.first.syncAttempts, 1);

    await store.markFailed(['log-1']);
    expect(await store.pending(limit: 50), isEmpty);
    expect(await store.pendingCount(), 0);
  });

  test('prune removes synced logs beyond retention', () async {
    // 插入 510 条 synced + 1 条 pending
    for (var i = 1; i <= 510; i++) {
      final log = sample(i);
      await store.add(log);
    }
    await store.markSynced(List.generate(510, (i) => 'log-${i + 1}'));
    await store.add(sample(999));

    await store.prune();

    final count = await store.countAll();
    // 保留最近 500 条 synced + 1 条 pending = 501
    expect(count, 501);
    final syncedRemaining =
        await store.countByStatus('synced');
    expect(syncedRemaining, 500);
    expect(await store.pendingCount(), 1);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd inv_app && flutter test test/offline/offline_op_log_store_test.dart`
Expected: FAIL（`OfflineOpLogStore` undefined）

- [ ] **Step 3: 实现 OfflineOpLogStore**

Create `inv_app/lib/core/services/offline/offline_op_log_store.dart`：

```dart
import 'package:sqflite/sqflite.dart';

/// 本地操作日志实体（设计文档 §3.5）
class OfflineOpLog {
  final String logId;
  final String deviceSn;
  final String action;
  final Map<String, dynamic> params;
  final String result;
  final String channel;
  final DateTime opTime;
  final String syncStatus; // pending/syncing/synced/failed
  final int syncAttempts;

  const OfflineOpLog({
    required this.logId,
    required this.deviceSn,
    required this.action,
    this.params = const {},
    this.result = 'ok',
    this.channel = 'ble',
    required this.opTime,
    this.syncStatus = 'pending',
    this.syncAttempts = 0,
  });

  Map<String, dynamic> toJson() => {
        'log_id': logId,
        'device_sn': deviceSn,
        'action': action,
        'params': params,
        'result': result,
        'channel': channel,
        'op_time': opTime.toUtc().toIso8601String(),
      };

  factory OfflineOpLog.fromMap(Map<String, dynamic> map) => OfflineOpLog(
        logId: map['log_id'] as String,
        deviceSn: map['device_sn'] as String,
        action: map['action'] as String,
        params:
            (map['params'] as Map?)?.cast<String, dynamic>() ?? const {},
        result: (map['result'] as String?) ?? 'ok',
        channel: (map['channel'] as String?) ?? 'ble',
        opTime: DateTime.parse(map['op_time'] as String),
        syncStatus: (map['sync_status'] as String?) ?? 'pending',
        syncAttempts: (map['sync_attempts'] as int?) ?? 0,
      );
}

/// 本地操作日志存储（sqflite，表 local_op_logs）
///
/// 容量上限：500 条 / 30 天（仅清理已同步日志，设计文档 §3.5）。
class OfflineOpLogStore {
  final Future<Database> Function() _openDb;
  Database? _db;

  OfflineOpLogStore({Future<Database> Function()? openDb})
      : _openDb = openDb ?? _defaultOpen;

  static Future<Database> _defaultOpen() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      '$dir/local_op_logs.db',
      version: 1,
      onCreate: onCreate,
    );
  }

  /// 建表回调（测试与默认打开共用）
  static Future<void> onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE local_op_logs (
        log_id TEXT PRIMARY KEY,
        device_sn TEXT NOT NULL,
        action TEXT NOT NULL,
        params TEXT NOT NULL DEFAULT '{}',
        result TEXT NOT NULL DEFAULT 'ok',
        channel TEXT NOT NULL DEFAULT 'ble',
        op_time TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        sync_attempts INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_op_logs_status ON local_op_logs(sync_status, op_time)',
    );
  }

  Future<Database> get _database async => _db ??= await _openDb();

  Future<void> add(OfflineOpLog log) async {
    final db = await _database;
    await db.insert('local_op_logs', {
      'log_id': log.logId,
      'device_sn': log.deviceSn,
      'action': log.action,
      'params': jsonEncodeSafe(log.params),
      'result': log.result,
      'channel': log.channel,
      'op_time': log.opTime.toUtc().toIso8601String(),
      'sync_status': log.syncStatus,
      'sync_attempts': log.syncAttempts,
    });
    await prune();
  }

  /// 待同步日志（按时间正序，[limit] 条；attempts 已达 5 的 failed 不返回）
  Future<List<OfflineOpLog>> pending({int limit = 50}) async {
    final db = await _database;
    final rows = await db.query(
      'local_op_logs',
      where: 'sync_status IN (?, ?) AND sync_attempts < 5',
      whereArgs: ['pending', 'failed'],
      orderBy: 'op_time ASC',
      limit: limit,
    );
    return rows.map(OfflineOpLog.fromMap).toList(growable: false);
  }

  Future<int> pendingCount() async {
    final db = await _database;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM local_op_logs WHERE sync_status IN ('pending','failed') AND sync_attempts < 5",
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<int> countAll() async {
    final db = await _database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM local_op_logs');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<int> countByStatus(String status) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM local_op_logs WHERE sync_status = ?',
      [status],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> markSyncing(List<String> logIds) async {
    await _updateStatus(logIds, 'syncing');
  }

  Future<void> markSynced(List<String> logIds) async {
    await _updateStatus(logIds, 'synced');
  }

  Future<void> markFailed(List<String> logIds) async {
    await _updateStatus(logIds, 'failed');
  }

  /// 失败重试计数 +1（状态回 pending，等待下一次退避重试）
  Future<void> bumpAttempts(List<String> logIds) async {
    if (logIds.isEmpty) return;
    final db = await _database;
    await db.rawUpdate(
      'UPDATE local_op_logs SET sync_attempts = sync_attempts + 1, '
      "sync_status = 'pending' WHERE log_id IN (${List.filled(logIds.length, '?').join(',')})",
      logIds,
    );
  }

  Future<void> _updateStatus(List<String> logIds, String status) async {
    if (logIds.isEmpty) return;
    final db = await _database;
    await db.rawUpdate(
      'UPDATE local_op_logs SET sync_status = ? WHERE log_id IN '
      '(${List.filled(logIds.length, '?').join(',')})',
      [status, ...logIds],
    );
  }

  /// 容量清理：删除已同步且（超过 30 天 或 超出最近 500 条）的日志
  Future<void> prune() async {
    final db = await _database;
    await db.rawDelete('''
      DELETE FROM local_op_logs
      WHERE sync_status = 'synced' AND (
        op_time < datetime('now', '-30 days')
        OR rowid NOT IN (
          SELECT rowid FROM local_op_logs
          WHERE sync_status = 'synced'
          ORDER BY op_time DESC LIMIT 500
        )
      )
    ''');
  }
}

String jsonEncodeSafe(Map<String, dynamic> map) {
  // 无外部依赖的 JSON 编码（params 为简单值，直接序列化）
  final buffer = StringBuffer('{');
  var first = true;
  map.forEach((k, v) {
    if (!first) buffer.write(',');
    first = false;
    buffer.write('"${k.replaceAll('"', '\\"')}":${_encodeValue(v)}');
  });
  buffer.write('}');
  return buffer.toString();
}

String _encodeValue(Object? v) {
  if (v == null) return 'null';
  if (v is num || v is bool) return '$v';
  if (v is String) {
    return '"${v.replaceAll('"', '\\"').replaceAll('\n', '\\n')}"';
  }
  return '"${v.toString()}"';
}
```

> 说明：为避免引入 json 序列化依赖歧义，`jsonEncodeSafe` 为 params 提供轻量 JSON 编码；若执行时更倾向 `dart:convert` 的 `jsonEncode`，可直接替换（`import 'dart:convert';`，`jsonEncode(log.params)`）。

- [ ] **Step 4: 运行测试确认通过**

Run: `cd inv_app && flutter test test/offline/offline_op_log_store_test.dart`
Expected: PASS（5 个用例全部通过）

- [ ] **Step 5: 提交**

```bash
git add inv_app/lib/core/services/offline/offline_op_log_store.dart inv_app/test/offline/offline_op_log_store_test.dart
git commit -m "feat(app): add OfflineOpLogStore with retention pruning"
```

---

### Task 4: OfflineLogSyncService（自动同步 + 指数退避）

**Files:**
- Create: `inv_app/lib/core/services/offline/offline_log_api.dart`
- Create: `inv_app/lib/core/services/offline/offline_log_sync_service.dart`
- Test: Create `inv_app/test/offline/offline_log_sync_service_test.dart`

- [ ] **Step 1: 先写失败测试**

Create `inv_app/test/offline/offline_log_sync_service_test.dart`：

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/network_status_service.dart';
import 'package:inv_app/core/services/offline/offline_log_api.dart';
import 'package:inv_app/core/services/offline/offline_log_sync_service.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockOfflineLogApi extends Mock implements OfflineLogApi {}

class MockNetworkStatusService extends Mock implements NetworkStatusService {}

void main() {
  late OfflineOpLogStore store;
  late MockOfflineLogApi api;
  late MockNetworkStatusService networkStatus;
  late StreamController<bool> statusController;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    store = OfflineOpLogStore(
      openDb: () async => databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: OfflineOpLogStore.onCreate,
        ),
      ),
    );
    api = MockOfflineLogApi();
    networkStatus = MockNetworkStatusService();
    statusController = StreamController<bool>.broadcast();
    when(() => networkStatus.statusStream)
        .thenAnswer((_) => statusController.stream);
  });

  tearDown(() => statusController.close());

  OfflineOpLog sample(int seq) => OfflineOpLog(
        logId: 'sync-log-$seq',
        deviceSn: 'H1CNA6K20001',
        action: 'power_on',
        params: const {},
        result: 'ok',
        channel: 'ble',
        opTime: DateTime.utc(2026, 8, 10, 0, 0, seq),
      );

  test('syncNow uploads pending logs and marks synced', () async {
    await store.add(sample(1));
    await store.add(sample(2));
    when(() => api.upload(any())).thenAnswer((_) async =>
        const OfflineLogUploadResult(accepted: 2, duplicates: 0));

    final service = OfflineLogSyncService(
      store: store,
      api: api,
      networkStatus: networkStatus,
    );
    await service.syncNow();

    verify(() => api.upload(any())).called(1);
    expect(await store.pendingCount(), 0);
    expect(await store.countByStatus('synced'), 2);
  });

  test('upload failure bumps attempts and schedules backoff retry', () async {
    await store.add(sample(1));
    when(() => api.upload(any())).thenThrow(Exception('network down'));

    final service = OfflineLogSyncService(
      store: store,
      api: api,
      networkStatus: networkStatus,
    );
    await service.syncNow();

    // 状态回 pending，attempts=1
    final pending = await store.pending(limit: 50);
    expect(pending, hasLength(1));
    expect(pending.first.syncAttempts, 1);
    // 退避计时器已调度（30s 后再次尝试）
    expect(service.hasPendingRetry, isTrue);
    service.dispose();
  });

  test('start listens to network recovery and triggers syncNow', () async {
    await store.add(sample(1));
    when(() => api.upload(any())).thenAnswer((_) async =>
        const OfflineLogUploadResult(accepted: 1, duplicates: 0));

    final service = OfflineLogSyncService(
      store: store,
      api: api,
      networkStatus: networkStatus,
    );
    await service.start();

    statusController.add(true); // 网络恢复事件
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await service.syncNow();

    verify(() => api.upload(any())).called(greaterThanOrEqualTo(1));
    expect(await store.pendingCount(), 0);
    service.dispose();
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd inv_app && flutter test test/offline/offline_log_sync_service_test.dart`
Expected: FAIL（`OfflineLogApi`/`OfflineLogSyncService` undefined）

- [ ] **Step 3: 实现 OfflineLogApi**

Create `inv_app/lib/core/services/offline/offline_log_api.dart`：

```dart
import 'package:dio/dio.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';

/// 离线日志上传结果（设计文档 §4.3）
class OfflineLogUploadResult {
  final int accepted;
  final int duplicates;

  const OfflineLogUploadResult({
    required this.accepted,
    required this.duplicates,
  });
}

/// 离线日志上报接口（抽象，便于测试替换）
abstract class OfflineLogApi {
  Future<OfflineLogUploadResult> upload(List<OfflineOpLog> logs);
}

/// Dio 实现：POST /devices/offline-logs（需登录，JWT 由 Dio 拦截器注入）
class DioOfflineLogApi implements OfflineLogApi {
  DioOfflineLogApi(this._dio);

  final Dio _dio;

  @override
  Future<OfflineLogUploadResult> upload(List<OfflineOpLog> logs) async {
    final response = await _dio.post(
      '/devices/offline-logs',
      data: {'logs': logs.map((log) => log.toJson()).toList()},
    );
    final data = (response.data as Map<String, dynamic>)['data']
        as Map<String, dynamic>;
    return OfflineLogUploadResult(
      accepted: (data['accepted'] as num?)?.toInt() ?? 0,
      duplicates: (data['duplicates'] as num?)?.toInt() ?? 0,
    );
  }
}
```

- [ ] **Step 4: 实现 OfflineLogSyncService**

Create `inv_app/lib/core/services/offline/offline_log_sync_service.dart`：

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:inv_app/core/services/network_status_service.dart';
import 'package:inv_app/core/services/offline/offline_log_api.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';

/// 离线操作日志同步服务（设计文档 §3.5）
///
/// - 触发：网络恢复事件 / App 启动（start）/ 手动 syncNow
/// - 批次 ≤50 条；失败按指数退避重试（30s/1min/5min/15min/60min 封顶）
/// - 单条重试 5 次后标记 failed，等待手动重试
class OfflineLogSyncService {
  OfflineLogSyncService({
    required this.store,
    required this.api,
    required this.networkStatus,
  });

  final OfflineOpLogStore store;
  final OfflineLogApi api;
  final NetworkStatusService networkStatus;

  /// 指数退避序列（与协议无关，纯客户端策略）
  static const List<Duration> backoffSteps = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 60),
  ];

  static const int maxAttempts = 5;
  static const int batchSize = 50;

  Timer? _retryTimer;
  StreamSubscription<bool>? _netSub;
  bool _started = false;

  /// 是否有退避重试在等待（测试断言用）
  bool get hasPendingRetry => _retryTimer?.isActive ?? false;

  /// 启动：监听网络恢复事件并立即尝试一次
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _netSub = networkStatus.statusStream
        .where((online) => online)
        .listen((_) {
      _retryTimer?.cancel();
      syncNow();
    });
    await syncNow();
  }

  /// 立即同步一轮（可手动触发）
  Future<void> syncNow() async {
    _retryTimer?.cancel();
    if (!_started) {
      // 未 start 时允许手动同步，但不挂监听
    }
    final pending = await store.pending(limit: batchSize);
    if (pending.isEmpty) return;

    await store.markSyncing(pending.map((log) => log.logId).toList());
    try {
      final result = await api.upload(pending);
      // 服务端按 accepted 计数：只标记被接受的为 synced
      final acceptedIds = pending
          .take(result.accepted)
          .map((log) => log.logId)
          .toList();
      if (acceptedIds.isNotEmpty) {
        await store.markSynced(acceptedIds);
      }
      // 若一批没传完（accepted < len），继续下一批
      if (await store.pendingCount() > 0) {
        _scheduleRetry(0);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OfflineLogSync] upload failed: $e');
      }
      await store.bumpAttempts(pending.map((log) => log.logId).toList());
      final attempts = (await store.pending(limit: batchSize))
          .fold<int>(0, (max, log) => log.syncAttempts > max ? log.syncAttempts : max);
      if (attempts >= maxAttempts) {
        await store.markFailed(pending.map((log) => log.logId).toList());
        return;
      }
      _scheduleRetry(attempts);
    }
  }

  void _scheduleRetry(int attemptIndex) {
    _retryTimer?.cancel();
    final index =
        attemptIndex.clamp(0, backoffSteps.length - 1).toInt();
    _retryTimer = Timer(backoffSteps[index], () {
      syncNow();
    });
  }

  void dispose() {
    _retryTimer?.cancel();
    _netSub?.cancel();
    _started = false;
  }
}
```

> 说明：测试中 `start()` 触发 `syncNow()` 会立刻上传一次（api mock 返回 accepted=1），随后网络事件再次触发——故测试断言 `called(greaterThanOrEqualTo(1))`。

- [ ] **Step 5: 运行测试确认通过**

Run: `cd inv_app && flutter test test/offline/offline_log_sync_service_test.dart`
Expected: PASS（3 个用例全部通过）

- [ ] **Step 6: 提交**

```bash
git add inv_app/lib/core/services/offline/offline_log_api.dart inv_app/lib/core/services/offline/offline_log_sync_service.dart inv_app/test/offline/offline_log_sync_service_test.dart
git commit -m "feat(app): add OfflineLogSyncService with exponential backoff"
```

---

### Task 5: BleBindingService（配网后自动绑定 + 场景 B 一键绑定）

**Files:**
- Create: `inv_app/lib/core/services/ble/ble_binding_service.dart`
- Test: Create `inv_app/test/ble/ble_binding_service_test.dart`

- [ ] **Step 1: 先写失败测试**

Create `inv_app/test/ble/ble_binding_service_test.dart`：

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_binding_service.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockBleDeviceManager extends Mock implements BleDeviceManager {}

class MockBleDeviceKeyStore extends Mock implements BleDeviceKeyStore {}

class MockDio extends Mock implements Dio {}

void main() {
  late MockBleDeviceManager manager;
  late MockBleDeviceKeyStore keyStore;
  late MockDio dio;
  late OfflineOpLogStore logStore;
  late BleBindingService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    manager = MockBleDeviceManager();
    keyStore = MockBleDeviceKeyStore();
    dio = MockDio();
    logStore = OfflineOpLogStore(
      openDb: () async => databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: OfflineOpLogStore.onCreate,
        ),
      ),
    );
    service = BleBindingService(
      manager: manager,
      keyStore: keyStore,
      dio: dio,
      logStore: logStore,
    );
  });

  test('bindAfterProvision: full flow binds and stores key', () async {
    final session = MockBleDeviceSession();
    when(() => manager.connectDevice('AA:BB:CC:DD:EE:FF', autoConnect: any(named: 'autoConnect'), autoReconnect: any(named: 'autoReconnect')))
        .thenAnswer((_) async => session);
    when(() => session.sn).thenReturn('H1CNA6K20001');
    when(() => keyStore.read('H1CNA6K20001')).thenAnswer((_) async => null);
    when(() => dio.post('/devices/bind', data: any())).thenAnswer((_) async {
      return Response(
        requestOptions: RequestOptions(path: '/devices/bind'),
        data: {'code': 0, 'data': {'device_key': 'a2V5LWJhc2U2NA=='}},
      );
    });
    when(() => session.bind('a2V5LWJhc2U2NA==')).thenAnswer((_) async {});
    when(() => keyStore.write('H1CNA6K20001', 'a2V5LWJhc2U2NA=='))
        .thenAnswer((_) async {});

    final outcome = await service.bindAfterProvision(
      macAddress: 'AA:BB:CC:DD:EE:FF',
      knownSn: 'H1CNA6K20001',
    );

    expect(outcome, BindOutcome.bound);
    verify(() => session.bind('a2V5LWJhc2U2NA==')).called(1);
    verify(() => keyStore.write('H1CNA6K20001', 'a2V5LWJhc2U2NA==')).called(1);
    // 绑定日志已记录
    expect(await logStore.pendingCount(), 1);
  });

  test('bindAfterProvision: skips when already bound locally', () async {
    final session = MockBleDeviceSession();
    when(() => manager.connectDevice('AA:BB:CC:DD:EE:FF', autoConnect: any(named: 'autoConnect'), autoReconnect: any(named: 'autoReconnect')))
        .thenAnswer((_) async => session);
    when(() => session.sn).thenReturn('H1CNA6K20001');
    when(() => keyStore.read('H1CNA6K20001')).thenAnswer((_) async => 'existing-key');

    final outcome = await service.bindAfterProvision(
      macAddress: 'AA:BB:CC:DD:EE:FF',
      knownSn: 'H1CNA6K20001',
    );

    expect(outcome, BindOutcome.alreadyBound);
    verifyNever(() => dio.post('/devices/bind', data: any()));
    expect(await logStore.pendingCount(), 0);
  });

  test('bindAfterProvision: server already_bound returns alreadyBound', () async {
    final session = MockBleDeviceSession();
    when(() => manager.connectDevice('AA:BB:CC:DD:EE:FF', autoConnect: any(named: 'autoConnect'), autoReconnect: any(named: 'autoReconnect')))
        .thenAnswer((_) async => session);
    when(() => session.sn).thenReturn('H1CNA6K20001');
    when(() => keyStore.read('H1CNA6K20001')).thenAnswer((_) async => null);
    when(() => dio.post('/devices/bind', data: any())).thenAnswer((_) async {
      return Response(
        requestOptions: RequestOptions(path: '/devices/bind'),
        data: {'code': 5002, 'message': 'device already bound'},
      );
    });

    final outcome = await service.bindAfterProvision(
      macAddress: 'AA:BB:CC:DD:EE:FF',
      knownSn: 'H1CNA6K20001',
    );

    expect(outcome, BindOutcome.alreadyBound);
  });

  test('bindAfterProvision: unauthenticated returns needLogin', () async {
    final session = MockBleDeviceSession();
    when(() => manager.connectDevice('AA:BB:CC:DD:EE:FF', autoConnect: any(named: 'autoConnect'), autoReconnect: any(named: 'autoReconnect')))
        .thenAnswer((_) async => session);
    when(() => session.sn).thenReturn('H1CNA6K20001');
    when(() => keyStore.read('H1CNA6K20001')).thenAnswer((_) async => null);
    when(() => dio.post('/devices/bind', data: any())).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/devices/bind'),
        response: Response(
          requestOptions: RequestOptions(path: '/devices/bind'),
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    final outcome = await service.bindAfterProvision(
      macAddress: 'AA:BB:CC:DD:EE:FF',
      knownSn: 'H1CNA6K20001',
    );

    expect(outcome, BindOutcome.needLogin);
  });
}

// mocktail 无法直接构造 BleDeviceSession 的 mock 子类时使用此辅助；
// BleDeviceSession 为具体类，可被 mocktail mock（见 Task 2 的 Mock 用法）。
class MockBleDeviceSession extends Mock implements BleDeviceSession {}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd inv_app && flutter test test/ble/ble_binding_service_test.dart`
Expected: FAIL（`BleBindingService` undefined）

- [ ] **Step 3: 实现 BleBindingService**

Create `inv_app/lib/core/services/ble/ble_binding_service.dart`：

```dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';

/// 绑定结果（供 UI 提示）
enum BindOutcome { bound, alreadyBound, needLogin, failed }

/// 绑定编排服务（设计文档 §3.2）
///
/// 场景 A（配网后全自动）与场景 B（扫描发现一键确认）共用：
/// 连接 → 确认未绑 → 云端取 device_key → 写 AUTH bind → 本地存 key → 记日志。
class BleBindingService {
  BleBindingService({
    required this.manager,
    required this.keyStore,
    required this.dio,
    required this.logStore,
  });

  final BleDeviceManager manager;
  final BleDeviceKeyStore keyStore;
  final Dio dio;
  final OfflineOpLogStore logStore;

  /// 配网成功后自动绑定（场景 A）
  Future<BindOutcome> bindAfterProvision({
    required String macAddress,
    String? knownSn,
  }) async {
    try {
      final session = await manager.connectDevice(macAddress);
      final sn = knownSn ?? session.sn;
      if (sn == null || sn.isEmpty) {
        return BindOutcome.failed;
      }
      return _bindCore(session, sn);
    } catch (e) {
      if (kDebugMode) debugPrint('[BleBinding] connect failed: $e');
      return BindOutcome.failed;
    }
  }

  /// 内部核心：读 key → 云端绑定 → 写设备 → 存 key → 记日志
  Future<BindOutcome> _bindCore(BleDeviceSession session, String sn) async {
    // 本地已有 key：视为已绑定
    if (await keyStore.read(sn) != null) {
      return BindOutcome.alreadyBound;
    }

    // 云端绑定，获取 device_key
    String deviceKey;
    try {
      final response = await dio.post('/devices/bind', data: {'sn': sn});
      final body = response.data as Map<String, dynamic>;
      if (body['code'] == 5002) {
        return BindOutcome.alreadyBound;
      }
      if (body['code'] != 0) {
        if (kDebugMode) debugPrint('[BleBinding] bind api error: ${body['code']}');
        return BindOutcome.failed;
      }
      deviceKey = (body['data'] as Map<String, dynamic>)['device_key'] as String;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return BindOutcome.needLogin;
      }
      if (kDebugMode) debugPrint('[BleBinding] bind api exception: $e');
      return BindOutcome.failed;
    } catch (e) {
      if (kDebugMode) debugPrint('[BleBinding] bind api exception: $e');
      return BindOutcome.failed;
    }

    // 写入设备 AUTH bind
    try {
      await session.bind(deviceKey);
    } catch (e) {
      if (kDebugMode) debugPrint('[BleBinding] device bind rejected: $e');
      return BindOutcome.failed;
    }

    // 本地持久化 + 操作日志
    await keyStore.write(sn, deviceKey);
    await logStore.add(OfflineOpLog(
      logId: _newLogId(),
      deviceSn: sn,
      action: 'bind',
      params: const {},
      result: 'ok',
      channel: 'cloud',
      opTime: DateTime.now(),
    ));
    return BindOutcome.bound;
  }

  /// 生成同步幂等键（UUID v4）
  static String _newLogId() {
    // 复用 crypto 随机源；格式 8-4-4-4-12 便于服务端正则校验
    final rnd = _RandomUuid();
    return rnd();
  }
}

class _RandomUuid {
  final _random = _SecureRandomShim();
  String call() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

class _SecureRandomShim {
  int nextInt(int max) => DateTime.now().microsecondsSinceEpoch % max;
}
```

> 说明：`_RandomUuid` 仅为避免新增运行时依赖；若 Task 1 已添加 `uuid` 包，可将 `_newLogId()` 替换为 `const Uuid().v4()` 并删除 `_RandomUuid`/`_SecureRandomShim`（推荐，确定性更强）。替换后同步删除本文件中两个私有类。

- [ ] **Step 4: 运行测试确认通过**

Run: `cd inv_app && flutter test test/ble/ble_binding_service_test.dart`
Expected: PASS（4 个用例全部通过）

- [ ] **Step 5: 提交**

```bash
git add inv_app/lib/core/services/ble/ble_binding_service.dart inv_app/test/ble/ble_binding_service_test.dart
git commit -m "feat(app): add BleBindingService for auto bind after provisioning"
```

---

### Task 6: BlePollingService（180s 遥测轮询）

**Files:**
- Create: `inv_app/lib/core/services/ble/ble_polling_service.dart`
- Test: Create `inv_app/test/ble/ble_polling_service_test.dart`

- [ ] **Step 1: 先写失败测试**

Create `inv_app/test/ble/ble_polling_service_test.dart`：

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/ble/ble_polling_service.dart';
import 'package:mocktail/mocktail.dart';

class MockBleDeviceManager extends Mock implements BleDeviceManager {}

class MockBleDeviceSession extends Mock implements BleDeviceSession {}

void main() {
  test('polls ready sessions at interval and emits telemetry', () {
    fakeAsync((async) {
      final manager = MockBleDeviceManager();
      final session = MockBleDeviceSession();
      when(() => session.state).thenReturn(BleDeviceState.ready);
      when(() => session.sn).thenReturn('H1CNA6K20001');
      when(() => session.readTelemetrySnapshot()).thenAnswer(
        (_) async => {'power_w': 3000, 'status': 1},
      );
      when(() => manager.sessions).thenReturn({
        'AA:BB:CC:DD:EE:FF': session,
      });

      final service = BlePollingService(
        manager: manager,
        interval: const Duration(seconds: 180),
      );
      final received = <BlePolledTelemetry>[];
      service.telemetry.listen(received.add);

      service.start();
      async.elapse(const Duration(seconds: 181));

      expect(received, hasLength(1));
      expect(received.first.sn, 'H1CNA6K20001');
      expect(received.first.data['power_w'], 3000);
      expect(service.isRunning, isTrue);

      service.stop();
      async.elapse(const Duration(seconds: 181));
      expect(received, hasLength(1)); // 停止后不再轮询
    });
  });

  test('skips sessions that are not ready', () {
    fakeAsync((async) {
      final manager = MockBleDeviceManager();
      final session = MockBleDeviceSession();
      when(() => session.state).thenReturn(BleDeviceState.connecting);
      when(() => manager.sessions).thenReturn({
        'AA:BB:CC:DD:EE:FF': session,
      });

      final service = BlePollingService(manager: manager);
      final received = <BlePolledTelemetry>[];
      service.telemetry.listen(received.add);

      service.start();
      async.elapse(const Duration(seconds: 181));

      expect(received, isEmpty);
      verifyNever(() => session.readTelemetrySnapshot());
      service.stop();
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd inv_app && flutter test test/ble/ble_polling_service_test.dart`
Expected: FAIL（`BlePollingService` undefined）

- [ ] **Step 3: 实现 BlePollingService**

Create `inv_app/lib/core/services/ble/ble_polling_service.dart`：

```dart
import 'dart:async';

import 'package:inv_app/core/services/ble/ble_device_manager.dart';

/// 一次轮询得到的遥测快照
class BlePolledTelemetry {
  final String sn;
  final Map<String, dynamic> data;

  const BlePolledTelemetry({required this.sn, required this.data});
}

/// 定时轮询已就绪 BLE 会话的遥测快照（设计文档 §3.3）
///
/// 默认 180s；与设备 80s 节拍 notify 推送并存，轮询作为主动拉取兜底。
class BlePollingService {
  BlePollingService({
    required this.manager,
    this.interval = const Duration(seconds: 180),
  });

  final BleDeviceManager manager;
  Duration interval;

  Timer? _timer;
  final _controller = StreamController<BlePolledTelemetry>.broadcast();

  bool get isRunning => _timer?.isActive ?? false;

  /// 轮询遥测流
  Stream<BlePolledTelemetry> get telemetry => _controller.stream;

  void start() {
    if (isRunning) return;
    _timer = Timer.periodic(interval, (_) => _pollOnce());
    _pollOnce();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void setInterval(Duration value) {
    interval = value;
    if (isRunning) {
      _timer?.cancel();
      _timer = Timer.periodic(interval, (_) => _pollOnce());
    }
  }

  Future<void> _pollOnce() async {
    for (final session in manager.sessions.values) {
      if (session.state != BleDeviceState.ready || session.sn == null) {
        continue;
      }
      try {
        final data = await session.readTelemetrySnapshot();
        _controller.add(
          BlePolledTelemetry(sn: session.sn!, data: data),
        );
      } catch (_) {
        // 单设备读取失败不影响其他设备与下一周期
      }
    }
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd inv_app && flutter test test/ble/ble_polling_service_test.dart`
Expected: PASS（2 个用例全部通过）

- [ ] **Step 5: 提交**

```bash
git add inv_app/lib/core/services/ble/ble_polling_service.dart inv_app/test/ble/ble_polling_service_test.dart
git commit -m "feat(app): add BlePollingService with configurable interval"
```

---

### Task 7: BleDirectService（开关聚合：权限 / 扫描 / 自动连接 / 轮询）

**Files:**
- Create: `inv_app/lib/core/services/ble/ble_direct_service.dart`
- Test: Create `inv_app/test/ble/ble_direct_service_test.dart`

- [ ] **Step 1: 先写失败测试**

Create `inv_app/test/ble/ble_direct_service_test.dart`：

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/ble/ble_direct_service.dart';
import 'package:inv_app/core/services/ble/ble_polling_service.dart';
import 'package:mocktail/mocktail.dart';

class MockBleAdapter extends Mock implements BleAdapter {}

class MockBleDeviceManager extends Mock implements BleDeviceManager {}

class MockBlePollingService extends Mock implements BlePollingService {}

class MockStorageService extends Mock implements StorageServiceLike {}

// 最小化存储抽象：仅暴露本服务所需方法（真实 StorageService 见 Task 8 注册）
abstract class StorageServiceLike {
  Future<bool> getIsBleDirectEnabled();
  Future<void> saveIsBleDirectEnabled(bool value);
}

void main() {
  late MockBleAdapter adapter;
  late MockBleDeviceManager manager;
  late MockBlePollingService polling;
  late MockStorageService storage;
  late StreamController<BleAdapterStatus> statusController;

  setUp(() {
    adapter = MockBleAdapter();
    manager = MockBleDeviceManager();
    polling = MockBlePollingService();
    storage = MockStorageService();
    statusController = StreamController<BleAdapterStatus>.broadcast();

    when(() => adapter.status).thenAnswer((_) async => BleAdapterStatus.on);
    when(() => adapter.statusStream).thenAnswer((_) => statusController.stream);
    when(() => storage.getIsBleDirectEnabled()).thenAnswer((_) async => false);
    when(() => storage.saveIsBleDirectEnabled(any())).thenAnswer((_) async {});
    when(() => manager.startAutoConnect()).thenAnswer((_) async {});
    when(() => manager.stopAutoConnect()).thenAnswer((_) async {});
    when(() => manager.disconnectAll()).thenAnswer((_) async {});
  });

  tearDown(() => statusController.close());

  test('setEnabled(true) starts manager and polling', () async {
    final service = BleDirectService(
      adapter: adapter,
      manager: manager,
      polling: polling,
      storage: storage,
    );

    await service.setEnabled(true);

    verify(() => storage.saveIsBleDirectEnabled(true)).called(1);
    verify(() => manager.startAutoConnect()).called(1);
    verify(() => polling.start()).called(1);
    expect(service.enabled, isTrue);

    await service.dispose();
  });

  test('setEnabled(false) stops everything', () async {
    final service = BleDirectService(
      adapter: adapter,
      manager: manager,
      polling: polling,
      storage: storage,
    );
    await service.setEnabled(true);

    await service.setEnabled(false);

    verify(() => manager.stopAutoConnect()).called(1);
    verify(() => manager.disconnectAll()).called(1);
    verify(() => polling.stop()).called(1);
    expect(service.enabled, isFalse);

    await service.dispose();
  });

  test('setEnabled throws when bluetooth off', () async {
    when(() => adapter.status).thenAnswer((_) async => BleAdapterStatus.off);
    final service = BleDirectService(
      adapter: adapter,
      manager: manager,
      polling: polling,
      storage: storage,
    );

    await expectLater(service.setEnabled(true), throwsStateError);
    expect(service.enabled, isFalse);
    await service.dispose();
  });

  test('scan emits unbound candidate devices', () async {
    when(() => adapter.scan(serviceUuids: any(named: 'serviceUuids'), timeout: any(named: 'timeout')))
        .thenAnswer((_) => Stream.fromIterable([
              const BleScanResult(
                macAddress: 'AA:BB:CC:DD:EE:FF',
                name: 'CS-INV-6K2',
                rssi: -60,
                serviceUuids: [BleCtProtocol.serviceUuid],
              ),
            ]));

    final service = BleDirectService(
      adapter: adapter,
      manager: manager,
      polling: polling,
      storage: storage,
    );
    final found = <BleDiscoveredDevice>[];
    service.unboundDevices.listen(found.add);

    await service.setEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(found, hasLength(1));
    expect(found.first.macAddress, 'AA:BB:CC:DD:EE:FF');
    expect(found.first.name, 'CS-INV-6K2');

    await service.dispose();
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd inv_app && flutter test test/ble/ble_direct_service_test.dart`
Expected: FAIL（`BleDirectService` undefined）

- [ ] **Step 3: 实现 BleDirectService**

Create `inv_app/lib/core/services/ble/ble_direct_service.dart`：

```dart
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
  final StorageService storage;

  static const Duration _rescanInterval = Duration(seconds: 30);

  bool _enabled = false;
  Timer? _scanTimer;
  StreamSubscription<BleScanResult>? _scanSub;
  final _enabledController = StreamController<bool>.broadcast();
  final _unboundController =
      StreamController<BleDiscoveredDevice>.broadcast();

  bool get enabled => _enabled;

  Stream<bool> get enabledStream => _enabledController.stream;

  /// 未绑定设备发现流（场景 B：UI 弹一键确认）
  Stream<BleDiscoveredDevice> get unboundDevices =>
      _unboundController.stream;

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
    _scanSub = adapter
        .scan(
          serviceUuids: const [BleCtProtocol.serviceUuid],
          timeout: const Duration(seconds: 15),
        )
        .listen((result) {
      if (!_enabled) return;
      // 已连接会话忽略；未绑定候选交由 UI 确认（场景 B）
      if (manager.sessionOf(result.macAddress) != null) return;
      _unboundController.add(
        BleDiscoveredDevice(
          macAddress: result.macAddress,
          name: result.name,
        ),
      );
    }, onError: (Object e) {
      if (kDebugMode) debugPrint('[BleDirect] scan error: $e');
    });
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
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd inv_app && flutter test test/ble/ble_direct_service_test.dart`
Expected: PASS（4 个用例全部通过）

- [ ] **Step 5: 提交**

```bash
git add inv_app/lib/core/services/ble/ble_direct_service.dart inv_app/test/ble/ble_direct_service_test.dart
git commit -m "feat(app): add BleDirectService aggregating scan/autoconnect/polling"
```

---

### Task 8: StorageService 扩展（BLE 直连开关 + 轮询周期）+ newOfflineLogId()

**目标**：StorageService 抽象类与 SharedPreferences 实现新增 4 个方法；新增 UUID v4 离线日志 ID 工具函数。

- [ ] **Step 1: 写失败测试**

新建 `inv_app/test/core/utils/offline_log_id_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/utils/offline_log_id.dart';

void main() {
  group('newOfflineLogId', () {
    test('生成 UUID v4 格式且唯一', () {
      final id1 = newOfflineLogId();
      final id2 = newOfflineLogId();
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
            .hasMatch(id1),
        isTrue,
      );
      expect(id1, isNot(id2));
    });
  });
}
```

Run: `cd inv_app && flutter test test/core/utils/offline_log_id_test.dart`
Expected: FAIL（`offline_log_id.dart` undefined）。

- [ ] **Step 2: 实现工具函数**

新建 `inv_app/lib/core/utils/offline_log_id.dart`：

```dart
import 'package:uuid/uuid.dart';

/// 生成离线操作日志 ID（UUID v4，服务端按 user_id + log_id 幂等去重）
String newOfflineLogId() => const Uuid().v4();
```

- [ ] **Step 3: 扩展 StorageService 抽象类**

在 `inv_app/lib/core/services/storage_service.dart` 抽象类中追加：

```dart
  Future<bool> getIsBleDirectEnabled();
  Future<void> saveIsBleDirectEnabled(bool value);

  Future<int> getBlePollInterval();
  Future<void> saveBlePollInterval(int seconds);
```

- [ ] **Step 4: 实现 SharedPreferences 存储**

在 `SharedPreferencesStorageService` 实现中追加（shared_prefs 键 `ble_direct_enabled`、`ble_poll_interval`，轮询周期默认 180 秒）：

```dart
  static const _kIsBleDirectEnabled = 'ble_direct_enabled';
  static const _kBlePollInterval = 'ble_poll_interval';

  @override
  Future<bool> getIsBleDirectEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_kIsBleDirectEnabled) ?? false;
  }

  @override
  Future<void> saveIsBleDirectEnabled(bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(_kIsBleDirectEnabled, value);
  }

  @override
  Future<int> getBlePollInterval() async {
    final prefs = await _prefs;
    return prefs.getInt(_kBlePollInterval) ?? 180;
  }

  @override
  Future<void> saveBlePollInterval(int seconds) async {
    final prefs = await _prefs;
    await prefs.setInt(_kBlePollInterval, seconds);
  }
```

> 注：若 `SharedPreferencesStorageService` 内部不是 `_prefs` 字段名，按实际字段调整。实现前先 `grep "class SharedPreferencesStorageService"` 确认。

- [ ] **Step 5: 测试通过 + 全量回归**

Run: `cd inv_app && flutter test test/core/utils/offline_log_id_test.dart && flutter analyze`
Expected: PASS；analyze 无新增告警。

- [ ] **Step 6: 提交**

```bash
git add inv_app/lib/core/services/storage_service.dart inv_app/lib/core/utils/offline_log_id.dart inv_app/test/core/utils/offline_log_id_test.dart
git commit -m "feat(app): extend StorageService with BLE direct toggle & poll interval"
```

---

### Task 9: service_locator 注册 6 个新服务

**目标**：在 `service_locator.dart` 注册 OfflineOpLogStore / OfflineLogApi / OfflineLogSyncService / BleBindingService / BlePollingService / BleDirectService，供页面与 Bloc 通过 `getIt<>()` 获取。

- [ ] **Step 1: 前提检查**

```bash
grep -n "BleDeviceManager\|BleAdapter\|BleDeviceKeyStore" inv_app/lib/core/services/service_locator.dart
```

- 若 BleDeviceManager / BleAdapter / BleDeviceKeyStore **尚未注册**，先在现有注册区（NetworkStatusService 附近）补注册：

```dart
getIt.registerLazySingleton<BleDeviceKeyStore>(
  () => SecureStorageBleDeviceKeyStore(
    storage: getIt<FlutterSecureStorage>(),
  ),
);

getIt.registerLazySingleton<BleAdapter>(() => FlutterBlueUltraAdapter());

getIt.registerLazySingleton<BleDeviceManager>(
  () => BleDeviceManager(adapter: getIt<BleAdapter>()),
  dispose: (manager) => manager.dispose(),
);
```

- 若已注册则跳过。按实际构造函数签名核对（`BleDeviceManager` 构造参数以 `ble_device_manager.dart` 为准）。

- [ ] **Step 2: 注册新服务**

在 NetworkStatusService 注册之后追加：

```dart
getIt.registerLazySingleton<OfflineOpLogStore>(
  () => OfflineOpLogStore(),
  dispose: (store) => store.close(),
);

getIt.registerLazySingleton<OfflineLogApi>(
  () => DioOfflineLogApi(getIt<Dio>()),
);

getIt.registerLazySingleton<OfflineLogSyncService>(
  () => OfflineLogSyncService(
    store: getIt<OfflineOpLogStore>(),
    api: getIt<OfflineLogApi>(),
    networkStatus: getIt<NetworkStatusService>(),
  ),
  dispose: (service) => service.dispose(),
);

getIt.registerLazySingleton<BleBindingService>(
  () => BleBindingService(
    dio: getIt<Dio>(),
    keyStore: getIt<BleDeviceKeyStore>(),
    logStore: getIt<OfflineOpLogStore>(),
  ),
);

getIt.registerLazySingleton<BlePollingService>(
  () => BlePollingService(
    manager: getIt<BleDeviceManager>(),
    keyStore: getIt<BleDeviceKeyStore>(),
    storage: getIt<StorageService>(),
  ),
  dispose: (service) => service.dispose(),
);

getIt.registerLazySingleton<BleDirectService>(
  () => BleDirectService(
    adapter: getIt<BleAdapter>(),
    manager: getIt<BleDeviceManager>(),
    polling: getIt<BlePollingService>(),
    storage: getIt<StorageService>(),
  ),
);
```

> 构造函数参数以 Task 5/6/7 的实现为准；若参数名有差异（如 `networkStatusService`），在注册处对齐。

- [ ] **Step 3: 验证**

Run: `cd inv_app && flutter analyze`
Expected: 无未定义类型告警；若报 `OfflineOpLogStore` 等未定义，说明导入缺失——在 service_locator.dart 顶部补 import。

- [ ] **Step 4: 提交**

```bash
git add inv_app/lib/core/services/service_locator.dart
git commit -m "feat(app): register BLE direct & offline log services in get_it"
```

---

### Task 10: l10n 新增 31 个键（zh / en / getter）

**目标**：为设置页、绑定提示、操作日志页补充国际化字符串。

- [ ] **Step 1: 在 app_zh.dart 追加（Map 末尾，逗号收尾）**

```dart
  // === BLE 直连（设置页）===
  'ble_direct_enabled': '通过 BLE 直连设备',
  'ble_direct_enabled_desc': '打开后通过蓝牙识别并连接逆变器设备，与网络服务并存',
  'ble_direct_on': '已开启 BLE 直连',
  'ble_direct_off': '已关闭 BLE 直连',
  'ble_poll_interval': '轮询周期',
  'ble_poll_interval_desc': '通过 BLE 读取设备遥测数据的间隔',
  'poll_interval_60s': '60 秒',
  'poll_interval_180s': '180 秒',
  'poll_interval_300s': '300 秒',
  'poll_interval_saved': '轮询周期已更新',

  // === 绑定提示 ===
  'ble_binding_in_progress': '正在自动绑定设备…',
  'ble_binding_success': '设备绑定成功',
  'ble_binding_already_bound': '设备已绑定，跳过',
  'ble_binding_need_login': '绑定需要登录，请先登录',
  'ble_binding_failed': '设备绑定失败',
  'ble_bind_confirm_title': '发现新设备',
  'ble_bind_confirm_desc': '检测到未绑定的逆变器设备，是否绑定？',
  'ble_bind_confirm_action': '绑定',

  // === 操作日志页 ===
  'op_logs': '操作日志',
  'op_logs_subtitle': '绑定、控制、参数与升级记录',
  'op_logs_empty': '暂无操作日志',
  'op_log_sync_now': '立即同步',
  'op_log_synced_toast': '离线日志已同步',
  'op_log_sync_failed_toast': '日志同步失败，稍后重试',
  'op_log_sync_status_synced': '已同步',
  'op_log_sync_status_pending': '待同步',
  'op_log_sync_status_syncing': '同步中',
  'op_log_sync_status_failed': '同步失败',
  'op_log_action_bind': '绑定设备',
  'op_log_action_unbind': '解绑设备',
  'op_log_action_control': '下发命令',
  'op_log_action_set_param': '修改参数',
  'op_log_action_ota': 'OTA 升级',
  'op_log_channel_cloud': '云端',
  'op_log_channel_ble': '蓝牙',
  'op_log_created_at': '操作时间',
```

（共 38 个键，含 7 个 action/channel 映射键。）

- [ ] **Step 2: 在 app_en.dart 追加对应英文**

```dart
  // === BLE direct (settings) ===
  'ble_direct_enabled': 'Connect via BLE',
  'ble_direct_enabled_desc': 'Discover and connect inverters over Bluetooth, alongside network services',
  'ble_direct_on': 'BLE direct enabled',
  'ble_direct_off': 'BLE direct disabled',
  'ble_poll_interval': 'Poll interval',
  'ble_poll_interval_desc': 'Interval for reading device telemetry over BLE',
  'poll_interval_60s': '60 seconds',
  'poll_interval_180s': '180 seconds',
  'poll_interval_300s': '300 seconds',
  'poll_interval_saved': 'Poll interval updated',
  'ble_binding_in_progress': 'Binding device…',
  'ble_binding_success': 'Device bound',
  'ble_binding_already_bound': 'Already bound, skipped',
  'ble_binding_need_login': 'Please sign in to bind devices',
  'ble_binding_failed': 'Binding failed',
  'ble_bind_confirm_title': 'New device found',
  'ble_bind_confirm_desc': 'An unbound inverter is detected. Bind it?',
  'ble_bind_confirm_action': 'Bind',
  'op_logs': 'Operation logs',
  'op_logs_subtitle': 'Bind, control, parameter and upgrade history',
  'op_logs_empty': 'No operation logs',
  'op_log_sync_now': 'Sync now',
  'op_log_synced_toast': 'Offline logs synced',
  'op_log_sync_failed_toast': 'Sync failed, retrying later',
  'op_log_sync_status_synced': 'Synced',
  'op_log_sync_status_pending': 'Pending',
  'op_log_sync_status_syncing': 'Syncing',
  'op_log_sync_status_failed': 'Failed',
  'op_log_action_bind': 'Bind device',
  'op_log_action_unbind': 'Unbind device',
  'op_log_action_control': 'Send command',
  'op_log_action_set_param': 'Update parameters',
  'op_log_action_ota': 'OTA upgrade',
  'op_log_channel_cloud': 'Cloud',
  'op_log_channel_ble': 'BLE',
  'op_log_created_at': 'Time',
```

- [ ] **Step 3: app_localizations.dart 追加 getter（`_localizedStrings` 风格）**

```dart
  // BLE 直连
  String get bleDirectEnabled => _localizedStrings['ble_direct_enabled']!;
  String get bleDirectEnabledDesc => _localizedStrings['ble_direct_enabled_desc']!;
  String get bleDirectOn => _localizedStrings['ble_direct_on']!;
  String get bleDirectOff => _localizedStrings['ble_direct_off']!;
  String get blePollInterval => _localizedStrings['ble_poll_interval']!;
  String get blePollIntervalDesc => _localizedStrings['ble_poll_interval_desc']!;
  String get pollIntervalSaved => _localizedStrings['poll_interval_saved']!;

  // 绑定提示
  String get bleBindingInProgress => _localizedStrings['ble_binding_in_progress']!;
  String get bleBindingSuccess => _localizedStrings['ble_binding_success']!;
  String get bleBindingAlreadyBound => _localizedStrings['ble_binding_already_bound']!;
  String get bleBindingNeedLogin => _localizedStrings['ble_binding_need_login']!;
  String get bleBindingFailed => _localizedStrings['ble_binding_failed']!;
  String get bleBindConfirmTitle => _localizedStrings['ble_bind_confirm_title']!;
  String get bleBindConfirmDesc => _localizedStrings['ble_bind_confirm_desc']!;
  String get bleBindConfirmAction => _localizedStrings['ble_bind_confirm_action']!;

  // 操作日志页
  String get opLogs => _localizedStrings['op_logs']!;
  String get opLogsSubtitle => _localizedStrings['op_logs_subtitle']!;
  String get opLogsEmpty => _localizedStrings['op_logs_empty']!;
  String get opLogSyncNow => _localizedStrings['op_log_sync_now']!;
  String get opLogSyncedToast => _localizedStrings['op_log_synced_toast']!;
  String get opLogSyncFailedToast => _localizedStrings['op_log_sync_failed_toast']!;
  String get opLogCreatedAt => _localizedStrings['op_log_created_at']!;

  // 状态映射（供日志页复用）
  String opLogSyncStatus(String status) {
    switch (status) {
      case 'synced': return _localizedStrings['op_log_sync_status_synced']!;
      case 'syncing': return _localizedStrings['op_log_sync_status_syncing']!;
      case 'failed': return _localizedStrings['op_log_sync_status_failed']!;
      default: return _localizedStrings['op_log_sync_status_pending']!;
    }
  }

  String opLogAction(String action) {
    switch (action) {
      case 'bind': return _localizedStrings['op_log_action_bind']!;
      case 'unbind': return _localizedStrings['op_log_action_unbind']!;
      case 'control': return _localizedStrings['op_log_action_control']!;
      case 'set_param': return _localizedStrings['op_log_action_set_param']!;
      case 'ota': return _localizedStrings['op_log_action_ota']!;
      default: return action;
    }
  }

  String opLogChannel(String channel) => channel == 'ble'
      ? _localizedStrings['op_log_channel_ble']!
      : _localizedStrings['op_log_channel_cloud']!;
```

- [ ] **Step 4: 验证**

Run: `cd inv_app && flutter analyze`
Expected: 无告警（getter 全部有对应键；`!` 断言安全——zh/en 均含全部键）。

- [ ] **Step 5: 提交**

```bash
git add inv_app/lib/l10n/app_zh.dart inv_app/lib/l10n/app_en.dart inv_app/lib/l10n/app_localizations.dart
git commit -m "feat(app): add l10n keys for BLE direct mode & operation logs"
```

---

### Task 11: 设置页新增「通过 BLE 直连设备」开关 + 轮询周期对话框

**目标**：在 `settings_page.dart` 新增 SwitchListTile（参考现有 `_toggleLocalMode` 模式），开启时调用 `BleDirectService.setEnabled(true)`；新增轮询周期选择对话框（60/180/300s）。

- [ ] **Step 1: 状态字段与加载**

在 `_SettingsPageState` 中追加字段（参考 `_isLocalMode`）：

```dart
  bool _isBleDirectEnabled = false;
  int _blePollInterval = 180;
```

`initState` / 现有 `_loadSettings()`（或等价方法）中加载：

```dart
    final bleDirect = await _storage.getIsBleDirectEnabled();
    final pollInterval = await _storage.getBlePollInterval();
    if (mounted) {
      setState(() {
        _isBleDirectEnabled = bleDirect;
        _blePollInterval = pollInterval;
      });
    }
```

- [ ] **Step 2: 开关处理器（参考 `_toggleLocalMode`）**

```dart
  Future<void> _toggleBleDirect(bool value) async {
    await _storage.saveIsBleDirectEnabled(value);
    // 打开/关闭聚合服务（校验蓝牙权限 → 自动连接 → 轮询；关闭 → 断开全部）
    await getIt<BleDirectService>().setEnabled(value);
    if (!mounted) return;
    setState(() => _isBleDirectEnabled = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value ? l10n.bleDirectOn : l10n.bleDirectOff)),
    );
  }

  Future<void> _showPollIntervalDialog() async {
    final options = [60, 180, 300];
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.blePollInterval),
        children: options.map((seconds) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, seconds),
            child: Text(
              seconds == 60
                  ? l10n.str('poll_interval_60s')
                  : seconds == 180
                      ? l10n.str('poll_interval_180s')
                      : l10n.str('poll_interval_300s'),
            ),
          );
        }).toList(),
      ),
    );
    if (selected == null || !mounted) return;
    await _storage.saveBlePollInterval(selected);
    getIt<BlePollingService>().setInterval(Duration(seconds: selected));
    setState(() => _blePollInterval = selected);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.pollIntervalSaved)),
    );
  }
```

- [ ] **Step 3: UI 插入（在现有 localMode SwitchListTile 附近）**

```dart
            SwitchListTile(
              title: Text(l10n.bleDirectEnabled),
              subtitle: Text(l10n.bleDirectEnabledDesc),
              value: _isBleDirectEnabled,
              onChanged: _toggleBleDirect,
            ),
            ListTile(
              title: Text(l10n.blePollInterval),
              subtitle: Text(l10n.blePollIntervalDesc),
              trailing: Text(
                '$_blePollInterval s',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              onTap: _showPollIntervalDialog,
            ),
```

- [ ] **Step 4: 恢复默认设置同步处理**

在现有「恢复默认」逻辑（`saveIsLocalMode(false)` 附近）追加：

```dart
            await _storage.saveIsBleDirectEnabled(false);
            await _storage.saveBlePollInterval(180);
            await getIt<BleDirectService>().setEnabled(false);
            _isBleDirectEnabled = false;
            _blePollInterval = 180;
```

- [ ] **Step 5: 验证**

Run: `cd inv_app && flutter analyze`
Expected: 无告警（`getIt<BleDirectService>()` / `getIt<BlePollingService>()` 依赖 Task 9 注册；若 `l10n` 局部变量未在方法内声明，按文件内现有用法获取）。

- [ ] **Step 6: 提交**

```bash
git add inv_app/lib/features/profile/presentation/pages/settings_page.dart
git commit -m "feat(app): add BLE direct toggle & poll interval dialog to settings"
```

---

### Task 12: 配网成功后自动绑定（场景 A）

**目标**：`wifi_config_page.dart` 的 `_onBleProvisionSuccess()`（约 629 行）在配网成功时触发 `BleBindingService.bindAfterProvision()`，全自动零操作。

- [ ] **Step 1: 前提确认**

- `_selectedBleDevice`（`BleDeviceInfo?`，含 `sn` / `macAddress`）在 BLE 配网流程中已记录——见 `ble_provisioning_service.dart` 的 `BleDeviceInfo`。
- `_provisionSuccess` 状态位在 `_onBleProvisionSuccess()` 中置 true（629-637 行）。

- [ ] **Step 2: 改造 `_onBleProvisionSuccess()`**

在现有 setState 之后追加自动绑定调用（不阻塞成功页展示，fire-and-forget + 结果提示）：

```dart
  void _onBleProvisionSuccess() {
    if (!mounted) return;
    setState(() {
      _provisioning = false;
      _provisionSuccess = true;
      _bleErrorMessage = null;
    });
    _triggerAutoBind();
  }

  /// 场景 A：配网成功后自动绑定（零操作）
  Future<void> _triggerAutoBind() async {
    final device = _selectedBleDevice;
    if (device == null) return;
    if (!await getIt<StorageService>().getIsBleDirectEnabled()) return;
    final binding = getIt<BleBindingService>();
    final outcome = await binding.bindAfterProvision(
      macAddress: device.macAddress,
      knownSn: device.sn,
    );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final message = switch (outcome) {
      BindOutcome.bound => l10n.bleBindingSuccess,
      BindOutcome.alreadyBound => l10n.bleBindingAlreadyBound,
      BindOutcome.needLogin => l10n.bleBindingNeedLogin,
      BindOutcome.failed => l10n.bleBindingFailed,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
```

> 说明：`bindAfterProvision` 内部（Task 5 已实现）：本地 key 存在则直接 `alreadyBound`；否则云端 `POST /devices/bind`（带 device_key 响应）→ `session.bind()` → 写 SecureStorage → 记离线日志（action=bind, channel=cloud）。

- [ ] **Step 3: 验证**

Run: `cd inv_app && flutter analyze`
Expected: 无告警（需 import `ble_binding_service.dart`、`service_locator.dart`、`app_localizations.dart`——后者已存在）。

- [ ] **Step 4: 提交**

```bash
git add inv_app/lib/features/device/presentation/pages/wifi_config_page.dart
git commit -m "feat(app): auto-bind device after BLE provisioning success"
```

---

### Task 13: 解绑副作用（清本地 key + 记日志）+ 设备详情页日志入口

**目标**：云端解绑成功后清除本地 BLE 凭证并记录 unbind 离线日志；`device_edit_page.dart` 新增「操作日志」入口。

- [ ] **Step 1: device_bloc 解绑副作用**

`device_bloc.dart` 的 `_onUnbindRequested`（284-294 行）success 分支追加清理逻辑：

```dart
  Future<void> _onUnbindRequested(
    DeviceUnbindRequested event,
    Emitter<DeviceState> emit,
  ) async {
    emit(DeviceLoading());
    final result = await repository.unbind(event.sn);
    result.fold(
      (failure) => emit(DeviceError(message: failure.message)),
      (_) async {
        // 解绑副作用：清本地 BLE 凭证 + 记录解绑操作日志
        await getIt<BleDeviceKeyStore>().deleteKey(event.sn);
        await getIt<OfflineOpLogStore>().add(
          sn: event.sn,
          action: 'unbind',
          params: {},
          channel: 'cloud',
        );
        emit(DeviceUnbindSuccess());
      },
    );
  }
```

> 若 Bloc 中不便直接 `getIt`，可改为在构造器注入 `BleDeviceKeyStore` 与 `OfflineOpLogStore`（推荐后者，测试更友好）；两者均可，执行时按现有 Bloc 依赖注入风格选择。

- [ ] **Step 2: 同步单测**

若 `device_bloc_test.dart` 存在且覆盖 unbind 场景：mock 注入的 `BleDeviceKeyStore` / `OfflineOpLogStore`，断言 unbind 成功后 `deleteKey` 与 `add` 各调用一次。

- [ ] **Step 3: 设备详情页日志入口**

`device_edit_page.dart` 中现有 unbind ListTile（约 98 行）上方插入：

```dart
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(l10n.opLogs),
              subtitle: Text(l10n.opLogsSubtitle),
              onTap: () => context.push('/device/op-logs/${sn}'),
            ),
```

> `context.push` 依赖 go_router（`app_router.dart` 已用 GoRoute）；若页面已通过 `context.push` 跳转（如编辑/OTA 页），直接复用；`sn` 取页面持有的设备 SN 字段（`widget.sn` 或等价）。路由注册在 Task 14 完成，本步先写入口（analyze 会因路由未注册通过——go_router 的 `push` 是运行时解析，编译期不报错）。

- [ ] **Step 4: 验证**

Run: `cd inv_app && flutter analyze && flutter test`
Expected: 无告警；既有测试全绿。

- [ ] **Step 5: 提交**

```bash
git add inv_app/lib/features/device/presentation/bloc/device_bloc.dart inv_app/lib/features/device/presentation/pages/device_edit_page.dart
git commit -m "feat(app): clear BLE key & log unbind; add op-log entry in device edit"
```

---

### Task 14: 操作日志页 + 路由注册

**目标**：新建 `device_op_logs_page.dart`（按 SN 展示本地离线操作日志 + 状态过滤 + 立即同步）；在 `app_router.dart` 注册 `/device/op-logs/:sn`。

- [ ] **Step 1: 写失败测试（页面 smoke）**

新建 `inv_app/test/features/device/device_op_logs_page_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/device/presentation/pages/device_op_logs_page.dart';

void main() {
  testWidgets('DeviceOpLogsPage 可构建', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DeviceOpLogsPage(sn: 'TEST-SN-001')),
    );
    expect(find.byType(DeviceOpLogsPage), findsOneWidget);
  });
}
```

Run: `cd inv_app && flutter test test/features/device/device_op_logs_page_test.dart`
Expected: FAIL（页面 undefined）。

- [ ] **Step 2: 实现页面**

新建 `inv_app/lib/features/device/presentation/pages/device_op_logs_page.dart`（结构参考现有列表页：Scaffold + AppBar + RefreshIndicator + ListView；核心逻辑约 180 行）：

```dart
import 'package:flutter/material.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';
import 'package:inv_app/core/services/offline/offline_log_sync_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class DeviceOpLogsPage extends StatefulWidget {
  const DeviceOpLogsPage({super.key, required this.sn});
  final String sn;

  @override
  State<DeviceOpLogsPage> createState() => _DeviceOpLogsPageState();
}

class _DeviceOpLogsPageState extends State<DeviceOpLogsPage> {
  final _store = getIt<OfflineOpLogStore>();
  final _syncService = getIt<OfflineLogSyncService>();
  List<OfflineOpLog> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs = await _store.listBySn(widget.sn, limit: 200);
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  Future<void> _syncNow() async {
    final synced = await _syncService.syncNow();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(synced ? l10n.opLogSyncedToast : l10n.opLogSyncFailedToast)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.opLogs),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: l10n.opLogSyncNow,
            onPressed: _syncNow,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? Center(child: Text(l10n.opLogsEmpty))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _logs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      return ListTile(
                        leading: Icon(
                          log.action == 'ota'
                              ? Icons.system_update
                              : log.action == 'control'
                                  ? Icons.touch_app
                                  : log.action == 'set_param'
                                      ? Icons.tune
                                      : log.action == 'unbind'
                                          ? Icons.link_off
                                          : Icons.link,
                        ),
                        title: Text(l10n.opLogAction(log.action)),
                        subtitle: Text(
                          '${l10n.opLogChannel(log.channel)} · '
                          '${l10n.opLogSyncStatus(log.syncStatus)} · '
                          '${log.createdAt.toLocal()}',
                        ),
                        trailing: _StatusChip(status: log.syncStatus),
                      );
                    },
                  ),
                ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (color, label) = switch (status) {
      'synced' => (Colors.green, l10n.opLogSyncStatus('synced')),
      'syncing' => (Colors.blue, l10n.opLogSyncStatus('syncing')),
      'failed' => (Colors.red, l10n.opLogSyncStatus('failed')),
      _ => (Colors.orange, l10n.opLogSyncStatus('pending')),
    };
    return Chip(
      label: Text(label, style: TextStyle(fontSize: 11, color: color)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
```

> 依赖确认：`OfflineOpLog` 实体字段（sn/action/channel/createdAt/syncStatus）与 `OfflineOpLogStore.listBySn(sn, {limit})` 方法签名以 Task 3 实现为准；若字段名不同（如 `syncedAt`），在页面处对齐。

- [ ] **Step 3: 路由注册**

`app_router.dart` 在 ShellRoute 之后（如 `/ota` 附近）追加：

```dart
      GoRoute(
        path: '/device/op-logs/:sn',
        name: 'deviceOpLogs',
        pageBuilder: (context, state) => _slidePage(
          state,
          DeviceOpLogsPage(sn: state.pathParameters['sn']!),
        ),
      ),
```

并在文件顶部 import `device_op_logs_page.dart`。

- [ ] **Step 4: 验证**

Run: `cd inv_app && flutter test test/features/device/device_op_logs_page_test.dart && flutter analyze`
Expected: PASS；analyze 无告警。

- [ ] **Step 5: 提交**

```bash
git add inv_app/lib/features/device/presentation/pages/device_op_logs_page.dart inv_app/lib/core/router/app_router.dart inv_app/test/features/device/device_op_logs_page_test.dart
git commit -m "feat(app): add operation log page & route"
```

---

### Task 15: 启动恢复 + 全量验证 + 自审记录

**目标**：App 启动时恢复 BLE 直连模式（开关打开则自动连接+轮询）并启动离线日志同步；全量验证；记录自审结论。

- [ ] **Step 1: 启动恢复**

在启动流程中（`main.dart` 初始化完成后或 `SplashPage` 登录态恢复后，选现有主流程插入点）追加：

```dart
    // 恢复 BLE 直连模式（设置开关为开时）
    final storage = getIt<StorageService>();
    if (await storage.getIsBleDirectEnabled()) {
      await getIt<BleDirectService>().restore();
    }
    // 启动离线操作日志同步（监听网络状态，自动退避重试）
    getIt<OfflineLogSyncService>().start();
```

> `BleDirectService.restore()`（Task 7 已实现）负责幂等恢复：已启用则跳过，未启用但配置为开则执行 `setEnabled(true)` 流程。

- [ ] **Step 2: 全量验证**

```bash
cd inv_app && flutter pub get
flutter analyze
flutter test
```

Expected: analyze 0 告警；全部测试 PASS（含新增：offline_log_id / offline_op_log_store / offline_log_sync_service / ble_binding_service / ble_polling_service / ble_direct_service / ble_device_session / device_op_logs_page）。

```bash
cd .. && make analyze-app
```

Expected: PASS（与 flutter analyze 等价；若 Makefile 目标名不同按实际执行）。

- [ ] **Step 3: 手动冒烟（可选，需真机）**

1. 设置 → 打开「通过 BLE 直连设备」→ 观察扫描/自动连接/180s 轮询遥测刷新。
2. 配网流程 → 配网成功后自动绑定（SnackBar 提示绑定结果）。
3. 飞行模式 → 控制命令走 BLE 兜底（本计划范围外，见自审）→ 操作日志记入本地 → 恢复网络 → 自动同步。
4. 设备详情 → 操作日志 → 查看/立即同步。

- [ ] **Step 4: 提交**

```bash
git add inv_app/lib/main.dart
# 如插入点在 SplashPage 则：
git add inv_app/lib/features/auth/presentation/pages/splash_page.dart
```

按实际插入文件提交。

---

## 自审记录（plan 完成时填写）

### Spec 覆盖核对

| 设计文档章节 | 计划 Task | 状态 |
|---|---|---|
| §3.1 设置开关「通过 BLE 直连设备」 | Task 11 | ✅ |
| §3.2 场景 A 配网后自动绑定 | Task 12 | ✅ |
| §3.3 场景 B 扫描发现一键确认（防抢绑） | Task 5（bindAfterProvision 支持 unbound 流，页面确认入口未做） | ⚠️ 见范围说明 |
| §3.4 180s 轮询（60/180/300 可配） | Task 6 / Task 11 | ✅ |
| §3.5 离线操作日志（sqflite 本地 + 状态机） | Task 3 | ✅ |
| §3.6 自动同步 + 指数退避（30s/1m/5m/15m/60m） | Task 4 | ✅ |
| §3.7 控制命令 HTTP 优先、BLE 仅离线兜底 | 未列入本计划 | ⚠️ 见范围说明 |
| §3.8 操作日志入口（设备详情页） | Task 13 | ✅ |
| §3.9 解绑：云端解绑 + 清本地 key + 记日志 | Task 13 | ✅ |
| §4 后端扩展（device_key 下发、offline-logs 接口） | 后端计划 Task 1-7 | ✅ |
| §5.2 固件修订清单 | 后端/App 计划未覆盖 | ⚠️ 固件团队交付 |
| §6 协议修订（TELEMETRY Read 权限、时间校准） | 固件侧 + Task 2 协议字段 | ⚠️ 见范围说明 |

### 范围说明

1. **控制通道 BLE 兜底**（`device_control_page._sendCommand` 离线分支）为**后续独立任务**，不在本计划内——本计划仅完成通道基础设施（会话/鉴权/轮询/日志）。
2. **场景 B 一键确认 UI**（扫描发现未绑定设备弹窗）依赖 `BleDirectService.unboundDevices` 流（Task 7 已提供数据源），页面入口另行排期。
3. **固件修订**（TELEMETRY Read 权限、时间校准 NVS）由固件团队按设计文档 §5/§6 执行，App 端协议字段已在 Task 2 对齐。
4. **控制命令离线日志**：`_sendCommand` 的日志埋点（action=control / set_param / ota）需在后续控制通道任务中一并完成；本计划已在 Task 13 完成 bind/unbind 两类日志。

### 类型一致性核对

- `OfflineOpLogStore.listBySn` / `OfflineOpLog` 字段：Task 3 定义 → Task 14 页面消费，已对齐；若实现时字段名调整，同步更新 Task 14 示例代码。
- `BleDirectService.restore()`：Task 7 定义 → Task 15 调用，签名已对齐。
- `BlePollingService.setInterval(Duration)`：Task 6 定义 → Task 11 调用，已对齐。
- `BleBindingService.bindAfterProvision(macAddress, knownSn)` / `BindOutcome`：Task 5 定义 → Task 12 调用，已对齐。
- `OfflineLogSyncService.syncNow()` 返回 `Future<bool>`：Task 4 定义 → Task 14 调用，已对齐。
- l10n：Task 10 定义的 38 键与 getter，Task 11/12/14 消费，zh/en 双语齐备。
 DI：Task 9 注册 6 个新服务，Task 11/12/14/15 通过 `getIt` 获取，类型均已在注册表内。

---

## 附录 B：PIN 方案修订（2026-08-10 定稿）

> 设计文档已更新（§1.2 决策表 +11/12 行、§3.2 双场景、§4.1 登记制、§5.4 PIN 机制、§6 修订③、§7.1/§8/§9）。本附录列出对本计划的**差异修订**，执行时按附录优先。

### 核心变化

1. **device_key 由 App 本地生成**（32B 随机 Base64）——绑定不再依赖云端生成，**完全离网可用**。
2. **绑定无需登录态**（离线可用）；联网后补登记 `POST /devices/bind{sn, device_key}`（需登录，401 则待登录后补）。
3. **PIN 双入口**：配网（写 WiFi 凭据前 AUTH `{mode:"pin_check", pin}`）+ 场景 B 绑定（bind 消息带 pin）。**App 不持有 PRODUCT_SECRET**，PIN 仅透传用户输入，校验权威在设备端。
4. `BindOutcome` 增加 `invalidPin` / `locked`；移除 `needLogin` 作为绑定前置（仅影响补登记）。

### 受影响 Task 及修订

#### Task 2（BleDeviceSession 协议扩展）修订

- AUTH 支持 `pin_check` 模式：新增 `checkPin(String pin)` 方法（写 AUTH `{mode:"pin_check", pin}` → 等待 notify `{result:"ok"/"rejected"}`）；`_onAuthNotify` 分支增加 `'pin_check'`。
- `bind(...)` 方法签名增加可选 `pin` 参数：`bind(String deviceKey, {String? pin, DateTime? issuedAt})`——场景 B 传 pin，场景 A 不传（配网已验证）。
- 测试用例增加：pin_check 成功/失败/锁定（rejected:locked）3 例。

#### Task 5（BleBindingService）修订

- 新增 App 端 key 生成（`dart:math` `Random.secure()`，32 字节 → Base64）：

```dart
String generateDeviceKey() {
  final rand = Random.secure();
  final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
  return base64Encode(bytes);
}
```

- `bindAfterProvision` 签名修订（场景 B 带 pin；场景 A 从配网页经 `_triggerAutoBind` 调用时 pin 传 null）：

```dart
enum BindOutcome { bound, alreadyBound, invalidPin, locked, needLoginForSync, failed }

Future<BindOutcome> bindAfterProvision({
  required String macAddress,
  String? knownSn,
  String? pin, // 场景 B 必传；场景 A 配网已验 PIN 传 null
}) async {
  // 1. 本地已有 key → alreadyBound
  // 2. 读 INFO：bound=true → alreadyBound；bound=false 继续
  // 3. 生成 device_key（本地，离网可用）
  // 4. AUTH bind{device_key, pin?, issued_at}（pin 非空则设备端同时校验 PIN）
  //    → notify rejected:invalid_pin → invalidPin
  //    → notify rejected:locked → locked
  // 5. 存 secure_storage + 记日志（action=bind, channel=ble）
  // 6. 尝试联网补登记 POST /devices/bind{SN, device_key}（401 → needLoginForSync，等待同步服务重试）
  // 7. → bound
}
```

- `_bindCore` 相应调整：移除登录态前置；云端 bind 调用从"取 key"改为"补登记"。
- 测试用例更新：PIN 错误分支（invalidPin）、锁定分支（locked）、离网绑定成功（无网络时仍 bound）、补登记 401 → needLoginForSync。

#### Task 10（l10n）追加键（zh/en 双写，约 9 个）

```dart
  'pin_input_title': '输入设备 PIN 码',
  'pin_input_hint': 'PIN 码见设备铭牌（6 位数字）',
  'pin_input_confirm': '确认',
  'pin_invalid': 'PIN 码错误，请重新输入',
  'pin_locked': '错误次数过多，设备已锁定 30 分钟',
  'pin_check_failed': 'PIN 校验失败',
  'bind_registered_later': '绑定成功，联网后自动同步',
  'ble_binding_need_login'（现有键改为）: '绑定已保存，登录后自动同步',
  'pin_required': '请输入 PIN 码后再试',
```

（en 对照：`PIN required` / `Enter the 6-digit PIN from the device nameplate` / `Invalid PIN, try again` / `Too many attempts, device locked for 30 minutes` / `Bound offline, will sync when online` 等）

#### Task 12（配网页自动绑定）修订

- 配网流程（BLE 模式）新增 **PIN 输入步骤**（写 WiFi 凭据前）：
  - UI：`_provisionStep` 流程中插入 PIN 输入框（6 位数字键盘），或复用现有 BLE 步骤卡片
  - 逻辑：`_provisionService.startProvision(...)` 前先 `session.checkPin(pin)`，失败提示 `l10n.pinInvalid` / `l10n.pinLocked`，不进入配网
- `_triggerAutoBind()` 更新：移除登录态检查；调用 `bindAfterProvision(macAddress: ..., knownSn: ..., pin: null)`（配网已验）；结果提示按新 BindOutcome 映射。

#### 其余 Task

Task 1（依赖）/ Task 3/4（日志存储与同步）/ Task 6/7（轮询与聚合）/ Task 8（StorageService）/ Task 9（DI）/ Task 11（设置页）/ Task 13（解绑）/ Task 14（日志页）/ Task 15（启动恢复）**不受影响**，按原计划执行。

### 安全约束（新增）

- **App 代码不包含 PRODUCT_SECRET**（不实现 compute_pin），仅透传用户输入——App 反编译无法提取密钥。
- 场景 B 无 PIN 无法绑定（设备端拒绝）；锁定期间设备端返回 rejected:locked，App 提示等待。

### 自审补充

- 绑定全链路离网：生成 key → 写设备 → 存本地 ✅；补登记延迟联网 ✅
- 登录态不再是绑定前置（仅补登记/日志同步需要）✅
- l10n 键总量 38 + 9 = 47（zh/en 齐备）✅
```
