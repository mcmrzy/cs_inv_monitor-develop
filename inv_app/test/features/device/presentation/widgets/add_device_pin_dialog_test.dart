import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/device/presentation/widgets/add_device_pin_dialog.dart';

import '../../../../helpers/pump_app.dart';

Widget _host({ValueChanged<String?>? onResult}) {
  return Builder(
    builder: (context) => Center(
      child: ElevatedButton(
        onPressed: () async {
          final result = await showDialog<String>(
            context: context,
            builder: (_) => const AddDevicePinDialog(
              title: '输入PIN',
              hintText: '6位PIN',
              invalidPinMessage: 'PIN必须为6位数字',
              cancelLabel: '取消',
              confirmLabel: '确认',
            ),
          );
          onResult?.call(result);
        },
        child: const Text('打开'),
      ),
    ),
  );
}

Future<void> _openDialog(
  WidgetTester tester, {
  ValueChanged<String?>? onResult,
}) async {
  await pumpMinimalApp(tester, _host(onResult: onResult));
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('六位PIN确认后返回', (tester) async {
    String? result;
    await _openDialog(tester, onResult: (value) => result = value);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(result, '123456');
  });

  testWidgets('空值和五位PIN均保留弹窗并显示校验错误', (tester) async {
    await _openDialog(tester);

    await tester.tap(find.text('确认'));
    await tester.pump();
    expect(find.byType(AddDevicePinDialog), findsOneWidget);
    expect(find.text('PIN必须为6位数字'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '12345');
    await tester.tap(find.text('确认'));
    await tester.pump();
    expect(find.byType(AddDevicePinDialog), findsOneWidget);
    expect(find.text('PIN必须为6位数字'), findsOneWidget);
  });

  testWidgets('关闭弹窗后释放PIN controller', (tester) async {
    await _openDialog(tester);
    final controller =
        tester.widget<TextField>(find.byType(TextField)).controller!;

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byType(AddDevicePinDialog), findsNothing);
    expect(() => controller.addListener(() {}), throwsFlutterError);
  });

  testWidgets('退场帧内重复确认只关闭一次', (tester) async {
    var resultCount = 0;
    await _openDialog(tester, onResult: (_) => resultCount++);
    await tester.enterText(find.byType(TextField), '123456');

    final confirm = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '确认'),
    );
    confirm.onPressed!();
    confirm.onPressed!();
    await tester.pumpAndSettle();

    expect(resultCount, 1);
    expect(find.text('打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
