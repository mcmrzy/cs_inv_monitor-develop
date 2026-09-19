// 设备调试页 widget 测试
//
// 注入手写 FakeDeviceDebugApi（不依赖 mocktail），覆盖：
// 1. 无会话 → 显示「未开启」；点开始 → fake 收到 startDebugSession（默认 1 小时）
// 2. active 会话 + 样本 → 渲染上下两张 LineChart；选线 Chip 勾选/取消改变曲线数量
// 3. 点停止 → fake 收到 stopDebugSession（携带会话 id）
//
// 视口写法参照 history_chart_page_test：tester.view.physicalSize /
// devicePixelRatio=1.0 / addTearDown(tester.view.reset)，不用 setSurfaceSize、
// 不 pump 长时长（页面轮询 Timer 由 dispose 取消，不会遗留 pending timer）。

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/device/data/device_debug_api.dart';
import 'package:inv_app/features/device/presentation/pages/device_debug_page.dart';
import 'package:inv_app/l10n/app_localizations.dart';

import '../../helpers/pump_app.dart';

/// 手写 Fake：记录调用并模拟后端会话状态迁移
class FakeDeviceDebugApi implements DeviceDebugApi {
  FakeDeviceDebugApi({
    required this.initialInfo,
    required this.samplesPage,
    this.startError,
    this.stopError,
  });

  DeviceDebugSessionInfo initialInfo;
  DeviceDebugSamplesPage samplesPage;
  Object? startError;
  Object? stopError;

  int startCalls = 0;
  int stopCalls = 0;
  final List<int> startDurations = [];
  final List<String> startRequestIds = [];
  String? lastStoppedSessionId;

  @override
  Future<DeviceDebugSessionInfo> getDebugSession(String sn) async =>
      initialInfo;

  @override
  Future<DeviceDebugSessionStartResult> startDebugSession(
    String sn, {
    required int durationSeconds,
    required String requestId,
  }) async {
    startCalls++;
    startDurations.add(durationSeconds);
    startRequestIds.add(requestId);
    final err = startError;
    if (err != null) throw err;
    // 模拟后端：开始成功即返回 active 会话
    final session = DeviceDebugSession(
      id: 'sess-new',
      deviceSn: sn,
      status: 'active',
      intervalSeconds: 30,
      durationSeconds: durationSeconds,
      startedAt: DateTime.now().toUtc(),
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: durationSeconds)),
      source: 'app',
    );
    initialInfo = DeviceDebugSessionInfo(
      session: session,
      deviceOnline: true,
      supported: true,
      intervalSeconds: 30,
    );
    return DeviceDebugSessionStartResult(session: session);
  }

  @override
  Future<DeviceDebugSession?> stopDebugSession(String sn, String sessionId) async {
    stopCalls++;
    lastStoppedSessionId = sessionId;
    final err = stopError;
    if (err != null) throw err;
    final current = initialInfo.session;
    final stopped = current == null
        ? null
        : DeviceDebugSession(
            id: current.id,
            deviceSn: current.deviceSn,
            status: 'stopped',
            intervalSeconds: current.intervalSeconds,
            durationSeconds: current.durationSeconds,
            startedAt: current.startedAt,
            expiresAt: current.expiresAt,
            stoppedAt: DateTime.now().toUtc(),
            requestedBy: current.requestedBy,
            source: current.source,
            startTaskId: current.startTaskId,
            stopTaskId: current.stopTaskId,
            lastSampleAt: current.lastSampleAt,
            failureReason: current.failureReason,
            createdAt: current.createdAt,
            updatedAt: current.updatedAt,
          );
    initialInfo = DeviceDebugSessionInfo(
      session: stopped,
      deviceOnline: true,
      supported: true,
      intervalSeconds: 30,
    );
    return stopped;
  }

  @override
  Future<DeviceDebugSamplesPage> getDebugSamples(
    String sn, {
    String? sessionId,
    int windowMinutes = 15,
    String? after,
    int limit = 200,
  }) async =>
      samplesPage;
}

DeviceDebugSession activeSession({String id = 'sess-1'}) => DeviceDebugSession(
      id: id,
      deviceSn: 'SN-DEBUG-1',
      status: 'active',
      intervalSeconds: 30,
      durationSeconds: 3600,
      startedAt: DateTime.now().toUtc(),
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 50)),
      source: 'app',
    );

DeviceDebugSample sampleAt(
  DateTime time, {
  double? pv1Voltage,
  double? buck1Current,
  double? batteryVoltage,
  double? batteryCurrent,
  double? acVoltage,
  double? acCurrent,
}) =>
    DeviceDebugSample(
      time: time.toUtc(),
      metrics: DeviceDebugMetrics(
        pv1Voltage: pv1Voltage,
        buck1Current: buck1Current,
        batteryVoltage: batteryVoltage,
        batteryCurrent: batteryCurrent,
        acVoltage: acVoltage,
        acCurrent: acCurrent,
      ),
    );

