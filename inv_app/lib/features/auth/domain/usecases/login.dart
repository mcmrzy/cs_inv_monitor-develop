import 'package:fpdart/fpdart.dart';
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
    String country = 'CN',
  }) {
    return repository.register(
      phone: phone,
      password: password,
      code: code,
      country: country,
    );
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
    String? captchaToken,
  }) {
    return repository.sendCode(
      phone: phone,
      type: type,
      captchaToken: captchaToken,
    );
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
    return repository.resetPassword(
      phone: phone,
      code: code,
      newPassword: newPassword,
    );
  }
}

class ChangePasswordUseCase {
  final AuthRepository repository;

  ChangePasswordUseCase(this.repository);

  Future<Either<Failure, void>> call({
    required String oldPassword,
    required String newPassword,
  }) {
    return repository.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
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
    String? email,
    String? country,
    String? regionName,
    String? bio,
    String? timezone,
  }) {
    return repository.updateProfile(
      nickname: nickname,
      avatar: avatar,
      email: email,
      country: country,
      regionName: regionName,
      bio: bio,
      timezone: timezone,
    );
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

class PhoneCodeLoginUseCase {
  final AuthRepository repository;

  PhoneCodeLoginUseCase(this.repository);

  Future<Either<Failure, LoginResponse>> call({
    required String phone,
    required String code,
  }) {
    return repository.phoneCodeLogin(phone: phone, code: code);
  }
}

class EmailCodeLoginUseCase {
  final AuthRepository repository;

  EmailCodeLoginUseCase(this.repository);

  Future<Either<Failure, LoginResponse>> call({
    required String email,
    required String code,
  }) {
    return repository.emailCodeLogin(email: email, code: code);
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
    String country = '',
  }) {
    return repository.emailRegister(
      email: email,
      password: password,
      code: code,
      phone: phone,
      nickname: nickname,
      country: country,
    );
  }
}

class SendEmailCodeUseCase {
  final AuthRepository repository;

  SendEmailCodeUseCase(this.repository);

  Future<Either<Failure, void>> call({
    required String email,
    required String type,
    String? captchaToken,
  }) {
    return repository.sendEmailCode(
      email: email,
      type: type,
      captchaToken: captchaToken,
    );
  }
}

class RefreshTokenUseCase {
  final AuthRepository repository;

  RefreshTokenUseCase(this.repository);

  Future<Either<Failure, LoginResponse>> call({
    required String refreshToken,
  }) {
    return repository.refreshToken(refreshToken: refreshToken);
  }
}

class WechatLoginUseCase {
  final AuthRepository repository;

  WechatLoginUseCase(this.repository);

  Future<Either<Failure, LoginResponse>> call({
    required String code,
  }) {
    return repository.wechatLogin(code: code);
  }
}

class GoogleLoginUseCase {
  final AuthRepository repository;

  GoogleLoginUseCase(this.repository);

  Future<Either<Failure, LoginResponse>> call({
    required String idToken,
  }) {
    return repository.googleLogin(idToken: idToken);
  }
}

class JVerifyLoginUseCase {
  final AuthRepository repository;

  JVerifyLoginUseCase(this.repository);

  Future<Either<Failure, LoginResponse>> call({
    required String loginToken,
  }) {
    return repository.jverifyLogin(loginToken: loginToken);
  }
}
