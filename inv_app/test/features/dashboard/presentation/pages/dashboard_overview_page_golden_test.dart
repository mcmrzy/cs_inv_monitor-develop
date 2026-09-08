// Golden 基线测试（light 模式）：数据概览页。
//
// 重要说明：
// - golden 文件在本机 win32 上用 `flutter test --update-goldens` 生成，
//   对字体版本（assets/fonts/NotoSansSC-VF.ttf）、Flutter 版本与平台
//   文本排版引擎敏感；在 linux CI 上直接比对很可能不匹配。
//   CI 暂不运行 golden 测试，等后续引入 --exclude-tags / 按平台跳过方案。
// - 选择 DashboardOverviewPage 而不是 DashboardPage：后者 header 渲染
//   DateTime.now() 的"最后更新"时间，golden 跨进程不稳定。
// - 字体通过 test/helpers/golden_fonts.dart 加载真实字体，避免默认 Ahem
//   字体把所有字形渲染成色块。
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/dashboard/domain/entities/dashboard_data.dart';
import 'package:inv_app/features/dashboard/domain/entities/station_rank_item.dart';
import 'package:inv_app/features/dashboard/domain/entities/trend_data_point.dart';
import 'package:inv_app/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:inv_app/features/dashboard/presentation/pages/dashboard_overview_page.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/golden_fonts.dart';
import '../../../../helpers/mock_providers.dart';


/// 生产 light 主题 + 真实测试字体。
///
/// 除 textTheme 外，还必须给主题里"显式构造的 TextStyle"（appBarTheme.
/// titleTextStyle、tabBarTheme.labelStyle 等）逐个补 fontFamily：这些样式
/// 不经过 textTheme 继承，缺省时会落到测试默认字体渲染成方块。
ThemeData _goldenLightTheme() {
  final base = AppTheme.light;
  TextStyle withFont(TextStyle? style) =>
      (style ?? const TextStyle()).copyWith(fontFamily: kGoldenFontFamily);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: kGoldenFontFamily),
    primaryTextTheme:
        base.primaryTextTheme.apply(fontFamily: kGoldenFontFamily),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: withFont(base.appBarTheme.titleTextStyle),
      toolbarTextStyle: withFont(base.appBarTheme.toolbarTextStyle),
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelStyle: withFont(base.tabBarTheme.labelStyle),
      unselectedLabelStyle: withFont(base.tabBarTheme.unselectedLabelStyle),
    ),
  );
}

DashboardData _fixedData() {
  return DashboardData(
    todayEnergy: 42.5,
    totalEnergy: 10240.8,
    deviceTotal: 8,
    onlineCount: 6,
    offlineCount: 1,
    faultCount: 1,
    trendData: List.generate(
      7,
      (i) => TrendDataPoint(
        date: '0${i + 1}/01',
        energy: 20.0 + i * 3.5,
        load: 12.0 + i * 1.2,
        cumulative: 100.0 + i * 20,
      ),
    ),
    stationRanking: const [
      StationRankItem(
        stationId: 1,
        stationName: '城东工业园区电站',
        energy: 128.6,
        deviceCount: 4,
      ),
      StationRankItem(
        stationId: 2,
        stationName: '南山物流园电站',
        energy: 96.2,
        deviceCount: 3,
      ),
      StationRankItem(
        stationId: 3,
        stationName: '乡村振兴示范电站',
        energy: 54.1,
        deviceCount: 1,
      ),
    ],
    recentAlarms: const [
      {
        'id': 1,
        'alarm_level': 2,
        'fault_message': 'Grid voltage warning',
        'device_sn': 'INV-001',
        'occurred_at': '2026-09-01T08:00:00Z',
      },
      {
        'id': 2,
        'alarm_level': 3,
        'fault_message': 'Inverter fault F04',
        'device_sn': 'INV-002',
        'occurred_at': '2026-09-02T09:30:00Z',
      },
    ],
    isFromCache: false,
  );
}

class _FakeDashboardEvent extends Fake implements DashboardEvent {}

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
    registerFallbackValue(_FakeDashboardEvent());
  });

  testWidgets('dashboard 概览页 light 模式渲染基线', (tester) async {
    tester.view.physicalSize = const Size(750, 1624);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final dashboardBloc = MockDashboardBloc();
    when(() => dashboardBloc.state)
        .thenReturn(DashboardLoaded(data: _fixedData()));
    when(() => dashboardBloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => dashboardBloc.add(any())).thenAnswer((_) {});

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        builder: (_, __) => BlocProvider<DashboardBloc>.value(
          value: dashboardBloc,
          child: MaterialApp(
            locale: const Locale('zh', 'CN'),
            theme: _goldenLightTheme(),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const DashboardOverviewPage(),
          ),
        ),
      ),
    );
    // 首帧布局，再固定推进越过能量数字 800ms 计数动画（确定性截图）。
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 100));

    await expectLater(
      find.byType(DashboardOverviewPage),
      matchesGoldenFile('goldens/dashboard_overview_page_light.png'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, tags: 'golden');
}
