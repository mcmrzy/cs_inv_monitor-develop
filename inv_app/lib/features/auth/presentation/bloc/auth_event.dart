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
  final String country;

  const AuthRegisterRequested({
    required this.phone,
    required this.password,
    required this.code,
    this.country = 'CN',
  });

  @override
  List<Object?> get props => [phone, password, code, country];
}

class AuthLogoutRequested extends AuthEvent {}

class AuthSendCodeRequested extends AuthEvent {
  final String phone;
  final String type;
  final String? captchaToken;
  final String requestId;

  const AuthSendCodeRequested({
    required this.phone,
    required this.type,
    required this.requestId,
    this.captchaToken,
  });

  @override
  List<Object?> get props => [phone, type, captchaToken, requestId];
}

class AuthCodeRequestId {
  static int _sequence = 0;

  static String next() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '$timestamp-${_sequence++}';
  }
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
  final String requestId;
  final String? nickname;
  final String? avatar;
  final String? email;
  final String? country;
  final String? regionName;
  final String? bio;

  const AuthUpdateProfileRequested({
    required this.requestId,
    this.nickname,
    this.avatar,
    this.email,
    this.country,
    this.regionName,
    this.bio,
  });

  @override
  List<Object?> get props => [
        requestId,
        nickname,
        avatar,
        email,
        country,
        regionName,
        bio,
      ];
}

class AuthProfileRequestId {
  static int _sequence = 0;

  static String next() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '$timestamp-${_sequence++}';
  }
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

class AuthPhoneCodeLoginRequested extends AuthEvent {
  final String phone;
  final String code;

  const AuthPhoneCodeLoginRequested({
    required this.phone,
    required this.code,
  });

  @override
  List<Object?> get props => [phone, code];
}

class AuthEmailCodeLoginRequested extends AuthEvent {
  final String email;
  final String code;

  const AuthEmailCodeLoginRequested({
    required this.email,
    required this.code,
  });

  @override
  List<Object?> get props => [email, code];
}

class AuthEmailRegisterRequested extends AuthEvent {
  final String email;
  final String password;
  final String code;
  final String phone;
  final String nickname;
  final String country;

  const AuthEmailRegisterRequested({
    required this.email,
    required this.password,
    required this.code,
    required this.phone,
    required this.nickname,
    this.country = '',
  });

  @override
  List<Object?> get props => [email, password, code, phone, nickname, country];
}

class AuthSendEmailCodeRequested extends AuthEvent {
  final String email;
  final String type;
  final String? captchaToken;
  final String requestId;

  const AuthSendEmailCodeRequested({
    required this.email,
    required this.type,
    required this.requestId,
    this.captchaToken,
  });

  @override
  List<Object?> get props => [email, type, captchaToken, requestId];
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

class AuthOrganizationContextSwitchRequested extends AuthEvent {
  final int organizationId;
  final String organizationName;
  final Completer<void> completer;

  const AuthOrganizationContextSwitchRequested({
    required this.organizationId,
    required this.organizationName,
    required this.completer,
  });

  @override
  List<Object?> get props => [organizationId, organizationName];
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
