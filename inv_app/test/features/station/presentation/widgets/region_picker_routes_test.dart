import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/station/presentation/widgets/region_picker_routes.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 回归测试：RegionPickerPage 省/市/区三级模式必须渲染省份列。
/// 背景：provinceOnly 改造时 else 分支误删省份列，导致电站页
/// 只能选市/区、无法切换省份（cities/districts 恒为第一个省的数据）。
void main() {
  const provinces = ['广东省', '湖南省'];

  List<String> citiesFn(String p) =>
      p == '广东省' ? ['广州市', '深圳市'] : ['长沙市', '株洲市'];

  List<String> districtsFn(String p, String c) => switch (c) {
        '广州市' => ['天河区', '越秀区'],
        '深圳市' => ['南山区', '福田区'],
        '长沙市' => ['岳麓区', '芙蓉区'],
        _ => ['荷塘区'],
      };

  RegionPickerPage buildPicker({bool provinceOnly = false}) => RegionPickerPage(
        provinces: provinces,
        citiesFn: citiesFn,
        districtsFn: districtsFn,
        provinceOnly: provinceOnly,
      );

  Widget hostApp(Widget child) => MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          builder: (context, screenUtilChild) => screenUtilChild!,
          child: child,
        ),
      );

  testWidgets('省/市/区三级模式渲染省份列及其选项', (tester) async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));

    await tester.pumpWidget(hostApp(buildPicker()));
    await tester.pumpAndSettle();

    // 三列标题齐全（省份列曾被误删，此处为核心回归断言）
    expect(find.text(zh.localProvince), findsOneWidget);
    expect(find.text(zh.localCity), findsOneWidget);
    expect(find.text(zh.localDistrict), findsOneWidget);

    // 省份列展示省份选项（初始定位第一项）
    expect(find.text('广东省'), findsOneWidget);
    expect(find.text('湖南省'), findsOneWidget);

    // 初始省（广东省）对应的城市/区县联动
    expect(find.text('广州市'), findsOneWidget);
    expect(find.text('深圳市'), findsOneWidget);
    expect(find.text('天河区'), findsOneWidget);
  });

  testWidgets('拖动省份列后城市/区县联动刷新', (tester) async {
    await tester.pumpWidget(hostApp(buildPicker()));
    await tester.pumpAndSettle();

    // 省份列向上拖一项（itemExtent=44）：广东省 → 湖南省
    await tester.drag(find.text('广东省'), const Offset(0, -44));
    await tester.pumpAndSettle();

    // 城市联动为湖南省的市级
    expect(find.text('长沙市'), findsOneWidget);
    expect(find.text('株洲市'), findsOneWidget);
    expect(find.text('广州市'), findsNothing);
    expect(find.text('深圳市'), findsNothing);
  });

  testWidgets('provinceOnly 模式仅省份列，确认后市/区为空', (tester) async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    Map<String, String>? picked;

    await tester.pumpWidget(
      hostApp(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                picked = await Navigator.of(context)
                    .push<Map<String, String>>(
                  MaterialPageRoute(
                    builder: (_) => buildPicker(provinceOnly: true),
                  ),
                );
              },
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();

    // 仅省份列：市/区列标题与选项均不渲染
    expect(find.text(zh.localProvince), findsOneWidget);
    expect(find.text(zh.localCity), findsNothing);
    expect(find.text(zh.localDistrict), findsNothing);
    expect(find.text('广州市'), findsNothing);

    await tester.tap(find.text(zh.confirm));
    await tester.pumpAndSettle();

    expect(picked, {'province': '广东省', 'city': '', 'district': ''});
  });

  testWidgets('三级模式确认返回省/市/区', (tester) async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    Map<String, String>? picked;

    await tester.pumpWidget(
      hostApp(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                picked = await Navigator.of(context)
                    .push<Map<String, String>>(
                  MaterialPageRoute(
                    builder: (_) => buildPicker(),
                  ),
                );
              },
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(zh.confirm));
    await tester.pumpAndSettle();

    expect(
      picked,
      {'province': '广东省', 'city': '广州市', 'district': '天河区'},
    );
  });
}
