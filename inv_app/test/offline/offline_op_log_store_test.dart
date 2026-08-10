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
    // sqflite 对同一 path（含 :memory:）默认单例缓存：先清理上一用例
    // 残留的内存库，否则后续用例会命中旧数据触发 UNIQUE 冲突。
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
