import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/entities/organization.dart';
import 'package:inv_app/core/widgets/create_organization_dialog.dart';

Widget _host({required CreateOrganization onSubmit}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () => showDialog<Organization>(
            context: context,
            builder: (_) => CreateOrganizationDialog(onSubmit: onSubmit),
          ),
          child: const Text('打开'),
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
  testWidgets('取消时释放两个输入控制器', (tester) async {
    await _open(
      tester,
      _host(
        onSubmit: ({required String name, String? description}) async =>
            const Organization(id: 1, name: 'unused'),
      ),
    );

    final controllers = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .map((field) => field.controller)
        .toList();
    expect(controllers, hasLength(2));

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    for (final controller in controllers) {
      expect(() => controller.addListener(() {}), throwsFlutterError);
    }
  });

  testWidgets('创建 pending 时只提交一次并阻止 dismiss', (tester) async {
    final result = Completer<Organization>();
    var submitCount = 0;
    await _open(
      tester,
      _host(
        onSubmit: ({required String name, String? description}) {
          submitCount++;
          expect(name, '新组织');
          expect(description, '描述');
          return result.future;
        },
      ),
    );

    await tester.enterText(find.byType(TextField).first, '新组织');
    await tester.enterText(find.byType(TextField).last, '描述');
    await tester.tap(find.text('创建'));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(submitCount, 1);

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(find.byType(CreateOrganizationDialog), findsOneWidget);

    result.complete(const Organization(id: 2, name: '新组织'));
    await tester.pumpAndSettle();
    expect(find.byType(CreateOrganizationDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('创建请求完成前页面销毁不触发已销毁上下文', (tester) async {
    final result = Completer<Organization>();
    await _open(
      tester,
      _host(
        onSubmit: ({required String name, String? description}) => result.future,
      ),
    );

    await tester.enterText(find.byType(TextField).first, '新组织');
    await tester.tap(find.text('创建'));
    await tester.pumpWidget(const SizedBox.shrink());
    result.complete(const Organization(id: 3, name: '新组织'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
