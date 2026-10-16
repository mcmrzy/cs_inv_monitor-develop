import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_overview.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/presentation/pages/ota_check_all_page.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/pump_app.dart';

class _Ota extends Mock implements OtaRepository {}

void main() {
  for (final unreported in [false, true]) {
    testWidgets(
        'check-all uses server eligibility with version unreported=$unreported',
        (tester) async {
      final devices = MockDeviceBloc();
      final ota = _Ota();
      when(() => devices.stream)
          .thenAnswer((_) => const Stream<DeviceState>.empty());
      when(() => devices.state).thenReturn(
        const DeviceListLoaded(
          devices: [
            {'sn': 'SN', 'name': '逆变器', 'status': 1},
          ],
          total: 1,
        ),
      );
      when(() => ota.getFirmwareOverview('SN')).thenAnswer(
        (_) async => Right(
          DeviceFirmwareOverview(
            deviceSn: 'SN',
            deviceModel: 'L10',
            isOnline: true,
            modules: [
              FirmwareModuleOverview(
                target: 'esp',
                currentVersion: unreported ? '' : '1.0.0',
                latestFirmwareId: 42,
                latestVersion: '1.1.0',
                versionState: unreported ? 'unreported' : 'outdated',
                updateAvailable: true,
                isSupported: true,
                isConnected: !unreported,
                isEligible: true,
              ),
            ],
          ),
        ),
      );
      getIt.registerSingleton<OtaRepository>(ota);
      addTearDown(getIt.reset);

      await pumpApp(tester, const OtaCheckAllPage(), deviceBloc: devices);

      expect(find.text('有更新 (1)'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '去升级'), findsOneWidget);
      expect(find.text('通信采集'), findsOneWidget);
      expect(find.text('硬件版本未确认'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
