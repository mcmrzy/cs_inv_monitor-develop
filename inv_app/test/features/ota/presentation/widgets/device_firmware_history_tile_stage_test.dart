import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_history.dart';
import 'package:inv_app/features/ota/presentation/widgets/device_firmware_history_tile.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 「升级中」分阶段展示：设备上报的原始阶段(device_upgrades.stage)让用户看清
/// 是在下载 / 校验 / 写入设备 / 重启生效，而不是笼统的「升级中」。
void main() {
  Widget host(DeviceFirmwareHistory item) => MaterialApp(
        locale: const Locale('zh'),
        theme: ThemeData.light(useMaterial3: true),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          builder: (_, __) => Scaffold(
            body: SizedBox(
              width: 340,
              child: DeviceFirmwareHistoryTile(item: item),
            ),
          ),
        ),
      );

  DeviceFirmwareHistory item({
    required String status,
    required String stage,
    int progress = 84,
    int? stageProgress,
    int? overallProgress,
  }) =>
      DeviceFirmwareHistory(
        id: 1,
        deviceSn: 'H1ZZX0013900001P',
        firmwareId: 10,
        target: 'arm',
        oldVersion: '1.0.0',
        firmwareVersion: '1.1.0',
        status: status,
        stage: stage,
        progress: progress,
        stageProgress: stageProgress,
        overallProgress: overallProgress,
        changelog: '',
        updatedAt: DateTime(2026, 9, 14, 10, 0),
      );

  testWidgets('stage=installing 时显示「写入设备」', (tester) async {
    await tester
        .pumpWidget(host(item(status: 'upgrading', stage: 'installing')));
    // ScreenUtilInit 的 child 延后一帧构建，需再 pump 一次才进树
    await tester.pumpAndSettle();
    expect(find.text('写入设备'), findsOneWidget);
  });

  testWidgets('stage=rebooting 时显示「重启生效」', (tester) async {
    await tester
        .pumpWidget(host(item(status: 'upgrading', stage: 'rebooting')));
    await tester.pumpAndSettle();
    expect(find.text('重启生效'), findsOneWidget);
  });

  testWidgets('stage=receiving is transfer, never downloading', (tester) async {
    await tester
        .pumpWidget(host(item(status: 'upgrading', stage: 'receiving')));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(DeviceFirmwareHistoryTile)),
    )!;
    expect(find.text(l10n.transferring), findsOneWidget);
    expect(find.text('下载固件'), findsNothing);
  });

  testWidgets('explicit transfer zero is separate from overall 70',
      (tester) async {
    await tester.pumpWidget(
      host(
        item(
          status: 'upgrading',
          stage: 'transferring',
          progress: 70,
          stageProgress: 0,
          overallProgress: 70,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(DeviceFirmwareHistoryTile)),
    )!;
    expect(find.text('${l10n.transferring} 0%'), findsOneWidget);
    expect(find.text('整体进度 70%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy weighted 84 is overall; phase remains unknown',
      (tester) async {
    await tester
        .pumpWidget(host(item(status: 'upgrading', stage: 'installing')));
    await tester.pumpAndSettle();
    expect(find.text('写入设备 --'), findsOneWidget);
    expect(find.text('整体进度 84%'), findsOneWidget);
    expect(find.text('写入设备 84%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧数据 stage 为空时回退显示 status 文案', (tester) async {
    await tester.pumpWidget(host(item(status: 'upgrading', stage: '')));
    await tester.pumpAndSettle();
    expect(find.text('升级中'), findsOneWidget);
  });
}
