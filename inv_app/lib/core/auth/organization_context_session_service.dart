import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/features/auth/domain/entities/user.dart';
import 'package:inv_app/features/auth/domain/repositories/auth_repository.dart';

class OrganizationContextSwitchException implements Exception {
  final String message;

  const OrganizationContextSwitchException(this.message);

  @override
  String toString() => message;
}

/// Switches the server authorization context, then commits the corresponding
/// tokens, permissions and local organization selection as one local unit.
class OrganizationContextSessionService {
  final AuthRepository _repository;
  final StorageService _storage;

  OrganizationContextSessionService(this._repository, this._storage);

  Future<AuthorizationContextResponse> switchContext({
    required int organizationId,
    required String organizationName,
  }) async {
    if (organizationId <= 0) {
      throw const OrganizationContextSwitchException(
        'Invalid organization context.',
      );
    }

    final previous = await _StoredAuthorizationContext.capture(_storage);
    final refreshToken = previous.refreshToken?.trim();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const OrganizationContextSwitchException(
        'Missing refresh token.',
      );
    }

    final remoteResult = await _repository.switchOrganizationContext(
      organizationId: organizationId,
      refreshToken: refreshToken,
    );
    final response = remoteResult.fold(
      (failure) => throw OrganizationContextSwitchException(failure.message),
      (value) => value,
    );

    if (response.accessToken.isEmpty ||
        response.refreshToken.isEmpty ||
        response.activeOrganizationId != organizationId) {
      throw const OrganizationContextSwitchException(
        'Invalid organization context response.',
      );
    }

    try {
      await _storage.saveToken(response.accessToken);
      await _storage.saveRefreshToken(response.refreshToken);
      await _storage.savePermissions(response.permissions);
      await _storage.saveActiveOrgId(response.activeOrganizationId);
      await _storage.saveActiveOrgName(organizationName);
    } catch (error) {
      Object? rollbackError;
      try {
        await previous.restore(_storage);
      } catch (restoreError) {
        rollbackError = restoreError;
      }
      throw OrganizationContextSwitchException(
        rollbackError == null
            ? 'Failed to persist organization context: $error'
            : 'Failed to persist organization context: $error; '
                'rollback failed: $rollbackError',
      );
    }

    return response;
  }
}

class _StoredAuthorizationContext {
  final String? accessToken;
  final String? refreshToken;
  final List<String> permissions;
  final int? organizationId;
  final String? organizationName;

  const _StoredAuthorizationContext({
    required this.accessToken,
    required this.refreshToken,
    required this.permissions,
    required this.organizationId,
    required this.organizationName,
  });

  static Future<_StoredAuthorizationContext> capture(
    StorageService storage,
  ) async {
    return _StoredAuthorizationContext(
      accessToken: await storage.getToken(),
      refreshToken: await storage.getRefreshToken(),
      permissions: List<String>.of(await storage.getPermissions()),
      organizationId: await storage.getActiveOrgId(),
      organizationName: await storage.getActiveOrgName(),
    );
  }

  Future<void> restore(StorageService storage) async {
    await _restoreString(accessToken, storage.saveToken, storage.deleteToken);
    await _restoreString(
      refreshToken,
      storage.saveRefreshToken,
      storage.deleteRefreshToken,
    );
    await storage.savePermissions(permissions);
    if (organizationId == null) {
      await storage.deleteActiveOrgId();
    } else {
      await storage.saveActiveOrgId(organizationId!);
    }
    await _restoreString(
      organizationName,
      storage.saveActiveOrgName,
      storage.deleteActiveOrgName,
    );
  }
}

Future<void> _restoreString(
  String? value,
  Future<void> Function(String) save,
  Future<void> Function() remove,
) async {
  if (value == null) {
    await remove();
  } else {
    await save(value);
  }
}
