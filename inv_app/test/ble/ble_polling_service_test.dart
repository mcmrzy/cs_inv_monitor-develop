import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/ble/ble_polling_service.dart';
import 'package:mocktail/mocktail.dart';

class MockBleDeviceManager extends Mock implements BleDeviceManager {}

class MockBleDeviceSession extends Mock implements BleDeviceSession {}

void main() {
  test('polls ready sessions at interval and emits telemetry', () {
    fakeAsync((async) {
      final manager = MockBleDeviceManager();
      final session = MockBleDeviceSession();
      when(() => session.state).thenReturn(BleDeviceState.ready);
      when(() => session.sn).thenReturn('H1CNA6K20001');
      when(() => session.readTelemetrySnapshot()).thenAnswer(
        (_) async => {'power_w': 3000, 'status': 1},
      );
      when(() => manager.sessions).thenReturn({
        'AA:BB:CC:DD:EE:FF': session,
      });

      final service = BlePollingService(
        manager: manager,
        interval: const Duration(seconds: 180),
      );
      final received = <BlePolledTelemetry>[];
      service.telemetry.listen(received.add);

      service.start();
      async.elapse(const Duration(seconds: 181));

      expect(received, hasLength(1));
      expect(received.first.sn, 'H1CNA6K20001');
      expect(received.first.data['power_w'], 3000);
      expect(service.isRunning, isTrue);

      service.stop();
      async.elapse(const Duration(seconds: 181));
      expect(received, hasLength(1)); // 停止后不再轮询
    });
  });

  test('skips sessions that are not ready', () {
    fakeAsync((async) {
      final manager = MockBleDeviceManager();
      final session = MockBleDeviceSession();
      when(() => session.state).thenReturn(BleDeviceState.connecting);
      when(() => manager.sessions).thenReturn({
        'AA:BB:CC:DD:EE:FF': session,
      });

      final service = BlePollingService(manager: manager);
      final received = <BlePolledTelemetry>[];
      service.telemetry.listen(received.add);

      service.start();
      async.elapse(const Duration(seconds: 181));

      expect(received, isEmpty);
      verifyNever(() => session.readTelemetrySnapshot());
      service.stop();
    });
  });

  test('does not start another poll while the previous read is pending', () {
    fakeAsync((async) {
      final manager = MockBleDeviceManager();
      final session = MockBleDeviceSession();
      final pendingRead = Completer<Map<String, dynamic>>();
      when(() => session.state).thenReturn(BleDeviceState.ready);
      when(() => session.sn).thenReturn('H1CNA6K20001');
      when(() => session.readTelemetrySnapshot())
          .thenAnswer((_) => pendingRead.future);
      when(() => manager.sessions).thenReturn({
        'AA:BB:CC:DD:EE:FF': session,
      });

      final service = BlePollingService(
        manager: manager,
        interval: const Duration(seconds: 1),
      );

      service.start();
      async.elapse(const Duration(seconds: 1));
      verify(() => session.readTelemetrySnapshot()).called(1);

      async.elapse(const Duration(seconds: 3));
      verifyNever(() => session.readTelemetrySnapshot());

      pendingRead.complete({'power_w': 3000});
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      verify(() => session.readTelemetrySnapshot()).called(1);

      service.dispose();
    });
  });

  test('drops pending read results after stop or dispose', () {
    fakeAsync((async) {
      final manager = MockBleDeviceManager();
      final session = MockBleDeviceSession();
      final pendingRead = Completer<Map<String, dynamic>>();
      when(() => session.state).thenReturn(BleDeviceState.ready);
      when(() => session.sn).thenReturn('H1CNA6K20001');
      when(() => session.readTelemetrySnapshot())
          .thenAnswer((_) => pendingRead.future);
      when(() => manager.sessions).thenReturn({
        'AA:BB:CC:DD:EE:FF': session,
      });

      final service = BlePollingService(
        manager: manager,
        interval: const Duration(seconds: 1),
      );
      final received = <BlePolledTelemetry>[];
      service.telemetry.listen(received.add);

      service.start();
      async.elapse(const Duration(seconds: 1));
      service.stop();
      pendingRead.complete({'power_w': 3000});
      async.flushMicrotasks();

      expect(received, isEmpty);
      service.dispose();

      final disposedManager = MockBleDeviceManager();
      final disposedSession = MockBleDeviceSession();
      final disposedRead = Completer<Map<String, dynamic>>();
      when(() => disposedSession.state).thenReturn(BleDeviceState.ready);
      when(() => disposedSession.sn).thenReturn('H1CNA6K20002');
      when(() => disposedSession.readTelemetrySnapshot())
          .thenAnswer((_) => disposedRead.future);
      when(() => disposedManager.sessions).thenReturn({
        '11:22:33:44:55:66': disposedSession,
      });
      final disposedService = BlePollingService(
        manager: disposedManager,
        interval: const Duration(seconds: 1),
      );
      final disposedReceived = <BlePolledTelemetry>[];
      disposedService.telemetry.listen(disposedReceived.add);

      disposedService.start();
      async.elapse(const Duration(seconds: 1));
      disposedService.dispose();
      disposedRead.complete({'power_w': 2000});
      async.flushMicrotasks();

      expect(disposedReceived, isEmpty);
    });
  });
}
