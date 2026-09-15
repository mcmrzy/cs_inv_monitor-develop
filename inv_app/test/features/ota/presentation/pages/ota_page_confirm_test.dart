import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_history.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_overview.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/presentation/bloc/ota_bloc.dart';
import 'package:inv_app/features/ota/presentation/pages/ota_page.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class _MockOtaBloc extends MockBloc<OtaEvent, OtaState> implements OtaBloc {}

class _DeviceRepo implements DeviceRepository {
  @override
  Future<Either<Failure, Map<String, dynamic>>> getDetail(String sn) async =>
      Right({
        'device': {
          'sn': sn,
          'alias': '屋顶逆变器',
          'model': 'CS-10K',
          'status': 1,
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
  Future<Either<Failure, DeviceFirmwareOverview>> getFirmwareOverview(
    String sn,
  ) async =>
      Right(DeviceFirmwareOverview(
        deviceSn: sn,
        deviceModel: 'CS-10K',
        isOnline: true,
        modules: const [
          FirmwareModuleOverview(
            target: 'arm',
            currentVersion: '1.0.0',
            latestFirmwareId: 2,
            latestVersion: '1.1.0',
            versionState: 'outdated',
            updateAvailable: true,
          ),
        ],
      ));

  @override
  Future<Either<Failure, DeviceFirmwareHistoryPage>> getDeviceHistory(
    String sn, {
    String? targetChip,
    String? status,
    DateTime? startTime,
    DateTime? endTime,
    int page = 1,
    int pageSize = 20,
  }) async =>
      Right(DeviceFirmwareHistoryPage(
        items: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
      ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('legacy OTA landing renders the independent device flow only',
      (tester) async {
    final bloc = _MockOtaBloc();
    const legacyPackage = OTAUpdateAvailable(info: {
      'upgrade_mode': 'package',
      'main_version': 'V9.9.9',
      'current_main_version': 'V8.8.8',
      'firmware_id': 99,
      'chips_to_upgrade': <dynamic>[],
    });
    whenListen(
      bloc,
      Stream<OtaState>.value(legacyPackage),
      initialState: legacyPackage,
    );

    await tester.pumpWidget(
      BlocProvider<OtaBloc>.value(
        value: bloc,
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: OTAPage(
            deviceSN: 'SN123',
            deviceRepository: _DeviceRepo(),
            otaRepository: _OtaRepo(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('deviceFirmwareHero')), findsOneWidget);
    expect(find.text('系统主控'), findsOneWidget);
    expect(find.text('V9.9.9'), findsNothing);
    expect(find.text('V8.8.8'), findsNothing);
  });
}
