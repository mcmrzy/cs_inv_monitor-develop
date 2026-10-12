import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/firmware_download_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/ota/domain/entities/local_channel.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/presentation/pages/local_ota_page.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/pump_app.dart';

class _Downloads extends Mock implements FirmwareDownloadService {}

class _Repository extends Mock implements OtaRepository {}

class _Adapter extends Mock implements BleAdapter {}

class _KeyStore extends Mock implements BleDeviceKeyStore {}

void main() {
  late _Downloads downloads;
  late _Repository repository;
  final canonical = <String, dynamic>{
    'firmware_id': 7,
    'download_url': 'https://example.test/canonical.bin',
    'file_name': 'canonical.bin',
    'file_size': 32,
    'model': 'L10',
    'target_chip': 'arm',
    'firmware_version': '1.2.0',
    'file_sha256': 'a' * 64,
    'release_signature': 'canonical-signature',
    'security_version': 5,
    'hardware_versions': ['HW-2'],
    'supported_channels': ['ble'],
  };
  Map<Symbol, dynamic>? downloadArguments;

  setUp(() async {
    await getIt.reset();
    downloadArguments = null;
    downloads = _Downloads();
    repository = _Repository();
    when(() => downloads.progressStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => downloads.isFirmwareDownloaded(any()))
        .thenAnswer((_) async => false);
    when(() => downloads.listDownloadedFirmwares()).thenAnswer((_) async => []);
    when(() => repository.getFirmwareInfo(7))
        .thenAnswer((_) async => Right(canonical));
    when(
      () => downloads.downloadFirmware(
        url: any(named: 'url'),
        fileName: any(named: 'fileName'),
        firmwareId: any(named: 'firmwareId'),
        expectedSize: any(named: 'expectedSize'),
        expectedSha256: any(named: 'expectedSha256'),
        deviceModel: any(named: 'deviceModel'),
        targetChip: any(named: 'targetChip'),
        version: any(named: 'version'),
        signature: any(named: 'signature'),
        securityVersion: any(named: 'securityVersion'),
        supportedChannels: any(named: 'supportedChannels'),
        hardwareVersions: any(named: 'hardwareVersions'),
      ),
    ).thenAnswer((call) async {
      downloadArguments = call.namedArguments;
      return '/tmp/canonical.bin';
    });
    getIt.registerSingleton<FirmwareDownloadService>(downloads);
    getIt.registerSingleton<OtaRepository>(repository);
    final adapter = _Adapter();
    when(() => adapter.stopScan()).thenAnswer((_) async {});
    getIt.registerSingleton<BleAdapter>(adapter);
    getIt.registerSingleton<BleDeviceManager>(
      BleDeviceManager(adapter: adapter, keyStore: _KeyStore()),
    );
  });
  tearDown(() async => getIt.reset());

  Future<void> pumpLegacy(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1000);
    addTearDown(tester.view.reset);
    await pumpMinimalApp(
      tester,
      LocalOTAPage(
        deviceSN: 'SN',
        deviceIP: '192.168.4.1',
        channel: LocalCommunicationChannel.ble,
        firmwareId: 7,
        firmwareUrl: 'https://example.test/other-build.bin',
        firmwareFileName: 'other-build.bin',
        fileSize: 99,
        deviceModel: 'OTHER',
        targetChip: 'esp',
        firmwareVersion: '9.9.9',
        fileSha256: 'b' * 64,
        releaseSignature: 'route-signature',
        securityVersion: 9,
      ),
    );
  }

  testWidgets('legacy URL deep link reloads all metadata by ID before download',
      (tester) async {
    await pumpLegacy(tester);
    verify(() => repository.getFirmwareInfo(7)).called(1);
    await tester.tap(find.widgetWithText(ElevatedButton, '下载固件'));
    await tester.pumpAndSettle();
    expect(downloadArguments, isNotNull);
    expect(downloadArguments![#url], canonical['download_url']);
    expect(downloadArguments![#fileName], canonical['file_name']);
    expect(downloadArguments![#expectedSize], 32);
    expect(downloadArguments![#expectedSha256], 'a' * 64);
    expect(downloadArguments![#deviceModel], 'L10');
    expect(downloadArguments![#targetChip], 'arm');
    expect(downloadArguments![#version], '1.2.0');
    expect(downloadArguments![#signature], 'canonical-signature');
    expect(downloadArguments![#securityVersion], 5);
    expect(downloadArguments![#hardwareVersions], ['HW-2']);
  });

  testWidgets('mismatched canonical firmware ID cannot repair a legacy route',
      (tester) async {
    when(() => repository.getFirmwareInfo(7))
        .thenAnswer((_) async => Right({...canonical, 'firmware_id': 8}));
    await pumpLegacy(tester);
    final button = tester
        .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '下载固件'));
    expect(button.onPressed, isNull);
    expect(downloadArguments, isNull);
    expect(find.textContaining('metadata ID does not match'), findsOneWidget);
  });

  testWidgets('route download is disabled until canonical record resolves',
      (tester) async {
    final pending = Completer<Either<Failure, Map<String, dynamic>>>();
    when(() => repository.getFirmwareInfo(7)).thenAnswer((_) => pending.future);
    await pumpLegacy(tester);
    final finder = find.widgetWithText(ElevatedButton, '下载固件');
    expect(tester.widget<ElevatedButton>(finder).onPressed, isNull);
    expect(downloadArguments, isNull);
    pending.complete(Right(canonical));
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(finder).onPressed, isNotNull);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(downloadArguments![#url], canonical['download_url']);
    expect(downloadArguments![#hardwareVersions], ['HW-2']);
  });

  testWidgets('no firmware ID and no scope keeps the old URL unavailable',
      (tester) async {
    await pumpMinimalApp(
      tester,
      const LocalOTAPage(
        deviceSN: 'SN',
        deviceIP: '192.168.4.1',
        channel: LocalCommunicationChannel.ble,
        firmwareUrl: 'https://example.test/other-build.bin',
        firmwareFileName: 'other-build.bin',
      ),
    );
    final button = tester
        .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '下载固件'));
    expect(button.onPressed, isNull);
    verifyNever(() => repository.getFirmwareInfo(any()));
    expect(downloadArguments, isNull);
  });
}