List<DeviceDebugSample> threeSamples() {
  final base = DateTime(2026, 9, 20, 10, 0, 0);
  return [
    sampleAt(
      base,
      pv1Voltage: 60.0,
      buck1Current: 8.0,
      batteryVoltage: 51.2,
      batteryCurrent: 5.0,
      acVoltage: 230.0,
      acCurrent: 1.5,
    ),
    sampleAt(
      base.add(const Duration(seconds: 30)),
      pv1Voltage: 60.5,
      buck1Current: 8.1,
      batteryVoltage: 51.3,
      batteryCurrent: 5.2,
      acVoltage: 229.8,
      acCurrent: 1.6,
    ),
    sampleAt(
      base.add(const Duration(seconds: 60)),
      pv1Voltage: 60.2,
      buck1Current: 7.9,
      batteryVoltage: 51.1,
      batteryCurrent: 5.1,
      acVoltage: 230.2,
      acCurrent: 1.4,
    ),
  ];
}

/// 放大视口（页面含双图与状态卡，800x600 会溢出）；
/// 用 tester.view 而非 setSurfaceSize，避免冻结 timer
void useLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(375, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 点击选线 Chip（按 label 定位其 FilterChip 祖先，避免命中 Text 触发告警）
Future<void> tapGroupChip(WidgetTester tester, String label) async {
  await tester.tap(
    find.ancestor(
      of: find.text(label),
      matching: find.byType(FilterChip),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('无会话显示「未开启」，点开始触发 startDebugSession（默认 1 小时）',
      (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    final api = FakeDeviceDebugApi(
      initialInfo: const DeviceDebugSessionInfo(
        session: null,
        deviceOnline: true,
        supported: true,
        intervalSeconds: 30,
      ),
      samplesPage: const DeviceDebugSamplesPage(items: [], nextCursor: ''),
    );
    useLargeViewport(tester);

    await pumpMinimalApp(tester, DeviceDebugPage(sn: 'SN-DEBUG-1', api: api));

    // 无会话 → 未开启徽标，无曲线，显示开始按钮
    expect(find.text(l10n.str('debug_status_not_started')), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
    expect(find.text(l10n.str('debug_start')), findsOneWidget);

    await tester.tap(find.text(l10n.str('debug_start')));
    await tester.pump();
    await tester.pump();

    expect(api.startCalls, 1);
    expect(api.startDurations.first, 3600); // 默认 1 小时
    expect(api.startRequestIds.first, isNotEmpty);

    // 开始成功 → 徽标变为已开启，出现停止按钮
    expect(find.text(l10n.str('debug_status_active')), findsOneWidget);
    expect(find.text(l10n.str('debug_stop')), findsOneWidget);
  });

  testWidgets('active 会话+样本渲染两张同步折线图，chips 可勾选切换曲线数量',
      (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    final api = FakeDeviceDebugApi(
      initialInfo: DeviceDebugSessionInfo(
        session: activeSession(),
        deviceOnline: true,
        supported: true,
        intervalSeconds: 30,
      ),
      samplesPage: DeviceDebugSamplesPage(
        items: threeSamples(),
        nextCursor: 'cursor-1',
      ),
    );
    useLargeViewport(tester);

    await pumpMinimalApp(tester, DeviceDebugPage(sn: 'SN-DEBUG-1', api: api));

    // 上下两张折线图（电压 / 电流）
    expect(find.byType(LineChart), findsNWidgets(2));

    // 默认选电池 + 负载：每张图 2 条曲线
    var charts =
        tester.widgetList<LineChart>(find.byType(LineChart)).toList();
    expect(charts[0].data.lineBarsData, hasLength(2));
    expect(charts[1].data.lineBarsData, hasLength(2));

    // 勾选 MPPT/PV1 → 电压/电流图各 3 条曲线
    await tapGroupChip(tester, 'MPPT/PV1');
    charts = tester.widgetList<LineChart>(find.byType(LineChart)).toList();
    expect(charts[0].data.lineBarsData, hasLength(3));
    expect(charts[1].data.lineBarsData, hasLength(3));

    // 取消勾选电池 → 回到 2 条（PV1 + 负载）
    await tapGroupChip(tester, l10n.str('debug_group_battery'));
    charts = tester.widgetList<LineChart>(find.byType(LineChart)).toList();
    expect(charts[0].data.lineBarsData, hasLength(2));
    expect(charts[1].data.lineBarsData, hasLength(2));
  });

  testWidgets('点停止触发 stopDebugSession 并携带会话 id', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    final api = FakeDeviceDebugApi(
      initialInfo: DeviceDebugSessionInfo(
        session: activeSession(),
        deviceOnline: true,
        supported: true,
        intervalSeconds: 30,
      ),
      samplesPage: const DeviceDebugSamplesPage(items: [], nextCursor: ''),
    );
    useLargeViewport(tester);

    await pumpMinimalApp(tester, DeviceDebugPage(sn: 'SN-DEBUG-1', api: api));

    expect(find.text(l10n.str('debug_stop')), findsOneWidget);

    await tester.tap(find.text(l10n.str('debug_stop')));
    await tester.pump();
    await tester.pump();

    expect(api.stopCalls, 1);
    expect(api.lastStoppedSessionId, 'sess-1');

    // 停止后徽标变已停止，回到开始按钮
    expect(find.text(l10n.str('debug_status_stopped')), findsOneWidget);
    expect(find.text(l10n.str('debug_start')), findsOneWidget);
  });
}
