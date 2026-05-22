import 'package:dartz/dartz.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/auth/domain/entities/user.dart';
import 'package:inv_app/features/auth/domain/repositories/auth_repository.dart';

class LoginUseCase {
  final AuthRepository repository;

  LoginUseCase(this.repository);

  Future<Either<Failure, LoginResponse>> call({
    required String account,
    required String password,
  }) {
    return repository.login(account: account, password: password);
  }
}

class RegisterUseCase {
  final AuthRepository repository;

  RegisterUseCase(this.repository);

  Future<Either<Failure, LoginResponse>> call({
    required String phone,
    required String password,
    required String code,
  }) {
    return repository.register(phone: phone, password: password, code: code);
  }
}

class LogoutUseCase {
  final AuthRepository repository;

  LogoutUseCase(this.repository);

  Future<Either<Failure, void>> call() {
    return repository.logout();
  }
}

class SendCodeUseCase {
  final AuthRepository repository;

  SendCodeUseCase(this.repository);

  Future<Either<Failure, void>> call({
    required String phone,
    required String type,
  }) {
    return repository.sendCode(phone: phone, type: type);
  }
}

class ResetPasswordUseCase {
  final AuthRepository repository;

  ResetPasswordUseCase(this.repository);

  Future<Either<Failure, void>> call({
    required String phone,
    required String code,
    required String newPassword,
  }) {
    return repository.resetPassword(phone: phone, code: code, newPassword: newPassword);
  }
}

class ChangePasswordUseCase {
  final AuthRepository repository;

  ChangePasswordUseCase(this.repository);

  Future<Either<Failure, void>> call({
    required String oldPassword,
    required String newPassword,
  }) {
    return repository.changePassword(oldPassword: oldPassword, newPassword: newPassword);
  }
}

class GetProfileUseCase {
  final AuthRepository repository;

  GetProfileUseCase(this.repository);

  Future<Either<Failure, User>> call() {
    return repository.getProfile();
  }
}

class UpdateProfileUseCase {
  final AuthRepository repository;

  UpdateProfileUseCase(this.repository);

  Future<Either<Failure, void>> call({
    String? nickname,
    String? avatar,
  }) {
    return repository.updateProfile(nickname: nickname, avatar: avatar);
  }
}

class EmailLoginUseCase {
  final AuthRepository repository;

  EmailLoginUseCase(this.repository);

  Future<Either<Failure, LoginResponse>> call({
    required String email,
    required String password,
  }) {
    return repository.emailLogin(email: email, password: password);
  }
}

class EmailRegisterUseCase {
  final AuthRepository repository;

  EmailRegisterUseCase(this.repository);

  Future<Either<Failure, LoginResponse>> call({
    required String email,
    required String password,
    required String code,
    required String phone,
    required String nickname,
  }) {
    return repository.emailRegister(email: email, password: password, code: code, phone: phone, nickname: nickname);
  }
}

class SendEmailCodeUseCase {
  final AuthRepository repository;

  SendEmailCodeUseCase(this.repository);

  Future<Either<Failure, void>> call({
    required String email,
    required String type,
  }) {
    return repository.sendEmailCode(email: email, type: type);
  }
}
