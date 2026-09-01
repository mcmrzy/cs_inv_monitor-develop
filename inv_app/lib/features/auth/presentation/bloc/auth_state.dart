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
  final int? activeOrganizationId;
  final User? user;

  const AuthAuthenticated({
    required this.userId,
    required this.phone,
    this.isSystemAdmin = false,
    this.permissions = const [],
    this.activeOrganizationId,
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
  List<Object?> get props => [
        userId,
        phone,
        isSystemAdmin,
        permissions,
        activeOrganizationId,
        user,
      ];
}

class AuthProfileUpdateSuccess extends AuthAuthenticated {
  final String requestId;

  const AuthProfileUpdateSuccess({
    required this.requestId,
    required super.userId,
    required super.phone,
    super.isSystemAdmin,
    super.permissions,
    super.activeOrganizationId,
    super.user,
  });

  @override
  List<Object?> get props => [...super.props, requestId];
}

class AuthUnauthenticated extends AuthState {}

class AuthError extends AuthState {
  final String message;

  const AuthError({required this.message});

  @override
  List<Object?> get props => [message];
}

class AuthProfileUpdateError extends AuthError {
  final String requestId;

  const AuthProfileUpdateError({
    required super.message,
    required this.requestId,
  });

  @override
  List<Object?> get props => [message, requestId];
}

class AuthRegisterSuccess extends AuthState {}

class AuthCodeSending extends AuthState {
  final String target;
  final String type;
  final String channel;
  final String requestId;

  const AuthCodeSending({
    required this.target,
    required this.type,
    required this.channel,
    required this.requestId,
  });

  @override
  List<Object?> get props => [target, type, channel, requestId];
}

class AuthCodeSent extends AuthState {
  final String target;
  final String type;
  final String channel;
  final String requestId;

  const AuthCodeSent({
    required this.target,
    required this.type,
    required this.channel,
    required this.requestId,
  });

  @override
  List<Object?> get props => [target, type, channel, requestId];
}

class AuthCodeSendError extends AuthError {
  final String target;
  final String type;
  final String channel;
  final String requestId;

  const AuthCodeSendError({
    required super.message,
    required this.target,
    required this.type,
    required this.channel,
    required this.requestId,
  });

  @override
  List<Object?> get props => [message, target, type, channel, requestId];
}

class AuthPasswordResetSuccess extends AuthState {}

class AuthPasswordChangedSuccess extends AuthState {}

class AuthTokenRefreshFailed extends AuthState {
  final String message;

  const AuthTokenRefreshFailed({required this.message});

  @override
  List<Object?> get props => [message];
}
