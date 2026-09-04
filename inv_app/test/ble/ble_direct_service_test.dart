import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/ble/ble_direct_service.dart';
import 'package:inv_app/core/services/ble/ble_polling_service.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:mocktail/mocktail.dart';

class MockBleAdapter extends Mock implements BleAdapter {}

class MockBleDeviceManager extends Mock implements BleDeviceManager {}

class MockBlePollingService extends Mock implements BlePollingService {}

class MockStorageService extends Mock implements StorageServiceLike {}

void main() {
  setUpAll(() {
    // any(named: 'timeout') 匹配 Duration 需要 fallback 值
    registerFallbackValue(Duration.zero);
  });

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
    when(() => storage.getIsBleAutoConnect()).thenAnswer((_) async => true);
    when(() => storage.saveIsBleAutoConnect(any())).thenAnswer((_) async {});
    when(() => manager.startAutoConnect()).thenAnswer((_) async {});
    when(() => manager.stopAutoConnect()).thenAnswer((_) async {});
    when(() => manager.disconnectAll()).thenAnswer((_) async {});
    // 默认扫描返回空流，避免未 stub 时 mocktail 返回 null 导致类型错误
    when(() => adapter.scan(
            serviceUuids: any(named: 'serviceUuids'),
            timeout: any(named: 'timeout'),),
        )
        .thenAnswer((_) => const Stream.empty());
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
    final scanResults = <BleScanResult>[
      const BleScanResult(
        macAddress: 'AA:BB:CC:DD:EE:FF',
        name: 'CS-INV-6K2',
        rssi: -60,
        serviceUuids: [BleCtProtocol.serviceUuid],
      ),
    ];
    when(() => adapter.scan(
            serviceUuids: any(named: 'serviceUuids'),
            timeout: any(named: 'timeout'),),
        )
        .thenAnswer((_) => Stream.fromIterable(scanResults));

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

  test('scan results cache dedupes by mac and exposes snapshot', () async {
    when(() => adapter.scan(
            serviceUuids: any(named: 'serviceUuids'),
            timeout: any(named: 'timeout'),),
        )
        .thenAnswer((_) => Stream.fromIterable(const [
              BleScanResult(
                macAddress: 'AA:BB:CC:DD:EE:FF',
                name: 'CS-INV-6K2',
                rssi: -60,
                serviceUuids: [BleCtProtocol.serviceUuid],
              ),
              BleScanResult(
                macAddress: 'AA:BB:CC:DD:EE:FF',
                name: 'CS-INV-6K2',
                rssi: -55,
                serviceUuids: [BleCtProtocol.serviceUuid],
              ),
            ]));

    final service = BleDirectService(
      adapter: adapter,
      manager: manager,
      polling: polling,
      storage: storage,
    );
    await service.setEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(service.scanResults, hasLength(1));
    expect(service.scanResults.first.name, 'CS-INV-6K2');

    await service.dispose();
  });

  test('auto connect disabled skips startAutoConnect on enable', () async {
    when(() => storage.getIsBleAutoConnect()).thenAnswer((_) async => false);
    final service = BleDirectService(
      adapter: adapter,
      manager: manager,
      polling: polling,
      storage: storage,
    );

    await service.setEnabled(true);

    verifyNever(() => manager.startAutoConnect());
    expect(service.autoConnect, isFalse);

    // 运行时打开自动连接
    await service.setAutoConnect(true);
    verify(() => manager.startAutoConnect()).called(1);
    expect(service.autoConnect, isTrue);

    await service.dispose();
  });

  test('forceReleaseResources releases resources regardless of enabled state',
      () async {
    final service = BleDirectService(
      adapter: adapter,
      manager: manager,
      polling: polling,
      storage: storage,
    );

    // 服务未启用时，forceReleaseResources 也应释放资源
    expect(service.enabled, isFalse);
    await service.forceReleaseResources();

    verify(() => manager.stopAutoConnect()).called(1);
    verify(() => manager.disconnectAll()).called(1);
    verify(() => polling.stop()).called(1);
    expect(service.enabled, isFalse);

    await service.dispose();
  });

  test('forceReleaseResources stops enabled service without persisting',
      () async {
    final service = BleDirectService(
      adapter: adapter,
      manager: manager,
      polling: polling,
      storage: storage,
    );
    await service.setEnabled(true);
    expect(service.enabled, isTrue);

    await service.forceReleaseResources();

    verify(() => manager.stopAutoConnect()).called(1);
    verify(() => manager.disconnectAll()).called(1);
    verify(() => polling.stop()).called(1);
    expect(service.enabled, isFalse);
    // 不应持久化关闭状态（与 setEnabled(false) 不同）
    verifyNever(() => storage.saveIsBleDirectEnabled(false));

    await service.dispose();
  });
}
