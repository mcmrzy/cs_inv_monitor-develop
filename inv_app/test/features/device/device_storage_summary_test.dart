import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/entities/bms_summary.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/device/presentation/pages/device_storage_page.dart';
import 'package:inv_app/features/device/presentation/widgets/bms_summary_view.dart';
import 'package:inv_app/features/device/presentation/widgets/bms_summary_components.dart';

import '../../bms_summary_test.dart' show summaryFixture;
import '../../helpers/pump_app.dart';

void main() {
  late Map<String, dynamic> realtime;
  late bool requestFails;
  final previewFont = Platform.environment['BMS_SUMMARY_PREVIEW_FONT'];
  final now = DateTime.utc(2026, 10, 8, 6, 32, 7);

  Map<String, dynamic> fixture({bool alarm = false, bool expired = false}) => {
        ...summaryFixture(),
        'age_ms': 800,
        'warning_flag': alarm ? 1 : 0,
        'protection_flag': alarm ? 1 : 0,
        'status_fault_flag': 0x0A00,
        'updated_at':
            now.subtract(const Duration(milliseconds: 800)).toIso8601String(),
        'reported_at': now.toIso8601String(),
        'expires_at':
            now.add(Duration(seconds: expired ? -1 : 210)).toIso8601String(),
      };

  Future<void> surface(
    WidgetTester tester,
    Map<String, dynamic> data, {
    DateTime Function()? clock,
    Locale locale = const Locale('en', 'US'),
    ThemeData? theme,
    GlobalKey? boundary,
  }) =>
      pumpMinimalApp(
        tester,
        RepaintBoundary(
          key: boundary,
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                locale.languageCode == 'zh' ? '储能电池' : 'Storage Battery',
              ),
            ),
            body: BmsSummaryView(
              summary: BmsSummary.fromJson(data),
              onRefresh: () async {},
              clock: clock ?? () => now,
            ),
          ),
        ),
        locale: locale,
        theme: theme,
      );

  Future<void> tab(WidgetTester tester, int i) async {
    await tester.tap(find.byKey(ValueKey('bms-tab-$i')));
    await tester.pumpAndSettle();
  }

  Future<void> expand(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  setUp(() {
    requestFails = false;
    realtime = {
      'bms_summary': {
        ...fixture(alarm: true),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'reported_at': DateTime.now().toUtc().toIso8601String(),
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(seconds: 210))
            .toIso8601String(),
      },
      'bms': {'bms_online': 0},
    };
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (requestFails) {
            handler.reject(DioException(requestOptions: options));
          } else {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'code': 0,
                  'data': {'realtime': realtime},
                },
              ),
            );
          }
        },
      ),
    );
    getIt.registerSingleton<Dio>(dio);
  });
  tearDown(() async => getIt.reset());

  testWidgets(
      'production page prefers CMD08 and retains snapshot on refresh failure',
      (tester) async {
    await pumpMinimalApp(
      tester,
      const DeviceStoragePage(sn: 'SN'),
      locale: const Locale('en', 'US'),
    );
    expect(find.text('51.24 V'), findsOneWidget);
    expect(find.text('80.5 %'), findsOneWidget);
    requestFails = true;
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Refresh failed · last received sample'), findsOneWidget);
    expect(find.text('51.24 V'), findsOneWidget);
    requestFails = false;
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Refresh failed · last received sample'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('overview, cell jump, 16 selections, null and balance details',
      (tester) async {
    await surface(tester, fixture());
    expect(find.text('-12.34 A'), findsOneWidget);
    expect(find.text('98.5 %'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('bms-cell-jump')));
    await tester.tap(find.byKey(const ValueKey('bms-cell-jump')));
    await tester.pumpAndSettle();
    expect(find.byType(BarChart), findsOneWidget);
    expect(find.text('15 mV'), findsOneWidget);
    for (var i = 0; i < 16; i++) {
      final cell = find.byKey(ValueKey('bms-cell-$i'));
      await tester.ensureVisible(cell);
      await tester.tap(cell);
      await tester.pumpAndSettle();
      final detail = find.byKey(const ValueKey('bms-selected-cell'));
      expect(
        find.descendant(
          of: detail,
          matching: find.text('C${(i + 1).toString().padLeft(2, '0')}'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(cell).flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
    }
    await tester.ensureVisible(find.byKey(const ValueKey('bms-cell-3')));
    await tester.tap(find.byKey(const ValueKey('bms-cell-3')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('bms-selected-cell')),
        matching: find.text('--'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'expiry ticks, masks metrics in every tab and preserves historical flags/raw',
      (tester) async {
    var clock = now;
    await surface(
      tester,
      {
        ...fixture(),
        'expires_at': now.add(const Duration(seconds: 1)).toIso8601String(),
      },
      clock: () => clock,
    );
    expect(find.text('51.24 V'), findsOneWidget);
    clock = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('BMS data expired'), findsOneWidget);
    expect(find.text('51.24 V'), findsNothing);
    await tab(tester, 1);
    expect(find.byType(BarChart), findsNothing);
    expect(find.text('3315 mV'), findsNothing);
    await tab(tester, 2);
    expect(find.text('Historical snapshot · not live state'), findsOneWidget);
    await expand(tester, 'Raw quantities');
    expect(find.text('-32768 raw'), findsOneWidget);
    expect(find.text('4294967295 raw'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('explicit offline and unknown expiry stay unavailable',
      (tester) async {
    for (final data in [
      {...fixture(), 'bms_online': 0},
      {...fixture(), 'expires_at': null},
      {...fixture(), 'age_ms': 120001},
      {...fixture(), 'layout': 1},
      {...fixture(), 'layout': null},
      {...fixture(), 'battery_count': null},
      {...fixture(), 'soc_raw': null},
      {...fixture(), 'age_ms': null},
      {
        ...fixture(),
        'expires_at': now.add(const Duration(seconds: 216)).toIso8601String(),
      },
    ]) {
      await surface(tester, data);
      expect(find.text('51.24 V'), findsNothing);
      expect(find.text('--'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('missing and reserved operating state never imply no activity',
      (tester) async {
    for (final word in [null, 0x20C8]) {
      await surface(tester, {...fixture(), 'status_fault_flag': word});
      expect(find.text('Operating state unknown'), findsWidgets);
      expect(find.text('No operating state reported'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
    await surface(tester, {...fixture(), 'status_fault_flag': 0});
    expect(find.text('No operating state reported'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('actual dark status and diagnostic foregrounds meet 4.5 contrast',
      (tester) async {
    for (final overrides in [
      <String, dynamic>{},
      {'warning_flag': 1},
      {'protection_flag': 1},
      {'status_fault_flag': 1},
      {'status_fault_flag': null},
    ]) {
      await surface(
        tester,
        {...fixture(), ...overrides},
        theme: ThemeData.dark(useMaterial3: true),
      );
      final surfaceMaterial = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(BmsSummaryView),
              matching: find.byType(Material),
            )
            .first,
      );
      final background = surfaceMaterial.color!.computeLuminance();
      final foreground = tester
          .widget<Text>(find.text('Online'))
          .style!
          .color!
          .computeLuminance();
      expect(
        (foreground + .05) / (background + .05),
        greaterThanOrEqualTo(4.5),
      );
      for (final text in tester.widgetList<Text>(find.text('Cell OV'))) {
        final fg = text.style!.color!.computeLuminance();
        expect((fg + .05) / (background + .05), greaterThanOrEqualTo(4.5));
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'operating and reserved bits are not active faults; missing words are unknown',
      (tester) async {
    await surface(tester, {...fixture(), 'status_fault_flag': 0xDF00});
    final faultRow = find.widgetWithText(BmsReadout, 'Faults');
    expect(
      find.descendant(of: faultRow, matching: find.text('No active items')),
      findsOneWidget,
    );
    expect(find.textContaining('Charge MOS ON'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber), findsNothing);
    await tester.pumpWidget(const SizedBox());
    for (final data in [
      {...fixture(), 'status_fault_flag': 0x20C8},
      {...fixture(), 'warning_flag': 0x40},
      {...fixture(), 'protection_flag': 0x8000},
      {
        ...fixture(),
        'warning_flag': null,
        'protection_flag': null,
        'status_fault_flag': null,
      },
    ]) {
      await surface(tester, data);
      expect(find.text('Diagnostic status unknown'), findsWidgets);
      expect(find.byIcon(Icons.warning_amber), findsNothing);
      await tab(tester, 2);
      await expand(tester, 'Status words & protocol codes');
      if (data['status_fault_flag'] == 0x20C8) {
        expect(find.textContaining('Reserved bit 13'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    }
    await surface(tester, {...fixture(), 'status_fault_flag': 0x0037});
    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    expect(find.textContaining('AFE Comm Fault'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'all provided fields, reported extrema, signed zero temperatures and exact payload',
      (tester) async {
    final data = {
      ...fixture(),
      'max_cell_voltage': 3500,
      'min_cell_voltage': 3200,
    };
    await surface(tester, data);
    await tab(tester, 1);
    expect(find.text('3315 mV'), findsWidgets);
    expect(find.text('3500 mV'), findsNothing);
    await tab(tester, 2);
    expect(
      find.text(DateFormat('yyyy-MM-dd HH:mm:ss').format(now.toLocal())),
      findsOneWidget,
    );
    await expand(tester, 'All measurements');
    for (final value in [
      '18.123 Ah',
      '28.456 Ah',
      '100.789 Ah',
      '3500 mV',
      '3200 mV',
      '-5.5 °C',
      '0.0 °C',
      '-12.3 °C',
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    expect(find.text('Cell 16'), findsOneWidget);
    expect(find.text('Cell temperature 4'), findsOneWidget);
    await expand(tester, 'Status words & protocol codes');
    expect(find.text('2 raw'), findsOneWidget);
    expect(find.text('7 raw'), findsOneWidget);
    expect(find.text('11 raw'), findsOneWidget);
    await expand(tester, 'Raw quantities');
    for (final value in [
      '4294967295 raw',
      '123456 raw',
      '500 raw',
      '-32768 raw',
      '805 raw',
      '985 raw',
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    await expand(tester, 'Raw payload (100 bytes)');
    final payload =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(
      payload.split(' '),
      List.generate(
        100,
        (i) => i.toRadixString(16).padLeft(2, '0').toUpperCase(),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final language in ['zh', 'en']) {
    for (final dark in [false, true]) {
      for (final width in [320, 360, 600]) {
        testWidgets(
            '$language ${dark ? 'dark' : 'light'} width $width large text and expanded tabs',
            (tester) async {
          tester.view.physicalSize = Size(width.toDouble(), 800);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue =
              width == 320 ? 1.8 : 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await surface(
            tester,
            fixture(alarm: true),
            locale: Locale(language),
            theme: dark
                ? ThemeData.dark(useMaterial3: true)
                : ThemeData.light(useMaterial3: true),
          );
          await tab(tester, 1);
          await tester.ensureVisible(find.byKey(const ValueKey('bms-cell-15')));
          await tester.tap(find.byKey(const ValueKey('bms-cell-15')));
          await tester.pumpAndSettle();
          await tab(tester, 2);
          for (final label in language == 'zh'
              ? ['状态字与协议原值', '全部测量值', '原始量', '原始报文（100 字节）']
              : [
                  'Status words & protocol codes',
                  'All measurements',
                  'Raw quantities',
                  'Raw payload (100 bytes)',
                ]) {
            await expand(tester, label);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }

  testWidgets('legacy offline and absent groups retain existing empty states',
      (tester) async {
    realtime = {
      'bms': {'bms_online': 0},
    };
    await pumpMinimalApp(
      tester,
      const DeviceStoragePage(sn: 'SN'),
      locale: const Locale('en', 'US'),
    );
    expect(find.textContaining('Battery management offline'), findsOneWidget);
    realtime = {};
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('No storage battery connected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final language in ['zh', 'en']) {
    testWidgets(
        'legacy $language flat payload, zero temperatures and alarm words fit small dark screen',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      realtime = {
        'bms_online': 1,
        'bms_soc': 80.5,
        'bms_soh': 98,
        'bms_alarm_w0': 65535,
        'bms_alarm_w1': 65535,
        'bms_alarm_w2': 65535,
        'bms_cell_temp_max': 0,
        'bms_cell_temp_min': -5,
        'battery_voltage': 51.2,
        'battery_current': -12,
      };
      final preview = Platform.environment['STORAGE_LEGACY_PREVIEW'];
      final boundary = GlobalKey();
      if (preview != null && previewFont != null) {
        await tester.runAsync(() async {
          final font = FontLoader('Roboto')
            ..addFont(
                File(previewFont).readAsBytes().then(ByteData.sublistView));
          await font.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
        });
      }
      await pumpMinimalApp(
          tester,
          RepaintBoundary(
              key: boundary, child: const DeviceStoragePage(sn: 'SN')),
          locale: Locale(language),
          theme: ThemeData.dark(useMaterial3: true));
      expect(find.text('51.20 V'), findsOneWidget);
      expect(find.text('-614 W'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (preview != null) {
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$preview-$language.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      final technical =
          find.text(language == 'zh' ? '技术详情' : 'Technical details');
      await tab(tester, 2);
      await tester.scrollUntilVisible(technical, 200);
      await Scrollable.ensureVisible(tester.element(technical), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(technical);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('0.0 °C'), 200);
      expect(find.text('0.0 °C'), findsOneWidget);
      expect(find.text('-5.0 °C'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final language in ['zh', 'en']) {
    for (final scenario in [
      'normal',
      'cells-alarm',
      'diagnostics',
      'expired',
      'wide-cells',
      'large-text',
      'dark',
      'dark-alarm',
      'large-cells-alarm',
      'large-diagnostics',
      'large-expired',
      'wide-normal',
      'wide-cells-alarm',
      'wide-diagnostics',
      'wide-expired',
    ]) {
      testWidgets(
        'real glyph $language $scenario screenshot',
        (tester) async {
          await tester.runAsync(() async {
            final font = FontLoader('Roboto');
            font.addFont(
              File(previewFont!).readAsBytes().then(ByteData.sublistView),
            );
            await font.load();
            final icons = FontLoader('MaterialIcons');
            icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
            await icons.load();
          });
          final width = scenario.startsWith('wide-')
              ? 600
              : scenario.startsWith('large-')
                  ? 320
                  : 360;
          tester.view.physicalSize = Size(width.toDouble(), 800);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue =
              scenario.startsWith('large-') ? 1.8 : 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final boundary = GlobalKey();
          await surface(
            tester,
            fixture(
              alarm: scenario.contains('alarm'),
              expired: scenario.contains('expired'),
            ),
            boundary: boundary,
            locale: Locale(language),
            theme: scenario.startsWith('dark')
                ? ThemeData.dark(useMaterial3: true)
                : ThemeData.light(useMaterial3: true),
          );
          if (scenario.contains('cells')) await tab(tester, 1);
          if (scenario.contains('diagnostics')) await tab(tester, 2);
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final render = boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await render.toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              'build/bms_summary_previews/production-$language-$scenario.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          if (scenario.contains('diagnostics')) {
            for (final label in language == 'zh'
                ? ['状态字与协议原值', '全部测量值', '原始量', '原始报文（100 字节）']
                : [
                    'Status words & protocol codes',
                    'All measurements',
                    'Raw quantities',
                    'Raw payload (100 bytes)',
                  ]) {
              await expand(tester, label);
              expect(tester.takeException(), isNull);
            }
          }
          await tester.pumpWidget(const SizedBox());
        },
        skip: previewFont == null,
      );
    }
  }
}
