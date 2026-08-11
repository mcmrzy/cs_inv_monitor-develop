import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_binding_service.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/device/presentation/pages/device_qr_bind_page.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mock_providers.dart';
import '../../helpers/pump_app.dart';

class MockBleAdapter extends Mock implements BleAdapter {}

class MockBleDeviceManager extends Mock implements BleDeviceManager {}

class MockBleBindingService extends Mock implements BleBindingService {}

class MockBleDeviceSession extends Mock implements BleDeviceSession {}

void main() {
  late MockBleAdapter adapter;
  late MockBleDeviceManager manager;
  late MockBleBindingService bindingService;
  late MockBleDeviceSession session;
  late DeviceBloc deviceBloc;

  // 16 位字母数字 SN（页面仅做长度/字符集与 INFO 对比，无需通过 parseSN 语义校验）
  const testSn = 'TESTSN1234567890';

  setUpAll(() {
    // any(named: 'serviceUuids'/'timeout') 需要对应类型的 fallback
    registerFallbackValue(const <String>[]);
    registerFallbackValue(const Duration(seconds: 1));
  });

  setUp(() {
    adapter = MockBleAdapter();
    manager = MockBleDeviceManager();
    bindingService = MockBleBindingService();
    session = MockBleDeviceSession();

    when(() => adapter.status).thenAnswer((_) async => BleAdapterStatus.on);
    when(
      () => adapter.scan(
        serviceUuids: any(named: 'serviceUuids'),
        timeout: any(named: 'timeout'),
      ),
    ).thenAnswer(
      (_) => Stream.value(
        const BleScanResult(
          macAddress: 'AA:BB:CC:DD:EE:FF',
          name: 'CS-Inverter',
          rssi: -55,
        ),
      ),
    );
    when(() => manager.connectDevice(any())).thenAnswer((_) async => session);
    when(() => manager.disconnectDevice(any())).thenAnswer((_) async {});
    when(() => session.readInfo()).thenAnswer(
      (_) async => <String, dynamic>{'sn': testSn, 'bound': false},
    );
    when(
      () => bindingService.bindAfterProvision(
        macAddress: any(named: 'macAddress'),
        knownSn: any(named: 'knownSn'),
        pin: any(named: 'pin'),
      ),
    ).thenAnswer((_) async => BindOutcome.bound);

    // 页面顶层 BlocConsumer<DeviceBloc> 需要真实 bloc（构造时依赖实时数据流）
    final mockRepository = MockDeviceRepository();
    final mockRealtime = MockRealtimeDataService();
    final mockCache = MockDataCacheService();
    when(() => mockRealtime.realtimeDataStream)
        .thenAnswer((_) => const Stream<InverterRealtime>.empty());
    deviceBloc = DeviceBloc(
      repository: mockRepository,
      realtimeDataService: mockRealtime,
      dataCacheService: mockCache,
    );
  });

  tearDown(() {
    deviceBloc.close();
  });

  Widget buildPage() => DeviceQrBindPage(
        sn: testSn,
        pin: '123456',
        adapter: adapter,
        manager: manager,
        bindingService: bindingService,
      );

  testWidgets('蓝牙关闭 → 显示失败态（SnackBar + 重试按钮，不崩溃）', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    when(() => adapter.status).thenAnswer((_) async => BleAdapterStatus.off);

    await pumpApp(tester, buildPage(), deviceBloc: deviceBloc);

    // SnackBar 提示蓝牙未开启（失败态页面同样展示该文案，共 2 处）
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(l10n.str('ble_bluetooth_off')),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.str('ble_bluetooth_off')), findsNWidgets(2));
    // 失败态展示重试按钮
    expect(find.text(l10n.str('ble_retry')), findsOneWidget);

    // 推进 SnackBar 生命周期，避免遗留 pending timer
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('扫描匹配成功 → 绑定成功文案', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));

    await pumpApp(tester, buildPage(), deviceBloc: deviceBloc);

    expect(find.text(l10n.str('qr_bind_title')), findsOneWidget);
    expect(find.text(l10n.str('ble_binding_success')), findsOneWidget);
    // 成功页展示 SN
    expect(find.text(testSn), findsOneWidget);
    // 结果区展示「重试」与「完成」
    expect(find.text(l10n.str('ble_retry')), findsOneWidget);
    expect(find.text(l10n.str('qr_bind_done')), findsOneWidget);

    verify(
      () => adapter.scan(
        serviceUuids: any(named: 'serviceUuids'),
        timeout: any(named: 'timeout'),
      ),
    ).called(1);
    verify(() => manager.connectDevice('AA:BB:CC:DD:EE:FF')).called(1);
    verify(
      () => bindingService.bindAfterProvision(
        macAddress: 'AA:BB:CC:DD:EE:FF',
        knownSn: testSn,
        pin: '123456',
      ),
    ).called(1);
  });

  testWidgets('扫描无匹配设备 → 未找到文案', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    when(
      () => adapter.scan(
        serviceUuids: any(named: 'serviceUuids'),
        timeout: any(named: 'timeout'),
      ),
    ).thenAnswer((_) => const Stream<BleScanResult>.empty());

    await pumpApp(tester, buildPage(), deviceBloc: deviceBloc);

    expect(find.text(l10n.str('qr_bind_not_found')), findsOneWidget);
    expect(find.text(l10n.str('ble_retry')), findsOneWidget);
    verifyNever(
      () => bindingService.bindAfterProvision(
        macAddress: any(named: 'macAddress'),
        knownSn: any(named: 'knownSn'),
        pin: any(named: 'pin'),
      ),
    );
  });

  testWidgets('扫描匹配失败（无 SN 字段）→ 未找到文案', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    when(() => session.readInfo()).thenAnswer(
      (_) async => <String, dynamic>{'bound': false},
    );

    await pumpApp(tester, buildPage(), deviceBloc: deviceBloc);

    expect(find.text(l10n.str('qr_bind_not_found')), findsOneWidget);
    verify(() => manager.connectDevice(any())).called(1);
  });

  testWidgets('匹配后绑定失败 → 绑定失败文案', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    when(
      () => bindingService.bindAfterProvision(
        macAddress: any(named: 'macAddress'),
        knownSn: any(named: 'knownSn'),
        pin: any(named: 'pin'),
      ),
    ).thenAnswer((_) async => BindOutcome.failed);

    await pumpApp(tester, buildPage(), deviceBloc: deviceBloc);

    expect(find.text(l10n.str('ble_binding_failed')), findsOneWidget);
    expect(find.text(l10n.str('qr_bind_done')), findsOneWidget);
  });

  testWidgets('点击「完成」返回上一页', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));

    // 宿主页 push 目标页，验证 pop 回到宿主
    await tester.pumpWidget(
      BlocProvider<DeviceBloc>.value(
        value: deviceBloc,
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          theme: ThemeData.light(useMaterial3: true),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => buildPage()),
                  ),
                  child: const Text('host'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // MaterialApp 本地化异步加载完成后才渲染 home，需先 settle
    await tester.pumpAndSettle();
    await tester.tap(find.text('host'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.str('qr_bind_done')));
    await tester.pumpAndSettle();

    // 已返回宿主页
    expect(find.byType(DeviceQrBindPage), findsNothing);
    expect(find.text('host'), findsOneWidget);
  });
}
