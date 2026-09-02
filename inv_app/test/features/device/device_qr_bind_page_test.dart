import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_binding_service.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';
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

class MockDeviceRepositoryBind extends Mock implements DeviceRepository {}

void main() {
  late MockBleAdapter adapter;
  late MockBleDeviceManager manager;
  late MockBleBindingService bindingService;
  late MockBleDeviceSession session;
  late MockDeviceRepositoryBind mockDeviceRepo;
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
    mockDeviceRepo = MockDeviceRepositoryBind();

    // 默认：云端绑定成功
    when(
      () => mockDeviceRepo.bind(any(), any(), pin: any(named: 'pin')),
    ).thenAnswer((_) async => const Right(null));

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
        deviceRepository: mockDeviceRepo,
      );

  testWidgets('云端绑定成功 → 直接显示成功文案', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));

    await pumpApp(tester, buildPage(), deviceBloc: deviceBloc);

    // 云端绑定成功，显示 done 页面
    expect(find.text(l10n.str('qr_bind_title')), findsOneWidget);
    expect(find.text(l10n.str('ble_binding_success')), findsOneWidget);
    // 成功页展示 SN
    expect(find.text(testSn), findsOneWidget);
    // 首次成功后只允许完成，不再暴露重复绑定入口。
    expect(find.text(l10n.str('ble_retry')), findsNothing);
    expect(find.text(l10n.str('qr_bind_done')), findsOneWidget);

    // 云端绑定被调用，BLE 未被调用
    verify(
      () => mockDeviceRepo.bind(testSn, null, pin: '123456'),
    ).called(1);
    verifyNever(
      () => adapter.scan(
        serviceUuids: any(named: 'serviceUuids'),
        timeout: any(named: 'timeout'),
      ),
    );
  });

  testWidgets('云端绑定失败 → 显示 cloudFailed 界面（重试云端 / 尝试BLE / 返回）', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    // 云端绑定返回 404 设备未注册
    when(
      () => mockDeviceRepo.bind(any(), any(), pin: any(named: 'pin')),
    ).thenAnswer((_) async => const Left(NotFoundFailure('device not found')));

    await pumpApp(tester, buildPage(), deviceBloc: deviceBloc);

    // cloudFailed 界面展示错误图标和按钮
    expect(find.text(l10n.str('ble_retry')), findsOneWidget); // 重试云端
    expect(find.text(l10n.qrBindTryBle), findsOneWidget); // 尝试 BLE
    expect(find.text(l10n.qrBindBack), findsOneWidget); // 返回
    // BLE 扫描未被调用
    verifyNever(
      () => adapter.scan(
        serviceUuids: any(named: 'serviceUuids'),
        timeout: any(named: 'timeout'),
      ),
    );
  });

  testWidgets('云端失败后点击「尝试BLE」→ BLE 扫描绑定成功', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    // 云端绑定失败
    when(
      () => mockDeviceRepo.bind(any(), any(), pin: any(named: 'pin')),
    ).thenAnswer((_) async => const Left(NotFoundFailure('device not found')));

    await pumpApp(tester, buildPage(), deviceBloc: deviceBloc);

    // 点击「尝试BLE扫描」
    await tester.tap(find.text(l10n.qrBindTryBle));
    await tester.pumpAndSettle();

    // BLE 绑定成功
    expect(find.text(l10n.str('ble_binding_success')), findsOneWidget);
    expect(find.text(testSn), findsOneWidget);

    // 验证 BLE 流程被调用
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

  testWidgets('云端失败后BLE扫描无匹配设备 → 未找到文案', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    // 云端绑定失败
    when(
      () => mockDeviceRepo.bind(any(), any(), pin: any(named: 'pin')),
    ).thenAnswer((_) async => const Left(NotFoundFailure('device not found')));
    // BLE 扫描返回空
    when(
      () => adapter.scan(
        serviceUuids: any(named: 'serviceUuids'),
        timeout: any(named: 'timeout'),
      ),
    ).thenAnswer((_) => const Stream<BleScanResult>.empty());

    await pumpApp(tester, buildPage(), deviceBloc: deviceBloc);

    // 点击「尝试BLE扫描」
    await tester.tap(find.text(l10n.qrBindTryBle));
    await tester.pumpAndSettle();

    // BLE 失败，展示未找到
    expect(find.text(l10n.str('qr_bind_not_found')), findsOneWidget);
    expect(find.text(l10n.str('ble_retry')), findsOneWidget); // BLE 重试
    expect(find.text(l10n.cloudBindFallback), findsOneWidget); // 回到云端
    verifyNever(
      () => bindingService.bindAfterProvision(
        macAddress: any(named: 'macAddress'),
        knownSn: any(named: 'knownSn'),
        pin: any(named: 'pin'),
      ),
    );
  });

  testWidgets('云端失败后BLE匹配失败（无SN字段）→ 未找到文案', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    // 云端绑定失败
    when(
      () => mockDeviceRepo.bind(any(), any(), pin: any(named: 'pin')),
    ).thenAnswer((_) async => const Left(NotFoundFailure('device not found')));
    // BLE 设备 INFO 无 SN 字段
    when(() => session.readInfo()).thenAnswer(
      (_) async => <String, dynamic>{'bound': false},
    );

    await pumpApp(tester, buildPage(), deviceBloc: deviceBloc);

    // 点击「尝试BLE扫描」
    await tester.tap(find.text(l10n.qrBindTryBle));
    await tester.pumpAndSettle();

    expect(find.text(l10n.str('qr_bind_not_found')), findsOneWidget);
    verify(() => manager.connectDevice(any())).called(1);
  });

  testWidgets('云端失败后BLE匹配绑定失败 → 绑定失败文案', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    // 云端绑定失败
    when(
      () => mockDeviceRepo.bind(any(), any(), pin: any(named: 'pin')),
    ).thenAnswer((_) async => const Left(NotFoundFailure('device not found')));
    // BLE 绑定返回失败
    when(
      () => bindingService.bindAfterProvision(
        macAddress: any(named: 'macAddress'),
        knownSn: any(named: 'knownSn'),
        pin: any(named: 'pin'),
      ),
    ).thenAnswer((_) async => BindOutcome.failed);

    await pumpApp(tester, buildPage(), deviceBloc: deviceBloc);

    // 点击「尝试BLE扫描」
    await tester.tap(find.text(l10n.qrBindTryBle));
    await tester.pumpAndSettle();

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
