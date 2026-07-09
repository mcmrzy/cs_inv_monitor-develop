/// Widget test helper that pumps widgets with the full app provider setup.
///
/// Use [pumpApp] in widget tests to render a widget wrapped in all necessary
/// providers (BlocProviders, MaterialApp, localization delegates). This ensures
/// that widgets under test have access to the same inherited providers they
/// would receive in the real application.
///
/// ```dart
/// testWidgets('renders counter', (tester) async {
///   await pumpApp(tester, const MyWidget());
///   expect(find.text('0'), findsOneWidget);
/// });
/// ```
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/alarm/presentation/bloc/alarm_bloc.dart';
import 'package:inv_app/features/notification/presentation/bloc/notification_bloc.dart';
import 'package:inv_app/features/dashboard/presentation/bloc/dashboard_bloc.dart';

/// Pumps [widget] wrapped in the full set of app providers.
///
/// By default this injects mock BlocProviders. You can override any of them
/// by passing custom instances via the named parameters.
///
/// Additional [providers] can be supplied to wrap the widget with extra
/// [BlocProvider] or [RepositoryProvider] instances that are not part of
/// the standard set.
///
/// The [locale] parameter defaults to Chinese (zh_CN) which matches the
/// production default. Set it to `Locale('en', 'US')` for English tests.
Future<void> pumpApp(
  WidgetTester tester,
  Widget widget, {
  AuthBloc? authBloc,
  StationBloc? stationBloc,
  DeviceBloc? deviceBloc,
  AlarmBloc? alarmBloc,
  NotificationBloc? notificationBloc,
  DashboardBloc? dashboardBloc,
  List<BlocProvider> additionalProviders = const [],
  Locale locale = const Locale('zh', 'CN'),
  ThemeData? theme,
}) async {
  // Collect all BlocProviders — only add those that are provided (non-null).
  final blocProviders = <BlocProvider>[
    if (authBloc != null) BlocProvider<AuthBloc>.value(value: authBloc),
    if (stationBloc != null)
      BlocProvider<StationBloc>.value(value: stationBloc),
    if (deviceBloc != null) BlocProvider<DeviceBloc>.value(value: deviceBloc),
    if (alarmBloc != null) BlocProvider<AlarmBloc>.value(value: alarmBloc),
    if (notificationBloc != null)
      BlocProvider<NotificationBloc>.value(value: notificationBloc),
    if (dashboardBloc != null)
      BlocProvider<DashboardBloc>.value(value: dashboardBloc),
    ...additionalProviders,
  ];

  Widget app = _buildMaterialApp(widget, locale, theme);

  if (blocProviders.isNotEmpty) {
    app = MultiBlocProvider(providers: blocProviders, child: app);
  }

  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

/// Pumps [widget] with only a [MaterialApp] and localization — no BlocProviders.
///
/// Useful for testing pure/presentational widgets that do not depend on any
/// Bloc state.
Future<void> pumpMinimalApp(
  WidgetTester tester,
  Widget widget, {
  Locale locale = const Locale('zh', 'CN'),
  ThemeData? theme,
}) async {
  await tester.pumpWidget(_buildMaterialApp(widget, locale, theme));
  await tester.pumpAndSettle();
}

/// Builds the inner [MaterialApp] with localization delegates.
MaterialApp _buildMaterialApp(
  Widget child,
  Locale locale,
  ThemeData? theme,
) {
  return MaterialApp(
    locale: locale,
    theme: theme ?? ThemeData.light(useMaterial3: true),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Material(child: child),
  );
}
