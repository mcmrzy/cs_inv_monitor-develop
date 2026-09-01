import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/device/presentation/pages/device_control_page.dart';

import '../../../../helpers/pump_app.dart';

Widget _host({required SaveDeviceSchedule onSave}) {
  return Builder(
    builder: (context) => Center(
      child: ElevatedButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => DeviceScheduleDialog(
            title: '编辑计划',
            initialStart: '08:00',
            initialEnd: '10:00',
            initialMode: 'charge',
            startLabel: '开始时间',
            startHint: 'HH:mm',
            endLabel: '结束时间',
            endHint: 'HH:mm',
            modeLabel: '模式',
            modeHint: 'charge/discharge',
            cancelLabel: '取消',
            saveLabel: '保存',
            onSave: onSave,
          ),
        ),
        child: const Text('打开'),
      ),
    ),
  );
}

Future<void> _open(
  WidgetTester tester,
  SaveDeviceSchedule onSave,
) async {
  await pumpMinimalApp(tester, _host(onSave: onSave));
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('取消时释放三个输入 controller', (tester) async {
    await _open(tester, (_, __, ___) => true);

    final controllers = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .map((field) => field.controller)
        .toList();
    expect(controllers, hasLength(3));

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    for (final controller in controllers) {
      expect(() => controller.addListener(() {}), throwsFlutterError);
    }
  });

  testWidgets('保存 pending 时快速连点只提交一次', (tester) async {
    final result = Completer<bool>();
    var submitCount = 0;
    await _open(tester, (start, end, mode) {
      submitCount++;
      expect(start, '08:00');
      expect(end, '10:00');
      expect(mode, 'charge');
      return result.future;
    });

    await tester.tap(find.text('保存'));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(submitCount, 1);
    expect(find.byType(DeviceScheduleDialog), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(find.byType(DeviceScheduleDialog), findsOneWidget);

    result.complete(true);
    await tester.pumpAndSettle();

    expect(find.byType(DeviceScheduleDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存失败时保留输入并允许重试', (tester) async {
    var submitCount = 0;
    await _open(tester, (start, end, mode) {
      submitCount++;
      return false;
    });

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '09:30');
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(submitCount, 1);
    expect(find.byType(DeviceScheduleDialog), findsOneWidget);
    expect(tester.widget<TextField>(fields.at(0)).controller!.text, '09:30');

    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(submitCount, 2);
  });

  testWidgets('异步保存完成前页面销毁不访问已失效 Navigator',
      (tester) async {
    final result = Completer<bool>();
    await _open(tester, (_, __, ___) => result.future);

    await tester.tap(find.text('保存'));
    await tester.pumpWidget(const SizedBox.shrink());
    result.complete(true);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
