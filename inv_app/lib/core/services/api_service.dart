import 'package:dio/dio.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:fpdart/fpdart.dart';
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
      '/organizations',
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
      '/organizations',
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
      '/organizations/$orgId',
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
      '/organizations/$orgId',
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
      '/organizations/$orgId',
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
      '/organizations/$orgId/members',
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
      '/organizations/$orgId/members',
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
      '/organizations/$orgId/members/$userId',
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
      '/organizations/$orgId/members/$userId',
      fromJson: (json) => json,
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (_) => {},
    );
  }

  // ==================== Invitation APIs ====================

  /// 发送邀请（批量接口的单邮箱形态：emails x assignments）
  /// 返回创建结果 Map（含 created 数量与 results 明细，results[].invite_link
  /// 为相对路径，仅在创建时返回一次）
  Future<Map<String, dynamic>> sendInvitation({
    required int orgId,
    required String email,
    required String roleCode,
    int? expiresHours,
  }) async {
    final result = await post<Map<String, dynamic>>(
      '/invitations/create',
      data: {
        'emails': [email],
        'assignments': [
          {'organization_id': orgId, 'role_code': roleCode},
        ],
        if (expiresHours != null) 'expires_hours': expiresHours,
      },
      fromJson: (json) => Map<String, dynamic>.from(json as Map),
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (data) => data,
    );
  }

  /// 获取邀请列表（分页结构 {items: [], total, page, page_size}）
  Future<List<OrganizationInvitation>> listInvitations(int orgId) async {
    final result = await get<List<OrganizationInvitation>>(
      '/invitations/list',
      queryParameters: {'organization_id': orgId, 'page': 1, 'page_size': 100},
      fromJson: (data) {
        final list = data is Map ? (data['items'] as List) : (data as List);
        return list
            .map(
              (item) => OrganizationInvitation.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
      },
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (invitations) => invitations,
    );
  }

  /// 撤销邀请（路径与后端一致：/invitations/:id/revoke）
  Future<void> revokeInvitation(int invitationId) async {
    final result = await delete<Map<String, dynamic>>(
      '/invitations/$invitationId/revoke',
      fromJson: (json) => json,
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (_) => {},
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
      '/devices/request-transfer',
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
      '/devices/transfers/list',
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
      '/devices/transfers/approve/$transferId',
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
      '/devices/transfers/reject/$transferId',
      data: {'reason': reason},
      fromJson: (json) => json,
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (_) => {},
    );
  }
}
