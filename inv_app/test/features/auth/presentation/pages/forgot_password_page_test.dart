import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/pump_app.dart';

class _FakeAuthEvent extends Fake implements AuthEvent {}

void main() {
  late MockAuthBloc authBloc;
  late StreamController<AuthState> states;
  late List<AuthEvent> addedEvents;

  setUpAll(() {
    registerFallbackValue(_FakeAuthEvent());
  });

  setUp(() {
    authBloc = MockAuthBloc();
    states = StreamController<AuthState>.broadcast();
    addedEvents = <AuthEvent>[];
    when(() => authBloc.state).thenReturn(AuthInitial());
    when(() => authBloc.stream).thenAnswer((_) => states.stream);
    when(() => authBloc.add(any())).thenAnswer((invocation) {
      addedEvents.add(invocation.positionalArguments.single as AuthEvent);
    });
  });

  tearDown(() async {
    await states.close();
  });

  Future<void> pumpPage(
    WidgetTester tester,
    Future<String?> Function(BuildContext) captchaLauncher,
  ) {
    return pumpApp(
      tester,
      ForgotPasswordPage(captchaLauncher: captchaLauncher),
      authBloc: authBloc,
    );
  }

  Finder sendButton() =>
      find.byKey(const Key('forgot-password-send-code-button'));

  Finder resetButton() =>
      find.byKey(const Key('forgot-password-reset-button'));

  Future<void> enterPhone(WidgetTester tester) {
    return tester.enterText(
      find.byType(TextFormField).first,
      '13800138000',
    );
  }

  AuthSendCodeRequested latestCodeRequest() {
    return addedEvents.whereType<AuthSendCodeRequested>().last;
  }

  testWidgets('验证码弹窗未结束时快速点击只发起一次验证', (tester) async {
    final captcha = Completer<String?>();
    var launchCount = 0;
    await pumpPage(tester, (_) {
      launchCount++;
      return captcha.future;
    });
    await enterPhone(tester);

    await tester.tap(sendButton());
    await tester.tap(sendButton());

    expect(launchCount, 1);
    expect(tester.widget<ElevatedButton>(sendButton()).onPressed, isNull);

    captcha.complete(null);
    await tester.pump();

    expect(tester.widget<ElevatedButton>(sendButton()).onPressed, isNotNull);
    verifyNever(() => authBloc.add(any()));
  });

  testWidgets('滑块等待期间忽略其他认证状态并保持请求锁', (tester) async {
    final captcha = Completer<String?>();
    var launchCount = 0;
    await pumpPage(tester, (_) {
      launchCount++;
      return captcha.future;
    });
    await enterPhone(tester);
    await tester.tap(sendButton());

    states.add(
      const AuthCodeSent(
        target: '13800138000',
        type: 'login',
        channel: 'phone',
        requestId: 'other-request',
      ),
    );
    await tester.pump();

    expect(tester.widget<ElevatedButton>(sendButton()).onPressed, isNull);
    await tester.tap(sendButton(), warnIfMissed: false);
    expect(launchCount, 1);

    captcha.complete(null);
    await tester.pump();
  });

  testWidgets('验证通过后只派发一次重置验证码事件', (tester) async {
    await pumpPage(tester, (_) async => 'captcha-token');
    await enterPhone(tester);

    await tester.tap(sendButton());
    await tester.pump();

    expect(addedEvents, hasLength(1));
    final event = latestCodeRequest();
    expect(event.phone, '13800138000');
    expect(event.type, 'reset');
    expect(event.captchaToken, 'captcha-token');
    expect(event.requestId, isNotEmpty);
  });

  testWidgets('滑块验证异常后恢复按钮', (tester) async {
    await pumpPage(tester, (_) => Future<String?>.error(Exception('failed')));
    await enterPhone(tester);

    await tester.tap(sendButton());
    await tester.pump();

    expect(tester.widget<ElevatedButton>(sendButton()).onPressed, isNotNull);
    verifyNever(() => authBloc.add(any()));
  });

  testWidgets('发码失败后恢复按钮并允许重试', (tester) async {
    await pumpPage(tester, (_) async => 'captcha-token');
    await enterPhone(tester);
    await tester.tap(sendButton());
    await tester.pump();
    final request = latestCodeRequest();

    states.add(
      AuthCodeSendError(
        message: 'send failed',
        target: '13800138000',
        type: 'reset',
        channel: 'phone',
        requestId: request.requestId,
      ),
    );
    await tester.pump();

    expect(tester.widget<ElevatedButton>(sendButton()).onPressed, isNotNull);

    await tester.tap(sendButton());
    await tester.pump();
    expect(addedEvents.whereType<AuthSendCodeRequested>(), hasLength(2));
  });

  testWidgets('发码成功才开始倒计时且页面销毁后 Timer 不再回调', (tester) async {
    await pumpPage(tester, (_) async => 'captcha-token');
    await enterPhone(tester);
    await tester.tap(sendButton());
    await tester.pump();
    final request = latestCodeRequest();

    expect(find.text('60s'), findsNothing);

    states.add(
      AuthCodeSent(
        target: '13800138000',
        type: 'reset',
        channel: 'phone',
        requestId: request.requestId,
      ),
    );
    await tester.pump();
    expect(find.text('60s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('59s'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('发码事件派发后修改手机号不会锁定新号码', (tester) async {
    await pumpPage(tester, (_) async => 'captcha-token');
    await enterPhone(tester);
    await tester.tap(sendButton());
    await tester.pump();
    final request = latestCodeRequest();

    await tester.enterText(
      find.byType(TextFormField).first,
      '13900139000',
    );
    states.add(
      AuthCodeSent(
        target: '13800138000',
        type: 'reset',
        channel: 'phone',
        requestId: request.requestId,
      ),
    );
    await tester.pump();

    expect(find.text('60s'), findsNothing);
    expect(tester.widget<ElevatedButton>(sendButton()).onPressed, isNotNull);
  });

  testWidgets('修改手机号后旧请求失败不显示错误', (tester) async {
    await pumpPage(tester, (_) async => 'captcha-token');
    await enterPhone(tester);
    await tester.tap(sendButton());
    await tester.pump();
    final request = latestCodeRequest();

    await tester.enterText(
      find.byType(TextFormField).first,
      '13900139000',
    );
    states.add(
      AuthCodeSendError(
        message: 'stale-request-error',
        target: request.phone,
        type: request.type,
        channel: 'phone',
        requestId: request.requestId,
      ),
    );
    await tester.pump();

    expect(find.text('stale-request-error'), findsNothing);
    expect(tester.widget<ElevatedButton>(sendButton()).onPressed, isNotNull);
  });

  testWidgets('忽略资料更新专属失败终态', (tester) async {
    await pumpPage(tester, (_) async => null);

    states.add(
      const AuthProfileUpdateError(
        message: 'profile-only-error',
        requestId: 'profile-request',
      ),
    );
    await tester.pump();

    expect(find.textContaining('profile-only-error'), findsNothing);
    expect(tester.widget<ElevatedButton>(resetButton()).onPressed, isNotNull);
  });

  testWidgets('倒计时期间修改手机号会清空旧验证码并恢复发送', (tester) async {
    await pumpPage(tester, (_) async => 'captcha-token');
    final fields = find.byType(TextFormField);
    await enterPhone(tester);
    await tester.tap(sendButton());
    await tester.pump();
    final request = latestCodeRequest();
    states.add(
      AuthCodeSent(
        target: '13800138000',
        type: 'reset',
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
    expect(tester.widget<ElevatedButton>(sendButton()).onPressed, isNotNull);
  });

  testWidgets('快速点击重置按钮只派发一次重置事件', (tester) async {
    await pumpPage(tester, (_) async => null);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '13800138000');
    await tester.enterText(fields.at(1), '123456');
    await tester.enterText(fields.at(2), 'new-password');
    await tester.enterText(fields.at(3), 'new-password');
    await tester.ensureVisible(resetButton());
    await tester.pumpAndSettle();

    await tester.tap(resetButton());
    await tester.tap(resetButton());

    final captured = verify(() => authBloc.add(captureAny())).captured;
    expect(captured, hasLength(1));
    final event = captured.single as AuthResetPasswordRequested;
    expect(event.phone, '13800138000');
    expect(event.code, '123456');
    expect(event.newPassword, 'new-password');
  });
}
