import 'package:dio/dio.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:dartz/dartz.dart';
import 'package:inv_app/core/entities/organization.dart';

class ApiService {
  final Dio _dio;

  ApiService(this._dio);

  Future<Either<Failure, T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(dynamic) fromJson,
  }) async {
    try {
      final response = await _dio.get(path, queryParameters: queryParameters);
      return _handleResponse(response, fromJson);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    required T Function(dynamic) fromJson,
  }) async {
    try {
      final response =
          await _dio.post(path, data: data, queryParameters: queryParameters);
      return _handleResponse(response, fromJson);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    required T Function(dynamic) fromJson,
  }) async {
    try {
      final response =
          await _dio.put(path, data: data, queryParameters: queryParameters);
      return _handleResponse(response, fromJson);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    required T Function(dynamic) fromJson,
  }) async {
    try {
      final response =
          await _dio.delete(path, data: data, queryParameters: queryParameters);
      return _handleResponse(response, fromJson);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Either<Failure, T> _handleResponse<T>(
    Response response,
    T Function(dynamic) fromJson,
  ) {
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = response.data;
      if (data is Map<String, dynamic>) {
        if (data['code'] == 0) {
          return Right(fromJson(data['data'] ?? {}));
        } else {
          final code = data['code'];
          final msg = data['message'] ?? 'Unknown error';
          // 将错误码和消息一起传递，方便 translateError 按 code 查找
          return Left(ServerFailure(code != null ? '[$code] $msg' : msg));
        }
      }
      return const Left(ServerFailure('Invalid response format'));
    }
    return Left(ServerFailure('HTTP ${response.statusCode}'));
  }

  Failure _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkFailure('Connection timeout');
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        if (statusCode == 401) {
          return const UnauthorizedFailure('Unauthorized');
        } else if (statusCode == 403) {
          return const ForbiddenFailure('Forbidden');
        } else if (statusCode == 404) {
          return const NotFoundFailure('Not found');
        }
        // 尝试解析错误信息
        if (e.response?.data != null) {
          final data = e.response!.data;
          if (data is Map<String, dynamic>) {
            final code = data['code'];
            final msg = data['message'] ?? 'Unknown error';
            return ServerFailure(code != null ? '[$code] $msg' : msg);
          }
        }
        return ServerFailure('Server error: $statusCode');
      case DioExceptionType.cancel:
        return const NetworkFailure('Request cancelled');
      case DioExceptionType.connectionError:
        return const NetworkFailure('No internet connection');
      default:
        return const NetworkFailure('Network error');
    }
  }

  // ==================== Organization APIs ====================

  /// 获取用户所属的所有组织
  Future<List<Organization>> getOrganizations() async {
    final result = await get<List<Organization>>(
      '/api/v1/organizations',
      fromJson: (data) => (data as List)
          .map(
            (item) =>
                Organization.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (orgs) => orgs,
    );
  }

  /// 创建新组织
  Future<Organization> createOrganization({
    required String name,
    String? description,
  }) async {
    final result = await post<Organization>(
      '/api/v1/organizations',
      data: {
        'name': name,
        if (description != null) 'description': description,
      },
      fromJson: (json) => Organization.fromJson(json as Map<String, dynamic>),
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (org) => org,
    );
  }

  /// 获取组织详情
  Future<Organization> getOrganization(int orgId) async {
    final result = await get<Organization>(
      '/api/v1/organizations/$orgId',
      fromJson: (json) => Organization.fromJson(json as Map<String, dynamic>),
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (org) => org,
    );
  }

  /// 更新组织信息
  Future<Organization> updateOrganization(
    int orgId, {
    required String name,
    String? description,
  }) async {
    final result = await put<Organization>(
      '/api/v1/organizations/$orgId',
      data: {
        'name': name,
        if (description != null) 'description': description,
      },
      fromJson: (json) => Organization.fromJson(json as Map<String, dynamic>),
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (org) => org,
    );
  }

  /// 删除组织
  Future<void> deleteOrganization(int orgId) async {
    final result = await delete<Map<String, dynamic>>(
      '/api/v1/organizations/$orgId',
      fromJson: (json) => json,
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (_) => {},
    );
  }

  // ==================== Organization Members APIs ====================

  /// 获取组织成员列表
  Future<List<OrganizationMember>> getOrganizationMembers(int orgId) async {
    final result = await get<List<OrganizationMember>>(
      '/api/v1/organizations/$orgId/members',
      fromJson: (data) => (data as List)
          .map(
            (item) => OrganizationMember.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (members) => members,
    );
  }

  /// 添加组织成员
  Future<OrganizationMember> addOrganizationMember({
    required int orgId,
    required String email,
    required OrgMemberRole role,
  }) async {
    final result = await post<OrganizationMember>(
      '/api/v1/organizations/$orgId/members',
      data: {
        'email': email,
        'role': role.apiValue,
      },
      fromJson: (json) =>
          OrganizationMember.fromJson(json as Map<String, dynamic>),
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (member) => member,
    );
  }

  /// 更新组织成员角色
  Future<OrganizationMember> updateMemberRole({
    required int orgId,
    required int userId,
    required OrgMemberRole role,
  }) async {
    final result = await put<OrganizationMember>(
      '/api/v1/organizations/$orgId/members/$userId',
      data: {'role': role.apiValue},
      fromJson: (json) =>
          OrganizationMember.fromJson(json as Map<String, dynamic>),
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (member) => member,
    );
  }

  /// 移除组织成员
  Future<void> removeOrganizationMember(int orgId, int userId) async {
    final result = await delete<Map<String, dynamic>>(
      '/api/v1/organizations/$orgId/members/$userId',
      fromJson: (json) => json,
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (_) => {},
    );
  }

  // ==================== Invitation APIs ====================

  /// 发送邀请
  Future<OrganizationInvitation> sendInvitation({
    required int orgId,
    required String email,
    required OrgMemberRole role,
    int? days,
  }) async {
    final result = await post<OrganizationInvitation>(
      '/api/v1/invitations/create',
      data: {
        'organization_id': orgId,
        'email': email,
        'role': role.apiValue,
        if (days != null) 'expires_in_days': days,
      },
      fromJson: (json) =>
          OrganizationInvitation.fromJson(json as Map<String, dynamic>),
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (invitation) => invitation,
    );
  }

  /// 获取邀请列表
  Future<List<OrganizationInvitation>> listInvitations(int orgId) async {
    final result = await get<List<OrganizationInvitation>>(
      '/api/v1/invitations/list',
      queryParameters: {'organization_id': orgId},
      fromJson: (data) => (data as List)
          .map(
            (item) => OrganizationInvitation.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (invitations) => invitations,
    );
  }

  /// 撤销邀请
  Future<void> revokeInvitation(int invitationId) async {
    final result = await delete<Map<String, dynamic>>(
      '/api/v1/invitations/revoke/$invitationId',
      fromJson: (json) => json,
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (_) => {},
    );
  }

  /// 复制邀请链接
  Future<String> copyInviteLink(int invitationId) async {
    final result = await post<Map<String, dynamic>>(
      '/api/v1/invitations/copy-link/$invitationId',
      fromJson: (json) => json,
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (data) => data['link'] as String,
    );
  }

  // ==================== Device Transfer APIs ====================

  /// 发起设备转移请求
  Future<void> requestDeviceTransfer({
    required String deviceSn,
    required int targetOrgId,
    String? reason,
  }) async {
    final result = await post<Map<String, dynamic>>(
      '/api/v1/devices/request-transfer',
      data: {
        'device_sn': deviceSn,
        'target_org_id': targetOrgId,
        if (reason != null) 'reason': reason,
      },
      fromJson: (json) => json,
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (_) => {},
    );
  }

  /// 获取转移请求列表
  Future<List<DeviceTransferRequest>> listTransferRequests() async {
    final result = await get<List<DeviceTransferRequest>>(
      '/api/v1/devices/transfers/list',
      fromJson: (data) => (data as List)
          .map(
            (item) => DeviceTransferRequest.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (requests) => requests,
    );
  }

  /// 审批转移请求
  Future<void> approveTransfer(int transferId, {String? approvalNote}) async {
    final result = await post<Map<String, dynamic>>(
      '/api/v1/devices/transfers/approve/$transferId',
      data: {
        if (approvalNote != null) 'note': approvalNote,
      },
      fromJson: (json) => json,
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (_) => {},
    );
  }

  /// 拒绝转移请求
  Future<void> rejectTransfer(int transferId, String reason) async {
    final result = await post<Map<String, dynamic>>(
      '/api/v1/devices/transfers/reject/$transferId',
      data: {'reason': reason},
      fromJson: (json) => json,
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (_) => {},
    );
  }
}
