import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
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
  late MockEmailRegisterUseCase mockEmailRegisterUseCase;
  late MockSendEmailCodeUseCase mockSendEmailCodeUseCase;
  late MockRefreshTokenUseCase mockRefreshTokenUseCase;
  late MockWechatLoginUseCase mockWechatLoginUseCase;
  late MockGoogleLoginUseCase mockGoogleLoginUseCase;
  late MockStorageService mockStorageService;
  late MockMQTTService mockMQTTService;
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
    mockEmailRegisterUseCase = MockEmailRegisterUseCase();
    mockSendEmailCodeUseCase = MockSendEmailCodeUseCase();
    mockRefreshTokenUseCase = MockRefreshTokenUseCase();
    mockWechatLoginUseCase = MockWechatLoginUseCase();
    mockGoogleLoginUseCase = MockGoogleLoginUseCase();
    mockStorageService = MockStorageService();
    mockMQTTService = MockMQTTService();
    mockJPushService = MockJPushService();

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
      emailRegisterUseCase: mockEmailRegisterUseCase,
      sendEmailCodeUseCase: mockSendEmailCodeUseCase,
      refreshTokenUseCase: mockRefreshTokenUseCase,
      wechatLoginUseCase: mockWechatLoginUseCase,
      googleLoginUseCase: mockGoogleLoginUseCase,
      storageService: mockStorageService,
      mqttService: mockMQTTService,
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
  },);

  // ---------------------------------------------------------------------------
  // AuthCheckRequested
  // ---------------------------------------------------------------------------
  group('AuthCheckRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] when token and userId exist',
      build: () {
        when(() => mockStorageService.getToken()).thenAnswer((_) async => 'token');
        when(() => mockStorageService.getUserId()).thenAnswer((_) async => 1);
        when(() => mockStorageService.getUserPhone()).thenAnswer((_) async => '13800138000');
        when(() => mockStorageService.getUserRole()).thenAnswer((_) async => 3);
        when(() => mockGetProfileUseCase()).thenAnswer(
          (_) async => right<Failure, User>(createTestUser()),
        );
        when(() => mockMQTTService.connect(
          any(),
          username: any(named: 'username'),
          password: any(named: 'password'),
        ),).thenAnswer((_) async {});
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
        when(() => mockStorageService.getUserId()).thenAnswer((_) async => null);
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
        when(() => mockLoginUseCase(
          account: any(named: 'account'),
          password: any(named: 'password'),
        ),).thenAnswer((_) async => right<Failure, LoginResponse>(loginResponse));
        when(() => mockStorageService.saveToken(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveRefreshToken(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveUserId(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveUserPhone(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveUserRole(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveRememberPassword(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveSavedPhone(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveSavedPassword(any())).thenAnswer((_) async {});
        when(() => mockStorageService.getToken()).thenAnswer((_) async => 'token');
        when(() => mockMQTTService.connect(
          any(),
          username: any(named: 'username'),
          password: any(named: 'password'),
        ),).thenAnswer((_) async {});
        when(() => mockJPushService.bindUser(any())).thenAnswer((_) async {});
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthLoginRequested(
        account: '13800138000',
        password: 'password123',
      ),),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>(),
      ],
      verify: (_) {
        verify(() => mockStorageService.saveToken(loginResponse.token)).called(1);
        verify(() => mockStorageService.saveUserId(loginResponse.user.id)).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] on login failure',
      build: () {
        when(() => mockLoginUseCase(
          account: any(named: 'account'),
          password: any(named: 'password'),
        ),).thenAnswer((_) async => left<Failure, LoginResponse>(createTestServerFailure()));
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthLoginRequested(
        account: '13800138000',
        password: 'wrong',
      ),),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthError>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'saves credentials when rememberPassword is true',
      build: () {
        when(() => mockLoginUseCase(
          account: any(named: 'account'),
          password: any(named: 'password'),
        ),).thenAnswer((_) async => right<Failure, LoginResponse>(loginResponse));
        when(() => mockStorageService.saveToken(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveRefreshToken(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveUserId(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveUserPhone(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveUserRole(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveRememberPassword(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveSavedPhone(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveSavedPassword(any())).thenAnswer((_) async {});
        when(() => mockStorageService.getToken()).thenAnswer((_) async => 'token');
        when(() => mockMQTTService.connect(
          any(),
          username: any(named: 'username'),
          password: any(named: 'password'),
        ),).thenAnswer((_) async {});
        when(() => mockJPushService.bindUser(any())).thenAnswer((_) async {});
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthLoginRequested(
        account: '13800138000',
        password: 'password123',
        rememberPassword: true,
      ),),
      verify: (_) {
        verify(() => mockStorageService.saveRememberPassword(true)).called(1);
        verify(() => mockStorageService.saveSavedPhone('13800138000')).called(1);
        verify(() => mockStorageService.saveSavedPassword('password123')).called(1);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // AuthLogoutRequested
  // ---------------------------------------------------------------------------
  group('AuthLogoutRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthUnauthenticated] and clears storage',
      build: () {
        when(() => mockLogoutUseCase()).thenAnswer(
          (_) async => right<Failure, void>(null),
        );
        when(() => mockStorageService.deleteToken()).thenAnswer((_) async {});
        when(() => mockStorageService.deleteRefreshToken()).thenAnswer((_) async {});
        when(() => mockStorageService.deleteUserId()).thenAnswer((_) async {});
        when(() => mockStorageService.deleteUserPhone()).thenAnswer((_) async {});
        when(() => mockStorageService.deleteUserRole()).thenAnswer((_) async {});
        when(() => mockMQTTService.disconnect()).thenAnswer((_) async {});
        when(() => mockJPushService.unbindUser()).thenAnswer((_) async {});
        return authBloc;
      },
      act: (bloc) => bloc.add(AuthLogoutRequested()),
      expect: () => [isA<AuthUnauthenticated>()],
      verify: (_) {
        verify(() => mockStorageService.deleteToken()).called(1);
        verify(() => mockStorageService.deleteRefreshToken()).called(1);
        verify(() => mockStorageService.deleteUserId()).called(1);
        verify(() => mockMQTTService.disconnect()).called(1);
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
        when(() => mockEmailLoginUseCase(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),).thenAnswer((_) async => right<Failure, LoginResponse>(loginResponse));
        when(() => mockStorageService.saveToken(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveRefreshToken(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveUserId(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveUserPhone(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveUserRole(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveRememberPassword(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveSavedPhone(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveSavedPassword(any())).thenAnswer((_) async {});
        when(() => mockStorageService.getToken()).thenAnswer((_) async => 'token');
        when(() => mockMQTTService.connect(
          any(),
          username: any(named: 'username'),
          password: any(named: 'password'),
        ),).thenAnswer((_) async {});
        when(() => mockJPushService.bindUser(any())).thenAnswer((_) async {});
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthEmailLoginRequested(
        email: 'test@example.com',
        password: 'password123',
      ),),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] on email login failure',
      build: () {
        when(() => mockEmailLoginUseCase(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),).thenAnswer((_) async => left<Failure, LoginResponse>(createTestServerFailure()));
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthEmailLoginRequested(
        email: 'test@example.com',
        password: 'wrong',
      ),),
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
        when(() => mockSendCodeUseCase(
          phone: any(named: 'phone'),
          type: any(named: 'type'),
        ),).thenAnswer((_) async => right<Failure, void>(null));
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthSendCodeRequested(
        phone: '13800138000',
        type: 'login',
      ),),
      expect: () => [
        isA<AuthCodeSending>(),
        isA<AuthCodeSent>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthCodeSending, AuthError] on failure',
      build: () {
        when(() => mockSendCodeUseCase(
          phone: any(named: 'phone'),
          type: any(named: 'type'),
        ),).thenAnswer((_) async => left<Failure, void>(createTestServerFailure()));
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthSendCodeRequested(
        phone: '13800138000',
        type: 'login',
      ),),
      expect: () => [
        isA<AuthCodeSending>(),
        isA<AuthError>(),
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
        when(() => mockResetPasswordUseCase(
          phone: any(named: 'phone'),
          code: any(named: 'code'),
          newPassword: any(named: 'newPassword'),
        ),).thenAnswer((_) async => right<Failure, void>(null));
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthResetPasswordRequested(
        phone: '13800138000',
        code: '1234',
        newPassword: 'newpass123',
      ),),
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
        when(() => mockChangePasswordUseCase(
          oldPassword: any(named: 'oldPassword'),
          newPassword: any(named: 'newPassword'),
        ),).thenAnswer((_) async => right<Failure, void>(null));
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthChangePasswordRequested(
        oldPassword: 'oldpass',
        newPassword: 'newpass',
      ),),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthPasswordChangedSuccess>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] on failure',
      build: () {
        when(() => mockChangePasswordUseCase(
          oldPassword: any(named: 'oldPassword'),
          newPassword: any(named: 'newPassword'),
        ),).thenAnswer((_) async => left<Failure, void>(createTestServerFailure('Old password incorrect')));
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthChangePasswordRequested(
        oldPassword: 'wrong_old',
        newPassword: 'newpass',
      ),),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthError>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // AuthTokenRefreshed
  // ---------------------------------------------------------------------------
  group('AuthTokenRefreshed', () {
    blocTest<AuthBloc, AuthState>(
      'saves new token without emitting states',
      build: () {
        when(() => mockStorageService.saveToken(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveRefreshToken(any())).thenAnswer((_) async {});
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthTokenRefreshed(
        token: 'new_token',
        refreshToken: 'new_refresh',
      ),),
      expect: () => <AuthState>[],
      verify: (_) {
        verify(() => mockStorageService.saveToken('new_token')).called(1);
        verify(() => mockStorageService.saveRefreshToken('new_refresh')).called(1);
      },
    );
  });
}
