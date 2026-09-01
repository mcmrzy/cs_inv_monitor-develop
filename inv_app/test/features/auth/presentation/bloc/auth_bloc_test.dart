import 'package:bloc_test/bloc_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/auth/domain/entities/user.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/test_data.dart';

void main() {
  late AuthBloc authBloc;
  late MockLoginUseCase mockLoginUseCase;
  late MockRegisterUseCase mockRegisterUseCase;
  late MockLogoutUseCase mockLogoutUseCase;
  late MockSendCodeUseCase mockSendCodeUseCase;
  late MockResetPasswordUseCase mockResetPasswordUseCase;
  late MockChangePasswordUseCase mockChangePasswordUseCase;
  late MockGetProfileUseCase mockGetProfileUseCase;
  late MockUpdateProfileUseCase mockUpdateProfileUseCase;
  late MockEmailLoginUseCase mockEmailLoginUseCase;
  late MockPhoneCodeLoginUseCase mockPhoneCodeLoginUseCase;
  late MockEmailCodeLoginUseCase mockEmailCodeLoginUseCase;
  late MockEmailRegisterUseCase mockEmailRegisterUseCase;
  late MockSendEmailCodeUseCase mockSendEmailCodeUseCase;
  late MockRefreshTokenUseCase mockRefreshTokenUseCase;
  late MockWechatLoginUseCase mockWechatLoginUseCase;
  late MockGoogleLoginUseCase mockGoogleLoginUseCase;
  late MockJVerifyLoginUseCase mockJVerifyLoginUseCase;
  late MockStorageService mockStorageService;
  late MockJPushService mockJPushService;

  setUp(() {
    mockLoginUseCase = MockLoginUseCase();
    mockRegisterUseCase = MockRegisterUseCase();
    mockLogoutUseCase = MockLogoutUseCase();
    mockSendCodeUseCase = MockSendCodeUseCase();
    mockResetPasswordUseCase = MockResetPasswordUseCase();
    mockChangePasswordUseCase = MockChangePasswordUseCase();
    mockGetProfileUseCase = MockGetProfileUseCase();
    mockUpdateProfileUseCase = MockUpdateProfileUseCase();
    mockEmailLoginUseCase = MockEmailLoginUseCase();
    mockPhoneCodeLoginUseCase = MockPhoneCodeLoginUseCase();
    mockEmailCodeLoginUseCase = MockEmailCodeLoginUseCase();
    mockEmailRegisterUseCase = MockEmailRegisterUseCase();
    mockSendEmailCodeUseCase = MockSendEmailCodeUseCase();
    mockRefreshTokenUseCase = MockRefreshTokenUseCase();
    mockWechatLoginUseCase = MockWechatLoginUseCase();
    mockGoogleLoginUseCase = MockGoogleLoginUseCase();
    mockJVerifyLoginUseCase = MockJVerifyLoginUseCase();
    mockStorageService = MockStorageService();
    mockJPushService = MockJPushService();

    // AuthBloc 依赖 isSystemAdmin/permissions 存储（新组织架构），提供默认 stub
    when(() => mockStorageService.getIsSystemAdmin())
        .thenAnswer((_) async => false);
    when(() => mockStorageService.saveIsSystemAdmin(any()))
        .thenAnswer((_) async {});
    when(() => mockStorageService.deleteIsSystemAdmin())
        .thenAnswer((_) async {});
    when(() => mockStorageService.getPermissions())
        .thenAnswer((_) async => <String>[]);
    when(() => mockStorageService.getActiveOrgId())
        .thenAnswer((_) async => null);
    when(() => mockStorageService.savePermissions(any()))
        .thenAnswer((_) async {});
    when(() => mockStorageService.deletePermissions())
        .thenAnswer((_) async {});
    // 用户资料本地缓存（冷启动展示 + 登出清除）
    when(() => mockStorageService.getString(any()))
        .thenAnswer((_) async => null);
    when(() => mockStorageService.saveString(any(), any()))
        .thenAnswer((_) async {});
    // 登出时清除组织上下文与电站缓存
    when(() => mockStorageService.deleteActiveOrgId())
        .thenAnswer((_) async {});
    when(() => mockStorageService.deleteActiveOrgName())
        .thenAnswer((_) async {});
    when(() => mockStorageService.deleteStationCache())
        .thenAnswer((_) async {});

    authBloc = AuthBloc(
      loginUseCase: mockLoginUseCase,
      registerUseCase: mockRegisterUseCase,
      logoutUseCase: mockLogoutUseCase,
      sendCodeUseCase: mockSendCodeUseCase,
      resetPasswordUseCase: mockResetPasswordUseCase,
      changePasswordUseCase: mockChangePasswordUseCase,
      getProfileUseCase: mockGetProfileUseCase,
      updateProfileUseCase: mockUpdateProfileUseCase,
      emailLoginUseCase: mockEmailLoginUseCase,
      phoneCodeLoginUseCase: mockPhoneCodeLoginUseCase,
      emailCodeLoginUseCase: mockEmailCodeLoginUseCase,
      emailRegisterUseCase: mockEmailRegisterUseCase,
      sendEmailCodeUseCase: mockSendEmailCodeUseCase,
      refreshTokenUseCase: mockRefreshTokenUseCase,
      wechatLoginUseCase: mockWechatLoginUseCase,
      googleLoginUseCase: mockGoogleLoginUseCase,
      jverifyLoginUseCase: mockJVerifyLoginUseCase,
      storageService: mockStorageService,
      jpushService: mockJPushService,
    );
  });

  tearDown(() {
    authBloc.close();
  });

  test(
    'initial state is AuthInitial',
    () {
      expect(authBloc.state, equals(AuthInitial()));
    },
  );

  // ---------------------------------------------------------------------------
  // AuthCheckRequested
  // ---------------------------------------------------------------------------
  group('AuthCheckRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] when token and userId exist',
      build: () {
        when(() => mockStorageService.getToken())
            .thenAnswer((_) async => 'token');
        when(() => mockStorageService.getUserId()).thenAnswer((_) async => 1);
        when(() => mockStorageService.getUserPhone())
            .thenAnswer((_) async => '13800138000');
        when(() => mockStorageService.getUserRole()).thenAnswer((_) async => 3);
        when(() => mockGetProfileUseCase()).thenAnswer(
          (_) async => right<Failure, User>(createTestUser()),
        );
        when(() => mockJPushService.bindUser(any())).thenAnswer((_) async {});
        return authBloc;
      },
      act: (bloc) => bloc.add(AuthCheckRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthUnauthenticated] when no token',
      build: () {
        when(() => mockStorageService.getToken()).thenAnswer((_) async => null);
        when(() => mockStorageService.getUserId())
            .thenAnswer((_) async => null);
        return authBloc;
      },
      act: (bloc) => bloc.add(AuthCheckRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthUnauthenticated>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // AuthLoginRequested
  // ---------------------------------------------------------------------------
  group('AuthLoginRequested', () {
    final loginResponse = createTestLoginResponse();

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] on successful login',
      build: () {
        when(
          () => mockLoginUseCase(
            account: any(named: 'account'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => right<Failure, LoginResponse>(loginResponse));
        when(() => mockStorageService.saveToken(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveRefreshToken(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveUserId(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveUserPhone(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveUserRole(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveRememberPassword(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveSavedPhone(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveSavedPassword(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.getToken())
            .thenAnswer((_) async => 'token');
        when(() => mockJPushService.bindUser(any())).thenAnswer((_) async {});
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const AuthLoginRequested(
          account: '13800138000',
          password: 'password123',
        ),
      ),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>(),
      ],
      verify: (_) {
        verify(() => mockStorageService.saveToken(loginResponse.token))
            .called(1);
        verify(() => mockStorageService.saveUserId(loginResponse.user.id))
            .called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] on login failure',
      build: () {
        when(
          () => mockLoginUseCase(
            account: any(named: 'account'),
            password: any(named: 'password'),
          ),
        ).thenAnswer(
          (_) async => left<Failure, LoginResponse>(createTestServerFailure()),
        );
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const AuthLoginRequested(
          account: '13800138000',
          password: 'wrong',
        ),
      ),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthError>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'saves credentials when rememberPassword is true',
      build: () {
        when(
          () => mockLoginUseCase(
            account: any(named: 'account'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => right<Failure, LoginResponse>(loginResponse));
        when(() => mockStorageService.saveToken(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveRefreshToken(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveUserId(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveUserPhone(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveUserRole(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveRememberPassword(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveSavedPhone(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveSavedPassword(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.getToken())
            .thenAnswer((_) async => 'token');
        when(() => mockJPushService.bindUser(any())).thenAnswer((_) async {});
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const AuthLoginRequested(
          account: '13800138000',
          password: 'password123',
          rememberPassword: true,
        ),
      ),
      verify: (_) {
        verify(() => mockStorageService.saveRememberPassword(true)).called(1);
        verify(() => mockStorageService.saveSavedPhone('13800138000'))
            .called(1);
        verify(() => mockStorageService.saveSavedPassword('password123'))
            .called(1);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // AuthLogoutRequested
  // ---------------------------------------------------------------------------
  group('AuthLogoutRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthUnauthenticated] and clears storage',
      build: () {
        when(() => mockLogoutUseCase()).thenAnswer(
          (_) async => right<Failure, void>(null),
        );
        when(() => mockStorageService.deleteToken()).thenAnswer((_) async {});
        when(() => mockStorageService.deleteRefreshToken())
            .thenAnswer((_) async {});
        when(() => mockStorageService.deleteUserId()).thenAnswer((_) async {});
        when(() => mockStorageService.deleteUserPhone())
            .thenAnswer((_) async {});
        when(() => mockStorageService.deleteUserRole())
            .thenAnswer((_) async {});
        when(() => mockJPushService.unbindUser()).thenAnswer((_) async {});
        return authBloc;
      },
      act: (bloc) => bloc.add(AuthLogoutRequested()),
      // guest 离网模式下状态可能已是 AuthUnauthenticated（Equatable 去重），
      // 实现先 emit 瞬时 AuthLoading 强制状态变化，确保登出跳转通知生效
      expect: () => [isA<AuthLoading>(), isA<AuthUnauthenticated>()],
      verify: (_) {
        verify(() => mockStorageService.deleteToken()).called(1);
        verify(() => mockStorageService.deleteRefreshToken()).called(1);
        verify(() => mockStorageService.deleteUserId()).called(1);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // AuthEmailLoginRequested
  // ---------------------------------------------------------------------------
  group('AuthEmailLoginRequested', () {
    final loginResponse = createTestLoginResponse();

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] on successful email login',
      build: () {
        when(
          () => mockEmailLoginUseCase(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => right<Failure, LoginResponse>(loginResponse));
        when(() => mockStorageService.saveToken(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveRefreshToken(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveUserId(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveUserPhone(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveUserRole(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveRememberPassword(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveSavedPhone(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveSavedPassword(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.getToken())
            .thenAnswer((_) async => 'token');
        when(() => mockJPushService.bindUser(any())).thenAnswer((_) async {});
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const AuthEmailLoginRequested(
          email: 'test@example.com',
          password: 'password123',
        ),
      ),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] on email login failure',
      build: () {
        when(
          () => mockEmailLoginUseCase(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer(
          (_) async => left<Failure, LoginResponse>(createTestServerFailure()),
        );
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const AuthEmailLoginRequested(
          email: 'test@example.com',
          password: 'wrong',
        ),
      ),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthError>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // AuthSendCodeRequested
  // ---------------------------------------------------------------------------
  group('AuthSendCodeRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthCodeSending, AuthCodeSent] on success',
      build: () {
        when(
          () => mockSendCodeUseCase(
            phone: any(named: 'phone'),
            type: any(named: 'type'),
          ),
        ).thenAnswer((_) async => right<Failure, void>(null));
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const AuthSendCodeRequested(
          phone: '13800138000',
          type: 'login',
          requestId: 'request-1',
        ),
      ),
      expect: () => [
        const AuthCodeSending(
          target: '13800138000',
          type: 'login',
          channel: 'phone',
          requestId: 'request-1',
        ),
        const AuthCodeSent(
          target: '13800138000',
          type: 'login',
          channel: 'phone',
          requestId: 'request-1',
        ),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthCodeSending, AuthError] on failure',
      build: () {
        when(
          () => mockSendCodeUseCase(
            phone: any(named: 'phone'),
            type: any(named: 'type'),
          ),
        ).thenAnswer(
          (_) async => left<Failure, void>(createTestServerFailure()),
        );
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const AuthSendCodeRequested(
          phone: '13800138000',
          type: 'login',
          requestId: 'request-1',
        ),
      ),
      expect: () => [
        const AuthCodeSending(
          target: '13800138000',
          type: 'login',
          channel: 'phone',
          requestId: 'request-1',
        ),
        isA<AuthCodeSendError>()
            .having((state) => state.target, 'target', '13800138000')
            .having((state) => state.type, 'type', 'login')
            .having((state) => state.channel, 'channel', 'phone')
            .having((state) => state.requestId, 'requestId', 'request-1'),
      ],
    );
  });

  group('AuthSendEmailCodeRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits request identity on success',
      build: () {
        when(
          () => mockSendEmailCodeUseCase(
            email: any(named: 'email'),
            type: any(named: 'type'),
          ),
        ).thenAnswer((_) async => right<Failure, void>(null));
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const AuthSendEmailCodeRequested(
          email: 'user@example.com',
          type: 'register',
          requestId: 'request-1',
        ),
      ),
      expect: () => const [
        AuthCodeSending(
          target: 'user@example.com',
          type: 'register',
          channel: 'email',
          requestId: 'request-1',
        ),
        AuthCodeSent(
          target: 'user@example.com',
          type: 'register',
          channel: 'email',
          requestId: 'request-1',
        ),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // AuthResetPasswordRequested
  // ---------------------------------------------------------------------------
  group('AuthResetPasswordRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthPasswordResetSuccess] on success',
      build: () {
        when(
          () => mockResetPasswordUseCase(
            phone: any(named: 'phone'),
            code: any(named: 'code'),
            newPassword: any(named: 'newPassword'),
          ),
        ).thenAnswer((_) async => right<Failure, void>(null));
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const AuthResetPasswordRequested(
          phone: '13800138000',
          code: '1234',
          newPassword: 'newpass123',
        ),
      ),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthPasswordResetSuccess>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // AuthChangePasswordRequested
  // ---------------------------------------------------------------------------
  group('AuthChangePasswordRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthPasswordChangedSuccess] on success',
      build: () {
        when(
          () => mockChangePasswordUseCase(
            oldPassword: any(named: 'oldPassword'),
            newPassword: any(named: 'newPassword'),
          ),
        ).thenAnswer((_) async => right<Failure, void>(null));
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const AuthChangePasswordRequested(
          oldPassword: 'oldpass',
          newPassword: 'newpass',
        ),
      ),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthPasswordChangedSuccess>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] on failure',
      build: () {
        when(
          () => mockChangePasswordUseCase(
            oldPassword: any(named: 'oldPassword'),
            newPassword: any(named: 'newPassword'),
          ),
        ).thenAnswer(
          (_) async => left<Failure, void>(
            createTestServerFailure('Old password incorrect'),
          ),
        );
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const AuthChangePasswordRequested(
          oldPassword: 'wrong_old',
          newPassword: 'newpass',
        ),
      ),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthError>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // AuthUpdateProfileRequested
  // ---------------------------------------------------------------------------
  group('AuthUpdateProfileRequested', () {
    User existingUser() => User(
          id: 1,
          phone: '13800138000',
          nickname: 'Old name',
          email: 'old@example.com',
          avatar: '/old-avatar.jpg',
          country: '中国',
          region: '广东省',
          status: 1,
          createdAt: DateTime(2026),
        );

    blocTest<AuthBloc, AuthState>(
      'emits correlated success and preserves explicit empty field updates',
      seed: () => AuthProfileUpdateSuccess(
        requestId: 'previous-profile-success',
        userId: 1,
        phone: '13800138000',
        user: existingUser(),
      ),
      build: () {
        when(
          () => mockUpdateProfileUseCase(
            nickname: any(named: 'nickname'),
            avatar: any(named: 'avatar'),
            email: any(named: 'email'),
            country: any(named: 'country'),
            regionName: any(named: 'regionName'),
            bio: any(named: 'bio'),
          ),
        ).thenAnswer((_) async => right<Failure, void>(null));
        // 模拟服务器读写延迟：保存后仍返回旧资料。
        when(() => mockGetProfileUseCase()).thenAnswer(
          (_) async => right<Failure, User>(existingUser()),
        );
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const AuthUpdateProfileRequested(
          requestId: 'profile-clear-1',
          nickname: '',
          avatar: '',
          email: '',
          country: '',
          regionName: '',
          bio: '',
        ),
      ),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthProfileUpdateSuccess>()
            .having((state) => state.requestId, 'requestId', 'profile-clear-1')
            .having((state) => state.user?.nickname, 'nickname', '')
            .having((state) => state.user?.avatar, 'avatar', '')
            .having((state) => state.user?.email, 'email', '')
            .having((state) => state.user?.country, 'country', '')
            .having((state) => state.user?.region, 'region', '')
            .having((state) => state.user?.bio, 'bio', ''),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits correlated profile error on failure',
      seed: () => AuthProfileUpdateSuccess(
        requestId: 'previous-profile-success',
        userId: 1,
        phone: '13800138000',
        user: existingUser(),
      ),
      build: () {
        when(
          () => mockUpdateProfileUseCase(
            nickname: any(named: 'nickname'),
            avatar: any(named: 'avatar'),
            email: any(named: 'email'),
            country: any(named: 'country'),
            regionName: any(named: 'regionName'),
            bio: any(named: 'bio'),
          ),
        ).thenAnswer(
          (_) async => left<Failure, void>(
            createTestServerFailure('profile failed'),
          ),
        );
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const AuthUpdateProfileRequested(
          requestId: 'profile-fail-1',
          nickname: 'New name',
        ),
      ),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthProfileUpdateError>()
            .having((state) => state.requestId, 'requestId', 'profile-fail-1')
            .having((state) => state.message, 'message', 'profile failed'),
        isA<AuthAuthenticated>()
            .having(
              (state) => state.runtimeType,
              'runtimeType',
              AuthAuthenticated,
            )
            .having((state) => state.user?.nickname, 'nickname', 'Old name'),
      ],
    );
  });

  group('AuthState listener isolation', () {
    test('only profile update terminals are classified as profile-only states', () {
      const profileSuccess = AuthProfileUpdateSuccess(
        requestId: 'profile-success',
        userId: 1,
        phone: '13800138000',
      );
      const profileError = AuthProfileUpdateError(
        message: 'profile failed',
        requestId: 'profile-error',
      );

      expect(profileSuccess.isProfileUpdateTerminal, isTrue);
      expect(profileError.isProfileUpdateTerminal, isTrue);
      expect(
        const AuthAuthenticated(userId: 1, phone: '13800138000')
            .isProfileUpdateTerminal,
        isFalse,
      );
      expect(
        const AuthError(message: 'login failed').isProfileUpdateTerminal,
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // AuthTokenRefreshed
  // ---------------------------------------------------------------------------
  group('AuthTokenRefreshed', () {
    blocTest<AuthBloc, AuthState>(
      'saves new token without emitting states',
      build: () {
        when(() => mockStorageService.saveToken(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveRefreshToken(any()))
            .thenAnswer((_) async {});
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const AuthTokenRefreshed(
          token: 'new_token',
          refreshToken: 'new_refresh',
        ),
      ),
      expect: () => <AuthState>[],
      verify: (_) {
        verify(() => mockStorageService.saveToken('new_token')).called(1);
        verify(() => mockStorageService.saveRefreshToken('new_refresh'))
            .called(1);
      },
    );
  });
}
