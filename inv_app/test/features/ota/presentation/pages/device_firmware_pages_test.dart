import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_history.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/presentation/pages/device_firmware_detail_page.dart';
import 'package:inv_app/features/ota/presentation/pages/ota_tab_page.dart';
import 'package:inv_app/l10n/app_localizations.dart';

void main() {
  Widget localizedApp(
    Widget child, {
    Locale locale = const Locale('zh', 'CN'),
    TextScaler textScaler = TextScaler.noScaling,
    ThemeData? theme,
  }) =>
      MaterialApp(
        locale: locale,
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      );
  Widget app(Widget child) => localizedApp(child);

  testWidgets('firmware hub leads with devices and keeps secondary tools',
      (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(OtaTabPage(repository: _DeviceRepo())));
    await tester.pumpAndSettle();

    expect(find.text('设备固件升级'), findsOneWidget);
    expect(find.text('选择设备查看固件状态与更新记录'), findsOneWidget);
    expect(find.text('我的设备'), findsOneWidget);
    expect(find.text('屋顶逆变器'), findsOneWidget);
    expect(find.text('检查全部更新'), findsOneWidget);
    expect(find.text('近场连接升级'), findsOneWidget);
    expect(find.text('固件资源'), findsOneWidget);
    expect(find.text('全部更新记录'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('firmwareDeviceTotal')))
          .textSpan
          ?.toPlainText(),
      '1  设备总数',
    );
    final heroImageFinder = find.byWidgetPredicate((widget) {
      if (widget is! Image || widget.image is! ResizeImage) return false;
      final provider = widget.image as ResizeImage;
      return provider.imageProvider is AssetImage &&
          (provider.imageProvider as AssetImage).assetName ==
              CsergyAssets.xiaoshuoOtaGuide;
    });
    expect(heroImageFinder, findsOneWidget);
    final heroImage = tester.widget<Image>(heroImageFinder);
    expect((heroImage.image as ResizeImage).width, 248);
    expect(tester.takeException(), isNull);
  });

  testWidgets('firmware hub does not report zero devices before first load',
      (tester) async {
    final repository = _PendingListDeviceRepo();
    await tester.pumpWidget(app(OtaTabPage(repository: repository)));
    await tester.pump();

    final total = tester.widget<Text>(
      find.byKey(const Key('firmwareDeviceTotal')),
    );
    expect(total.textSpan?.toPlainText(), startsWith('—'));
  });

  testWidgets('firmware hub keeps total unknown after first-load failure',
      (tester) async {
    await tester.pumpWidget(app(OtaTabPage(repository: _FailedListDeviceRepo())));
    await tester.pumpAndSettle();

    final total = tester.widget<Text>(
      find.byKey(const Key('firmwareDeviceTotal')),
    );
    expect(total.textSpan?.toPlainText(), startsWith('—'));
  });

  testWidgets('firmware hub does not infer total when success omits total',
      (tester) async {
    await tester.pumpWidget(app(OtaTabPage(repository: _MissingTotalRepo())));
    await tester.pumpAndSettle();

    expect(find.text('屋顶逆变器'), findsOneWidget);
    final total = tester.widget<Text>(
      find.byKey(const Key('firmwareDeviceTotal')),
    );
    expect(total.textSpan?.toPlainText(), startsWith('—'));
  });

  testWidgets('firmware hub has no overflow in English at 1.5 text scale',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(localizedApp(
      OtaTabPage(repository: _DeviceRepo()),
      locale: const Locale('en'),
      textScaler: const TextScaler.linear(1.5),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('All Update Records'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('firmware hub has no overflow in Chinese at 1.5 text scale',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(localizedApp(
      OtaTabPage(repository: _DeviceRepo()),
      textScaler: const TextScaler.linear(1.5),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('全部更新记录'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('device page shows device data, functional modules and history',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(DeviceFirmwareDetailPage(
      deviceSN: 'INV-001',
      deviceRepository: _DeviceRepo(),
      otaRepository: _OtaRepo(),
    )));
    await tester.pumpAndSettle();

    for (final text in [
      '设备型号',
      '设备名称',
      '设备序列号',
      '硬件版本',
      // 展示名统一为「中文模块名（芯片）」，见 e14f20575
      '通信采集（ESP）',
      '系统中控（ARM）',
      '计算控制（DSP）',
      '电池管理（BMS）',
    ]) {
      expect(find.text(text), findsWidgets);
    }
    await tester.scrollUntilVisible(
      find.text('改善弱网重连稳定性'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('改善弱网重连稳定性'), findsOneWidget);
  });

  testWidgets('device summary uses a light brand surface without heavy shadow',
      (tester) async {
    await tester.pumpWidget(app(DeviceFirmwareDetailPage(
      deviceSN: 'INV-001',
      deviceRepository: _DeviceRepo(),
      otaRepository: _OtaRepo(),
    )));
    await tester.pumpAndSettle();

    final hero = tester.widget<Container>(
      find.byKey(const Key('deviceFirmwareHero')),
    );
    final decoration = hero.decoration as BoxDecoration;
    final gradient = decoration.gradient as LinearGradient;
    expect(gradient.colors, isNot(contains(const Color(0xFF0D47A1))));
    expect(decoration.boxShadow, anyOf(isNull, isEmpty));
    final status = tester.widget<Text>(
      find.byKey(const Key('deviceFirmwareStatusLabel')),
    );
    expect(status.style?.color, AppColors.success);
  });

  testWidgets('device summary remains readable in dark theme', (tester) async {
    await tester.pumpWidget(localizedApp(
      DeviceFirmwareDetailPage(
        deviceSN: 'INV-001',
        deviceRepository: _DeviceRepo(),
        otaRepository: _OtaRepo(),
      ),
      theme: ThemeData.dark(),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('deviceFirmwareHero')), findsOneWidget);
    final status = tester.widget<Text>(
      find.byKey(const Key('deviceFirmwareStatusLabel')),
    );
    expect(status.style?.color, AppColors.successLight);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'realtime offline status disables the in-flow update action and explains why',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(DeviceFirmwareDetailPage(
      deviceSN: 'INV-001',
      deviceRepository: _DeviceRepo(status: 1, realtimeOnline: false),
      otaRepository: _OtaRepo(),
    )));
    await tester.pumpAndSettle();

    expect(find.text('离线'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('检查固件更新'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('设备当前离线，联网后可检查固件更新'), findsOneWidget);
    final action = find.widgetWithText(FilledButton, '检查固件更新');
    expect(action, findsOneWidget);
    expect(tester.widget<FilledButton>(action).onPressed, isNull);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar,
      isNull,
    );
    expect(
      find.ancestor(of: action, matching: find.byType(ListView)),
      findsOneWidget,
    );
  });

  testWidgets('online device update action keeps routing to the update flow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/device',
      routes: [
        GoRoute(
          path: '/device',
          builder: (context, state) => DeviceFirmwareDetailPage(
            deviceSN: 'INV-001',
            deviceRepository: _DeviceRepo(status: 1, realtimeOnline: true),
            otaRepository: _OtaRepo(),
          ),
        ),
        GoRoute(
          path: '/ota/:sn',
          builder: (context, state) =>
              Text('update:${state.pathParameters['sn']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('检查固件更新'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, '检查固件更新'));
    await tester.pumpAndSettle();

    expect(find.text('update:INV-001'), findsOneWidget);
  });

  testWidgets('device status is used when realtime online status is absent',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(DeviceFirmwareDetailPage(
      deviceSN: 'INV-001',
      deviceRepository: _DeviceRepo(status: 2, realtimeOnline: null),
      otaRepository: _OtaRepo(),
    )));
    await tester.pumpAndSettle();

    expect(find.text('在线'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('检查固件更新'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final action = find.widgetWithText(FilledButton, '检查固件更新');
    expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
  });

  testWidgets('update action is disabled while refresh loads and after failure',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _RefreshingDeviceRepo();
    await tester.pumpWidget(app(DeviceFirmwareDetailPage(
      deviceSN: 'INV-001',
      deviceRepository: repository,
      otaRepository: _OtaRepo(),
    )));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('检查固件更新'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    FilledButton action() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '检查固件更新'),
        );
    expect(action().onPressed, isNotNull);

    final refresh =
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
    final refreshFuture = refresh.onRefresh();
    await tester.pump();
    expect(action().onPressed, isNull);

    repository.refreshResult
        .complete(const Left(ServerFailure('refresh failed')));
    await refreshFuture;
    await tester.pumpAndSettle();
    expect(action().onPressed, isNull);
  });

  testWidgets('update action is the final list content after the update log',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(DeviceFirmwareDetailPage(
      deviceSN: 'INV-001',
      deviceRepository: _DeviceRepo(),
      otaRepository: _OtaRepo(),
    )));
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(
      find.byKey(const Key('deviceFirmwareDetailList')),
    );
    final children =
        (list.childrenDelegate as SliverChildListDelegate).children;
    final logIndex = children.indexWhere(
      (child) => child.key == const Key('firmwareUpdateLogHeader'),
    );
    final actionIndex = children.indexWhere(
      (child) => child.key == const Key('firmwareUpdateAction'),
    );

    expect(logIndex, greaterThanOrEqualTo(0));
    expect(actionIndex, greaterThan(logIndex));
    expect(actionIndex, children.length - 1);
  });

  testWidgets('english large text layout has no overflow at 390 by 844',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(localizedApp(
      DeviceFirmwareDetailPage(
        deviceSN: 'INV-001',
        deviceRepository: _DeviceRepo(),
        otaRepository: _OtaRepo(),
      ),
      locale: const Locale('en'),
      textScaler: const TextScaler.linear(1.5),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('Check for Firmware Updates'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('chinese large text layout has no overflow at 390 by 844',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(localizedApp(
      DeviceFirmwareDetailPage(
        deviceSN: 'INV-001',
        deviceRepository: _DeviceRepo(),
        otaRepository: _OtaRepo(),
      ),
      textScaler: const TextScaler.linear(1.5),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('检查固件更新'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _DeviceRepo implements DeviceRepository {
  _DeviceRepo({this.status = 1, this.realtimeOnline = true});

  final int status;
  final bool? realtimeOnline;

  @override
  Future<Either<Failure, Map<String, dynamic>>> getList({
    int? stationId,
    int? status,
    int page = 1,
    int pageSize = 20,
  }) async =>
      const Right({
        'items': [
          {'sn': 'INV-001', 'alias': '屋顶逆变器', 'model': 'CS-10K', 'status': 1},
        ],
        'total': 1,
      });

  @override
  Future<Either<Failure, Map<String, dynamic>>> getDetail(String sn) async {
    final detail = <String, dynamic>{
      'device': {
        'sn': 'INV-001',
        'alias': '屋顶逆变器',
        'model': 'CS-10K',
        'status': status,
        'hardware_version': 'H2.1',
        'firmware_esp': '1.2.0',
        'firmware_arm': '2.3.0',
        'firmware_dsp': '3.1.0',
        'firmware_bms': '4.0.1',
      },
    };
    if (realtimeOnline != null) {
      detail['online_status'] = {'online': realtimeOnline};
    }
    return Right(detail);
  }

  @override
  InverterRealtime? parseRealtimeData(dynamic raw) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingListDeviceRepo extends _DeviceRepo {
  final result = Completer<Either<Failure, Map<String, dynamic>>>();

  @override
  Future<Either<Failure, Map<String, dynamic>>> getList({
    int? stationId,
    int? status,
    int page = 1,
    int pageSize = 20,
  }) =>
      result.future;
}

class _FailedListDeviceRepo extends _DeviceRepo {
  @override
  Future<Either<Failure, Map<String, dynamic>>> getList({
    int? stationId,
    int? status,
    int page = 1,
    int pageSize = 20,
  }) async =>
      const Left(ServerFailure('load failed'));
}

class _MissingTotalRepo extends _DeviceRepo {
  @override
  Future<Either<Failure, Map<String, dynamic>>> getList({
    int? stationId,
    int? status,
    int page = 1,
    int pageSize = 20,
  }) async =>
      const Right({
        'items': [
          {'sn': 'INV-001', 'alias': '屋顶逆变器', 'model': 'CS-10K'},
        ],
      });
}

class _RefreshingDeviceRepo extends _DeviceRepo {
  _RefreshingDeviceRepo() : super(status: 1, realtimeOnline: true);

  final refreshResult = Completer<Either<Failure, Map<String, dynamic>>>();
  int callCount = 0;

  @override
  Future<Either<Failure, Map<String, dynamic>>> getDetail(String sn) {
    if (callCount++ == 0) return super.getDetail(sn);
    return refreshResult.future;
  }
}

class _OtaRepo implements OtaRepository {
  @override
  Future<Either<Failure, DeviceFirmwareHistoryPage>> getDeviceHistory(
    String sn, {
    int page = 1,
    int pageSize = 20,
  }) async =>
      Right(DeviceFirmwareHistoryPage(
        items: [
          DeviceFirmwareHistory(
            id: 1,
            deviceSn: sn,
            target: 'esp',
            oldVersion: '1.1.0',
            newVersion: '1.2.0',
            status: 'success',
            changelog: '改善弱网重连稳定性',
            updatedAt: DateTime.utc(2026, 9, 10),
          ),
        ],
        total: 1,
        page: page,
        pageSize: pageSize,
      ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
