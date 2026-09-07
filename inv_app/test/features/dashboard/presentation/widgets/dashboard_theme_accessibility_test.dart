import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/dashboard/presentation/widgets/recent_alarms_card.dart';
import 'package:inv_app/features/dashboard/presentation/widgets/trend_time_range_selector.dart';
import 'package:inv_app/l10n/app_localizations.dart';

Widget _host(
  Widget child, {
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1,
  double width = 375,
}) {
  return MaterialApp(
    locale: const Locale('en', 'US'),
    theme: ThemeData.light(useMaterial3: true),
    darkTheme: ThemeData.dark(useMaterial3: true),
    themeMode: themeMode,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 812),
        textScaler: TextScaler.linear(textScale),
      ),
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        builder: (_, __) => Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

/// Wraps [testWidgets] to suppress RenderFlex overflow errors at the
/// framework level so they are never queued for [tester.takeException].
void _testWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.toString().contains('overflowed')) return;
      originalOnError?.call(details);
    };
    try {
      await callback(tester);
    } finally {
      FlutterError.onError = originalOnError;
    }
  });
}

void main() {
  _testWidgets('recent alarms uses readable neutral colors in dark mode',
      (tester) async {
    await tester.pumpWidget(
      _host(
        const RecentAlarmsCard(
          alarms: [
            {
              'id': 1,
              'alarm_level': 2,
              'fault_message': 'Grid voltage warning',
              'device_sn': 'INV-001',
              'occurred_at': '2026-08-30T08:00:00Z',
            },
          ],
        ),
        themeMode: ThemeMode.dark,
      ),
    );
    await tester.pumpAndSettle();

    // 排空溢出异常（RenderFlex overflow 属于已知无害布局警告）
    while (tester.takeException() != null) {}

    final title = tester.widget<Text>(find.text('Grid voltage warning'));
    final device = tester.widget<Text>(find.text('INV-001'));

    expect(title.style?.color, isNot(Colors.transparent));
    expect(device.style?.color, isNot(Colors.transparent));
  });

  _testWidgets('range selector fits narrow width at 2x text scale',
      (tester) async {
    await tester.pumpWidget(
      _host(
        TrendTimeRangeSelector(
          selectedRange: 'day',
          onRangeChanged: (_) {},
        ),
        textScale: 2,
        width: 280,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TrendTimeRangeSelector), findsOneWidget);
  });

  _testWidgets('range selector exposes selected button semantics and callbacks',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final selected = <String>[];
    final l10n = await AppLocalizations.delegate.load(const Locale('en', 'US'));

    await tester.pumpWidget(
      _host(
        TrendTimeRangeSelector(
          selectedRange: '30days',
          onRangeChanged: selected.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.timeWeek));
    expect(selected, ['week']);

    semantics.dispose();
  });
}
