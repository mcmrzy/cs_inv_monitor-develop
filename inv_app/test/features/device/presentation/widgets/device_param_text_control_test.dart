import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/device/domain/entities/device_param.dart';
import 'package:inv_app/features/device/presentation/widgets/device_param_text_control.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  testWidgets('parent rebuild preserves draft text and cursor', (tester) async {
    final hostKey = GlobalKey<_TextControlHostState>();
    final changes = <MapEntry<String, String>>[];

    await pumpMinimalApp(
      tester,
      _TextControlHost(
        key: hostKey,
        initialValue: 'server value',
        onChanged: (key, value) => changes.add(MapEntry(key, value)),
      ),
    );

    final controllerBefore =
        tester.widget<TextField>(find.byType(TextField)).controller!;
    await tester.tap(find.byType(TextField));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'local draft',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    hostKey.currentState!.setExternalValue('local draft');
    await tester.pump();
    hostKey.currentState!.rebuildParent();
    await tester.pump();

    final controllerAfter =
        tester.widget<TextField>(find.byType(TextField)).controller!;
    expect(identical(controllerAfter, controllerBefore), isTrue);
    expect(controllerAfter.text, 'local draft');
    expect(
      controllerAfter.selection,
      const TextSelection.collapsed(offset: 5),
    );
    expect(changes.single.key, 'wifi_ssid');
    expect(changes.single.value, 'local draft');
  });

  testWidgets('external value change updates text and moves cursor to end',
      (tester) async {
    final hostKey = GlobalKey<_TextControlHostState>();

    await pumpMinimalApp(
      tester,
      _TextControlHost(
        key: hostKey,
        initialValue: 'old value',
        onChanged: (_, __) {},
      ),
    );

    final controllerBefore =
        tester.widget<TextField>(find.byType(TextField)).controller!;
    await tester.tap(find.byType(TextField));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'local draft',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();

    hostKey.currentState!.setExternalValue('server replacement');
    await tester.pump();

    final controllerAfter =
        tester.widget<TextField>(find.byType(TextField)).controller!;
    expect(identical(controllerAfter, controllerBefore), isTrue);
    expect(controllerAfter.text, 'server replacement');
    expect(
      controllerAfter.selection,
      TextSelection.collapsed(offset: 'server replacement'.length),
    );
  });

  testWidgets('disposing the control releases its editing state without error',
      (tester) async {
    await pumpMinimalApp(
      tester,
      _TextControlHost(
        initialValue: 'value',
        onChanged: (_, __) {},
      ),
    );

    await tester.tap(find.byType(TextField));
    final controller =
        tester.widget<TextField>(find.byType(TextField)).controller!;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(() => controller.addListener(() {}), throwsFlutterError);
  });
}

class _TextControlHost extends StatefulWidget {
  const _TextControlHost({
    super.key,
    required this.initialValue,
    required this.onChanged,
  });

  final String initialValue;
  final void Function(String key, String value) onChanged;

  @override
  State<_TextControlHost> createState() => _TextControlHostState();
}

class _TextControlHostState extends State<_TextControlHost> {
  late String _externalValue;

  @override
  void initState() {
    super.initState();
    _externalValue = widget.initialValue;
  }

  void rebuildParent() => setState(() {});

  void setExternalValue(String value) {
    setState(() => _externalValue = value);
  }

  @override
  Widget build(BuildContext context) {
    return DeviceParamTextControl(
      param: const DeviceParam(
        key: 'wifi_ssid',
        label: 'Wi-Fi SSID',
        value: 'server value',
        paramType: 'text',
      ),
      value: _externalValue,
      onChanged: widget.onChanged,
    );
  }
}
