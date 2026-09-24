import 'dart:async';

import 'package:flutter_blue_ultra/flutter_blue_ultra.dart' as fbu;
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:mocktail/mocktail.dart';

class MockBluetoothDevice extends Mock implements fbu.BluetoothDevice {}

void main() {
  test('missing optional characteristic reports a stream error', () async {
    final device = MockBluetoothDevice();
    when(() => device.discoverServices()).thenAnswer((_) async => []);
    final connection = FbuGattConnection(device);
    final errors = <Object>[];
    final errorReceived = Completer<void>();

    final subscription = connection.subscribe('service', 'missing').listen(
      (_) {},
      onError: (Object error) {
        errors.add(error);
        errorReceived.complete();
      },
    );

    await errorReceived.future.timeout(const Duration(seconds: 1));
    expect(errors.single, isA<StateError>());
    await subscription.cancel();
  });
}
