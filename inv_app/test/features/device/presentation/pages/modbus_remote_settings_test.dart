import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/device/presentation/pages/device_settings_page.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  setUp(() => getIt.pushNewScope());
  tearDown(() => getIt.popScope());

  for (final mismatch in [false, true]) {
    testWidgets(
        'remote writes are blocked with offline or mismatched identity $mismatch',
        (tester) async {
      var sent = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.method == 'POST') sent++;
            final dynamic data = switch (options.path.split('/').last) {
              'config-schema' => [
                  {
                    'param_key': 'set_overload_restart',
                    'control_type': 'boolean',
                    'display_name_key': 'config.set_overload_restart',
                  },
                ],
              'control-capabilities' => [
                  {'command_code': 'set_overload_restart', 'is_enabled': true},
                  {'command_code': 'query_config', 'is_enabled': true},
                ],
              'control-state' => {
                  'reported': {'set_overload_restart': 0},
                  'sync_status': 'synced',
                },
              _ => <String, dynamic>{},
            };
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'code': 0, 'data': data},
              ),
            );
          },
        ),
      );
      getIt.registerSingleton<Dio>(dio);
      await pumpMinimalApp(
        tester,
        Scaffold(
          body: RemoteSettingsTab(
            sn: 'PANEL-3KU',
            cloudOnline: mismatch,
            modelBindingMismatch: mismatch,
          ),
        ),
      );
      expect(sent, 0);
      expect(
        find.textContaining(mismatch ? '绑定型号不一致' : '云端离线'),
        findsOneWidget,
      );
      final readButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '读取设备'),
      );
      expect(readButton.onPressed, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
