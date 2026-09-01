import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/widgets/org_invitation_dialog.dart';

Widget _host({required SendOrganizationInvitation onSubmit}) {
  return ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showModalBottomSheet<OrgInvitationDialogResult>(
              context: context,
              isScrollControlled: true,
              builder: (_) => OrgInvitationDialog(
                allowedRoles: const ['org_admin', 'customer'],
                initialRole: 'customer',
                onSubmit: onSubmit,
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester, Widget host) async {
  await tester.pumpWidget(host);
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('关闭弹窗时释放输入控制器', (tester) async {
    await _open(
      tester,
      _host(
        onSubmit: ({
          required String email,
          required String roleCode,
          required int expiresHours,
        }) async =>
            <String, dynamic>{},
      ),
    );

    final controllers = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .map((field) => field.controller)
        .toList();
    expect(controllers, hasLength(2));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    for (final controller in controllers) {
      expect(() => controller.addListener(() {}), throwsFlutterError);
    }
  });

  testWidgets('请求 pending 时阻止重复提交和关闭', (tester) async {
    final result = Completer<Map<String, dynamic>>();
    var submitCount = 0;
    await _open(
      tester,
      _host(
        onSubmit: ({
          required String email,
          required String roleCode,
          required int expiresHours,
        }) {
          submitCount++;
          expect(email, 'user@example.com');
          expect(roleCode, 'customer');
          expect(expiresHours, 7 * 24);
          return result.future;
        },
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'user@example.com');
    await tester.tap(find.text('发送邀请'));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(submitCount, 1);

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(find.byType(OrgInvitationDialog), findsOneWidget);

    result.complete(const {'results': []});
    await tester.pumpAndSettle();
    expect(find.byType(OrgInvitationDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('请求完成前页面销毁不再操作弹窗状态', (tester) async {
    final result = Completer<Map<String, dynamic>>();
    await _open(
      tester,
      _host(
        onSubmit: ({
          required String email,
          required String roleCode,
          required int expiresHours,
        }) =>
            result.future,
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'user@example.com');
    await tester.tap(find.text('发送邀请'));
    await tester.pumpWidget(const SizedBox.shrink());
    result.complete(const {'results': []});
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
