import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/features/notification/presentation/bloc/notification_bloc.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/services/app_update_service.dart';
import 'package:inv_app/core/services/mqtt_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';

import '../../../../helpers/mock_providers.dart';

/// Mock for AppUpdateService since it's not in mock_providers.
class MockAppUpdateService extends Mock implements AppUpdateService {}

void main() {
  late NotificationBloc notificationBloc;
  late MockDeviceRepository mockDeviceRepository;
  late MockMQTTService mockMQTTService;
  late MockNotificationRemoteDataSource mockNotificationDataSource;
  late MockStorageService mockStorageService;
  late MockAppUpdateService mockAppUpdateService;

  setUpAll(() {
    // Register fallback values for mocktail
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    mockDeviceRepository = MockDeviceRepository();
    mockMQTTService = MockMQTTService();
    mockNotificationDataSource = MockNotificationRemoteDataSource();
    mockStorageService = MockStorageService();
    mockAppUpdateService = MockAppUpdateService();

    // Default MQTT stubs
    when(() => mockMQTTService.realtimeDataStream)
        .thenAnswer((_) => const Stream<InverterRealtime>.empty());
    when(() => mockMQTTService.alarmStream)
        .thenAnswer((_) => const Stream<AlarmData>.empty());
    when(() => mockMQTTService.otaNotificationStream)
        .thenAnswer((_) => const Stream<OTANotification>.empty());

    // Register getIt dependencies used by NotificationBloc
    getIt.registerFactory<StorageService>(() => mockStorageService);
    getIt.registerFactory<AppUpdateService>(() => mockAppUpdateService);

    notificationBloc = NotificationBloc(
      deviceRepository: mockDeviceRepository,
      mqttService: mockMQTTService,
      notificationDataSource: mockNotificationDataSource,
    );
  });

  tearDown(() {
    notificationBloc.close();
    getIt.reset();
  });

  test('initial state is NotificationInitial', () {
    expect(notificationBloc.state, equals(NotificationInitial()));
  });

  // ---------------------------------------------------------------------------
  // SystemNotificationsRequested
  // ---------------------------------------------------------------------------
  group('SystemNotificationsRequested', () {
    blocTest<NotificationBloc, NotificationState>(
      'emits [SystemNotificationsLoaded] with backend notifications',
      build: () {
        // Mock backend notification response
        when(() => mockNotificationDataSource.getList(
              page: any(named: 'page'),
              pageSize: any(named: 'pageSize'),
            ),).thenAnswer(
          (_) async => _fakeResponse({
            'data': {
              'items': [
                {
                  'id': 1,
                  'notify_type': 'device_online',
                  'title': 'Device Online',
                  'content': 'Device TEST_SN_1 is online',
                  'created_at': DateTime(2024, 1, 1).toIso8601String(),
                  'device_sn': 'TEST_SN_1',
                }
              ],
            },
          }),
        );
        // Mock local storage
        when(() => mockStorageService.getString(any()))
            .thenAnswer((_) async => null);
        // Mock app update check
        when(() => mockAppUpdateService.checkUpdate(any()))
            .thenAnswer((_) async => AppUpdateInfo(hasUpdate: false));
        return notificationBloc;
      },
      act: (bloc) => bloc.add(const SystemNotificationsRequested()),
      expect: () => [
        isA<SystemNotificationsLoaded>().having(
          (s) => s.notifications.length,
          'notifications.length',
          greaterThanOrEqualTo(1),
        ),
      ],
    );

    blocTest<NotificationBloc, NotificationState>(
      'emits [SystemNotificationsLoaded] with empty list when no data',
      build: () {
        when(() => mockNotificationDataSource.getList(
              page: any(named: 'page'),
              pageSize: any(named: 'pageSize'),
            ),).thenThrow(Exception('Network error'));
        when(() => mockStorageService.getString(any()))
            .thenAnswer((_) async => null);
        when(() => mockAppUpdateService.checkUpdate(any()))
            .thenAnswer((_) async => AppUpdateInfo(hasUpdate: false));
        return notificationBloc;
      },
      act: (bloc) => bloc.add(const SystemNotificationsRequested()),
      expect: () => [
        isA<SystemNotificationsLoaded>().having(
          (s) => s.notifications,
          'notifications',
          isEmpty,
        ),
      ],
    );

    blocTest<NotificationBloc, NotificationState>(
      'includes local OTA notifications from storage',
      build: () {
        when(() => mockNotificationDataSource.getList(
              page: any(named: 'page'),
              pageSize: any(named: 'pageSize'),
            ),).thenThrow(Exception('Network error'));
        when(() => mockStorageService.getString(any())).thenAnswer(
          (_) async =>
              '[{"type":4,"title":"设备固件更新","subtitle":"TEST_SN_1 有新固件可用","timestamp":"2024-01-01T00:00:00.000"}]',
        );
        when(() => mockAppUpdateService.checkUpdate(any()))
            .thenAnswer((_) async => AppUpdateInfo(hasUpdate: false));
        return notificationBloc;
      },
      act: (bloc) => bloc.add(const SystemNotificationsRequested()),
      expect: () => [
        isA<SystemNotificationsLoaded>().having(
          (s) => s.notifications.length,
          'notifications.length',
          1,
        ),
      ],
    );
  });
}

/// Creates a fake Dio Response for testing.
dynamic _fakeResponse(dynamic data) {
  return Response<dynamic>(
    requestOptions: RequestOptions(),
    statusCode: 200,
    data: data,
  );
}
