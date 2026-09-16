import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/device_live_data_service.dart';
import 'package:inv_app/core/services/ble/device_live_snapshot.dart';

void main() {
  const snA = 'H1CNA6K20001';
  const snB = 'H1CNA6K20002';
  final baseTime = DateTime.utc(2026, 9, 15, 8);

  group('DeviceLiveDataService source arbitration', () {
    late DeviceLiveDataService service;

    setUp(() {
      service = DeviceLiveDataService();
    });

    tearDown(() async {
      await service.dispose();
    });

    test('late older cloud data cannot replace a current BLE sample', () {
      final connectionGeneration = service.beginBleConnection(snA);

      expect(
        service.add(
          DeviceLiveSnapshot.ble(
            deviceSn: snA,
            data: const {'power_w': 3200},
            sampledAt: baseTime.add(const Duration(seconds: 20)),
            receivedAt: baseTime.add(const Duration(seconds: 21)),
            connectionGeneration: connectionGeneration,
            quality: DeviceLiveQuality.good,
            qualityFlags: 0,
            bootId: 'boot-1',
            sampleSequence: 2,
            timeQuality: 'device_clock',
            schemaVersion: 'v2-test',
          ),
        ),
        isTrue,
      );

      expect(
        service.add(
          DeviceLiveSnapshot.cloud(
            deviceSn: snA,
            data: const {'power_w': 2800},
            sampledAt: baseTime.add(const Duration(seconds: 10)),
            receivedAt: baseTime.add(const Duration(seconds: 30)),
            quality: DeviceLiveQuality.good,
          ),
        ),
        isFalse,
      );

      final latest = service.latestFor(snA);
      expect(latest?.source, DeviceLiveSource.ble);
      expect(latest?.data['power_w'], 3200);
    });

    test('device streams and caches stay isolated by serial number', () async {
      final receivedForA = <DeviceLiveSnapshot>[];
      final subscription = service.watchDevice(snA).listen(receivedForA.add);

      service.add(
        DeviceLiveSnapshot.cloud(
          deviceSn: snB,
          data: const {'power_w': 900},
          sampledAt: baseTime,
          receivedAt: baseTime,
          quality: DeviceLiveQuality.good,
        ),
      );
      service.add(
        DeviceLiveSnapshot.cloud(
          deviceSn: snA,
          data: const {'power_w': 1800},
          sampledAt: baseTime,
          receivedAt: baseTime,
          quality: DeviceLiveQuality.good,
        ),
      );
      await pumpEventQueue();

      expect(receivedForA, hasLength(1));
      expect(receivedForA.single.deviceSn, snA);
      expect(service.latestFor(snA)?.data['power_w'], 1800);
      expect(service.latestFor(snB)?.data['power_w'], 900);

      await subscription.cancel();
    });

    test('results from an old BLE connection generation are ignored', () {
      final oldGeneration = service.beginBleConnection(snA);
      final currentGeneration = service.beginBleConnection(snA);

      expect(currentGeneration, greaterThan(oldGeneration));
      expect(
        service.add(
          DeviceLiveSnapshot.ble(
            deviceSn: snA,
            data: const {'power_w': 1000},
            sampledAt: baseTime.add(const Duration(seconds: 30)),
            receivedAt: baseTime.add(const Duration(seconds: 31)),
            connectionGeneration: oldGeneration,
            quality: DeviceLiveQuality.good,
            qualityFlags: 0,
            bootId: 'boot-1',
            sampleSequence: 3,
            timeQuality: 'device_clock',
            schemaVersion: 'v2-test',
          ),
        ),
        isFalse,
      );
      expect(service.latestFor(snA), isNull);

      expect(
        service.add(
          DeviceLiveSnapshot.ble(
            deviceSn: snA,
            data: const {'power_w': 2000},
            sampledAt: baseTime.add(const Duration(seconds: 20)),
            receivedAt: baseTime.add(const Duration(seconds: 21)),
            connectionGeneration: currentGeneration,
            quality: DeviceLiveQuality.good,
            qualityFlags: 0,
            bootId: 'boot-1',
            sampleSequence: 2,
            timeQuality: 'device_clock',
            schemaVersion: 'v2-test',
          ),
        ),
        isTrue,
      );
      expect(service.latestFor(snA)?.data['power_w'], 2000);
    });

    test('a snapshot without sampledAt stays unknown and is not newest', () {
      final unknown = DeviceLiveSnapshot.cloud(
        deviceSn: snA,
        data: const {'power_w': 1000},
        sampledAt: null,
        receivedAt: baseTime.add(const Duration(hours: 1)),
        quality: DeviceLiveQuality.unknown,
      );

      expect(
        unknown.freshnessAt(baseTime.add(const Duration(hours: 1))),
        DeviceLiveFreshness.unknown,
      );
      expect(service.add(unknown), isTrue);

      final known = DeviceLiveSnapshot.cloud(
        deviceSn: snA,
        data: const {'power_w': 2000},
        sampledAt: baseTime,
        receivedAt: baseTime.add(const Duration(minutes: 1)),
        quality: DeviceLiveQuality.good,
      );
      expect(service.add(known), isTrue);

      final lateUnknown = DeviceLiveSnapshot.cloud(
        deviceSn: snA,
        data: const {'power_w': 3000},
        sampledAt: null,
        receivedAt: baseTime.add(const Duration(hours: 2)),
        quality: DeviceLiveQuality.good,
      );
      expect(service.add(lateUnknown), isFalse);
      expect(service.latestFor(snA), same(known));
    });

    test('freshness is based on sampledAt rather than receivedAt', () {
      final snapshot = DeviceLiveSnapshot.cloud(
        deviceSn: snA,
        data: const {'power_w': 1000},
        sampledAt: baseTime,
        receivedAt: baseTime.add(const Duration(hours: 3)),
        quality: DeviceLiveQuality.good,
      );

      expect(
        snapshot.freshnessAt(
          baseTime.add(const Duration(seconds: 59)),
          freshFor: const Duration(minutes: 1),
        ),
        DeviceLiveFreshness.fresh,
      );
      expect(
        snapshot.freshnessAt(
          baseTime.add(const Duration(minutes: 2)),
          freshFor: const Duration(minutes: 1),
        ),
        DeviceLiveFreshness.stale,
      );
    });

    test('an obviously future sampledAt is unknown and cannot win', () {
      final known = DeviceLiveSnapshot.cloud(
        deviceSn: snA,
        data: const {'power_w': 1000},
        sampledAt: baseTime,
        receivedAt: baseTime,
        quality: DeviceLiveQuality.good,
      );
      final future = DeviceLiveSnapshot.cloud(
        deviceSn: snA,
        data: const {'power_w': 9000},
        sampledAt: baseTime.add(const Duration(minutes: 10)),
        receivedAt: baseTime.add(const Duration(seconds: 1)),
        quality: DeviceLiveQuality.degraded,
      );

      expect(service.add(known), isTrue);
      expect(
        future.freshnessAt(baseTime.add(const Duration(seconds: 1))),
        DeviceLiveFreshness.unknown,
      );
      expect(service.add(future), isFalse);
      expect(service.latestFor(snA), same(known));
    });

    test('disconnect keeps the BLE last value until newer cloud data arrives', () {
      final generation = service.beginBleConnection(snA);
      final ble = DeviceLiveSnapshot.ble(
        deviceSn: snA,
        data: const {'power_w': 2000},
        sampledAt: baseTime.add(const Duration(seconds: 20)),
        receivedAt: baseTime.add(const Duration(seconds: 21)),
        connectionGeneration: generation,
        quality: DeviceLiveQuality.good,
        qualityFlags: 0,
        bootId: 'boot-1',
        sampleSequence: 2,
        timeQuality: 'device_clock',
        schemaVersion: 'v2-test',
      );
      expect(service.add(ble), isTrue);

      service.endBleConnection(snA, generation);
      expect(service.latestFor(snA), same(ble));
      expect(
        service.add(
          DeviceLiveSnapshot.cloud(
            deviceSn: snA,
            data: const {'power_w': 1000},
            sampledAt: baseTime.add(const Duration(seconds: 10)),
            receivedAt: baseTime.add(const Duration(seconds: 30)),
            quality: DeviceLiveQuality.good,
          ),
        ),
        isFalse,
      );
      expect(
        service.add(
          DeviceLiveSnapshot.cloud(
            deviceSn: snA,
            data: const {'power_w': 3000},
            sampledAt: baseTime.add(const Duration(seconds: 30)),
            receivedAt: baseTime.add(const Duration(seconds: 31)),
            quality: DeviceLiveQuality.good,
          ),
        ),
        isTrue,
      );
      expect(service.latestFor(snA)?.source, DeviceLiveSource.cloud);
      expect(service.latestFor(snA)?.data['power_w'], 3000);
    });

    test('invalid-quality candidates are never selected', () {
      expect(
        service.add(
          DeviceLiveSnapshot.cloud(
            deviceSn: snA,
            data: const {'power_w': 9999},
            sampledAt: baseTime,
            receivedAt: baseTime,
            quality: DeviceLiveQuality.invalid,
          ),
        ),
        isFalse,
      );
      expect(service.latestFor(snA), isNull);
    });

    test('BLE envelope preserves contract metadata and unknown quality bits', () {
      final snapshot = DeviceLiveSnapshot.ble(
        deviceSn: snA,
        data: const {
          'ac': {'voltage': 230.1},
        },
        sampledAt: baseTime,
        receivedAt: baseTime.add(const Duration(seconds: 1)),
        connectionGeneration: service.beginBleConnection(snA),
        quality: DeviceLiveQuality.degraded,
        qualityFlags: 0x41,
        bootId: 'boot-test-01',
        sampleSequence: 42,
        timeQuality: 'device_clock',
        schemaVersion: 'v2-test',
      );

      expect(snapshot.bootId, 'boot-test-01');
      expect(snapshot.sampleSequence, 42);
      expect(snapshot.timeQuality, 'device_clock');
      expect(snapshot.schemaVersion, 'v2-test');
      expect(snapshot.qualityFlags, 0x41);
      expect(snapshot.data['ac'], {'voltage': 230.1});
    });

    test('BLE sampledAt is required by the telemetry contract', () {
      final snapshot = DeviceLiveSnapshot.ble(
        deviceSn: snA,
        data: const {'power_w': 1000},
        sampledAt: baseTime,
        receivedAt: baseTime,
        connectionGeneration: service.beginBleConnection(snA),
        quality: DeviceLiveQuality.good,
        qualityFlags: 0,
        bootId: 'boot-test-01',
        sampleSequence: 1,
        timeQuality: 'device_clock',
        schemaVersion: 'v2-test',
      );

      expect(snapshot.sampledAt, isNotNull);

      final dynamic bleFactory = DeviceLiveSnapshot.ble;
      expect(
        () => bleFactory(
          deviceSn: snA,
          data: const {'power_w': 1000},
          sampledAt: null,
          receivedAt: baseTime,
          connectionGeneration: service.beginBleConnection(snA),
          quality: DeviceLiveQuality.good,
          qualityFlags: 0,
          bootId: 'boot-test-01',
          sampleSequence: 1,
          timeQuality: 'device_clock',
          schemaVersion: 'v2-test',
        ),
        throwsA(isA<TypeError>()),
      );
    });

    test('snapshot data is deeply immutable', () {
      final nested = <String, dynamic>{'voltage': 230.1};
      final snapshot = DeviceLiveSnapshot.cloud(
        deviceSn: snA,
        data: {'ac': nested},
        sampledAt: baseTime,
        receivedAt: baseTime,
        quality: DeviceLiveQuality.good,
      );

      expect(
        () => (snapshot.data['ac'] as Map<String, dynamic>)['voltage'] = 0,
        throwsUnsupportedError,
      );
      nested['voltage'] = 0;
      expect((snapshot.data['ac'] as Map<String, dynamic>)['voltage'], 230.1);
    });

    test('BLE envelope rejects missing required contract metadata', () {
      expect(
        () => DeviceLiveSnapshot.ble(
          deviceSn: snA,
          data: const {'power_w': 1000},
          sampledAt: baseTime,
          receivedAt: baseTime,
          connectionGeneration: service.beginBleConnection(snA),
          quality: DeviceLiveQuality.good,
        ),
        throwsArgumentError,
      );
    });
  });
}
