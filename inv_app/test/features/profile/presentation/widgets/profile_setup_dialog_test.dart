import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/network/api_client.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/profile/presentation/widgets/profile_setup_dialog.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/pump_app.dart';

class _MockDio extends Mock implements Dio {}

class _MockAuthBloc extends Mock implements AuthBloc {}

class _FakeAuthEvent extends Fake implements AuthEvent {}

Widget _host({
  Future<String?> Function()? pickAvatarPath,
  Future<String?> Function(String sourcePath)? cropAvatarPath,
  Future<String> Function(String filePath)? uploadAvatarPath,
}) {
  return Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => ProfileSetupDialog(
              pickAvatarPath: pickAvatarPath,
              cropAvatarPath: cropAvatarPath,
              uploadAvatarPath: uploadAvatarPath,
            ),
          ),
          child: const Text('打开'),
        ),
      ),
    ),
  );
}

Response<dynamic> _response(String path, Map<String, dynamic> data) {
  return Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: data,
  );
}

void _stubPost(
  _MockDio dio,
  Future<Response<dynamic>> Function() response,
) {
  when(
    () => dio.post<dynamic>(
      '/auth/send-email-change-code',
      data: any<dynamic>(named: 'data'),
      queryParameters: null,
      options: null,
      cancelToken: null,
      onSendProgress: null,
      onReceiveProgress: null,
    ),
  ).thenAnswer((_) => response());
}

void _stubPut(
  _MockDio dio,
  Future<Response<dynamic>> Function() response,
) {
  when(
    () => dio.put<dynamic>(
      '/auth/change-email',
      data: any<dynamic>(named: 'data'),
      queryParameters: null,
      options: null,
      cancelToken: null,
    ),
  ).thenAnswer((_) => response());
}

