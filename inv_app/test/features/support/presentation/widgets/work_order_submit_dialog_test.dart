import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:inv_app/features/support/presentation/widgets/work_order_submit_dialog.dart';
import 'package:inv_app/l10n/app_localizations.dart';

const _templates = <Map<String, dynamic>>[
  {
    'templateId': 'repair',
    'title': '设备故障',
    'description': '设备运行异常，需要检修',
    'priority': 'high',
  },
];

Widget _host({
  Future<List<XFile>> Function()? pickImages,
  ValueChanged<WorkOrderSubmitData>? onSubmitted,
}) {
  return ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              const Text('base-route'),
              ElevatedButton(
                onPressed: () async {
                  final data = await showDialog<WorkOrderSubmitData>(
                    context: context,
                    builder: (_) => WorkOrderSubmitDialog(
                      templates: _templates,
                      deviceOptions: const [('SN-001', '客厅逆变器')],
                      pickImages: pickImages,
                    ),
                  );
                  if (data != null) onSubmitted?.call(data);
                },
                child: const Text('打开'),
              ),
            ],
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
  testWidgets('弹窗关闭时释放标题和描述 controllers', (tester) async {
    await _open(tester, _host());

    final controllers = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .map((field) => field.controller)
        .toList();
    expect(controllers, hasLength(2));

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    for (final controller in controllers) {
      expect(() => controller.addListener(() {}), throwsFlutterError);
    }
  });

  testWidgets('图片选择返回时弹窗已关闭不更新销毁状态', (tester) async {
    final picked = Completer<List<XFile>>();
    await _open(tester, _host(pickImages: () => picked.future));

    await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    picked.complete(const []);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('图片选择 pending 时快速连点只启动一次', (tester) async {
    final picked = Completer<List<XFile>>();
    var pickCount = 0;
    await _open(
      tester,
      _host(
        pickImages: () {
          pickCount++;
          return picked.future;
        },
      ),
    );

    final addImage = find.byIcon(Icons.add_photo_alternate_outlined);
    await tester.tap(addImage);
    await tester.tap(addImage);

    expect(pickCount, 1);

    picked.complete(const []);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('退场期间快速连点提交只返回一次且不误退底层页', (tester) async {
    var submittedCount = 0;
    WorkOrderSubmitData? submittedData;
    await _open(
      tester,
      _host(
        onSubmitted: (data) {
          submittedCount++;
          submittedData = data;
        },
      ),
    );

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '故障标题');
    await tester.enterText(fields.at(1), '故障描述');

    final submit = find.byType(FilledButton);
    await tester.tap(submit);
    await tester.tap(submit, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(submittedCount, 1);
    expect(submittedData?.title, '故障标题');
    expect(submittedData?.description, '故障描述');
    expect(submittedData?.templateType, 'repair');
    expect(submittedData?.priority, 'medium');
    expect(submittedData?.deviceSn, isEmpty);
    expect(submittedData?.images, isEmpty);
    expect(find.text('base-route'), findsOneWidget);
    expect(find.byType(WorkOrderSubmitDialog), findsNothing);
  });
}
