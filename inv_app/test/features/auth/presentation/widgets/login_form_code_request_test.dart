import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/core/services/jverify_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/auth/presentation/widgets/login_form.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/pump_app.dart';

class _MockAuthBloc extends Mock implements AuthBloc {}

class _FakeAuthEvent extends Fake implements AuthEvent {}

void main() {
  late _MockAuthBloc authBloc;
  late MockStorageService storageService;
  late MockJVerifyService jverifyService;
  late StreamController<AuthState> authStates;

  setUpAll(() {
    registerFallbackValue(_FakeAuthEvent());
  });

  setUp(() async {
    await getIt.reset();
    authBloc = _MockAuthBloc();
    storageService = MockStorageService();
    jverifyService = MockJVerifyService();
    authStates = StreamController<AuthState>.broadcast();

    when(() => authBloc.state).thenReturn(AuthInitial());
    when(() => authBloc.stream).thenAnswer((_) => authStates.stream);
    when(() => storageService.getRememberPassword())
        .thenAnswer((_) async => false);
    when(() => jverifyService.isInitSuccess()).thenAnswer((_) async => true);
    when(() => jverifyService.checkVerifyEnable())
        .thenAnswer((_) async => false);

    getIt.registerSingleton<StorageService>(storageService);
    getIt.registerSingleton<JVerifyService>(jverifyService);
  });

  tearDown(() async {
    await authStates.close();
    await getIt.reset();
  });

  Future<void> openCodeLogin(WidgetTester tester, LoginForm form) async {
    await pumpApp(tester, form, authBloc: authBloc, useScaffold: true);
    await tester.tap(find.text('验证码登录'));
    await tester.pump();
  }

  Finder fieldWithKeyboard(TextInputType keyboardType) {
    return find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.keyboardType == keyboardType,
    );
  }

  AuthSendCodeRequested capturePhoneCodeRequest() {
    final captured = verify(() => authBloc.add(captureAny())).captured;
    expect(captured, hasLength(1));
    expect(captured.single, isA<AuthSendCodeRequested>());
    return captured.single as AuthSendCodeRequested;
  }

  AuthSendEmailCodeRequested captureEmailCodeRequest() {
    final captured = verify(() => authBloc.add(captureAny())).captured;
    expect(captured, hasLength(1));
    expect(captured.single, isA<AuthSendEmailCodeRequested>());
    return captured.single as AuthSendEmailCodeRequested;
  }

  testWidgets('手机验证码快速连点只打开一次验证并保留 login 发码类型',
      (tester) async {
    final captcha = Completer<String?>();
    var captchaLaunches = 0;
    await openCodeLogin(
      tester,
      LoginForm(
        captchaLauncher: (_) {
          captchaLaunches++;
          return captcha.future;
        },
      ),
    );
    await tester.enterText(fieldWithKeyboard(TextInputType.phone), '13800138000');

    final sendButton = find.widgetWithText(ElevatedButton, '发送');
    await tester.tap(sendButton);
    await tester.tap(sendButton);

    expect(captchaLaunches, 1);
    captcha.complete('phone-captcha-token');
    await tester.pump();

    final request = capturePhoneCodeRequest();
    expect(request.phone, '13800138000');
    expect(request.type, 'login');
    expect(request.captchaToken, 'phone-captcha-token');
    expect(request.requestId, isNotEmpty);
  });

  testWidgets('邮箱验证码快速连点只派发一次邮箱 login 发码事件', (tester) async {
    final captcha = Completer<String?>();
    var captchaLaunches = 0;
    await openCodeLogin(
      tester,
      LoginForm(
        captchaLauncher: (_) {
          captchaLaunches++;
          return captcha.future;
        },
      ),
    );
    await tester.tap(find.text('邮箱验证码'));
    await tester.pump();
    await tester.enterText(
      fieldWithKeyboard(TextInputType.emailAddress),
      'user@example.com',
    );

    final sendButton = find.widgetWithText(ElevatedButton, '发送');
    await tester.tap(sendButton);
    await tester.tap(sendButton);

    expect(captchaLaunches, 1);
    captcha.complete('email-captcha-token');
    await tester.pump();

    final request = captureEmailCodeRequest();
    expect(request.email, 'user@example.com');
    expect(request.type, 'login');
    expect(request.captchaToken, 'email-captcha-token');
    expect(request.requestId, isNotEmpty);
  });

  testWidgets('取消滑块后立即解锁并允许重新发送', (tester) async {
    var captchaLaunches = 0;
    await openCodeLogin(
      tester,
      LoginForm(
        captchaLauncher: (_) async {
          captchaLaunches++;
          return captchaLaunches == 1 ? null : 'retry-token';
        },
      ),
    );
    await tester.enterText(fieldWithKeyboard(TextInputType.phone), '13800138000');

    await tester.tap(find.widgetWithText(ElevatedButton, '发送'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, '发送'));
    await tester.pump();

    expect(captchaLaunches, 2);
    final request = capturePhoneCodeRequest();
    expect(request.phone, '13800138000');
    expect(request.type, 'login');
    expect(request.captchaToken, 'retry-token');
    expect(request.requestId, isNotEmpty);
  });

  testWidgets('滑块验证异常后恢复发送按钮', (tester) async {
    await openCodeLogin(
      tester,
      LoginForm(
        captchaLauncher: (_) => Future<String?>.error(Exception('failed')),
      ),
    );
    await tester.enterText(fieldWithKeyboard(TextInputType.phone), '13800138000');

    await tester.tap(find.widgetWithText(ElevatedButton, '发送'));
    await tester.pump();

    final sendButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '发送'),
    );
    expect(sendButton.onPressed, isNotNull);
    verifyNever(() => authBloc.add(any()));
  });

  testWidgets('滑块验证期间切换验证码通道不会发送旧通道验证码', (tester) async {
    final captcha = Completer<String?>();
    await openCodeLogin(
      tester,
      LoginForm(captchaLauncher: (_) => captcha.future),
    );
    await tester.enterText(fieldWithKeyboard(TextInputType.phone), '13800138000');

    await tester.tap(find.widgetWithText(ElevatedButton, '发送'));
    await tester.tap(find.text('邮箱验证码'));
    await tester.pump();
    captcha.complete('late-token');
    await tester.pump();

    verifyNever(() => authBloc.add(any()));
    final sendButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '发送'),
    );
    expect(sendButton.onPressed, isNotNull);
  });

  testWidgets('发码事件派发后修改目标不会给新目标启动倒计时', (tester) async {
    await openCodeLogin(
      tester,
      LoginForm(captchaLauncher: (_) async => 'token'),
    );
    final phoneField = fieldWithKeyboard(TextInputType.phone);
    await tester.enterText(phoneField, '13800138000');
    await tester.tap(find.widgetWithText(ElevatedButton, '发送'));
    await tester.pump();
    final request = capturePhoneCodeRequest();

    final loginButton = tester.widget<InkWell>(
      find.byKey(const Key('login-submit-button')),
    );
    expect(loginButton.onTap, isNull);

    await tester.enterText(phoneField, '13900139000');
    authStates.add(
      AuthCodeSent(
        target: '13800138000',
        type: 'login',
        channel: 'phone',
        requestId: request.requestId,
      ),
    );
    await tester.pump();

    expect(find.text('60s'), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, '发送'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('忽略其他认证流程的发码成功状态', (tester) async {
    await openCodeLogin(
      tester,
      LoginForm(captchaLauncher: (_) async => 'token'),
    );
    await tester.enterText(fieldWithKeyboard(TextInputType.phone), '13800138000');
    await tester.tap(find.widgetWithText(ElevatedButton, '发送'));
    await tester.pump();
    final request = capturePhoneCodeRequest();

    authStates.add(
      AuthCodeSent(
        target: '13800138000',
        type: 'register',
        channel: 'phone',
        requestId: request.requestId,
      ),
    );
    await tester.pump();

    expect(find.text('60s'), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const Key('login-send-code-button')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('相同类型通道目标的旧 requestId 结果不得完成当前请求',
      (tester) async {
    await openCodeLogin(
      tester,
      LoginForm(captchaLauncher: (_) async => 'token'),
    );
    await tester.enterText(
      fieldWithKeyboard(TextInputType.phone),
      '13800138000',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, '发送'));
    await tester.pump();
    final request = capturePhoneCodeRequest();
    final staleRequestId = '${request.requestId}-stale';

    authStates.add(
      AuthCodeSent(
        target: request.phone,
        type: request.type,
        channel: 'phone',
        requestId: staleRequestId,
      ),
    );
    await tester.pump();
    authStates.add(
      AuthCodeSendError(
        message: 'stale request failed',
        target: request.phone,
        type: request.type,
        channel: 'phone',
        requestId: staleRequestId,
      ),
    );
    await tester.pump();

    expect(find.text('60s'), findsNothing);
    expect(find.text('stale request failed'), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const Key('login-send-code-button')),
          )
          .onPressed,
      isNull,
    );

    authStates.add(
      AuthCodeSent(
        target: request.phone,
        type: request.type,
        channel: 'phone',
        requestId: request.requestId,
      ),
    );
    await tester.pump();

    expect(find.text('60s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('修改目标后旧请求失败不会显示在新目标上', (tester) async {
    await openCodeLogin(
      tester,
      LoginForm(captchaLauncher: (_) async => 'token'),
    );
    final phoneField = fieldWithKeyboard(TextInputType.phone);
    await tester.enterText(phoneField, '13800138000');
    await tester.tap(find.widgetWithText(ElevatedButton, '发送'));
    await tester.pump();
    final request = capturePhoneCodeRequest();

    await tester.enterText(phoneField, '13900139000');
    await tester.pump();
    authStates.add(
      AuthCodeSendError(
        message: 'old request failed',
        target: request.phone,
        type: request.type,
        channel: 'phone',
        requestId: request.requestId,
      ),
    );
    await tester.pump();

    expect(find.text('old request failed'), findsNothing);
    expect(find.text('60s'), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, '发送'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('登录按钮快速连点只派发一次登录事件', (tester) async {
    await pumpApp(tester, const LoginForm(), authBloc: authBloc);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '13800138000');
    await tester.enterText(fields.at(1), 'password123');
    final loginButton = find.byKey(const Key('login-submit-button'));

    await tester.tap(loginButton);
    await tester.tap(loginButton);

    final captured = verify(() => authBloc.add(captureAny())).captured;
    expect(captured, hasLength(1));
    expect(captured.single, isA<AuthLoginRequested>());
  });

  testWidgets('滑块等待期间关闭表单不会派发事件或触发异步 setState',
      (tester) async {
    final captcha = Completer<String?>();
    await openCodeLogin(
      tester,
      LoginForm(captchaLauncher: (_) => captcha.future),
    );
    await tester.enterText(fieldWithKeyboard(TextInputType.phone), '13800138000');
    await tester.tap(find.widgetWithText(ElevatedButton, '发送'));

    await tester.pumpWidget(const SizedBox.shrink());
    captcha.complete('late-token');
    await tester.pump();

    verifyNever(() => authBloc.add(any()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('发码成功后的倒计时在表单关闭时安全取消', (tester) async {
    await openCodeLogin(
      tester,
      LoginForm(captchaLauncher: (_) async => 'token'),
    );
    await tester.enterText(fieldWithKeyboard(TextInputType.phone), '13800138000');
    await tester.tap(find.widgetWithText(ElevatedButton, '发送'));
    await tester.pump();
    final request = capturePhoneCodeRequest();

    authStates.add(
      AuthCodeSent(
        target: '13800138000',
        type: 'login',
        channel: 'phone',
        requestId: request.requestId,
      ),
    );
    await tester.pump();
    expect(find.text('60s'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('倒计时期间修改目标会清空旧验证码并恢复发送', (tester) async {
    await openCodeLogin(
      tester,
      LoginForm(captchaLauncher: (_) async => 'token'),
    );
    final phoneField = fieldWithKeyboard(TextInputType.phone);
    final codeField = fieldWithKeyboard(TextInputType.number);
    await tester.enterText(phoneField, '13800138000');
    await tester.tap(find.widgetWithText(ElevatedButton, '发送'));
    await tester.pump();
    final request = capturePhoneCodeRequest();
    authStates.add(
      AuthCodeSent(
        target: '13800138000',
        type: 'login',
        channel: 'phone',
        requestId: request.requestId,
      ),
    );
    await tester.pump();
    await tester.enterText(codeField, '123456');

    await tester.enterText(phoneField, '13900139000');
    await tester.pump();

    expect(find.text('60s'), findsNothing);
    expect(tester.widget<TextField>(codeField).controller!.text, isEmpty);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, '发送'),
          )
          .onPressed,
      isNotNull,
    );
  });
}
