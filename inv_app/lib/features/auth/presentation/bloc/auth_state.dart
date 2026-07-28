part of 'auth_bloc.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final int userId;
  final String phone;
  final bool isSystemAdmin;
  final List<String> permissions;
  final User? user;

  const AuthAuthenticated({
    required this.userId,
    required this.phone,
    this.isSystemAdmin = false,
    this.permissions = const [],
    this.user,
  });

  // Convenience getters that delegate to the user object
  String? get nickname => user?.nickname;
  String? get email => user?.email;
  String? get country => user?.country;
  String? get regionName => user?.region;
  String? get bio => user?.bio;
  String? get avatar => user?.avatar;

  @override
  List<Object?> get props => [userId, phone, isSystemAdmin, permissions, user];
}

class AuthUnauthenticated extends AuthState {}

class AuthError extends AuthState {
  final String message;

  const AuthError({required this.message});

  @override
  List<Object?> get props => [message];
}

class AuthRegisterSuccess extends AuthState {}

class AuthCodeSending extends AuthState {}

class AuthCodeSent extends AuthState {}

class AuthPasswordResetSuccess extends AuthState {}

class AuthPasswordChangedSuccess extends AuthState {}

class AuthTokenRefreshFailed extends AuthState {
  final String message;

  const AuthTokenRefreshFailed({required this.message});

  @override
  List<Object?> get props => [message];
}
