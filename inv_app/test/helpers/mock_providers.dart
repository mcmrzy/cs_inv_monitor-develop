/// Mock providers for testing.
///
/// This file contains mock classes created using mocktail for commonly used
/// repositories, services, and other dependencies in the inv_app project.
/// Use these mocks in widget tests and bloc tests to isolate the unit under
/// test from real implementations.
library;

import 'package:mocktail/mocktail.dart';
import 'package:inv_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:inv_app/features/auth/domain/usecases/login.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';
import 'package:inv_app/features/station/domain/repositories/station_repository.dart';
import 'package:inv_app/features/alarm/domain/repositories/alarm_repository.dart';
import 'package:inv_app/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/services/mqtt_service.dart';
import 'package:inv_app/core/services/locale_service.dart';
import 'package:inv_app/core/services/data_cache_service.dart';
import 'package:inv_app/core/services/notification_service.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/offline_cache_service.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/core/services/jpush_service.dart';
import 'package:inv_app/features/notification/data/datasources/notification_remote_data_source.dart';
import 'package:inv_app/features/dashboard/data/datasources/dashboard_sse_data_source.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/alarm/presentation/bloc/alarm_bloc.dart';
import 'package:inv_app/features/notification/presentation/bloc/notification_bloc.dart';
import 'package:inv_app/features/dashboard/presentation/bloc/dashboard_bloc.dart';

// ---------------------------------------------------------------------------
// Repository mocks
// ---------------------------------------------------------------------------

/// Mock implementation of [AuthRepository] for testing authentication flows.
class MockAuthRepository extends Mock implements AuthRepository {}

/// Mock implementation of [DeviceRepository] for testing device-related flows.
class MockDeviceRepository extends Mock implements DeviceRepository {}

/// Mock implementation of [StationRepository] for testing station-related flows.
class MockStationRepository extends Mock implements StationRepository {}

/// Mock implementation of [AlarmRepository] for testing alarm-related flows.
class MockAlarmRepository extends Mock implements AlarmRepository {}

/// Mock implementation of [DashboardRepository] for testing dashboard flows.
class MockDashboardRepository extends Mock implements DashboardRepository {}

/// Mock implementation of [OtaRepository] for testing OTA upgrade flows.
class MockOtaRepository extends Mock implements OtaRepository {}

// ---------------------------------------------------------------------------
// Service mocks
// ---------------------------------------------------------------------------

/// Mock implementation of [StorageService] for testing token and preference
/// storage without relying on real secure storage or shared preferences.
class MockStorageService extends Mock implements StorageService {}

/// Mock implementation of [MQTTService] for testing MQTT interactions
/// without a real broker connection.
class MockMQTTService extends Mock implements MQTTService {}

/// Mock implementation of [LocaleService] for testing locale switching.
class MockLocaleService extends Mock implements LocaleService {}

/// Mock implementation of [DataCacheService] for testing data caching logic.
class MockDataCacheService extends Mock implements DataCacheService {}

/// Mock implementation of [NotificationService] for testing local notifications.
class MockNotificationService extends Mock implements NotificationService {}

/// Mock implementation of [ConnectionModeService] for testing connection mode
/// switching between cloud and local modes.
class MockConnectionModeService extends Mock implements ConnectionModeService {}

/// Mock implementation of [OfflineCacheService] for testing offline data
/// caching.
class MockOfflineCacheService extends Mock implements OfflineCacheService {}

/// Mock implementation of [LocalCommunicationService] for testing BLE/WiFi
/// local communication.
class MockLocalCommunicationService extends Mock
    implements LocalCommunicationService {}

/// Mock implementation of [JPushService] for testing push notifications.
class MockJPushService extends Mock implements JPushService {}

/// Mock implementation of [NotificationRemoteDataSource] for testing
/// notification API calls.
class MockNotificationRemoteDataSource extends Mock
    implements NotificationRemoteDataSource {}

/// Mock implementation of [DashboardSSEDataSource] for testing SSE data
/// source.
class MockDashboardSSEDataSource extends Mock
    implements DashboardSSEDataSource {}

// ---------------------------------------------------------------------------
// UseCase mocks
// ---------------------------------------------------------------------------

/// Mock implementation of [LoginUseCase] for testing login logic in isolation.
class MockLoginUseCase extends Mock implements LoginUseCase {}

/// Mock implementation of [RegisterUseCase] for testing registration logic.
class MockRegisterUseCase extends Mock implements RegisterUseCase {}

/// Mock implementation of [LogoutUseCase] for testing logout logic.
class MockLogoutUseCase extends Mock implements LogoutUseCase {}

/// Mock implementation of [SendCodeUseCase] for testing SMS code sending.
class MockSendCodeUseCase extends Mock implements SendCodeUseCase {}

/// Mock implementation of [ResetPasswordUseCase] for testing password reset.
class MockResetPasswordUseCase extends Mock implements ResetPasswordUseCase {}

/// Mock implementation of [ChangePasswordUseCase] for testing password change.
class MockChangePasswordUseCase extends Mock implements ChangePasswordUseCase {}

/// Mock implementation of [GetProfileUseCase] for testing profile retrieval.
class MockGetProfileUseCase extends Mock implements GetProfileUseCase {}

/// Mock implementation of [UpdateProfileUseCase] for testing profile updates.
class MockUpdateProfileUseCase extends Mock implements UpdateProfileUseCase {}

/// Mock implementation of [EmailLoginUseCase] for testing email login.
class MockEmailLoginUseCase extends Mock implements EmailLoginUseCase {}

/// Mock implementation of [EmailRegisterUseCase] for testing email registration.
class MockEmailRegisterUseCase extends Mock implements EmailRegisterUseCase {}

/// Mock implementation of [SendEmailCodeUseCase] for testing email code sending.
class MockSendEmailCodeUseCase extends Mock implements SendEmailCodeUseCase {}

/// Mock implementation of [RefreshTokenUseCase] for testing token refresh.
class MockRefreshTokenUseCase extends Mock implements RefreshTokenUseCase {}

/// Mock implementation of [WechatLoginUseCase] for testing WeChat login.
class MockWechatLoginUseCase extends Mock implements WechatLoginUseCase {}

/// Mock implementation of [GoogleLoginUseCase] for testing Google login.
class MockGoogleLoginUseCase extends Mock implements GoogleLoginUseCase {}

// ---------------------------------------------------------------------------
// Bloc mocks
// ---------------------------------------------------------------------------

/// Mock implementation of [AuthBloc] for testing widgets that depend on
/// authentication state.
class MockAuthBloc extends Mock implements AuthBloc {}

/// Mock implementation of [StationBloc] for testing widgets that depend on
/// station state.
class MockStationBloc extends Mock implements StationBloc {}

/// Mock implementation of [DeviceBloc] for testing widgets that depend on
/// device state.
class MockDeviceBloc extends Mock implements DeviceBloc {}

/// Mock implementation of [AlarmBloc] for testing widgets that depend on
/// alarm state.
class MockAlarmBloc extends Mock implements AlarmBloc {}

/// Mock implementation of [NotificationBloc] for testing widgets that depend
/// on notification state.
class MockNotificationBloc extends Mock implements NotificationBloc {}

/// Mock implementation of [DashboardBloc] for testing widgets that depend on
/// dashboard state.
class MockDashboardBloc extends Mock implements DashboardBloc {}
