import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/features/onboarding/data/onboarding_storage.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorageService extends Mock implements StorageService {}

void main() {
  late _MockStorageService storage;

  setUp(() async {
    await getIt.reset();
    storage = _MockStorageService();
    getIt.registerSingleton<StorageService>(storage);
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('首次安装时需要展示引导', () async {
    when(
      () => storage.getString(OnboardingStorage.keyLastSeenVersion),
    ).thenAnswer((_) async => null);

    expect(await OnboardingStorage().needsOnboarding(), isTrue);
  });

  test('已看过当前版本时不再展示引导', () async {
    when(
      () => storage.getString(OnboardingStorage.keyLastSeenVersion),
    ).thenAnswer((_) async => AppConfig.version);

    expect(await OnboardingStorage().needsOnboarding(), isFalse);
  });

  test('升级到新版本后重新展示引导', () async {
    when(
      () => storage.getString(OnboardingStorage.keyLastSeenVersion),
    ).thenAnswer((_) async => '0.9.0');

    expect(await OnboardingStorage().needsOnboarding(), isTrue);
  });

  test('读取失败时不阻塞启动', () async {
    when(
      () => storage.getString(OnboardingStorage.keyLastSeenVersion),
    ).thenThrow(StateError('read failed'));

    expect(await OnboardingStorage().needsOnboarding(), isFalse);
  });

  test('记录已看版本时写入当前版本', () async {
    when(
      () => storage.saveString(any(), any()),
    ).thenAnswer((_) async {});

    await OnboardingStorage().markSeen();

    verify(
      () => storage.saveString(
        OnboardingStorage.keyLastSeenVersion,
        AppConfig.version,
      ),
    ).called(1);
  });

  test('记录已看版本写入失败时吞掉异常', () async {
    when(
      () => storage.saveString(any(), any()),
    ).thenThrow(StateError('write failed'));

    await expectLater(OnboardingStorage().markSeen(), completes);
  });
}
