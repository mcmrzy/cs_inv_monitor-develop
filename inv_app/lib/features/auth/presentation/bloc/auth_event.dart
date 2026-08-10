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
  final String? email;
  final String? country;
  final String? regionName;
  final String? bio;

  const AuthUpdateProfileRequested({
    this.nickname,
    this.avatar,
    this.email,
    this.country,
    this.regionName,
    this.bio,
  });

  @override
  List<Object?> get props => [nickname, avatar, email, country, regionName, bio];
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

/// 修改手机号/邮箱成功后，同步更新 AuthBloc 状态与本地缓存（无需重新请求服务器）
class AuthContactChanged extends AuthEvent {
  final String? newPhone;
  final String? newEmail;

  const AuthContactChanged({this.newPhone, this.newEmail});

  @override
  List<Object?> get props => [newPhone, newEmail];
}

class AuthTokenRefreshed extends AuthEvent {
  final String token;
  final String? refreshToken;

  const AuthTokenRefreshed({
    required this.token,
    this.refreshToken,
  });

  @override
  List<Object?> get props => [token, refreshToken];
}

class AuthWechatLoginRequested extends AuthEvent {
  final String code;

  const AuthWechatLoginRequested({required this.code});

  @override
  List<Object?> get props => [code];
}

class AuthGoogleLoginRequested extends AuthEvent {
  final String idToken;

  const AuthGoogleLoginRequested({required this.idToken});

  @override
  List<Object?> get props => [idToken];
}

/// 使用已获取的 loginToken 直接登录（不再重新拉起授权页）
class AuthJVerifyLoginWithTokenRequested extends AuthEvent {
  final String loginToken;

  const AuthJVerifyLoginWithTokenRequested({required this.loginToken});

  @override
  List<Object?> get props => [loginToken];
}
