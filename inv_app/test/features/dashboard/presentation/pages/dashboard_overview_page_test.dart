import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/dashboard/domain/entities/dashboard_data.dart';
import 'package:inv_app/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:inv_app/features/dashboard/presentation/pages/dashboard_overview_page.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/pump_app.dart';

class _MockDashboardBloc extends MockBloc<DashboardEvent, DashboardState>
    implements DashboardBloc {}

class _MockConnectionModeService extends Mock
    implements ConnectionModeService {}

void main() {
  late _MockDashboardBloc dashboardBloc;
  late _MockConnectionModeService connectionModeService;

  const cachedState = DashboardLoaded(
    data: DashboardData(
      todayEnergy: 0,
      totalEnergy: 0,
      deviceTotal: 0,
      onlineCount: 0,
      offlineCount: 0,
      faultCount: 0,
      trendData: [],
      stationRanking: [],
      recentAlarms: [],
      isFromCache: true,
    ),
    isSSEConnected: true,
  );

  setUp(() async {
    await getIt.reset();
    dashboardBloc = _MockDashboardBloc();
    connectionModeService = _MockConnectionModeService();
    when(() => connectionModeService.isGuestLocalMode).thenReturn(false);
    getIt.registerSingleton<ConnectionModeService>(connectionModeService);
    whenListen(
      dashboardBloc,
      const Stream<DashboardState>.empty(),
      initialState: cachedState,
    );
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets(
    'cached-data retry is an accessible button with a 48px touch target',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final l10n =
          await AppLocalizations.delegate.load(const Locale('en', 'US'));

      await pumpApp(
        tester,
        const DashboardOverviewPage(),
        dashboardBloc: dashboardBloc,
        locale: const Locale('en', 'US'),
      );

      final retryButton = find.widgetWithText(TextButton, l10n.retry);
      expect(retryButton, findsOneWidget);

      final retrySemantics = tester.getSemantics(retryButton);
      expect(retrySemantics.label, l10n.retry);
      expect(retrySemantics.hasFlag(SemanticsFlag.isButton), isTrue);

      final size = tester.getSize(retryButton);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));

      semantics.dispose();
    },
  );
}
