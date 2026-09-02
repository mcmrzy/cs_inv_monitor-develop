import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/device/domain/entities/device_param.dart';
import 'package:inv_app/features/device/presentation/widgets/device_param_write_dialog.dart';

import '../../../../helpers/pump_app.dart';

const _param = DeviceParam(
  key: 'grid_voltage',
  label: 'Grid voltage',
  value: 220,
  minValue: 180,
  maxValue: 260,
  unit: 'V',
  paramType: 'number',
  description: 'Target voltage',
);

Widget _host({required FutureOr<void> Function(num value) onConfirm}) {
  return Builder(
    builder: (context) => Center(
      child: ElevatedButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => DeviceParamWriteDialog(
            param: _param,
            cancelLabel: '取消',
            confirmLabel: '确认',
            onConfirm: onConfirm,
          ),
        ),
        child: const Text('打开'),
      ),
    ),
  );
}

Future<void> _openDialog(
  WidgetTester tester,
  FutureOr<void> Function(num value) onConfirm,
) async {
  await pumpMinimalApp(tester, _host(onConfirm: onConfirm));
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('弹窗关闭时释放数值输入 controller', (tester) async {
    await _openDialog(tester, (_) {});

    final controller =
        tester.widget<TextField>(find.byType(TextField)).controller!;
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byType(DeviceParamWriteDialog), findsNothing);
    expect(() => controller.addListener(() {}), throwsFlutterError);
  });

  testWidgets('确认 pending 时快速连点只提交一次', (tester) async {
    final result = Completer<void>();
    var submitCount = 0;
    await _openDialog(tester, (_) {
      submitCount++;
      return result.future;
    });

    await tester.enterText(find.byType(TextField), '230.5');
    await tester.tap(find.text('确认'));
    await tester.tap(find.text('确认'));

    expect(submitCount, 1);
    expect(find.byType(DeviceParamWriteDialog), findsOneWidget);

    result.complete();
    await tester.pumpAndSettle();

    expect(find.byType(DeviceParamWriteDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('异步确认完成时弹窗已销毁不会 setState 或 dismiss',
      (tester) async {
    final result = Completer<void>();
    await _openDialog(tester, (_) => result.future);

    await tester.tap(find.text('确认'));
    await tester.pumpWidget(const SizedBox.shrink());
    result.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
