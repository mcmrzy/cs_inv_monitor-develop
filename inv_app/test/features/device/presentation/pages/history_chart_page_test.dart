import 'package:fl_chart/fl_chart.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flutter/material.dart' show DateUtils, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/device/presentation/pages/history_chart_page.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/pump_app.dart';

/// P0 回归：历史曲线页此前读不存在的 `item['x']/item['y']` 字段，
/// 整页数据恒为 0 平线。本组测试锁定修复后的行为：
/// 1. day 档向后端发 period='hour'（走小时表拿 24 个小时桶）；
/// 2. y 值按指标映射后端真实字段（发电→energy_produce）；
/// 3. x 值取后端 `time` 字段解析；
/// 4. 空数据/单行数据给空态或真实单点，不画 0 平线。
void main() {
  late MockDeviceRepository mockDeviceRepository;
  late MockRealtimeDataService mockRealtimeDataService;

  /// 后端 GetHistoryData（period=hour，device_telemetry_hour）的真实行结构
  List<Map<String, dynamic>> hourRows({
    double energy1 = 0.8,
    double energy2 = 1.2,
  }) =>
      [
        {
          'time': '2026-09-08T05:00:00Z',
          'avg_power': 1.5,
          'max_power': 3.2,
          'energy_produce': energy1,
          'avg_temperature': 40.0,
          'run_minutes': 60,
        },
        {
          'time': '2026-09-08T06:00:00Z',
          'avg_power': 2.0,
          'max_power': 4.0,
          'energy_produce': energy2,
          'avg_temperature': 41.0,
          'run_minutes': 60,
        },
      ];

  void stubHistory(List<Map<String, dynamic>> rows) {
    when(
      () => mockDeviceRepository.getHistory(
        any(),
        any(),
        any(),
        any(),
      ),
    ).thenAnswer((_) async => right<Failure, List<dynamic>>(rows));
  }

  String pad2(int v) => v.toString().padLeft(2, '0');

  /// 页面结构为 AppBar+TabBar+筛选行+插画空态，默认 800x600 测试视口
  /// 会导致空态插画 RenderFlex 溢出；放大视口（用 tester.view 而非
  /// setSurfaceSize，避免冻结 timer）
  void useLargeViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(375, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// DeviceBloc 必须在 testWidgets 体内（FakeAsync zone）创建：
  /// 若在 setUp 里创建，其事件循环的 microtask 挂在真实 zone 上，
  /// 不会被 widget 测试的 pump flush，状态永远停在 DeviceInitial
  DeviceBloc buildBloc() {
    when(() => mockRealtimeDataService.realtimeDataStream)
        .thenAnswer((_) => const Stream<InverterRealtime>.empty());
    final bloc = DeviceBloc(
      repository: mockDeviceRepository,
      realtimeDataService: mockRealtimeDataService,
    );
    addTearDown(bloc.close);
    return bloc;
  }

  setUp(() {
    mockDeviceRepository = MockDeviceRepository();
    mockRealtimeDataService = MockRealtimeDataService();
  });

  testWidgets('day 档向后端发 period=hour 且 x/y 取自 time/energy_produce',
      (tester) async {
    stubHistory(hourRows());
    useLargeViewport(tester);
    final deviceBloc = buildBloc();
    await pumpApp(
      tester,
      const HistoryChartPage(deviceSN: 'TEST_SN_1'),
      deviceBloc: deviceBloc,
    );

    final now = DateTime.now();
    final dayStr = '${now.year}-${pad2(now.month)}-${pad2(now.day)}';
    // P0 ②：day 档不再发 period='day'（日表 start==end 只回 1 行），
    // 改发 'hour' 走小时表
    verify(() => mockDeviceRepository.getHistory(
          'TEST_SN_1',
          dayStr,
          dayStr,
          'hour',
        ),).called(1);

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final spots = chart.data.lineBarsData.first.spots;

    // P0 ①：y 来自 energy_produce（发电指标），不是恒 0
    expect(
      spots.map((s) => s.y).toList(),
      [0.8, 1.2],
    );
    // x 来自 time 字段解析（本地时区的小时 + 分钟小数）
    final expectedX = hourRows()
        .map((r) {
          final t = DateTime.parse(r['time'] as String).toLocal();
          return t.hour + t.minute / 60.0;
        })
        .toList();
    expect(
      spots.map((s) => s.x).toList(),
      expectedX,
    );
  });

  testWidgets('空数据展示空态面板而不是 0 平线', (tester) async {
    stubHistory(const []);
    useLargeViewport(tester);
    final deviceBloc = buildBloc();
    await pumpApp(
      tester,
      const HistoryChartPage(deviceSN: 'TEST_SN_1'),
      deviceBloc: deviceBloc,
    );

    // 确认请求已发出且返回空，页面给出空态而不是画 (0,0) 假点
    verify(() => mockDeviceRepository.getHistory(
          any(),
          any(),
          any(),
          any(),
        ),).called(1);
    expect(find.byType(LineChart), findsNothing);
    expect(find.byType(XiaoshuoStatePanel), findsOneWidget);
  });

  testWidgets('单行数据渲染单点，不补 0 点不造平线', (tester) async {
    stubHistory(hourRows(energy2: 1.2).sublist(0, 1));
    useLargeViewport(tester);
    final deviceBloc = buildBloc();
    await pumpApp(
      tester,
      const HistoryChartPage(deviceSN: 'TEST_SN_1'),
      deviceBloc: deviceBloc,
    );

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final spots = chart.data.lineBarsData.first.spots;
    expect(spots, hasLength(1));
    expect(spots.first.y, 0.8);
  });

  testWidgets('month 档走日表 period=month 且发电映射 energy_produce',
      (tester) async {
    stubHistory(const [
      {
        'time': '2026-09-01T00:00:00Z',
        // 日表 avg_power 恒为 NULL→0（无负载字段）
        'avg_power': 0.0,
        'max_power': 4.2,
        'energy_produce': 9.9,
        'avg_temperature': 38.0,
        'run_minutes': 480,
      },
    ]);
    useLargeViewport(tester);
    final deviceBloc = buildBloc();
    await pumpApp(
      tester,
      const HistoryChartPage(deviceSN: 'TEST_SN_1'),
      deviceBloc: deviceBloc,
    );

    // 切到「月」Tab（TabBar 第 2 个）
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    verify(() => mockDeviceRepository.getHistory(
          'TEST_SN_1',
          '${now.year}-${pad2(now.month)}-01',
          '${now.year}-${pad2(now.month)}-${pad2(DateUtils.getDaysInMonth(now.year, now.month))}',
          'month',
        ),).called(1);

    // 默认选中发电指标：y 取 energy_produce=9.9，
    // 若映射仍取 avg_power 会得到 0（修复前恒零的直接证据）
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final spots = chart.data.lineBarsData.first.spots;
    expect(spots.map((s) => s.y).toList(), [9.9]);
  });
}
