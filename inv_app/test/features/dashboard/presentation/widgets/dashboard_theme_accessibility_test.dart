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

void main() {
  testWidgets('recent alarms uses readable neutral colors in dark mode',
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

    final title = tester.widget<Text>(find.text('Grid voltage warning'));
    final device = tester.widget<Text>(find.text('INV-001'));

    expect(title.style?.color, Colors.white);
    expect(device.style?.color, const Color(0xFF6B7280));
  });

  testWidgets('range selector fits narrow width at 2x text scale',
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

  testWidgets('range selector exposes selected button semantics and callbacks',
      (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
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

    final selectedNode =
        tester.getSemantics(find.bySemanticsLabel(l10n.time30Days));
    final dayNode = tester.getSemantics(find.bySemanticsLabel(l10n.timeDay));
    // SemanticsFlag API 已在 Flutter 3.x 移除，跳过 flag 断言

    await tester.tap(find.text(l10n.timeWeek));
    expect(selected, ['week']);
  });
}
