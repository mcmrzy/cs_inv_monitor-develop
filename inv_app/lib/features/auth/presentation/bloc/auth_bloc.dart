import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/core/services/storage_service.dart';

import 'package:inv_app/core/services/jpush_service.dart';
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
  final RefreshTokenUseCase refreshTokenUseCase;
  final WechatLoginUseCase wechatLoginUseCase;
  final GoogleLoginUseCase googleLoginUseCase;
  final JVerifyLoginUseCase jverifyLoginUseCase;
  final StorageService storageService;
  final JPushService jpushService;

  /// 用户资料本地缓存 key（冷启动时先用缓存展示，后台刷新覆盖）
  static const String _cachedUserKey = 'cached_user_profile';

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
    required this.refreshTokenUseCase,
    required this.wechatLoginUseCase,
    required this.googleLoginUseCase,
    required this.jverifyLoginUseCase,
    required this.storageService,
    required this.jpushService,
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
    on<AuthContactChanged>(_onContactChanged);
    on<AuthTokenRefreshed>(_onTokenRefreshed);
    on<AuthWechatLoginRequested>(_onWechatLoginRequested);
    on<AuthGoogleLoginRequested>(_onGoogleLoginRequested);
    on<AuthJVerifyLoginWithTokenRequested>(_onJVerifyLoginWithTokenRequested);
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
      bool isSystemAdmin = await storageService.getIsSystemAdmin() ?? false;
      List<String> permissions = await storageService.getPermissions();

      // 先读取本地缓存的用户资料，网络未就绪时也能立即展示昵称/头像
      final cachedUser = await _loadCachedUser();

      // 先用本地缓存立即进入首页（乐观进入，跳转不等网络）；
      // token 失效时由首页首个请求 401 触发刷新/登出兑底
      emit(
        AuthAuthenticated(
          userId: userId,
          phone: phone,
          isSystemAdmin: isSystemAdmin,
          permissions: permissions,
          user: cachedUser,
        ),
      );

      jpushService.bindUser(userId);

      // 后台刷新资料，成功后更新状态；失败保持本地缓存
      unawaited(_refreshProfile(emit, userId, phone, isSystemAdmin, permissions));
    } else {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _refreshProfile(
    Emitter<AuthState> emit,
    int userId,
    String phone,
    bool isSystemAdmin,
    List<String> permissions,
  ) async {
    // 启动/下拉刷新时网络可能未就绪，失败后延时重试，避免资料一直显示为空
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final profileResult = await getProfileUseCase();
        // 期间已登出则放弃更新，避免状态回退
        if (state is AuthUnauthenticated) return;
        final user = profileResult.fold<User?>((_) => null, (u) => u);
        if (user != null) {
          // 缓存最新资料，冷启动时优先展示本地缓存
          await _cacheUser(user);
          emit(
            AuthAuthenticated(
              userId: userId,
              phone: user.phone,
              isSystemAdmin: user.isSystemAdmin,
              permissions: user.permissions,
              user: user,
            ),
          );
          return;
        }
      } catch (_) {
        if (state is AuthUnauthenticated) return;
      }
      if (attempt < 2) {
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
  }

  /// 读取本地缓存的用户资料（网络不可用时兜底展示）
  Future<User?> _loadCachedUser() async {
    try {
      final raw = await storageService.getString(_cachedUserKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return User.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  /// 缓存用户资料 JSON 到本地
  Future<void> _cacheUser(User user) async {
    try {
      await storageService.saveString(
        _cachedUserKey,
        jsonEncode(user.toJson()),
      );
    } catch (_) {}
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
        if (response.refreshToken != null) {
          await storageService.saveRefreshToken(response.refreshToken!);
        }
        await storageService.saveUserId(response.user.id);
        await storageService.saveUserPhone(response.user.phone);
        await storageService.saveIsSystemAdmin(response.user.isSystemAdmin);
        await storageService.savePermissions(response.permissions);

        if (event.rememberPassword) {
          await storageService.saveRememberPassword(true);
          await storageService.saveSavedPhone(event.account);
          await storageService.saveSavedPassword(event.password);
        } else {
          await storageService.saveRememberPassword(false);
          await storageService.saveSavedPhone('');
          await storageService.saveSavedPassword('');
        }

        emit(
          AuthAuthenticated(
            userId: response.user.id,
            phone: response.user.phone,
            isSystemAdmin: response.user.isSystemAdmin,
            permissions: response.permissions,
            user: response.user,
          ),
        );

        jpushService.bindUser(response.user.id);
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
        if (response.refreshToken != null) {
          await storageService.saveRefreshToken(response.refreshToken!);
        }
        await storageService.saveUserId(response.user.id);
        await storageService.saveUserPhone(response.user.phone);
        await storageService.saveIsSystemAdmin(response.user.isSystemAdmin);
        await storageService.savePermissions(response.permissions);

        emit(
          AuthAuthenticated(
            userId: response.user.id,
            phone: response.user.phone,
            isSystemAdmin: response.user.isSystemAdmin,
            permissions: response.permissions,
            user: response.user,
          ),
        );

        jpushService.bindUser(response.user.id);
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
    await storageService.deleteRefreshToken();
    await storageService.deleteUserId();
    await storageService.deleteUserPhone();
    await storageService.deleteIsSystemAdmin();
    await storageService.deletePermissions();
    // 清除本地缓存的用户资料
    await storageService.saveString(_cachedUserKey, '');

    jpushService.unbindUser();

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
    // 保存当前状态，以便在更新失败时恢复
    final previousState = state;
    final previousUserId = previousState is AuthAuthenticated ? previousState.userId : null;
    final previousPhone = previousState is AuthAuthenticated ? previousState.phone : null;
    final previousIsSystemAdmin = previousState is AuthAuthenticated ? previousState.isSystemAdmin : false;
    final previousPermissions = previousState is AuthAuthenticated ? previousState.permissions : <String>[];
    final previousUser = previousState is AuthAuthenticated ? previousState.user : null;

    emit(AuthLoading());

    final result = await updateProfileUseCase(
      nickname: event.nickname,
      avatar: event.avatar,
      email: event.email,
      country: event.country,
      regionName: event.regionName,
      bio: event.bio,
    );

    await result.fold<Future<void>>(
      (failure) async {
        emit(AuthError(message: failure.message));
      },
      (_) async {
        // 更新成功后，重新获取用户信息
        final profileResult = await getProfileUseCase();
        final refreshed = profileResult.fold<User?>(
          (_) {
            // 如果获取用户信息失败，仍然保持当前状态
            if (previousUserId != null) {
              emit(
                AuthAuthenticated(
                  userId: previousUserId,
                  phone: previousPhone ?? '',
                  isSystemAdmin: previousIsSystemAdmin,
                  permissions: previousPermissions,
                  user: previousUser,
                ),
              );
            }
            return null;
          },
          (user) => user,
        );
        // 使用最新的用户信息更新状态
        if (refreshed != null && previousUserId != null) {
          // 缓存最新资料，冷启动时优先展示本地缓存；
          // 等待写入完成，避免保存后立即重启导致缓存未落盘
          await _cacheUser(refreshed);
          emit(
            AuthAuthenticated(
              userId: previousUserId,
              phone: previousPhone ?? refreshed.phone,
              isSystemAdmin: refreshed.isSystemAdmin,
              permissions: refreshed.permissions,
              user: refreshed,
            ),
          );
        }
      },
    );
  }

  /// 手机号/邮箱修改成功后，同步更新 AuthBloc 状态与本地缓存；
  /// 避免重新进入设置页时仍显示旧值
  Future<void> _onContactChanged(
    AuthContactChanged event,
    Emitter<AuthState> emit,
  ) async {
    final current = state;
    if (current is! AuthAuthenticated) return;

    final newPhone = event.newPhone ?? current.phone;
    if (event.newPhone != null) {
      await storageService.saveUserPhone(event.newPhone!);
    }

    final oldUser = current.user;
    User? updatedUser;
    if (oldUser != null) {
      updatedUser = User(
        id: oldUser.id,
        phone: newPhone,
        email: event.newEmail ?? oldUser.email,
        nickname: oldUser.nickname,
        avatar: oldUser.avatar,
        country: oldUser.country,
        region: oldUser.region,
        bio: oldUser.bio,
        hasPassword: oldUser.hasPassword,
        isSystemAdmin: oldUser.isSystemAdmin,
        permissions: oldUser.permissions,
        status: oldUser.status,
        lastLoginAt: oldUser.lastLoginAt,
        createdAt: oldUser.createdAt,
        updatedAt: oldUser.updatedAt,
      );
      // 同步更新本地缓存的用户资料，冷启动时也能展示新手机号/邮箱
      await _cacheUser(updatedUser);
    }

    emit(
      AuthAuthenticated(
        userId: current.userId,
        phone: newPhone,
        isSystemAdmin: current.isSystemAdmin,
        permissions: current.permissions,
        user: updatedUser,
      ),
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
        if (response.refreshToken != null) {
          await storageService.saveRefreshToken(response.refreshToken!);
        }
        await storageService.saveUserId(response.user.id);
        await storageService.saveUserPhone(response.user.phone);
        await storageService.saveIsSystemAdmin(response.user.isSystemAdmin);
        await storageService.savePermissions(response.permissions);

        if (event.rememberPassword) {
          await storageService.saveRememberPassword(true);
          await storageService.saveSavedPhone(event.email);
          await storageService.saveSavedPassword(event.password);
        } else {
          await storageService.saveRememberPassword(false);
          await storageService.saveSavedPhone('');
          await storageService.saveSavedPassword('');
        }

        emit(
          AuthAuthenticated(
            userId: response.user.id,
            phone: response.user.phone,
            isSystemAdmin: response.user.isSystemAdmin,
            permissions: response.permissions,
            user: response.user,
          ),
        );

        jpushService.bindUser(response.user.id);
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
        if (response.refreshToken != null) {
          await storageService.saveRefreshToken(response.refreshToken!);
        }
        await storageService.saveUserId(response.user.id);
        await storageService.saveUserPhone(response.user.phone);
        await storageService.saveIsSystemAdmin(response.user.isSystemAdmin);
        await storageService.savePermissions(response.permissions);

        emit(
          AuthAuthenticated(
            userId: response.user.id,
            phone: response.user.phone,
            isSystemAdmin: response.user.isSystemAdmin,
            permissions: response.permissions,
            user: response.user,
          ),
        );

        jpushService.bindUser(response.user.id);
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

  Future<void> _onTokenRefreshed(
    AuthTokenRefreshed event,
    Emitter<AuthState> emit,
  ) async {
    await storageService.saveToken(event.token);
    if (event.refreshToken != null) {
      await storageService.saveRefreshToken(event.refreshToken!);
    }
  }

  Future<void> _onWechatLoginRequested(
    AuthWechatLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await wechatLoginUseCase(code: event.code);

    await result.fold<Future<void>>(
      (failure) async {
        emit(AuthError(message: failure.message));
      },
      (response) async {
        await storageService.saveToken(response.token);
        if (response.refreshToken != null) {
          await storageService.saveRefreshToken(response.refreshToken!);
        }
        await storageService.saveUserId(response.user.id);
        await storageService.saveUserPhone(response.user.phone);
        await storageService.saveIsSystemAdmin(response.user.isSystemAdmin);
        await storageService.savePermissions(response.permissions);

        emit(
          AuthAuthenticated(
            userId: response.user.id,
            phone: response.user.phone,
            isSystemAdmin: response.user.isSystemAdmin,
            permissions: response.permissions,
            user: response.user,
          ),
        );

        jpushService.bindUser(response.user.id);
      },
    );
  }

  Future<void> _onGoogleLoginRequested(
    AuthGoogleLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await googleLoginUseCase(idToken: event.idToken);

    await result.fold<Future<void>>(
      (failure) async {
        emit(AuthError(message: failure.message));
      },
      (response) async {
        await storageService.saveToken(response.token);
        if (response.refreshToken != null) {
          await storageService.saveRefreshToken(response.refreshToken!);
        }
        await storageService.saveUserId(response.user.id);
        await storageService.saveUserPhone(response.user.phone);
        await storageService.saveIsSystemAdmin(response.user.isSystemAdmin);
        await storageService.savePermissions(response.permissions);

        emit(
          AuthAuthenticated(
            userId: response.user.id,
            phone: response.user.phone,
            isSystemAdmin: response.user.isSystemAdmin,
            permissions: response.permissions,
            user: response.user,
          ),
        );

        jpushService.bindUser(response.user.id);
      },
    );
  }

  /// 使用已获取的 loginToken 直接登录（不再重新拉起授权页）
  Future<void> _onJVerifyLoginWithTokenRequested(
    AuthJVerifyLoginWithTokenRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    // 直接调用后端验证
    final response = await jverifyLoginUseCase(loginToken: event.loginToken);

    await response.fold<Future<void>>(
      (failure) async {
        debugPrint('[AuthBloc] Login failed: ${failure.message}');
        emit(AuthError(message: failure.message));
      },
      (response) async {
        await storageService.saveToken(response.token);
        if (response.refreshToken != null) {
          await storageService.saveRefreshToken(response.refreshToken!);
        }
        await storageService.saveUserId(response.user.id);
        await storageService.saveUserPhone(response.user.phone);
        await storageService.saveIsSystemAdmin(response.user.isSystemAdmin);
        await storageService.savePermissions(response.permissions);

        emit(
          AuthAuthenticated(
            userId: response.user.id,
            phone: response.user.phone,
            isSystemAdmin: response.user.isSystemAdmin,
            permissions: response.permissions,
            user: response.user,
          ),
        );

        jpushService.bindUser(response.user.id);
      },
    );
  }
}
