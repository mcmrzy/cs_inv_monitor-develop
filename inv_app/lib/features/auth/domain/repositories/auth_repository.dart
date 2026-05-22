import 'package:dartz/dartz.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/auth/domain/entities/user.dart';

abstract class AuthRepository {
  Future<Either<Failure, LoginResponse>> login({
    required String account,
    required String password,
  });

  Future<Either<Failure, LoginResponse>> register({
    required String phone,
    required String password,
    required String code,
  });

  Future<Either<Failure, void>> logout();

  Future<Either<Failure, void>> sendCode({
    required String phone,
    required String type,
  });

  Future<Either<Failure, void>> resetPassword({
    required String phone,
    required String code,
    required String newPassword,
  });

  Future<Either<Failure, void>> changePassword({
    required String oldPassword,
    required String newPassword,
  });

  Future<Either<Failure, User>> getProfile();

  Future<Either<Failure, void>> updateProfile({
    String? nickname,
    String? avatar,
  });

  Future<Either<Failure, LoginResponse>> emailLogin({
    required String email,
    required String password,
  });

  Future<Either<Failure, LoginResponse>> emailRegister({
    required String email,
    required String password,
    required String code,
    required String phone,
    required String nickname,
  });

  Future<Either<Failure, void>> sendEmailCode({
    required String email,
    required String type,
  });
}
