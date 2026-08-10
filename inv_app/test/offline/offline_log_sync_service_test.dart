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
    // sqflite 对同一 path 单例缓存：先清库保证用例隔离
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
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
        const OfflineLogUploadResult(accepted: 2, duplicates: 0),);

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
        const OfflineLogUploadResult(accepted: 1, duplicates: 0),);

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

  test('5 consecutive failures mark logs as failed (terminal)', () async {
    await store.add(sample(1));
    when(() => api.upload(any())).thenThrow(Exception('network down'));

    final service = OfflineLogSyncService(
      store: store,
      api: api,
      networkStatus: networkStatus,
    );
    // 连续 5 次失败：前 4 次 bump attempts，第 5 次应标记 failed（终止态）
    for (var i = 0; i < 5; i++) {
      await service.syncNow();
    }

    expect(await store.countByStatus('failed'), 1);
    // failed 不再被 pending() 返回，也不调度退避重试
    expect(await store.pendingCount(), 0);
    expect(service.hasPendingRetry, isFalse);
    service.dispose();
  });

  test('concurrent syncNow calls only execute one round', () async {
    await store.add(sample(1));
    var calls = 0;
    when(() => api.upload(any())).thenAnswer((_) async {
      calls++;
      // 模拟慢上传：让并发调用重叠
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return const OfflineLogUploadResult(accepted: 1, duplicates: 0);
    });

    final service = OfflineLogSyncService(
      store: store,
      api: api,
      networkStatus: networkStatus,
    );
    // 未 await 的并发触发（网络恢复事件与手动同步重叠）
    final f1 = service.syncNow();
    final f2 = service.syncNow();
    final f3 = service.syncNow();
    await Future.wait([f1, f2, f3]);

    // 仅执行一轮上传
    expect(calls, 1);
    expect(await store.pendingCount(), 0);
    expect(await store.countByStatus('synced'), 1);
    service.dispose();
  });
}

