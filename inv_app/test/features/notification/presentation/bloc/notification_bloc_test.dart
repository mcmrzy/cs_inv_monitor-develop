import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/features/notification/presentation/bloc/notification_bloc.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/services/app_update_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';

import '../../../../helpers/mock_providers.dart';

/// Mock for AppUpdateService since it's not in mock_providers.
class MockAppUpdateService extends Mock implements AppUpdateService {}

void main() {
  group('SystemNotification serialization', () {
    test('preserves semantic app update version', () {
      final notification = SystemNotification(
        type: SystemNotificationType.appUpdate,
        title: '',
        subtitle: '',
        timestamp: DateTime.utc(2026, 7, 16),
        version: '2.3.0',
      );

      final restored = SystemNotification.fromJson(notification.toJson());

      expect(restored.version, '2.3.0');
      expect(restored.type, SystemNotificationType.appUpdate);
    });

    test('falls back to deviceOnline when cached type index is out of range', () {
      // P2：历史版本可能写入已被删除的枚举 index，越界不得崩溃
      final restored = SystemNotification.fromJson({
        'type': 999,
        'title': 'legacy',
        'subtitle': 'sub',
        'timestamp': DateTime.utc(2026, 7, 16).toIso8601String(),
      });
      expect(restored.type, SystemNotificationType.deviceOnline);
      expect(restored.title, 'legacy');
    });

    test('tolerates non-int type and missing fields', () {
      // P2：脏数据（type 为字符串、字段缺失）回退默认值而不是抛异常
      final restored = SystemNotification.fromJson({
        'type': 'ota_available',
        'title': null,
      });
      expect(restored.type, SystemNotificationType.deviceOnline);
      expect(restored.title, '');
      expect(restored.subtitle, '');
    });

    test('extracts version from legacy localized title', () {
      final restored = SystemNotification.fromJson({
        'type': SystemNotificationType.appUpdate.index,
        'title': '发现新版本 v1.8.2',
        'subtitle': '点击查看详情并更新',
        'timestamp': DateTime.utc(2026, 7, 16).toIso8601String(),
      });

      expect(restored.version, '1.8.2');
    });
  });

  late NotificationBloc notificationBloc;
  late MockDeviceRepository mockDeviceRepository;
  late MockRealtimeDataService mockRealtimeDataService;
  late MockNotificationRemoteDataSource mockNotificationDataSource;
  late MockStorageService mockStorageService;
  late MockAppUpdateService mockAppUpdateService;

  setUpAll(() {
    // Register fallback values for mocktail
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    mockDeviceRepository = MockDeviceRepository();
    mockRealtimeDataService = MockRealtimeDataService();
    mockNotificationDataSource = MockNotificationRemoteDataSource();
    mockStorageService = MockStorageService();
    mockAppUpdateService = MockAppUpdateService();
    when(() => mockAppUpdateService.resolveCurrentVersionCode())
        .thenAnswer((_) async => 1);

    // Default RealtimeDataService stubs
    when(() => mockRealtimeDataService.realtimeDataStream)
        .thenAnswer((_) => const Stream<InverterRealtime>.empty());
    when(() => mockRealtimeDataService.alarmStream)
        .thenAnswer((_) => const Stream<AlarmData>.empty());

    // Register getIt dependencies used by NotificationBloc
    getIt.registerFactory<StorageService>(() => mockStorageService);
    getIt.registerFactory<AppUpdateService>(() => mockAppUpdateService);

    notificationBloc = NotificationBloc(
      deviceRepository: mockDeviceRepository,
      realtimeDataService: mockRealtimeDataService,
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
        when(
          () => mockNotificationDataSource.getList(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer(
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
        when(
          () => mockNotificationDataSource.getList(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenThrow(Exception('Network error'));
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
        when(
          () => mockNotificationDataSource.getList(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenThrow(Exception('Network error'));
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

    blocTest<NotificationBloc, NotificationState>(
      'skips unparseable local cache entries instead of dropping the batch',
      build: () {
        when(
          () => mockNotificationDataSource.getList(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenThrow(Exception('Network error'));
        // 第一条是非 Map 的坏条目，第二条是正常 OTA 通知：
        // 修复前整批 as Map 抛异常导致 0 条，修复后应只跳过坏条目
        when(() => mockStorageService.getString(any())).thenAnswer(
          (_) async =>
              '["bad-entry",{"type":4,"title":"设备固件更新","subtitle":"TEST_SN_1 有新固件可用","timestamp":"2024-01-01T00:00:00.000"}]',
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

    blocTest<NotificationBloc, NotificationState>(
      'checks app update again on manual refresh after first load',
      build: () {
        // 两次加载返回不同内容，避免 bloc 跳过相等的连续状态
        // （否则第二次 emit 的 SystemNotificationsLoaded([]) 与第一次相等被忽略）
        var callCount = 0;
        when(
          () => mockNotificationDataSource.getList(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            return _fakeResponse({
              'data': {'items': []},
            });
          }
          return _fakeResponse({
            'data': {
              'items': [
                {
                  'id': 7,
                  'notify_type': 'device_fault',
                  'title': 'Device Fault',
                  'content': 'Device TEST_SN_1 faulted',
                  'created_at': DateTime(2024, 1, 2).toIso8601String(),
                  'device_sn': 'TEST_SN_1',
                },
              ],
            },
          });
        });
        when(() => mockStorageService.getString(any()))
            .thenAnswer((_) async => null);
        when(() => mockAppUpdateService.checkUpdate(any()))
            .thenAnswer((_) async => AppUpdateInfo(hasUpdate: false));
        return notificationBloc;
      },
      act: (bloc) {
        // 首载：state 尚未 loaded，检查更新
        bloc.add(const SystemNotificationsRequested());
        // P2：手动刷新（manual=true）在已加载后仍需检查 App 更新
        bloc.add(const SystemNotificationsRequested(manual: true));
      },
      // 等 bloc 串行处理完两个事件（mock 链路多次 await，zero-delay 不够）
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<SystemNotificationsLoaded>(),
        isA<SystemNotificationsLoaded>(),
      ],
      verify: (_) {
        verify(() => mockAppUpdateService.checkUpdate(any())).called(2);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // SystemNotificationsLoadMoreRequested（分页加载更多）
  // ---------------------------------------------------------------------------
  group('SystemNotificationsLoadMoreRequested', () {
    blocTest<NotificationBloc, NotificationState>(
      'first load reports hasMore when backend total exceeds page size',
      build: () {
        // 20 条（满页），total=45 → 还有更多
        final items = List.generate(20, (i) {
          return {
            'id': i + 1,
            'notify_type': 'device_online',
            'title': 'Device Online',
            'content': 'Device SN_$i is online',
            'created_at': DateTime(2024, 1, 1).toIso8601String(),
            'device_sn': 'SN_$i',
          };
        });
        when(
          () => mockNotificationDataSource.getList(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer(
          (_) async => _fakeResponse({
            'data': {'items': items, 'total': 45},
          }),
        );
        when(() => mockStorageService.getString(any()))
            .thenAnswer((_) async => null);
        when(() => mockAppUpdateService.checkUpdate(any()))
            .thenAnswer((_) async => AppUpdateInfo(hasUpdate: false));
        return notificationBloc;
      },
      act: (bloc) => bloc.add(const SystemNotificationsRequested()),
      expect: () => [
        isA<SystemNotificationsLoaded>()
            .having((s) => s.page, 'page', 1)
            .having((s) => s.hasMore, 'hasMore', true)
            .having(
              (s) => s.notifications.length,
              'notifications.length',
              20,
            ),
      ],
    );

    blocTest<NotificationBloc, NotificationState>(
      'load more fetches next page and appends new backend notifications',
      build: () {
        final pages = <int, List<Map<String, dynamic>>>{
          1: [
            {
              'id': 1,
              'notify_type': 'device_online',
              'title': 'Device Online',
              'content': 'first page item',
              'created_at': DateTime(2024, 1, 2).toIso8601String(),
              'device_sn': 'SN_1',
            },
          ],
          2: [
            {
              'id': 2,
              'notify_type': 'device_offline',
              'title': 'Device Offline',
              'content': 'second page item',
              'created_at': DateTime(2024, 1, 1).toIso8601String(),
              'device_sn': 'SN_2',
            },
          ],
        };
        when(
          () => mockNotificationDataSource.getList(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer((inv) async {
          final page = inv.namedArguments[#page] as int;
          return _fakeResponse({
            'data': {'items': pages[page]!, 'total': 2},
          });
        });
        when(() => mockStorageService.getString(any()))
            .thenAnswer((_) async => null);
        when(() => mockAppUpdateService.checkUpdate(any()))
            .thenAnswer((_) async => AppUpdateInfo(hasUpdate: false));
        return notificationBloc;
      },
      act: (bloc) async {
        bloc.add(const SystemNotificationsRequested());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const SystemNotificationsLoadMoreRequested());
      },
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<SystemNotificationsLoaded>()
            .having((s) => s.page, 'page', 1)
            .having((s) => s.hasMore, 'hasMore', true),
        isA<SystemNotificationsLoaded>()
            .having((s) => s.page, 'page', 2)
            // total=2 全部加载完 → 没有更多
            .having((s) => s.hasMore, 'hasMore', false)
            .having(
              (s) => s.notifications.map((n) => n.id).toList(),
              'notification ids',
              [1, 2],
            ),
      ],
      verify: (_) {
        verify(
          () => mockNotificationDataSource.getList(
            page: 2,
            pageSize: 20,
          ),
        ).called(1);
      },
    );

    blocTest<NotificationBloc, NotificationState>(
      'load more is ignored when hasMore is false',
      build: () {
        when(
          () => mockNotificationDataSource.getList(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer(
          (_) async => _fakeResponse({
            'data': {
              'items': [
                {
                  'id': 1,
                  'notify_type': 'device_online',
                  'title': 'Device Online',
                  'content': 'only item',
                  'created_at': DateTime(2024, 1, 1).toIso8601String(),
                  'device_sn': 'SN_1',
                },
              ],
              'total': 1,
            },
          }),
        );
        when(() => mockStorageService.getString(any()))
            .thenAnswer((_) async => null);
        when(() => mockAppUpdateService.checkUpdate(any()))
            .thenAnswer((_) async => AppUpdateInfo(hasUpdate: false));
        return notificationBloc;
      },
      act: (bloc) async {
        bloc.add(const SystemNotificationsRequested());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const SystemNotificationsLoadMoreRequested());
      },
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<SystemNotificationsLoaded>()
            .having((s) => s.hasMore, 'hasMore', false),
      ],
      verify: (_) {
        verifyNever(
          () => mockNotificationDataSource.getList(
            page: 2,
            pageSize: any(named: 'pageSize'),
          ),
        );
      },
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
