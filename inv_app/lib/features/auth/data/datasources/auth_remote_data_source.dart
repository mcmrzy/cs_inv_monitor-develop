import 'package:dio/dio.dart';

class AuthRemoteDataSource {
  final Dio dio;

  AuthRemoteDataSource(this.dio);

  Future<Response> login(String account, String password) async {
    return await dio.post(
      '/auth/login',
      data: {
        'account': account,
        'password': password,
      },
    );
  }

  Future<Response> register(String phone, String password, String code) async {
    return await dio.post(
      '/auth/register',
      data: {
        'phone': phone,
        'password': password,
        'code': code,
      },
    );
  }

  Future<Response> sendCode(String phone, String type) async {
    return await dio.post(
      '/auth/send-code',
      data: {
        'phone': phone,
        'type': type,
      },
    );
  }

  Future<Response> resetPassword(
    String phone,
    String code,
    String newPassword,
  ) async {
    return await dio.post(
      '/auth/reset-password',
      data: {
        'phone': phone,
        'code': code,
        'new_password': newPassword,
      },
    );
  }

  Future<Response> changePassword(
    String oldPassword,
    String newPassword,
  ) async {
    return await dio.post(
      '/auth/change-password',
      data: {
        'old_password': oldPassword,
        'new_password': newPassword,
      },
    );
  }

  Future<Response> getProfile() async {
    return await dio.get('/auth/profile');
  }

  Future<Response> updateProfile(
    String? nickname,
    String? avatar, {
    String? timezone,
  }) async {
    final data = <String, dynamic>{
      'nickname': nickname,
      'avatar': avatar,
    };
    if (timezone != null) {
      data['timezone'] = timezone;
    }
    return await dio.put('/auth/profile', data: data);
  }

  Future<Response> emailLogin(String email, String password) async {
    return await dio.post(
      '/auth/email-login',
      data: {
        'email': email,
        'password': password,
      },
    );
  }

  Future<Response> emailRegister(
    String email,
    String password,
    String? nickname,
  ) async {
    return await dio.post(
      '/auth/email-register',
      data: {
        'email': email,
        'password': password,
        'nickname': nickname,
      },
    );
  }

  Future<Response> sendEmailCode(String email, String type) async {
    return await dio.post(
      '/auth/send-email-code',
      data: {
        'email': email,
        'type': type,
      },
    );
  }

  Future<Response> refreshToken(String refreshToken) async {
    return await dio.post(
      '/auth/refresh',
      data: {
        'refresh_token': refreshToken,
      },
    );
  }

  Future<Response> wechatLogin(String code) async {
    return await dio.post(
      '/auth/wechat-login',
      data: {
        'code': code,
      },
    );
  }

  Future<Response> googleLogin(String idToken) async {
    return await dio.post(
      '/auth/google-login',
      data: {
        'id_token': idToken,
      },
    );
  }
}

class AuthRemoteDataSourceImpl extends AuthRemoteDataSource {
  AuthRemoteDataSourceImpl(super.dio);
}
