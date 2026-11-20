import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/device/domain/entities/config_schema.dart';
import 'package:inv_app/features/device/presentation/pages/device_settings_page.dart';
import 'package:inv_app/features/device/presentation/widgets/config_param_controls.dart';
import 'package:inv_app/l10n/app_localizations.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  setUp(() => getIt.pushNewScope());
  tearDown(() => getIt.popScope());

  testWidgets('legacy remote parameters share the category card surface',
      (tester) async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final Object data = options.path.endsWith('/config-schema')
              ? [
                  {
                    'param_key': 'set_ac_charge_current',
                    'control_type': 'number',
                    'unit': 'A',
                  },
                ]
              : {
                  'reported': {'set_ac_charge_current': 24},
                  'sync_status': 'synced',
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
      const Scaffold(
        body: RemoteSettingsTab(sn: 'LEGACY-TEST', modelBindingMismatch: true),
      ),
    );
    await tester.tap(find.text('充电管理'));
    await tester.pumpAndSettle();
    final parameter = find.byType(ConfigParamControl);
    expect(parameter, findsOneWidget);
    expect(
      find.descendant(of: parameter, matching: find.text('24 A')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: parameter,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color != null,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('remote current picker uses only the model command options',
      (tester) async {
    tester.view.physicalSize = const Size(390, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var sent = 0;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: (options, handler) {
        if (options.method == 'POST') sent++;
        final dynamic data = switch (options.path.split('/').last) {
          'config-schema' => [
              {
                'param_key': 'set_ac_charge_current',
                'control_type': 'number',
                'min': 0,
                'max': 100,
                'step': 1,
                'unit': 'A',
              },
            ],
          'control-capabilities' => [
              {
                'command_code': 'set_ac_charge_current',
                'is_enabled': true,
                'parameter_schema': {
                  'args': [
                    {'key': 'value', 'enum': [2, 10, 20]},
                  ],
                },
              },
            ],
          'control-state' => {
              'reported': {'set_ac_charge_current': 10},
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
      }),
    );
    getIt.registerSingleton<Dio>(dio);
    await pumpMinimalApp(
      tester,
      const Scaffold(
        body: RemoteSettingsTab(sn: 'PANEL-3KU', cloudOnline: true),
      ),
    );
    await tester.tap(find.text('充电管理'));
    await tester.pumpAndSettle();
    expect(find.text('全部分类'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.widgetWithText(OutlinedButton, '10 A'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '2 A'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '10 A'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '20 A'), findsOneWidget);
    expect(find.text('15 A'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, '20 A'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, '20 A'), findsOneWidget);
    expect(sent, 0);
    await tester.ensureVisible(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'missing parameter');
    await tester.pumpAndSettle();
    expect(find.text('未找到匹配的参数'), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.text('充电管理'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '20 A'), findsOneWidget);
    expect(sent, 0);
    await tester.tap(find.text('全部分类'));
    await tester.pumpAndSettle();
    expect(find.text('全部分类'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '20 A'), findsNothing);
    await tester.tap(find.text('充电管理'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, '20 A'), findsOneWidget);
    expect(sent, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('remote value row keeps enum edits pending until apply',
      (tester) async {
    var writes = 0;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'POST') writes++;
          final data = switch (options.path.split('/').last) {
            'config-schema' => [
                {
                  'param_key': 'set_output_voltage',
                  'control_type': 'enum',
                  'enum_map': {'220': '220 V', '230': '230 V'},
                  'unit': 'V',
                },
              ],
            'control-capabilities' => [
                {'command_code': 'set_output_voltage', 'is_enabled': true},
              ],
            'control-state' => {
                'reported': {'set_output_voltage': 230},
                'sync_status': 'synced',
              },
            _ => throw StateError(options.path),
          };
          handler.resolve(
            Response(
              requestOptions: options,
              data: {'code': 0, 'data': data},
            ),
          );
        },
      ),
    );
    getIt.registerSingleton<Dio>(dio);
    await pumpMinimalApp(
      tester,
      const Scaffold(
        body: RemoteSettingsTab(sn: 'PANEL-3KU', cloudOnline: true),
      ),
    );

    final output = find.text('交流输出');
    await tester.ensureVisible(output);
    await tester.tap(output);
    await tester.pumpAndSettle();
    final row = find.byType(ConfigParamControl);
    final current = find.descendant(of: row, matching: find.text('230 V'));
    expect(current, findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);

    for (final action in ['取消', '确认']) {
      await tester.tap(current);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '220 V'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(action),
        ),
      );
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(current, action == '取消' ? findsOneWidget : findsNothing);
    }
    expect(find.descendant(of: row, matching: find.text('220 V')), findsOneWidget);
  });

  testWidgets('remote read applies only a new reported snapshot', (tester) async {
    const previousReport = '2026-09-21T06:25:59+00:00';
    const newReport = '2026-11-19T03:00:00+00:00';
    var queryCount = 0;
    var stateReads = 0;
    var hasNewReport = false;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final endpoint = options.path.split('/').last;
          if (endpoint == 'control-state') stateReads++;
          if (endpoint == 'control') {
            expect(options.data, {'command': 'query_config', 'params': {}});
            queryCount++;
          }
          final Object data = switch (endpoint) {
            'config-schema' => [
                {
                  'param_key': 'set_max_chg_curr',
                  'control_type': 'number',
                  'unit': 'A',
                },
              ],
            'control-capabilities' => [
                {'command_code': 'query_config', 'is_enabled': true},
              ],
            'control-state' => {
                'reported': {'set_max_chg_curr': hasNewReport ? 27 : 24},
                'reported_at': hasNewReport ? newReport : previousReport,
                'reported_revision': hasNewReport ? 9 : 1789971959,
                'desired': {'value': 205.2},
                'updated_at': '2026-11-12T09:02:49.496747+00:00',
                'sync_status': 'pending',
              },
            'control' => {'task_id': 'test-query'},
            _ => throw StateError('Unexpected endpoint $endpoint'),
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
    await tester.pumpWidget(
      ScreenUtilInit(
        builder: (_, __) => const MaterialApp(
          locale: Locale('zh', 'CN'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RemoteSettingsTab(sn: 'PANEL-6KU', cloudOnline: true),
          ),
        ),
      ),
    );
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final readButton = find.widgetWithText(OutlinedButton, '读取设备');
    expect(queryCount, 1);
    final originalRect = tester.getRect(readButton);
    expect(find.text('24 A'), findsOneWidget);
    expect(find.text('正在读取设备配置...'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(stateReads, greaterThanOrEqualTo(3));
    expect(find.text('24 A'), findsOneWidget);
    expect(find.textContaining('上次读取'), findsNothing);
    expect(tester.getRect(readButton), originalRect);

    hasNewReport = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('27 A'), findsOneWidget);
    expect(find.text('正在读取设备配置...'), findsNothing);
    expect(find.textContaining('上次读取'), findsOneWidget);
    expect(tester.getRect(readButton), originalRect);
  });

  testWidgets('current picker preserves half-amp steps declared by the schema',
      (tester) async {
    final schema = ConfigParamSchema.fromJson({
      'param_key': 'set_ac_charge_current',
      'control_type': 'number',
      'min': 1,
      'max': 2.2,
      'step': 0.5,
      'unit': 'A',
    });
    num? selected;
    await pumpMinimalApp(
      tester,
      Scaffold(
        body: ConfigParamControl(
          schema: schema,
          value: 2.2,
          modified: false,
          onRequestChange: (value) => selected = value as num,
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '2.2 A'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '2.2 A'), findsNothing);
    expect(find.widgetWithText(ListTile, '2 A'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '1.5 A'));
    await tester.pumpAndSettle();
    expect(selected, 1.5);
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
