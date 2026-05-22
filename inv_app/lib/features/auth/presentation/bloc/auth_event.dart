part of 'auth_bloc.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {}

class AuthLoginRequested extends AuthEvent {
  final String account;
  final String password;
  final bool rememberPassword;

  const AuthLoginRequested({
    required this.account,
    required this.password,
    this.rememberPassword = false,
  });

  @override
  List<Object?> get props => [account, password, rememberPassword];
}

class AuthRegisterRequested extends AuthEvent {
  final String phone;
  final String password;
  final String code;

  const AuthRegisterRequested({
    required this.phone,
    required this.password,
    required this.code,
  });

  @override
  List<Object?> get props => [phone, password, code];
}

class AuthLogoutRequested extends AuthEvent {}

class AuthSendCodeRequested extends AuthEvent {
  final String phone;
  final String type;

  const AuthSendCodeRequested({
    required this.phone,
    required this.type,
  });

  @override
  List<Object?> get props => [phone, type];
}

class AuthResetPasswordRequested extends AuthEvent {
  final String phone;
  final String code;
  final String newPassword;

  const AuthResetPasswordRequested({
    required this.phone,
    required this.code,
    required this.newPassword,
  });

  @override
  List<Object?> get props => [phone, code, newPassword];
}

class AuthChangePasswordRequested extends AuthEvent {
  final String oldPassword;
  final String newPassword;

  const AuthChangePasswordRequested({
    required this.oldPassword,
    required this.newPassword,
  });

  @override
  List<Object?> get props => [oldPassword, newPassword];
}

class AuthUpdateProfileRequested extends AuthEvent {
  final String? nickname;
  final String? avatar;

  const AuthUpdateProfileRequested({
    this.nickname,
    this.avatar,
  });

  @override
  List<Object?> get props => [nickname, avatar];
}

class AuthEmailLoginRequested extends AuthEvent {
  final String email;
  final String password;
  final bool rememberPassword;

  const AuthEmailLoginRequested({
    required this.email,
    required this.password,
    this.rememberPassword = false,
  });

  @override
  List<Object?> get props => [email, password, rememberPassword];
}

class AuthEmailRegisterRequested extends AuthEvent {
  final String email;
  final String password;
  final String code;
  final String phone;
  final String nickname;

  const AuthEmailRegisterRequested({
    required this.email,
    required this.password,
    required this.code,
    required this.phone,
    required this.nickname,
  });

  @override
  List<Object?> get props => [email, password, code, phone, nickname];
}

class AuthSendEmailCodeRequested extends AuthEvent {
  final String email;
  final String type;

  const AuthSendEmailCodeRequested({
    required this.email,
    required this.type,
  });

  @override
  List<Object?> get props => [email, type];
}
