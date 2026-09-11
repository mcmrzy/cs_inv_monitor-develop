import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/device/data/device_name_prompt_storage.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';
import 'package:inv_app/features/device/presentation/widgets/device_name_prompt_dialog.dart';
import 'package:inv_app/l10n/app_localizations.dart';

import '../../helpers/pump_app.dart';

class MockDeviceRepository extends Mock implements DeviceRepository {}

/// 用内存实现替代 SharedPreferences，聚焦弹窗与忽略记忆的联动
class FakeDeviceNamePromptStorage extends DeviceNamePromptStorage {
  FakeDeviceNamePromptStorage({this.skipped = false});

  bool skipped;
  final List<String> markedSkipped = <String>[];

  @override
  Future<bool> isSkipped(String sn) async => skipped;

  @override
  Future<void> markSkipped(String sn) async {
    markedSkipped.add(sn);
    skipped = true;
  }
}

const testSn = 'SN20250001';

void main() {
  late MockDeviceRepository repository;
  late AppLocalizations l10n;

  setUpAll(() {
    registerFallbackValue(const <String>[]);
  });

  setUp(() {
    repository = MockDeviceRepository();
  });

  /// 渲染一个按钮，点击后弹出命名引导并把结果写入 [result]
  Future<ValueNotifier<bool?>> openPrompt(
    WidgetTester tester, {
    required FakeDeviceNamePromptStorage storage,
  }) async {
    final result = ValueNotifier<bool?>(null);
    await pumpApp(
      tester,
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result.value = await DeviceNamePromptDialog.showIfNeeded(
              context,
              sn: testSn,
              repository: repository,
              storage: storage,
            );
          },
          child: const Text('open'),
        ),
      ),
    );
    l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('保存名称：调用 updateDevice 后关闭并返回 true', (tester) async {
    when(
      () => repository.updateDevice(any(), alias: any(named: 'alias')),
    ).thenAnswer((_) async => const Right(null));

    final storage = FakeDeviceNamePromptStorage();
    final result = await openPrompt(tester, storage: storage);

    expect(find.text(l10n.str('device_name_prompt_title')), findsOneWidget);
    // 弹窗内告知用户以后在哪里改
    expect(find.text(l10n.str('device_name_prompt_hint')), findsOneWidget);

    await tester.enterText(find.byType(TextField), '屋顶逆变器');
    await tester.tap(find.text(l10n.save));
    await tester.pumpAndSettle();

    expect(find.text(l10n.str('device_name_prompt_title')), findsNothing);
    verify(() => repository.updateDevice(testSn, alias: '屋顶逆变器')).called(1);
    expect(result.value, isTrue);
    expect(storage.markedSkipped, isEmpty);
  });

  testWidgets('点「暂不设置」：记住该 SN 且返回 false，不调用接口', (tester) async {
    final storage = FakeDeviceNamePromptStorage();
    final result = await openPrompt(tester, storage: storage);

    await tester.tap(find.text(l10n.str('device_name_prompt_skip')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.str('device_name_prompt_title')), findsNothing);
    expect(storage.markedSkipped, [testSn]);
    expect(result.value, isFalse);
    verifyNever(
      () => repository.updateDevice(any(), alias: any(named: 'alias')),
    );
  });

  testWidgets('名称留空后保存：等同跳过，同样不再提示', (tester) async {
    final storage = FakeDeviceNamePromptStorage();
    final result = await openPrompt(tester, storage: storage);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text(l10n.save));
    await tester.pumpAndSettle();

    expect(find.text(l10n.str('device_name_prompt_title')), findsNothing);
    expect(storage.markedSkipped, [testSn]);
    expect(result.value, isFalse);
    verifyNever(
      () => repository.updateDevice(any(), alias: any(named: 'alias')),
    );
  });

  testWidgets('已忽略过的设备：直接返回 false，不弹窗', (tester) async {
    final storage = FakeDeviceNamePromptStorage(skipped: true);
    final result = await openPrompt(tester, storage: storage);

    expect(find.text(l10n.str('device_name_prompt_title')), findsNothing);
    expect(result.value, isFalse);
    verifyNever(
      () => repository.updateDevice(any(), alias: any(named: 'alias')),
    );
  });

  testWidgets('保存失败：弹窗保留并提示错误', (tester) async {
    when(
      () => repository.updateDevice(any(), alias: any(named: 'alias')),
    ).thenAnswer((_) async => const Left(ServerFailure('boom')));

    final storage = FakeDeviceNamePromptStorage();
    final result = await openPrompt(tester, storage: storage);

    await tester.enterText(find.byType(TextField), '屋顶逆变器');
    await tester.tap(find.text(l10n.save));
    await tester.pumpAndSettle();

    // 失败时不能把用户输入丢掉，也不能记为「已忽略」
    expect(find.text(l10n.str('device_name_prompt_title')), findsOneWidget);
    expect(storage.markedSkipped, isEmpty);
    expect(result.value, isNull);
  });
}
