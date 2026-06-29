import 'package:dartz/dartz.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/services/api_service.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/features/auth/domain/entities/user.dart';
import 'package:inv_app/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final ApiService apiService;
  final StorageService storageService;

  AuthRepositoryImpl(this.apiService, this.storageService);

  @override
  Future<Either<Failure, LoginResponse>> login({
    required String account,
    required String password,
  }) async {
    return apiService.post(
      '/auth/login',
      data: {'account': account, 'password': password},
      fromJson: (json) => LoginResponse.fromJson(json),
    );
  }

  @override
  Future<Either<Failure, LoginResponse>> register({
    required String phone,
    required String password,
    required String code,
  }) async {
    return apiService.post(
      '/auth/register',
      data: {'phone': phone, 'password': password, 'code': code},
      fromJson: (json) => LoginResponse.fromJson(json),
    );
  }

  @override
  Future<Either<Failure, void>> logout() async {
    return apiService.post(
      '/auth/logout',
      fromJson: (_) {},
    );
  }

  @override
  Future<Either<Failure, void>> sendCode({
    required String phone,
    required String type,
  }) async {
    return apiService.post(
      '/auth/send-code',
      data: {'phone': phone, 'type': type},
      fromJson: (_) {},
    );
  }

  @override
  Future<Either<Failure, void>> resetPassword({
    required String phone,
    required String code,
    required String newPassword,
  }) async {
    return apiService.post(
      '/auth/reset-password',
      data: {'phone': phone, 'code': code, 'new_password': newPassword},
      fromJson: (_) {},
    );
  }

  @override
  Future<Either<Failure, void>> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    return apiService.post(
      '/auth/change-password',
      data: {'old_password': oldPassword, 'new_password': newPassword},
      fromJson: (_) {},
    );
  }

  @override
  Future<Either<Failure, User>> getProfile() async {
    return apiService.get(
      '/auth/profile',
      fromJson: (json) => User.fromJson(json),
    );
  }

  @override
  Future<Either<Failure, void>> updateProfile({
    String? nickname,
    String? avatar,
    String? timezone,
  }) async {
    final data = <String, dynamic>{
      'nickname': nickname,
      'avatar': avatar,
    };
    if (timezone != null) {
      data['timezone'] = timezone;
    }
    return apiService.put(
      '/auth/profile',
      data: data,
      fromJson: (_) {},
    );
  }

  @override
  Future<Either<Failure, LoginResponse>> emailLogin({
    required String email,
    required String password,
  }) async {
    return apiService.post(
      '/auth/email-login',
      data: {'email': email, 'password': password},
      fromJson: (json) => LoginResponse.fromJson(json),
    );
  }

  @override
  Future<Either<Failure, LoginResponse>> emailRegister({
    required String email,
    required String password,
    required String code,
    required String phone,
    required String nickname,
  }) async {
    return apiService.post(
      '/auth/email-register',
      data: {'email': email, 'password': password, 'code': code, 'phone': phone, 'nickname': nickname},
      fromJson: (json) => LoginResponse.fromJson(json),
    );
  }

  @override
  Future<Either<Failure, void>> sendEmailCode({
    required String email,
    required String type,
  }) async {
    return apiService.post(
      '/auth/send-email-code',
      data: {'email': email, 'type': type},
      fromJson: (_) {},
    );
  }

  @override
  Future<Either<Failure, LoginResponse>> refreshToken({
    required String refreshToken,
  }) async {
    return apiService.post(
      '/auth/refresh',
      data: {'refresh_token': refreshToken},
      fromJson: (json) => LoginResponse.fromJson(json),
    );
  }

  @override
  Future<Either<Failure, LoginResponse>> wechatLogin({
    required String code,
  }) async {
    return apiService.post(
      '/auth/wechat-login',
      data: {'code': code},
      fromJson: (json) => LoginResponse.fromJson(json),
    );
  }

  @override
  Future<Either<Failure, LoginResponse>> googleLogin({
    required String idToken,
  }) async {
    return apiService.post(
      '/auth/google-login',
      data: {'id_token': idToken},
      fromJson: (json) => LoginResponse.fromJson(json),
    );
  }
}
