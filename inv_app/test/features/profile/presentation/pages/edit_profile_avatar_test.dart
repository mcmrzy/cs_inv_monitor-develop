import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/features/auth/domain/entities/user.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/profile/presentation/pages/edit_profile_page.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/pump_app.dart';

class _FakeAuthEvent extends Fake implements AuthEvent {}

void main() {
  late MockAuthBloc authBloc;
  late MockStorageService storageService;
  late StreamController<AuthState> authStates;
  late List<AuthEvent> addedEvents;

  setUpAll(() {
    registerFallbackValue(_FakeAuthEvent());
  });

  setUp(() async {
    await getIt.reset();
    authBloc = MockAuthBloc();
    storageService = MockStorageService();
    authStates = StreamController<AuthState>.broadcast();
    addedEvents = <AuthEvent>[];

    when(() => authBloc.state).thenReturn(
      const AuthAuthenticated(userId: 1, phone: '13800138000'),
    );
    when(() => authBloc.stream).thenAnswer((_) => authStates.stream);
    when(() => authBloc.add(any())).thenAnswer((invocation) {
      addedEvents.add(invocation.positionalArguments.single as AuthEvent);
    });
    when(() => storageService.getToken()).thenAnswer((_) async => 'token');
    getIt.registerSingleton<StorageService>(storageService);
  });

  tearDown(() async {
    await authStates.close();
    await getIt.reset();
  });

  Finder get avatarButton =>
      find.byKey(const Key('edit-profile-avatar-button'));

  Future<void> pumpPage(
    WidgetTester tester, {
    required Future<String?> Function() pickAvatarPath,
    Future<String?> Function(String sourcePath)? cropAvatarPath,
    Future<String> Function(String filePath)? uploadAvatarPath,
    List<String>? renderedAvatarUrls,
  }) async {
    await pumpApp(
      tester,
      EditProfilePage(
        pickAvatarPath: pickAvatarPath,
        cropAvatarPath: cropAvatarPath,
        uploadAvatarPath: uploadAvatarPath,
        avatarImageProvider: (url) {
          renderedAvatarUrls?.add(url);
          return MemoryImage(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            ),
          );
        },
      ),
      authBloc: authBloc,
    );
    await tester.ensureVisible(avatarButton);
  }

  testWidgets('头像选择等待期间快速连点只启动一次', (tester) async {
    final picked = Completer<String?>();
    var pickCount = 0;
    await pumpPage(
      tester,
      pickAvatarPath: () {
        pickCount++;
        return picked.future;
      },
    );

    await tester.tap(avatarButton);
    await tester.tap(avatarButton);
    await tester.pump();

    expect(pickCount, 1);
    expect(tester.widget<GestureDetector>(avatarButton).onTap, isNull);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.edit_outlined).first,
          )
          .onPressed,
      isNull,
    );

    picked.complete(null);
    await tester.pump();
    expect(tester.widget<GestureDetector>(avatarButton).onTap, isNotNull);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
  });

  testWidgets('选图取消后释放锁并允许重试', (tester) async {
    var pickCount = 0;
    await pumpPage(
      tester,
      pickAvatarPath: () async {
        pickCount++;
        return null;
      },
    );

    await tester.tap(avatarButton);
    await tester.pump();
    await tester.tap(avatarButton);
    await tester.pump();

    expect(pickCount, 2);
    expect(tester.widget<GestureDetector>(avatarButton).onTap, isNotNull);
  });

  testWidgets('页面销毁后忽略迟到的选图结果', (tester) async {
    final picked = Completer<String?>();
    await pumpPage(
      tester,
      pickAvatarPath: () => picked.future,
    );

    await tester.tap(avatarButton);
    await tester.pumpWidget(const SizedBox.shrink());
    picked.complete('/tmp/avatar.jpg');
    await tester.pump();

    expect(tester.takeException(), isNull);
    verifyNever(() => authBloc.add(any()));
  });

  testWidgets('头像上传后等资料保存确认并忽略重复终态', (tester) async {
    await pumpPage(
      tester,
      pickAvatarPath: () async => '/tmp/source.jpg',
      cropAvatarPath: (_) async => '/tmp/cropped.jpg',
      uploadAvatarPath: (_) async => '/avatar.jpg',
    );

    await tester.tap(avatarButton);
    await tester.pump();

    final updates = addedEvents.whereType<AuthUpdateProfileRequested>().toList();
    expect(updates, hasLength(1));
    expect(updates.single.avatar, '/avatar.jpg');
    expect(tester.widget<GestureDetector>(avatarButton).onTap, isNull);

    final requestId = updates.single.requestId;
    final savedState = AuthProfileUpdateSuccess(
      requestId: requestId,
      userId: 1,
      phone: '13800138000',
      user: User(
        id: 1,
        phone: '13800138000',
        avatar: '/avatar.jpg',
        status: 1,
        createdAt: DateTime(2026),
      ),
    );
    authStates.add(const AuthError(message: 'unrelated auth error'));
    authStates.add(
      AuthProfileUpdateError(
        message: 'stale profile error',
        requestId: '$requestId-stale',
      ),
    );
    await tester.pump();
    expect(tester.widget<GestureDetector>(avatarButton).onTap, isNull);

    authStates.add(savedState);
    authStates.add(savedState);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.widget<GestureDetector>(avatarButton).onTap, isNotNull);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
  });

  testWidgets('头像资料保存超时后仍接收同请求迟到成功并刷新头像', (tester) async {
    final renderedAvatarUrls = <String>[];
    await pumpPage(
      tester,
      pickAvatarPath: () async => '/tmp/source.jpg',
      cropAvatarPath: (_) async => '/tmp/cropped.jpg',
      uploadAvatarPath: (_) async => '/late-avatar.jpg',
      renderedAvatarUrls: renderedAvatarUrls,
    );

    await tester.tap(avatarButton);
    await tester.pump();
    final update = addedEvents.whereType<AuthUpdateProfileRequested>().single;

    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(renderedAvatarUrls, isEmpty);
    expect(tester.widget<GestureDetector>(avatarButton).onTap, isNull);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);

    authStates.add(
      AuthProfileUpdateSuccess(
        requestId: update.requestId,
        userId: 1,
        phone: '13800138000',
        user: User(
          id: 1,
          phone: '13800138000',
          avatar: '/late-avatar.jpg',
          status: 1,
          createdAt: DateTime(2026),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      renderedAvatarUrls.any((url) => url.endsWith('/late-avatar.jpg')),
      isTrue,
    );
    expect(tester.widget<GestureDetector>(avatarButton).onTap, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('头像资料保存超时后销毁页面会取消迟到结果监听', (tester) async {
    await pumpPage(
      tester,
      pickAvatarPath: () async => '/tmp/source.jpg',
      cropAvatarPath: (_) async => '/tmp/cropped.jpg',
      uploadAvatarPath: (_) async => '/late-avatar.jpg',
    );

    await tester.tap(avatarButton);
    await tester.pump();
    final update = addedEvents.whereType<AuthUpdateProfileRequested>().single;
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(authStates.hasListener, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(authStates.hasListener, isFalse);

    authStates.add(
      AuthProfileUpdateSuccess(
        requestId: update.requestId,
        userId: 1,
        phone: '13800138000',
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
