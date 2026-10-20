import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/device/presentation/pages/device_control_page.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  setUp(() => getIt.pushNewScope());
  tearDown(() => getIt.popScope());

  Future<void> showControl(WidgetTester tester, List<dynamic>? capabilities) async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final endpoint = options.path.split('/').last;
      if (endpoint == 'control-capabilities' && capabilities == null) {
        handler.reject(DioException(requestOptions: options));
        return;
      }
      final dynamic data = switch (endpoint) {
        'control-capabilities' => capabilities,
        'control-fields' || 'control-overrides' => <dynamic>[],
        'commands' => {'items': <dynamic>[]},
        'energy-schedule' => {'periods': <dynamic>[]},
        'TEST-SN' => {'online_status': {'online': true}},
        _ => <String, dynamic>{},
      };
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {'code': 0, 'data': data},
      ));
    }));
    getIt.registerSingleton<Dio>(dio);
    await pumpMinimalApp(tester, const DeviceControlPage(deviceSN: 'TEST-SN'));
  }

  testWidgets('online device cannot send either AC command without capabilities', (tester) async {
    await showControl(tester, []);
    for (final text in ['开启', '关闭']) {
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, text));
      expect(button.onPressed, isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('each AC button requires its own enabled capability', (tester) async {
    await showControl(tester, [
      {'command_code': 'ac_on', 'risk_level': 2, 'is_enabled': true},
      {'command_code': 'ac_off', 'is_enabled': false},
    ]);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '开启')).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '关闭')).onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('capability request failure keeps both AC buttons disabled', (tester) async {
    await showControl(tester, null);
    for (final text in ['开启', '关闭']) {
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, text)).onPressed, isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
