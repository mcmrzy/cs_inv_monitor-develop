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
  final int role;
  final User? user;

  const AuthAuthenticated({
    required this.userId,
    required this.phone,
    required this.role,
    this.user,
  });

  @override
  List<Object?> get props => [userId, phone, role, user];
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
