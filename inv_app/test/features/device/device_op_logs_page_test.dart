import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/offline/offline_log_sync_service.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';
import 'package:inv_app/features/device/presentation/pages/device_op_logs_page.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/pump_app.dart';

class MockOfflineOpLogStore extends Mock implements OfflineOpLogStore {}

class MockOfflineLogSyncService extends Mock
    implements OfflineLogSyncService {}

void main() {
  late MockOfflineOpLogStore store;
  late MockOfflineLogSyncService syncService;

  setUp(() {
    store = MockOfflineOpLogStore();
    syncService = MockOfflineLogSyncService();
    when(
      () => store.listBySn(any(), limit: any(named: 'limit')),
    ).thenAnswer((_) async => <OfflineOpLog>[]);
    when(() => store.pendingCount()).thenAnswer((_) async => 0);
    when(() => syncService.syncNow()).thenAnswer((_) async {});
  });

  Widget buildPage() => DeviceOpLogsPage(
        sn: 'TEST-SN-001',
        store: store,
        syncService: syncService,
      );

  testWidgets('空态可构建：AppBar 标题 + 空态文案', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));

    await pumpMinimalApp(tester, buildPage());

    expect(find.text(l10n.opLogs), findsOneWidget);
    expect(find.text(l10n.opLogsEmpty), findsOneWidget);
    expect(find.byIcon(Icons.sync), findsOneWidget);
  });

  testWidgets('含日志时渲染列表项与状态 Chip', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    final log = OfflineOpLog(
      logId: 'l1',
      deviceSn: 'TEST-SN-001',
      action: 'unbind',
      opTime: DateTime(2026, 8, 10, 12, 30),
      syncStatus: 'synced',
    );
    when(
      () => store.listBySn(any(), limit: any(named: 'limit')),
    ).thenAnswer((_) async => [log]);

    await pumpMinimalApp(tester, buildPage());

    expect(find.text(l10n.opLogAction('unbind')), findsOneWidget);
    expect(find.byType(ListTile), findsOneWidget);
    final chip = find.descendant(
      of: find.byType(Chip),
      matching: find.text(l10n.opLogSyncStatus('synced')),
    );
    expect(chip, findsOneWidget);
  });

  testWidgets('点击同步按钮触发 syncNow 并展示 toast', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    when(() => store.pendingCount()).thenAnswer((_) async => 1);

    await pumpMinimalApp(tester, buildPage());
    await tester.tap(find.byIcon(Icons.sync));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => syncService.syncNow()).called(1);
    expect(find.text(l10n.opLogSyncedToast), findsOneWidget);

    // 推进 SnackBar 生命周期，避免遗留 pending timer
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
  });
}
