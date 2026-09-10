import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_history.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/presentation/pages/device_firmware_detail_page.dart';
import 'package:inv_app/features/ota/presentation/pages/ota_tab_page.dart';
import 'package:inv_app/l10n/app_localizations.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      );

  testWidgets('firmware hub leads with devices and keeps secondary tools',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(OtaTabPage(repository: _DeviceRepo())));
    await tester.pumpAndSettle();

    expect(find.text('设备固件升级'), findsOneWidget);
    expect(find.text('我的设备'), findsOneWidget);
    expect(find.text('屋顶逆变器'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('本地升级'), findsOneWidget);
    expect(find.text('固件库'), findsOneWidget);
    expect(find.text('升级历史'), findsOneWidget);
  });

  testWidgets('device page shows device data, functional modules and history',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(DeviceFirmwareDetailPage(
      deviceSN: 'INV-001',
      deviceRepository: _DeviceRepo(),
      otaRepository: _OtaRepo(),
    )));
    await tester.pumpAndSettle();

    for (final text in [
      '设备型号',
      '设备名称',
      '设备序列号',
      '硬件版本',
      '通信采集',
      '系统主控',
      '功率控制',
      '电池管理',
      '检查固件更新',
      '改善弱网重连稳定性',
    ]) {
      expect(find.text(text), findsWidgets);
    }
    expect(find.textContaining(RegExp(r'\b(ESP|ARM|DSP|BMS)\b')), findsNothing);
  });
}

class _DeviceRepo implements DeviceRepository {
  @override
  Future<Either<Failure, Map<String, dynamic>>> getList({
    int? stationId,
    int? status,
    int page = 1,
    int pageSize = 20,
  }) async => const Right({
        'items': [
          {'sn': 'INV-001', 'alias': '屋顶逆变器', 'model': 'CS-10K', 'status': 1},
        ],
        'total': 1,
      });

  @override
  Future<Either<Failure, Map<String, dynamic>>> getDetail(String sn) async =>
      const Right({
        'device': {
          'sn': 'INV-001',
          'alias': '屋顶逆变器',
          'model': 'CS-10K',
          'hardware_version': 'H2.1',
          'firmware_esp': '1.2.0',
          'firmware_arm': '2.3.0',
          'firmware_dsp': '3.1.0',
          'firmware_bms': '4.0.1',
        },
        'online_status': {'online': true},
      });

  @override
  InverterRealtime? parseRealtimeData(dynamic raw) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OtaRepo implements OtaRepository {
  @override
  Future<Either<Failure, DeviceFirmwareHistoryPage>> getDeviceHistory(
    String sn, {
    int page = 1,
    int pageSize = 20,
  }) async => Right(DeviceFirmwareHistoryPage(
        items: [
          DeviceFirmwareHistory(
            id: 1,
            deviceSn: sn,
            target: 'esp',
            oldVersion: '1.1.0',
            newVersion: '1.2.0',
            status: 'success',
            changelog: '改善弱网重连稳定性',
            updatedAt: DateTime.utc(2026, 9, 10),
          ),
        ],
        total: 1,
        page: page,
        pageSize: pageSize,
      ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
