import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/profile/presentation/widgets/contact_change_dialog.dart';

Widget _host({
  required Future<bool> Function(String value) onSendCode,
  required Future<bool> Function(String value, String code) onConfirm,
  ValueChanged<String>? onConfirmed,
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
                builder: (_) => ContactChangeDialog(
                  icon: Icons.phone_android,
                  title: '修改手机号',
                  description: '请输入新的手机号码',
                  valueLabel: '新手机号',
                  valueHint: '请输入手机号',
                  valueKeyboardType: TextInputType.phone,
                  valuePrefixIcon: Icons.phone,
                  codeLabel: '验证码',
                  codeHint: '请输入验证码',
                  sendCodeLabel: '发送验证码',
                  cancelLabel: '取消',
                  confirmLabel: '确认',
                  onSendCode: onSendCode,
                  onConfirm: onConfirm,
                  onConfirmed: onConfirmed ?? (_) {},
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

Future<void> _openDialog(WidgetTester tester, Widget host) async {
  tester.view.physicalSize = const Size(750, 1624);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(host);
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
  testWidgets('发送请求在弹窗关闭后完成不会更新已销毁状态', (tester) async {
    final sendResult = Completer<bool>();
    await _openDialog(
      tester,
      _host(
        onSendCode: (_) => sendResult.future,
        onConfirm: (_, __) async => false,
      ),
    );

    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.tap(find.text('发送验证码'));
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    sendResult.complete(true);
    await tester.pump();

    _expectNoException(tester);
    expect(find.text('60s'), findsNothing);
  });

  testWidgets('弹窗关闭时取消验证码倒计时器', (tester) async {
    await _openDialog(
      tester,
      _host(
        onSendCode: (_) async => true,
        onConfirm: (_, __) async => false,
      ),
    );

    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.tap(find.text('发送验证码'));
    await tester.pump();
    expect(find.text('60s'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 61));

    _expectNoException(tester);
  });

  testWidgets('弹窗关闭时释放输入框 controllers', (tester) async {
    await _openDialog(
      tester,
      _host(
        onSendCode: (_) async => false,
        onConfirm: (_, __) async => false,
      ),
    );

    final fields = tester.widgetList<EditableText>(find.byType(EditableText));
    final controllers = fields.map((field) => field.controller).toList();
    expect(controllers, hasLength(2));

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    for (final controller in controllers) {
      expect(
        () => controller.addListener(() {}),
        throwsFlutterError,
      );
    }
  });

  testWidgets('确认成功后传递输入值并关闭弹窗', (tester) async {
    String? submittedValue;
    String? submittedCode;
    String? confirmedValue;
    await _openDialog(
      tester,
      _host(
        onSendCode: (_) async => false,
        onConfirm: (value, code) async {
          submittedValue = value;
          submittedCode = code;
          return true;
        },
        onConfirmed: (value) => confirmedValue = value,
      ),
    );

    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(submittedValue, '13800138000');
    expect(submittedCode, '123456');
    expect(confirmedValue, '13800138000');
    expect(find.byType(ContactChangeDialog), findsNothing);
  });

  testWidgets('发送请求 pending 时快速连点只提交一次', (tester) async {
    final sendResult = Completer<bool>();
    var sendCount = 0;
    await _openDialog(
      tester,
      _host(
        onSendCode: (_) {
          sendCount++;
          return sendResult.future;
        },
        onConfirm: (_, __) async => false,
      ),
    );

    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.tap(find.text('发送验证码'));
    await tester.tap(find.text('发送验证码'));
    expect(sendCount, 1);

    sendResult.complete(false);
    await tester.pump();
    _expectNoException(tester);
  });

  testWidgets('确认 pending 时不可关闭且成功只同步一次', (tester) async {
    final confirmResult = Completer<bool>();
    var confirmCount = 0;
    var confirmedCount = 0;
    await _openDialog(
      tester,
      _host(
        onSendCode: (_) async => false,
        onConfirm: (_, __) {
          confirmCount++;
          return confirmResult.future;
        },
        onConfirmed: (_) => confirmedCount++,
      ),
    );

    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('确认'));
    await tester.tap(find.text('确认'));
    expect(confirmCount, 1);

    await tester.pump();
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();

    expect(find.byType(ContactChangeDialog), findsOneWidget);

    confirmResult.complete(true);
    await tester.pumpAndSettle();

    expect(confirmedCount, 1);
    expect(find.byType(ContactChangeDialog), findsNothing);
    _expectNoException(tester);
  });
}
