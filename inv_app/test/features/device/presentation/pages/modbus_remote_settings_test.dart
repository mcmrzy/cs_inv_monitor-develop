import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/device/domain/entities/config_schema.dart';
import 'package:inv_app/features/device/presentation/pages/device_settings_page.dart';
import 'package:inv_app/features/device/presentation/widgets/config_param_controls.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  setUp(() => getIt.pushNewScope());
  tearDown(() => getIt.popScope());

  testWidgets('remote numeric steps respect bounds and remain pending',
      (tester) async {
    var sent = 0;
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.method == 'POST') sent++;
        final dynamic data = switch (options.path.split('/').last) {
          'config-schema' => [
              {
                'param_key': 'set_ac_charge_current',
                'control_type': 'number',
                'min': 1,
                'max': 2,
                'step': 0.5,
                'unit': 'A',
              },
            ],
          'control-capabilities' => [
              {'command_code': 'set_ac_charge_current', 'is_enabled': true},
            ],
          'control-state' => {
              'reported': {'set_ac_charge_current': 1},
              'sync_status': 'synced',
            },
          _ => <String, dynamic>{},
        };
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {'code': 0, 'data': data},
        ));
      },
    ));
    getIt.registerSingleton<Dio>(dio);
    await pumpMinimalApp(
        tester,
        const Scaffold(
          body: RemoteSettingsTab(sn: 'PANEL-3KU', cloudOnline: true),
        ));
    await tester.tap(find.text('充电管理'));
    await tester.pumpAndSettle();
    expect(find.text('1.0 A'), findsWidgets);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '减少',
            ))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('增加'));
    await tester.pumpAndSettle();
    expect(find.text('1.5 A'), findsOneWidget);
    await tester.tap(find.byTooltip('增加'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '增加',
            ))
            .onPressed,
        isNull);
    expect(sent, 0);
    await tester.enterText(find.byType(TextField), 'missing parameter');
    await tester.pumpAndSettle();
    expect(find.text('未找到匹配的参数'), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.text('充电管理'), findsOneWidget);
    expect(find.text('2.0 A'), findsWidgets);
    expect(sent, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('SOC dropdown sends a numeric off value before the first read',
      (tester) async {
    final schema = ConfigParamSchema.fromJson({
      'param_key': 'set_soc_cutoff',
      'control_type': 'enum',
      'enum_map': {'0': 'off', for (var i = 5; i <= 50; i++) '$i': '$i%'},
    });
    dynamic target;
    await pumpMinimalApp(
      tester,
      Scaffold(
        body: ConfigParamControl(
          schema: schema,
          value: null,
          modified: false,
          onRequestChange: (value) => target = value,
        ),
      ),
    );
    final menu = find.byType(DropdownButton<String>);
    expect(tester.widget<DropdownButton<String>>(menu).value, isNull);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭').last);
    await tester.pumpAndSettle();
    expect(target, isA<int>());
    expect(target, 0);
  });

  test('equalization is visible only for supported lead battery types', () {
    final schema = ConfigParamSchema.fromJson({
      'param_key': 'set_equalize_voltage',
      'visibility': {'param': 'set_battery_type', 'in': [1, 2]},
    });
    expect(configParamVisible(schema, {}), isFalse);
    expect(configParamVisible(schema, {'set_battery_type': 3}), isFalse);
    expect(configParamVisible(schema, {'set_battery_type': 1}), isTrue);
    expect(configParamVisible(schema, {'set_battery_type': 2}), isTrue);
  });

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
      if (!mismatch) {
        await tester.enterText(find.byType(TextField), '不存在的参数');
        await tester.pumpAndSettle();
        expect(find.text('未找到匹配的参数'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '过载重启');
        await tester.pumpAndSettle();
        expect(find.text('过载重启'), findsWidgets);
        expect(sent, 0);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
