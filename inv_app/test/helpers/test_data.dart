/// Test data factory functions for domain entities.
///
/// This file provides factory functions to create standard test data for
/// domain entities used throughout the inv_app project. Each factory returns
/// sensible defaults that can be overridden via named parameters.
library;

import 'package:inv_app/features/auth/domain/entities/user.dart';
import 'package:inv_app/core/errors/failures.dart';

/// Creates a test [User] instance with sensible defaults.
///
/// All fields can be overridden by passing named parameters.
///
/// ```dart
/// final user = createTestUser();
/// final admin = createTestUser(role: 0);
/// ```
User createTestUser({
  int id = 1,
  String phone = '13800138000',
  String? email = 'test@example.com',
  String? nickname = 'Test User',
  String? avatar,
  int role = 3,
  int status = 1,
  DateTime? lastLoginAt,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return User(
    id: id,
    phone: phone,
    email: email,
    nickname: nickname,
    avatar: avatar,
    role: role,
    status: status,
    lastLoginAt: lastLoginAt,
    createdAt: createdAt ?? DateTime(2024, 1, 1),
    updatedAt: updatedAt,
  );
}

/// Creates a test [LoginResponse] instance with sensible defaults.
///
/// By default the token expires 2 hours from now.
///
/// ```dart
/// final response = createTestLoginResponse();
/// final custom = createTestLoginResponse(token: 'custom_token');
/// ```
LoginResponse createTestLoginResponse({
  String token = 'test_access_token',
  String? refreshToken = 'test_refresh_token',
  User? user,
  DateTime? expireAt,
}) {
  return LoginResponse(
    token: token,
    refreshToken: refreshToken,
    user: user ?? createTestUser(),
    expireAt: expireAt ?? DateTime.now().add(const Duration(hours: 2)),
  );
}

/// Creates a [ServerFailure] with a default test message.
Failure createTestServerFailure([String message = 'Server error']) {
  return ServerFailure(message);
}

/// Creates a [NetworkFailure] with a default test message.
Failure createTestNetworkFailure([String message = 'Network error']) {
  return NetworkFailure(message);
}

/// Creates a [CacheFailure] with a default test message.
Failure createTestCacheFailure([String message = 'Cache error']) {
  return CacheFailure(message);
}

/// Creates a [ValidationFailure] with a default test message.
Failure createTestValidationFailure([String message = 'Validation error']) {
  return ValidationFailure(message);
}

/// Creates a [UnauthorizedFailure] with a default test message.
Failure createTestUnauthorizedFailure([String message = 'Unauthorized']) {
  return UnauthorizedFailure(message);
}

/// Creates a mock device map as returned by [DeviceRepository.getList].
///
/// ```dart
/// final devices = createTestDeviceList(count: 3);
/// ```
Map<String, dynamic> createTestDeviceListResponse({int count = 2}) {
  final devices = List.generate(count, (i) => createTestDeviceMap(index: i));
  return {
    'list': devices,
    'total': count,
    'page': 1,
    'page_size': 20,
  };
}

/// Creates a single device map with sensible defaults.
Map<String, dynamic> createTestDeviceMap({
  int index = 0,
  String? sn,
  String? name,
  String? model,
  int? stationId,
  String status = 'online',
}) {
  return {
    'id': index + 1,
    'sn': sn ?? 'TEST_SN_${index + 1}',
    'name': name ?? 'Test Device ${index + 1}',
    'model': model ?? 'INV-5000',
    'station_id': stationId ?? 1,
    'status': status,
    'created_at': DateTime(2024, 1, 1).toIso8601String(),
  };
}

/// Creates a mock station list response as returned by
/// [StationRepository.getList].
Map<String, dynamic> createTestStationListResponse({int count = 2}) {
  final stations = List.generate(
    count,
    (i) => createTestStationMap(index: i),
  );
  return {
    'list': stations,
    'total': count,
    'page': 1,
    'page_size': 20,
  };
}

/// Creates a single station map with sensible defaults.
Map<String, dynamic> createTestStationMap({
  int index = 0,
  String? name,
  String? location,
}) {
  return {
    'id': index + 1,
    'name': name ?? 'Test Station ${index + 1}',
    'location': location ?? 'Test Location',
    'device_count': 5,
    'total_power': 100.0,
    'created_at': DateTime(2024, 1, 1).toIso8601String(),
  };
}

/// Creates a mock alarm list response as returned by
/// [AlarmRepository.getList].
Map<String, dynamic> createTestAlarmListResponse({int count = 2}) {
  final alarms = List.generate(
    count,
    (i) => createTestAlarmMap(index: i),
  );
  return {
    'list': alarms,
    'total': count,
    'page': 1,
    'page_size': 20,
  };
}

/// Creates a single alarm map with sensible defaults.
Map<String, dynamic> createTestAlarmMap({
  int index = 0,
  String? deviceSn,
  int level = 1,
  String type = 'fault',
  int status = 0,
}) {
  return {
    'id': index + 1,
    'device_sn': deviceSn ?? 'TEST_SN_${index + 1}',
    'level': level,
    'type': type,
    'message': 'Test alarm ${index + 1}',
    'status': status,
    'created_at': DateTime(2024, 1, 1).toIso8601String(),
  };
}

/// Creates a mock dashboard statistics response as returned by
/// [DashboardRepository.getStatistics].
Map<String, dynamic> createTestDashboardStatistics() {
  return {
    'total_power': 1500.5,
    'today_power': 25.3,
    'month_power': 750.2,
    'total_devices': 10,
    'online_devices': 8,
    'total_stations': 3,
    'recent_alarms': <dynamic>[],
  };
}
