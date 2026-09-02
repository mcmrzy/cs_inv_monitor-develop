import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/auth/presentation/widgets/register_form.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/pump_app.dart';

class _FakeAuthEvent extends Fake implements AuthEvent {}

void main() {
  late MockAuthBloc authBloc;
  late StreamController<AuthState> authStates;
  late List<AuthEvent> addedEvents;

  setUpAll(() {
    registerFallbackValue(_FakeAuthEvent());
  });

  setUp(() {
    authBloc = MockAuthBloc();
    authStates = StreamController<AuthState>.broadcast();
    addedEvents = <AuthEvent>[];
    whenListen(
      authBloc,
      authStates.stream,
      initialState: AuthInitial(),
    );
    when(() => authBloc.add(any())).thenAnswer((invocation) {
      addedEvents.add(invocation.positionalArguments.single as AuthEvent);
    });
  });

  tearDown(() async {
    await authStates.close();
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    required Future<String?> Function(BuildContext context) captchaPresenter,
  }) async {
    await pumpApp(
      tester,
      SingleChildScrollView(
        child: RegisterForm(captchaPresenter: captchaPresenter),
      ),
      authBloc: authBloc,
      useScaffold: true,
    );
    await tester.enterText(
      find.byType(TextFormField).first,
      '13800138000',
    );
    await tester.ensureVisible(find.byType(ElevatedButton));
    await tester.pump();
  }

  AuthSendCodeRequested latestPhoneCodeRequest() {
    return addedEvents.whereType<AuthSendCodeRequested>().last;
  }

  testWidgets('滑块验证未完成时快速连点只发起一次验证', (tester) async {
    final captchaResult = Completer<String?>();
    var captchaCalls = 0;
    await pumpForm(
      tester,
      captchaPresenter: (_) {
        captchaCalls++;
        return captchaResult.future;
      },
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(captchaCalls, 1);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    verifyNever(() => authBloc.add(any()));

    captchaResult.complete(null);
    await tester.pump();

    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('请求成功前保持禁用且失败后允许重试', (tester) async {
    await pumpForm(
      tester,
      captchaPresenter: (_) async => 'captcha-token',
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    final event = verify(() => authBloc.add(captureAny())).captured.single
        as AuthSendCodeRequested;
    expect(event.phone, '13800138000');
    expect(event.type, 'register');
    expect(event.captchaToken, 'captcha-token');

    authStates.add(
      AuthCodeSendError(
        message: 'send failed',
        target: '13800138000',
        type: 'register',
        channel: 'phone',
        requestId: event.requestId,
      ),
    );
    await tester.pump();

    expect(find.text('60s'), findsNothing);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('滑块验证异常后恢复发送按钮', (tester) async {
    await pumpForm(
      tester,
      captchaPresenter: (_) => Future<String?>.error(Exception('failed')),
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
    verifyNever(() => authBloc.add(any()));
  });

  testWidgets('滑块验证期间切换国家不会向错误通道发送旧账号', (tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('ListTile')) return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    final captchaResult = Completer<String?>();
    await pumpForm(
      tester,
      captchaPresenter: (_) => captchaResult.future,
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.tap(find.textContaining('(CN)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField).last, 'US');
    await tester.pump();
    await tester.tap(find.text('美国 (US)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    captchaResult.complete('late-token');
    await tester.pump();

    verifyNever(() => authBloc.add(any()));
    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('仅本表单发码成功后启动倒计时', (tester) async {
    await pumpForm(
      tester,
      captchaPresenter: (_) async => 'captcha-token',
    );

    authStates.add(
      const AuthCodeSent(
        target: '13800138000',
        type: 'register',
        channel: 'phone',
        requestId: 'external-request',
      ),
    );
    await tester.pump();

    expect(find.text('60s'), findsNothing);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    final request = latestPhoneCodeRequest();
    authStates.add(
      AuthCodeSent(
        target: '13800138000',
        type: 'register',
        channel: 'phone',
        requestId: request.requestId,
      ),
    );
    await tester.pump();

    expect(find.text('60s'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('59s'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('发码事件派发后修改手机号不会给新号码启动倒计时', (tester) async {
    await pumpForm(
      tester,
      captchaPresenter: (_) async => 'captcha-token',
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    final request = latestPhoneCodeRequest();
    final registerButton = tester.widget<InkWell>(
      find.byKey(const Key('register-submit-button')),
    );
    expect(registerButton.onTap, isNull);

    await tester.enterText(find.byType(TextFormField).first, '13900139000');
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
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('忽略其他认证流程的发码成功状态', (tester) async {
    await pumpForm(
      tester,
      captchaPresenter: (_) async => 'captcha-token',
    );
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    authStates.add(
      const AuthCodeSent(
        target: '13800138000',
        type: 'login',
        channel: 'phone',
        requestId: 'external-login-request',
      ),
    );
    await tester.pump();

    expect(find.text('60s'), findsNothing);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
  });

  testWidgets('相同目标的旧请求结果不会完成当前请求', (tester) async {
    await pumpForm(
      tester,
      captchaPresenter: (_) async => 'captcha-token',
    );
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    final currentRequest = latestPhoneCodeRequest();

    authStates.add(
      const AuthCodeSent(
        target: '13800138000',
        type: 'register',
        channel: 'phone',
        requestId: 'older-request',
      ),
    );
    await tester.pump();
    expect(find.text('60s'), findsNothing);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );

    authStates.add(
      const AuthCodeSendError(
        message: 'old request failed',
        target: '13800138000',
        type: 'register',
        channel: 'phone',
        requestId: 'older-request',
      ),
    );
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );

    authStates.add(
      AuthCodeSent(
        target: currentRequest.phone,
        type: currentRequest.type,
        channel: 'phone',
        requestId: currentRequest.requestId,
      ),
    );
    await tester.pump();

    expect(find.text('60s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('注册按钮快速连点只派发一次注册事件', (tester) async {
    await pumpApp(
      tester,
      SingleChildScrollView(
        child: RegisterForm(captchaPresenter: (_) async => null),
      ),
      authBloc: authBloc,
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '13800138000');
    await tester.enterText(fields.at(1), '123456');
    await tester.enterText(fields.at(2), 'password123');
    await tester.enterText(fields.at(3), 'password123');
    final registerButton = find.byKey(const Key('register-submit-button'));
    await tester.ensureVisible(registerButton);
    await tester.pump();

    await tester.tap(registerButton);
    await tester.tap(registerButton);

    final captured = verify(() => authBloc.add(captureAny())).captured;
    expect(captured, hasLength(1));
    expect(captured.single, isA<AuthRegisterRequested>());
  });

  testWidgets('注册失败后恢复提交门禁并可再次提交', (tester) async {
    await pumpApp(
      tester,
      SingleChildScrollView(
        child: RegisterForm(captchaPresenter: (_) async => null),
      ),
      authBloc: authBloc,
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '13800138000');
    await tester.enterText(fields.at(1), '123456');
    await tester.enterText(fields.at(2), 'password123');
    await tester.enterText(fields.at(3), 'password123');
    final registerButton = find.byKey(const Key('register-submit-button'));
    await tester.ensureVisible(registerButton);
    await tester.pump();

    await tester.tap(registerButton);
    await tester.pump();
    expect(
      tester.widget<InkWell>(registerButton).onTap,
      isNull,
    );
    expect(addedEvents.whereType<AuthRegisterRequested>(), hasLength(1));

    authStates.add(const AuthError(message: 'register failed'));
    await tester.pump();
    expect(
      tester.widget<InkWell>(registerButton).onTap,
      isNotNull,
    );

    await tester.tap(registerButton);
    expect(addedEvents.whereType<AuthRegisterRequested>(), hasLength(2));
  });

  testWidgets('60 秒倒计时结束时立即恢复发送', (tester) async {
    await pumpForm(
      tester,
      captchaPresenter: (_) async => 'captcha-token',
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    final request = latestPhoneCodeRequest();
    authStates.add(
      AuthCodeSent(
        target: '13800138000',
        type: 'register',
        channel: 'phone',
        requestId: request.requestId,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 60));

    expect(find.text('0s'), findsNothing);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('倒计时期间修改手机号会清空旧验证码并恢复发送', (tester) async {
    await pumpForm(
      tester,
      captchaPresenter: (_) async => 'captcha-token',
    );
    final fields = find.byType(TextFormField);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    final request = latestPhoneCodeRequest();
    authStates.add(
      AuthCodeSent(
        target: '13800138000',
        type: 'register',
        channel: 'phone',
        requestId: request.requestId,
      ),
    );
    await tester.pump();
    await tester.enterText(fields.at(1), '123456');

    await tester.enterText(fields.at(0), '13900139000');
    await tester.pump();

    expect(find.text('60s'), findsNothing);
    expect(tester.widget<TextFormField>(fields.at(1)).controller!.text, isEmpty);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('等待滑块验证时销毁组件不会访问已销毁状态', (tester) async {
    final captchaResult = Completer<String?>();
    await pumpForm(
      tester,
      captchaPresenter: (_) => captchaResult.future,
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    captchaResult.complete('late-token');
    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
    verifyNever(() => authBloc.add(any()));
  });

  testWidgets('倒计时期间销毁组件会取消 Timer', (tester) async {
    await pumpForm(
      tester,
      captchaPresenter: (_) async => 'captcha-token',
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    final request = latestPhoneCodeRequest();
    authStates.add(
      AuthCodeSent(
        target: '13800138000',
        type: 'register',
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
}
