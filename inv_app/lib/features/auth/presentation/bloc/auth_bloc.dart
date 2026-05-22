import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/services/mqtt_service.dart';
import 'package:inv_app/features/auth/domain/entities/user.dart';
import 'package:inv_app/features/auth/domain/usecases/login.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final LoginUseCase loginUseCase;
  final RegisterUseCase registerUseCase;
  final LogoutUseCase logoutUseCase;
  final SendCodeUseCase sendCodeUseCase;
  final ResetPasswordUseCase resetPasswordUseCase;
  final ChangePasswordUseCase changePasswordUseCase;
  final GetProfileUseCase getProfileUseCase;
  final UpdateProfileUseCase updateProfileUseCase;
  final EmailLoginUseCase emailLoginUseCase;
  final EmailRegisterUseCase emailRegisterUseCase;
  final SendEmailCodeUseCase sendEmailCodeUseCase;
  final StorageService storageService;
  final MQTTService mqttService;

  AuthBloc({
    required this.loginUseCase,
    required this.registerUseCase,
    required this.logoutUseCase,
    required this.sendCodeUseCase,
    required this.resetPasswordUseCase,
    required this.changePasswordUseCase,
    required this.getProfileUseCase,
    required this.updateProfileUseCase,
    required this.emailLoginUseCase,
    required this.emailRegisterUseCase,
    required this.sendEmailCodeUseCase,
    required this.storageService,
    required this.mqttService,
  }) : super(AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthSendCodeRequested>(_onSendCodeRequested);
    on<AuthResetPasswordRequested>(_onResetPasswordRequested);
    on<AuthChangePasswordRequested>(_onChangePasswordRequested);
    on<AuthUpdateProfileRequested>(_onUpdateProfileRequested);
    on<AuthEmailLoginRequested>(_onEmailLoginRequested);
    on<AuthEmailRegisterRequested>(_onEmailRegisterRequested);
    on<AuthSendEmailCodeRequested>(_onSendEmailCodeRequested);
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final token = await storageService.getToken();
    final userId = await storageService.getUserId();

    if (token != null && userId != null) {
      String phone = await storageService.getUserPhone() ?? '';
      int role = await storageService.getUserRole() ?? 5;
      User? user;

      try {
        final profileResult = await getProfileUseCase();
        profileResult.fold(
          (_) {},
          (u) {
            user = u;
            phone = u.phone;
            role = u.role;
          },
        );
      } catch (_) {}

      emit(AuthAuthenticated(
        userId: userId,
        phone: phone,
        role: role,
        user: user,
      ));

      _connectMQTT(phone.isNotEmpty ? phone : 'user_$userId');
    } else {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await loginUseCase(
      account: event.account,
      password: event.password,
    );

    await result.fold<Future<void>>(
      (failure) async {
        emit(AuthError(message: failure.message));
      },
      (response) async {
        await storageService.saveToken(response.token);
        await storageService.saveUserId(response.user.id);
        await storageService.saveUserPhone(response.user.phone);
        await storageService.saveUserRole(response.user.role);

        if (event.rememberPassword) {
          await storageService.saveRememberPassword(true);
          await storageService.saveSavedPhone(event.account);
          await storageService.saveSavedPassword(event.password);
        } else {
          await storageService.saveRememberPassword(false);
          await storageService.saveSavedPhone('');
          await storageService.saveSavedPassword('');
        }

        emit(AuthAuthenticated(
          userId: response.user.id,
          phone: response.user.phone,
          role: response.user.role,
          user: response.user,
        ));

        _connectMQTT(response.user.phone.isNotEmpty ? response.user.phone : 'user_${response.user.id}');
      },
    );
  }

  Future<void> _onRegisterRequested(
    AuthRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await registerUseCase(
      phone: event.phone,
      password: event.password,
      code: event.code,
    );

    await result.fold<Future<void>>(
      (failure) async {
        emit(AuthError(message: failure.message));
      },
      (response) async {
        await storageService.saveToken(response.token);
        await storageService.saveUserId(response.user.id);
        await storageService.saveUserPhone(response.user.phone);
        await storageService.saveUserRole(response.user.role);

        emit(AuthAuthenticated(
          userId: response.user.id,
          phone: response.user.phone,
          role: response.user.role,
          user: response.user,
        ));
      },
    );
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      await logoutUseCase();
    } catch (_) {}

    await storageService.deleteToken();
    await storageService.deleteUserId();
    await storageService.deleteUserPhone();
    await storageService.deleteUserRole();

    mqttService.disconnect();

    emit(AuthUnauthenticated());
  }

  Future<void> _onSendCodeRequested(
    AuthSendCodeRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthCodeSending());

    final result = await sendCodeUseCase(
      phone: event.phone,
      type: event.type,
    );

    result.fold(
      (failure) => emit(AuthError(message: failure.message)),
      (_) => emit(AuthCodeSent()),
    );
  }

  Future<void> _onResetPasswordRequested(
    AuthResetPasswordRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await resetPasswordUseCase(
      phone: event.phone,
      code: event.code,
      newPassword: event.newPassword,
    );

    result.fold(
      (failure) => emit(AuthError(message: failure.message)),
      (_) => emit(AuthPasswordResetSuccess()),
    );
  }

  Future<void> _onChangePasswordRequested(
    AuthChangePasswordRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await changePasswordUseCase(
      oldPassword: event.oldPassword,
      newPassword: event.newPassword,
    );

    result.fold(
      (failure) => emit(AuthError(message: failure.message)),
      (_) => emit(AuthPasswordChangedSuccess()),
    );
  }

  Future<void> _onUpdateProfileRequested(
    AuthUpdateProfileRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await updateProfileUseCase(
      nickname: event.nickname,
      avatar: event.avatar,
    );

    result.fold(
      (failure) => emit(AuthError(message: failure.message)),
      (_) {
        final currentState = state;
        if (currentState is AuthAuthenticated) {
          emit(AuthAuthenticated(
            userId: currentState.userId,
            phone: currentState.phone,
            role: currentState.role,
            user: currentState.user,
          ));
        }
      },
    );
  }

  Future<void> _onEmailLoginRequested(
    AuthEmailLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await emailLoginUseCase(
      email: event.email,
      password: event.password,
    );

    await result.fold<Future<void>>(
      (failure) async {
        emit(AuthError(message: failure.message));
      },
      (response) async {
        await storageService.saveToken(response.token);
        await storageService.saveUserId(response.user.id);
        await storageService.saveUserPhone(response.user.phone);
        await storageService.saveUserRole(response.user.role);

        if (event.rememberPassword) {
          await storageService.saveRememberPassword(true);
          await storageService.saveSavedPhone(event.email);
          await storageService.saveSavedPassword(event.password);
        } else {
          await storageService.saveRememberPassword(false);
          await storageService.saveSavedPhone('');
          await storageService.saveSavedPassword('');
        }

        emit(AuthAuthenticated(
          userId: response.user.id,
          phone: response.user.phone,
          role: response.user.role,
          user: response.user,
        ));

        _connectMQTT(response.user.phone.isNotEmpty ? response.user.phone : 'user_${response.user.id}');
      },
    );
  }

  Future<void> _onEmailRegisterRequested(
    AuthEmailRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await emailRegisterUseCase(
      email: event.email,
      password: event.password,
      code: event.code,
      phone: event.phone,
      nickname: event.nickname,
    );

    await result.fold<Future<void>>(
      (failure) async {
        emit(AuthError(message: failure.message));
      },
      (response) async {
        await storageService.saveToken(response.token);
        await storageService.saveUserId(response.user.id);
        await storageService.saveUserRole(response.user.role);

        emit(AuthAuthenticated(
          userId: response.user.id,
          phone: response.user.phone,
          role: response.user.role,
          user: response.user,
        ));

        _connectMQTT(response.user.phone.isNotEmpty ? response.user.phone : 'user_${response.user.id}');
      },
    );
  }

  Future<void> _onSendEmailCodeRequested(
    AuthSendEmailCodeRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthCodeSending());

    final result = await sendEmailCodeUseCase(
      email: event.email,
      type: event.type,
    );

    result.fold(
      (failure) => emit(AuthError(message: failure.message)),
      (_) => emit(AuthCodeSent()),
    );
  }

  void _connectMQTT(String clientId) async {
    try {
      await mqttService.connect(
        clientId,
        username: 'CSKJ-INV-SERVER-APP',
        password: 'CSKJINVSERVERAPP',
      );
      print('[MQTT] Connected as $clientId');
    } catch (e) {
      print('[MQTT] Connect failed: $e');
    }
  }
}