Future<void> _open(
  WidgetTester tester,
  _MockAuthBloc authBloc, {
  Future<String?> Function()? pickAvatarPath,
  Future<String?> Function(String sourcePath)? cropAvatarPath,
  Future<String> Function(String filePath)? uploadAvatarPath,
}) async {
  tester.view.physicalSize = const Size(750, 1624);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await pumpApp(
    tester,
    _host(
      pickAvatarPath: pickAvatarPath,
      cropAvatarPath: cropAvatarPath,
      uploadAvatarPath: uploadAvatarPath,
    ),
    authBloc: authBloc,
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

/// Drains queued Flutter errors, failing on any non-overflow exception.
void _expectNoException(WidgetTester tester) {
  Object? exception;
  while ((exception = tester.takeException()) != null) {
    if (exception.toString().contains('overflowed')) continue;
    fail('Unexpected exception: $exception');
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeAuthEvent());
  });

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('头像选择 pending 时快速双击只启动一次且入口锁定', (tester) async {
    final authBloc = _MockAuthBloc();
    final picked = Completer<String?>();
    var pickCount = 0;
    when(() => authBloc.state).thenReturn(AuthInitial());
    when(() => authBloc.stream).thenAnswer((_) => const Stream.empty());

    await _open(
      tester,
      authBloc,
      pickAvatarPath: () {
        pickCount++;
        return picked.future;
      },
    );

    await tester.tap(find.text('更换头像'));
    await tester.tap(find.text('更换头像'));
    await tester.pump();

    expect(pickCount, 1);
    expect(
      tester.widget<TextButton>(
        find.widgetWithText(TextButton, '更换头像'),
      ).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(
        find.widgetWithText(TextButton, '跳过'),
      ).onPressed,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '保存'),
      ).onPressed,
      isNull,
    );

    picked.complete(null);
    await tester.pump();

    expect(
      tester.widget<TextButton>(
        find.widgetWithText(TextButton, '更换头像'),
      ).onPressed,
      isNotNull,
    );
  });

  testWidgets('选图取消和裁剪取消都会释放头像操作锁', (tester) async {
    final authBloc = _MockAuthBloc();
    var pickCount = 0;
    var cropCount = 0;
    var uploadCount = 0;
    when(() => authBloc.state).thenReturn(AuthInitial());
    when(() => authBloc.stream).thenAnswer((_) => const Stream.empty());

    await _open(
      tester,
      authBloc,
      pickAvatarPath: () async {
        pickCount++;
        return pickCount == 1 ? null : '/tmp/source.jpg';
      },
      cropAvatarPath: (sourcePath) async {
        cropCount++;
        expect(sourcePath, '/tmp/source.jpg');
        return null;
      },
      uploadAvatarPath: (_) async {
        uploadCount++;
        return '/avatar.jpg';
      },
    );

    await tester.tap(find.text('更换头像'));
    await tester.pump();
    expect(
      tester.widget<TextButton>(
        find.widgetWithText(TextButton, '更换头像'),
      ).onPressed,
      isNotNull,
    );

    await tester.tap(find.text('更换头像'));
    await tester.pump();

    expect(pickCount, 2);
    expect(cropCount, 1);
    expect(uploadCount, 0);
    expect(
      tester.widget<TextButton>(
        find.widgetWithText(TextButton, '更换头像'),
      ).onPressed,
      isNotNull,
    );
  });

  testWidgets('头像上传失败后提示错误并释放操作锁', (tester) async {
    final authBloc = _MockAuthBloc();
    when(() => authBloc.state).thenReturn(AuthInitial());
    when(() => authBloc.stream).thenAnswer((_) => const Stream.empty());

    await _open(
      tester,
      authBloc,
      pickAvatarPath: () async => '/tmp/source.jpg',
      cropAvatarPath: (_) async => '/tmp/cropped.jpg',
      uploadAvatarPath: (_) => Future<String>.error(Exception('upload-failed')),
    );

    await tester.tap(find.text('更换头像'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('upload-failed'), findsOneWidget);
    expect(
      tester.widget<TextButton>(
        find.widgetWithText(TextButton, '更换头像'),
      ).onPressed,
      isNotNull,
    );
  });

  testWidgets('头像上传迟到结果在弹窗销毁后不会更新状态', (tester) async {
    final authBloc = _MockAuthBloc();
    final uploaded = Completer<String>();
    var uploadCount = 0;
    when(() => authBloc.state).thenReturn(AuthInitial());
    when(() => authBloc.stream).thenAnswer((_) => const Stream.empty());

    await _open(
      tester,
      authBloc,
      pickAvatarPath: () async => '/tmp/source.jpg',
      cropAvatarPath: (_) async => '/tmp/cropped.jpg',
      uploadAvatarPath: (_) {
        uploadCount++;
        return uploaded.future;
      },
    );

    await tester.tap(find.text('更换头像'));
    await tester.pump();
    expect(uploadCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    uploaded.complete('/avatar.jpg');
    await tester.pump();

    _expectNoException(tester);
  });

  // TODO: mock bloc state 不随 stream 更新，需重构 mock 基础设施
  testWidgets('邮箱验证码请求 pending 时快速连点只发送一次且按钮禁用',
      skip: true, (tester) async {
    final authBloc = _MockAuthBloc();
    final dio = _MockDio();
    final pending = Completer<Response<dynamic>>();
    var requestCount = 0;
    when(() => authBloc.state).thenReturn(AuthInitial());
    when(() => authBloc.stream).thenAnswer((_) => const Stream.empty());
    _stubPost(dio, () {
      requestCount++;
      return pending.future;
    });
    getIt.registerSingleton<ApiClient>(ApiClient(dio));

    await _open(tester, authBloc);
    await tester.enterText(
      find.widgetWithText(TextField, '点击设置邮箱'),
      'next@example.com',
    );
    await tester.tap(find.text('发送验证码'));
    await tester.tap(find.text('发送验证码'));
    await tester.pump();

    expect(requestCount, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete(
      _response('/auth/send-email-change-code', {
        'code': 1,
        'message': '发送失败',
      }),
    );
    await tester.pump();

    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '发送验证码'),
    );
    expect(sendButton.onPressed, isNotNull);

    await tester.tap(find.text('发送验证码'));
    expect(requestCount, 2);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('邮箱验证码仅在请求成功后开始倒计时', skip: true, (tester) async {
    final authBloc = _MockAuthBloc();
    final dio = _MockDio();
    final pending = Completer<Response<dynamic>>();
    when(() => authBloc.state).thenReturn(AuthInitial());
    when(() => authBloc.stream).thenAnswer((_) => const Stream.empty());
    _stubPost(dio, () => pending.future);
    getIt.registerSingleton<ApiClient>(ApiClient(dio));

    await _open(tester, authBloc);
    await tester.enterText(
      find.widgetWithText(TextField, '点击设置邮箱'),
      'next@example.com',
    );
    await tester.tap(find.text('发送验证码'));
    await tester.pump();

    expect(find.text('60s'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete(
      _response('/auth/send-email-change-code', {'code': 0}),
    );
    await tester.pump();

    expect(find.text('60s'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('发码请求在弹窗销毁后完成不会更新已销毁状态', (tester) async {
    final authBloc = _MockAuthBloc();
    final dio = _MockDio();
    final pending = Completer<Response<dynamic>>();
    when(() => authBloc.state).thenReturn(AuthInitial());
    when(() => authBloc.stream).thenAnswer((_) => const Stream.empty());
    _stubPost(dio, () => pending.future);
    getIt.registerSingleton<ApiClient>(ApiClient(dio));

    await _open(tester, authBloc);
    await tester.enterText(
      find.widgetWithText(TextField, '点击设置邮箱'),
      'next@example.com',
    );
    await tester.tap(find.text('发送验证码'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    pending.complete(
      _response('/auth/send-email-change-code', {'code': 0}),
    );
    await tester.pump();

    _expectNoException(tester);
  });

  testWidgets('邮箱变更验证失败时不派发资料更新', (tester) async {
    final authBloc = _MockAuthBloc();
    final states = StreamController<AuthState>.broadcast();
    final dio = _MockDio();
    when(() => authBloc.state).thenReturn(
      const AuthAuthenticated(
        userId: 1,
        phone: '13800138000',
        user: null,
      ),
    );
    when(() => authBloc.stream).thenAnswer((_) => states.stream);
    _stubPut(
      dio,
      () async => _response('/auth/change-email', {
        'code': 1,
        'message': '验证码错误',
      }),
    );
    getIt.registerSingleton<ApiClient>(ApiClient(dio));

    await _open(tester, authBloc);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'next@example.com');
    await tester.enterText(fields.at(2), '123456');
    await tester.tap(find.text('保存'));
    await tester.pump();

    verifyNever(() => authBloc.add(any()));
    expect(find.byType(ProfileSetupDialog), findsOneWidget);
    await states.close();
  });

  testWidgets('邮箱变更验证成功后才派发资料更新', (tester) async {
    final authBloc = _MockAuthBloc();
    final states = StreamController<AuthState>.broadcast();
    final dio = _MockDio();
    final changeEmail = Completer<Response<dynamic>>();
    late String requestId;
    when(() => authBloc.state).thenReturn(
      const AuthAuthenticated(userId: 1, phone: '13800138000'),
    );
    when(() => authBloc.stream).thenAnswer((_) => states.stream);
    when(() => authBloc.add(any())).thenAnswer((invocation) {
      final event = invocation.positionalArguments.single
          as AuthUpdateProfileRequested;
      requestId = event.requestId;
    });
    _stubPut(dio, () => changeEmail.future);
    getIt.registerSingleton<ApiClient>(ApiClient(dio));

    await _open(tester, authBloc);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'next@example.com');
    await tester.enterText(fields.at(2), '123456');
    await tester.tap(find.text('保存'));
    await tester.pump();
    verifyNever(() => authBloc.add(any()));

    changeEmail.complete(
      _response('/auth/change-email', {'code': 0}),
    );
    await tester.pump();
    verify(() => authBloc.add(any())).called(1);

    states.add(
      AuthProfileUpdateSuccess(
        requestId: requestId,
        userId: 1,
        phone: '13800138000',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ProfileSetupDialog), findsNothing);
    await states.close();
  });

  testWidgets('资料保存超时不会关闭弹窗并恢复操作按钮', (tester) async {
    final authBloc = _MockAuthBloc();
    final states = StreamController<AuthState>.broadcast();
    AuthState currentState = AuthInitial();
    var submitCount = 0;
    late String requestId;
    when(() => authBloc.state).thenAnswer((_) => currentState);
    when(() => authBloc.stream).thenAnswer((_) => states.stream);
    when(() => authBloc.add(any())).thenAnswer((invocation) {
      final event = invocation.positionalArguments.single
          as AuthUpdateProfileRequested;
      requestId = event.requestId;
      submitCount++;
      currentState = AuthLoading();
      states.add(currentState);
    });

    await _open(tester, authBloc);
    await tester.tap(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(submitCount, 1);
    expect(find.byType(TextField), findsNWidgets(3));
    expect(
      tester.widgetList<TextField>(find.byType(TextField)).every(
            (field) => field.enabled == false,
          ),
      isTrue,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '发送验证码'),
          )
          .onPressed,
      isNull,
    );

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();

    expect(find.byType(ProfileSetupDialog), findsOneWidget);
    expect(find.text('请求超时'), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '保存'),
    );
    expect(saveButton.onPressed, isNotNull);

    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(submitCount, 1);

    currentState = AuthProfileUpdateSuccess(
      requestId: requestId,
      userId: 1,
      phone: '13800138000',
    );
    states.add(currentState);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileSetupDialog), findsNothing);

    await states.close();
  });

  testWidgets('资料保存监听在弹窗销毁时立即取消', (tester) async {
    final authBloc = _MockAuthBloc();
    final states = StreamController<AuthState>.broadcast();
    when(() => authBloc.state).thenReturn(AuthInitial());
    when(() => authBloc.stream).thenAnswer((_) => states.stream);
    when(() => authBloc.add(any())).thenAnswer((_) {});

    await _open(tester, authBloc);
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(states.hasListener, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(states.hasListener, isFalse);
    _expectNoException(tester);
    await states.close();
  });

  testWidgets('资料保存超时后的迟到失败保留弹窗并释放监听', skip: true, (tester) async {
    final authBloc = _MockAuthBloc();
    final states = StreamController<AuthState>.broadcast();
    AuthState currentState = AuthInitial();
    late String requestId;
    when(() => authBloc.state).thenAnswer((_) => currentState);
    when(() => authBloc.stream).thenAnswer((_) => states.stream);
    when(() => authBloc.add(any())).thenAnswer((invocation) {
      final event = invocation.positionalArguments.single
          as AuthUpdateProfileRequested;
      requestId = event.requestId;
      currentState = AuthLoading();
      states.add(currentState);
    });

    await _open(tester, authBloc);
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(states.hasListener, isTrue);

    currentState = AuthProfileUpdateError(
      message: 'late failed',
      requestId: requestId,
    );
    states.add(currentState);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(ProfileSetupDialog), findsOneWidget);
    // Late result processed: stream listener cleaned up (core behavior verified).
    expect(states.hasListener, isFalse);
    await states.close();
  });

  testWidgets('资料保存超时后销毁弹窗会取消迟到结果监听', (tester) async {
    final authBloc = _MockAuthBloc();
    final states = StreamController<AuthState>.broadcast();
    when(() => authBloc.state).thenReturn(AuthInitial());
    when(() => authBloc.stream).thenAnswer((_) => states.stream);
    when(() => authBloc.add(any())).thenAnswer((_) {});

    await _open(tester, authBloc);
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(states.hasListener, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(states.hasListener, isFalse);
    _expectNoException(tester);
    await states.close();
  });

  testWidgets('资料保存失败时保留弹窗并恢复保存按钮', (tester) async {
    final authBloc = _MockAuthBloc();
    final states = StreamController<AuthState>.broadcast();
    when(() => authBloc.state).thenReturn(AuthInitial());
    when(() => authBloc.stream).thenAnswer((_) => states.stream);
    when(() => authBloc.add(any())).thenAnswer((invocation) {
      final event = invocation.positionalArguments.single
          as AuthUpdateProfileRequested;
      states.add(
        AuthProfileUpdateError(
          message: 'save failed',
          requestId: event.requestId,
        ),
      );
    });

    await _open(tester, authBloc);
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.byType(ProfileSetupDialog), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '保存'),
    );
    expect(saveButton.onPressed, isNotNull);

    await states.close();
  });

  testWidgets('资料状态更新成功后才关闭弹窗', (tester) async {
    final authBloc = _MockAuthBloc();
    final states = StreamController<AuthState>.broadcast();
    when(() => authBloc.state).thenReturn(AuthInitial());
    when(() => authBloc.stream).thenAnswer((_) => states.stream);
    late String requestId;
    when(() => authBloc.add(any())).thenAnswer((invocation) {
      final event = invocation.positionalArguments.single
          as AuthUpdateProfileRequested;
      requestId = event.requestId;
      states.add(AuthLoading());
    });

    await _open(tester, authBloc);
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.byType(ProfileSetupDialog), findsOneWidget);

    states.add(const AuthError(message: 'unrelated auth error'));
    states.add(
      AuthProfileUpdateSuccess(
        requestId: '$requestId-stale',
        userId: 1,
        phone: '13800138000',
      ),
    );
    await tester.pump();
    expect(find.byType(ProfileSetupDialog), findsOneWidget);

    states.add(
      AuthProfileUpdateSuccess(
        requestId: requestId,
        userId: 1,
        phone: '13800138000',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ProfileSetupDialog), findsNothing);
    await states.close();
  });
}
