/// Smoke tests for the test helper infrastructure.
///
/// Verifies that [pumpApp], [pumpMinimalApp], mock providers, and test data
/// factories all function correctly. These tests should always pass — if
/// they fail the test infrastructure itself is broken.
library;

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'pump_app.dart';
import 'mock_providers.dart';
import 'test_data.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/l10n/app_localizations.dart';

void main() {
  // -----------------------------------------------------------------------
  // Test data factories
  // -----------------------------------------------------------------------
  group('test_data factories', () {
    test('createTestUser returns valid User with defaults', () {
      final user = createTestUser();
      expect(user.id, 1);
      expect(user.phone, '13800138000');
      expect(user.email, 'test@example.com');
      expect(user.role, 3);
      expect(user.status, 1);
    });

    test('createTestUser allows overrides', () {
      final user = createTestUser(id: 42, phone: '111', role: 0);
      expect(user.id, 42);
      expect(user.phone, '111');
      expect(user.role, 0);
    });

    test('createTestLoginResponse returns valid LoginResponse', () {
      final response = createTestLoginResponse();
      expect(response.token, 'test_access_token');
      expect(response.refreshToken, 'test_refresh_token');
      expect(response.user.id, 1);
    });

    test('createTestLoginResponse allows custom user', () {
      final admin = createTestUser(role: 0);
      final response = createTestLoginResponse(user: admin);
      expect(response.user.role, 0);
    });

    test('failure factories return correct types', () {
      expect(createTestServerFailure(), isA<ServerFailure>());
      expect(createTestNetworkFailure(), isA<NetworkFailure>());
      expect(createTestCacheFailure(), isA<CacheFailure>());
      expect(createTestValidationFailure(), isA<ValidationFailure>());
      expect(createTestUnauthorizedFailure(), isA<UnauthorizedFailure>());
    });

    test('createTestDeviceMap returns valid device map', () {
      final device = createTestDeviceMap(index: 0);
      expect(device['sn'], 'TEST_SN_1');
      expect(device['name'], 'Test Device 1');
      expect(device['status'], 'online');
    });

    test('createTestDeviceListResponse returns paginated structure', () {
      final response = createTestDeviceListResponse(count: 3);
      expect(response['total'], 3);
      expect((response['list'] as List).length, 3);
    });

    test('createTestStationListResponse returns paginated structure', () {
      final response = createTestStationListResponse(count: 2);
      expect(response['total'], 2);
      expect((response['list'] as List).length, 2);
    });

    test('createTestAlarmListResponse returns paginated structure', () {
      final response = createTestAlarmListResponse(count: 4);
      expect(response['total'], 4);
      expect((response['list'] as List).length, 4);
    });

    test('createTestDashboardStatistics returns expected keys', () {
      final stats = createTestDashboardStatistics();
      expect(stats.containsKey('total_power'), isTrue);
      expect(stats.containsKey('today_power'), isTrue);
      expect(stats.containsKey('total_devices'), isTrue);
    });
  });

  // -----------------------------------------------------------------------
  // Mock providers
  // -----------------------------------------------------------------------
  group('mock providers', () {
    test('MockAuthRepository can be instantiated and stubbed', () async {
      final mockRepo = MockAuthRepository();
      when(() => mockRepo.logout()).thenAnswer(
        (_) async => right<Failure, void>(null),
      );
      final result = await mockRepo.logout();
      expect(result.isRight(), isTrue);
    });

    test('MockStorageService can be instantiated and stubbed', () async {
      final mockStorage = MockStorageService();
      when(() => mockStorage.getToken()).thenAnswer(
        (_) async => 'fake_token',
      );
      final token = await mockStorage.getToken();
      expect(token, 'fake_token');
    });

    test('MockMQTTService can be instantiated and stubbed', () async {
      final mockMqtt = MockMQTTService();
      when(() => mockMqtt.isConnected).thenReturn(false);
      expect(mockMqtt.isConnected, isFalse);
    });

    test('MockDeviceRepository can be stubbed with test data', () async {
      final mockRepo = MockDeviceRepository();
      when(() => mockRepo.getList()).thenAnswer(
        (_) async => right<Failure, Map<String, dynamic>>(
          createTestDeviceListResponse(count: 2),
        ),
      );
      final result = await mockRepo.getList();
      result.fold(
        (_) => fail('Expected right'),
        (data) => expect(data['total'], 2),
      );
    });
  });

  // -----------------------------------------------------------------------
  // pumpMinimalApp
  // -----------------------------------------------------------------------
  group('pumpMinimalApp', () {
    testWidgets('renders a simple widget with localization', (tester) async {
      await pumpMinimalApp(
        tester,
        const Center(child: Text('Hello')),
      );

      expect(find.text('Hello'), findsOneWidget);
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('provides AppLocalizations', (tester) async {
      AppLocalizations? captured;
      await pumpMinimalApp(
        tester,
        Builder(
          builder: (context) {
            captured = AppLocalizations.of(context);
            return const SizedBox();
          },
        ),
      );

      expect(captured, isNotNull);
    });
  });

  // -----------------------------------------------------------------------
  // pumpApp with mock BlocProviders
  // -----------------------------------------------------------------------
  group('pumpApp', () {
    testWidgets('renders widget without any bloc providers', (tester) async {
      await pumpApp(tester, const Center(child: Text('No Blocs')));

      expect(find.text('No Blocs'), findsOneWidget);
    });

    testWidgets('injects AuthBloc provider when supplied', (tester) async {
      final mockAuthBloc = MockAuthBloc();
      when(() => mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(AuthInitial()),
      );
      when(() => mockAuthBloc.state).thenReturn(AuthInitial());

      await pumpApp(
        tester,
        BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            return Text(state.runtimeType.toString());
          },
        ),
        authBloc: mockAuthBloc,
      );

      expect(find.text('AuthInitial'), findsOneWidget);
    });

    testWidgets('supports custom theme override', (tester) async {
      final darkTheme = ThemeData.dark(useMaterial3: true);
      await pumpApp(
        tester,
        Builder(
          builder: (context) {
            final brightness = Theme.of(context).brightness;
            return Text(brightness == Brightness.dark ? 'dark' : 'light');
          },
        ),
        theme: darkTheme,
      );

      expect(find.text('dark'), findsOneWidget);
    });

    testWidgets('supports English locale', (tester) async {
      await pumpMinimalApp(
        tester,
        const Center(child: Text('English')),
        locale: const Locale('en', 'US'),
      );

      expect(find.text('English'), findsOneWidget);
    });
  });
}
