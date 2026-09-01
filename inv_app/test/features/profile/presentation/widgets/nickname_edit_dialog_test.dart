import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/profile/presentation/widgets/nickname_edit_dialog.dart';

Widget _host({
  required Future<void> Function(String nickname) onConfirm,
}) {
  return ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => NicknameEditDialog(
                  initialValue: '旧昵称',
                  title: '昵称',
                  label: '昵称',
                  hint: '昵称',
                  cancelLabel: '取消',
                  confirmLabel: '确认',
                  onConfirm: onConfirm,
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openDialog(
  WidgetTester tester,
  Future<void> Function(String nickname) onConfirm,
) async {
  await tester.pumpWidget(_host(onConfirm: onConfirm));
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('使用初始昵称且取消时释放输入 controller', (tester) async {
    await _openDialog(tester, (_) async {});

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    final controller = editable.controller;
    expect(controller.text, '旧昵称');

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byType(NicknameEditDialog), findsNothing);
    expect(() => controller.addListener(() {}), throwsFlutterError);
  });

  testWidgets('确认 pending 时快速连点只提交一次且阻止关闭', (tester) async {
    final result = Completer<void>();
    var submitCount = 0;
    String? submittedNickname;
    await _openDialog(tester, (nickname) {
      submitCount++;
      submittedNickname = nickname;
      return result.future;
    });

    await tester.enterText(find.byType(TextField), '新昵称');
    await tester.tap(find.text('确认'));
    await tester.tap(find.text('确认'));
    await tester.pump();

    expect(submitCount, 1);
    expect(submittedNickname, '新昵称');
    expect(find.byType(NicknameEditDialog), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(find.byType(NicknameEditDialog), findsOneWidget);

    result.complete();
    await tester.pumpAndSettle();
    expect(find.byType(NicknameEditDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('提交完成前宿主销毁不会访问已销毁状态', (tester) async {
    final result = Completer<void>();
    await _openDialog(tester, (_) => result.future);

    await tester.tap(find.text('确认'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    result.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
