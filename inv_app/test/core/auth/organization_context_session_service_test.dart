import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/core/auth/organization_context_session_service.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/features/auth/domain/entities/user.dart';
import 'package:inv_app/features/auth/domain/repositories/auth_repository.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockStorageService extends Mock implements StorageService {}

void main() {
  late _MockAuthRepository repository;
  late _MockStorageService storage;
  late OrganizationContextSessionService service;

  const response = AuthorizationContextResponse(
    accessToken: 'new-access',
    refreshToken: 'new-refresh',
    activeOrganizationId: 22,
    permissions: ['devices:view', 'organizations:invite'],
  );

  setUp(() {
    repository = _MockAuthRepository();
    storage = _MockStorageService();
    service = OrganizationContextSessionService(repository, storage);

    when(() => storage.getToken()).thenAnswer((_) async => 'old-access');
    when(() => storage.getRefreshToken()).thenAnswer((_) async => 'old-refresh');
    when(() => storage.getPermissions())
        .thenAnswer((_) async => ['alerts:view']);
    when(() => storage.getActiveOrgId()).thenAnswer((_) async => 11);
    when(() => storage.getActiveOrgName()).thenAnswer((_) async => 'Org A');
    when(() => storage.saveToken(any())).thenAnswer((_) async {});
    when(() => storage.saveRefreshToken(any())).thenAnswer((_) async {});
    when(() => storage.savePermissions(any())).thenAnswer((_) async {});
    when(() => storage.saveActiveOrgId(any())).thenAnswer((_) async {});
    when(() => storage.saveActiveOrgName(any())).thenAnswer((_) async {});
  });

  test('commits tokens permissions and organization after remote success', () async {
    when(
      () => repository.switchOrganizationContext(
        organizationId: 22,
        refreshToken: 'old-refresh',
      ),
    ).thenAnswer((_) async => const Right(response));

    final result = await service.switchContext(
      organizationId: 22,
      organizationName: 'Org B',
    );

    expect(result, response);
    verify(() => storage.saveToken('new-access')).called(1);
    verify(() => storage.saveRefreshToken('new-refresh')).called(1);
    verify(
      () => storage.savePermissions(
        ['devices:view', 'organizations:invite'],
      ),
    ).called(1);
    verify(() => storage.saveActiveOrgId(22)).called(1);
    verify(() => storage.saveActiveOrgName('Org B')).called(1);
  });

  test('remote failure leaves all persisted context unchanged', () async {
    when(
      () => repository.switchOrganizationContext(
        organizationId: 22,
        refreshToken: 'old-refresh',
      ),
    ).thenAnswer(
      (_) async => const Left(ServerFailure('context switch failed')),
    );

    await expectLater(
      service.switchContext(organizationId: 22, organizationName: 'Org B'),
      throwsA(isA<OrganizationContextSwitchException>()),
    );

    verifyNever(() => storage.saveToken(any()));
    verifyNever(() => storage.saveRefreshToken(any()));
    verifyNever(() => storage.savePermissions(any()));
    verifyNever(() => storage.saveActiveOrgId(any()));
    verifyNever(() => storage.saveActiveOrgName(any()));
  });

  test('persistence failure restores the complete previous context', () async {
    when(
      () => repository.switchOrganizationContext(
        organizationId: 22,
        refreshToken: 'old-refresh',
      ),
    ).thenAnswer((_) async => const Right(response));
    when(() => storage.savePermissions(response.permissions))
        .thenThrow(StateError('disk full'));

    await expectLater(
      service.switchContext(organizationId: 22, organizationName: 'Org B'),
      throwsA(isA<OrganizationContextSwitchException>()),
    );

    verify(() => storage.saveToken('old-access')).called(1);
    verify(() => storage.saveRefreshToken('old-refresh')).called(1);
    verify(() => storage.savePermissions(['alerts:view'])).called(1);
    verify(() => storage.saveActiveOrgId(11)).called(1);
    verify(() => storage.saveActiveOrgName('Org A')).called(1);
  });
}
