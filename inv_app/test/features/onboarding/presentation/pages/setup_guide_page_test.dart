import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/onboarding/presentation/pages/setup_guide_page.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

class _StationBloc extends MockBloc<StationEvent, StationState>
    implements StationBloc {}

class _DeviceBloc extends MockBloc<DeviceEvent, DeviceState>
    implements DeviceBloc {}

class _Storage extends Mock implements StorageService {}

void main() {
  const primary = Key('setup-guide-primary-action');
  const secondary = Key('setup-guide-secondary-action');
  late _StationBloc stationBloc;
  late _DeviceBloc deviceBloc;
  late _Storage storage;
  late StreamController<StationState> stationStates;
  late StreamController<DeviceState> deviceStates;

  setUp(() async {
    await getIt.reset();
    stationBloc = _StationBloc();
    deviceBloc = _DeviceBloc();
    stationStates = StreamController<StationState>.broadcast();
    deviceStates = StreamController<DeviceState>.broadcast();
    whenListen(stationBloc, stationStates.stream,
        initialState: StationInitial(),);
    whenListen(deviceBloc, deviceStates.stream, initialState: DeviceInitial());
    storage = _Storage();
    when(() => storage.saveString(any(), any())).thenAnswer((_) async {});
    getIt.registerSingleton<StorageService>(storage);
  });

  tearDown(() async {
    await stationStates.close();
    await deviceStates.close();
    await getIt.reset();
  });

  Future<void> openGuide(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    Locale locale = const Locale('zh', 'CN'),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/setup-guide',
          builder: (_, __) => MultiBlocProvider(
            providers: [
              BlocProvider<StationBloc>.value(value: stationBloc),
              BlocProvider<DeviceBloc>.value(value: deviceBloc),
            ],
            child: const SetupGuidePage(),
          ),
        ),
        for (final path in ['/station/create', '/add-device', '/wifi-config'])
          GoRoute(
            path: path,
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => context.pop(),
                child: Text(path),
              ),
            ),
          ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(router.push<void>('/setup-guide'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  testWidgets('固定主按钮直达各步骤，完成后自动进到下一步', (tester) async {
    await openGuide(tester);

    await tap(tester, primary);
    expect(find.text('/station/create'), findsOneWidget);
    await tester.tap(find.text('/station/create'));
    await tester.pumpAndSettle();
    stationStates.add(const StationSummaryLoaded(stations: [1], summary: {}));
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 3 步'), findsOneWidget);

    await tap(tester, primary);
    expect(find.text('/add-device'), findsOneWidget);
    await tester.tap(find.text('/add-device'));
    await tester.pumpAndSettle();
    deviceStates.add(const DeviceListLoaded(devices: [1], total: 1));
    await tester.pumpAndSettle();
    expect(find.text('第 3 / 3 步'), findsOneWidget);
    expect(find.text('可选'), findsOneWidget);

    await tap(tester, primary);
    expect(find.text('/wifi-config'), findsOneWidget);
    await tester.tap(find.text('/wifi-config'));
    await tester.pumpAndSettle();
    await tap(tester, secondary);
    expect(find.text('home'), findsOneWidget);
    verify(() => storage.saveString('setup_guide_done', '1')).called(1);
  });

  for (final scenario in [
    (size: const Size(320, 568), scale: 2.0),
    (size: const Size(812, 375), scale: 1.0),
  ]) {
    testWidgets('英文 ${scenario.size} ×${scenario.scale} 的三步操作可见',
        (tester) async {
      await openGuide(
        tester,
        size: scenario.size,
        scale: scenario.scale,
        locale: const Locale('en'),
      );

      for (var step = 1; step <= 3; step++) {
        expect(find.text('Step $step of 3'), findsOneWidget);
        expect(find.byKey(primary).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (step < 3) await tap(tester, secondary);
      }
    });
  }
}
