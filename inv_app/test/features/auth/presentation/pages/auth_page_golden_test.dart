// Golden 基线测试（light 模式）：登录/注册页。
//
// 重要说明：
// - golden 文件在本机 win32 上用 `flutter test --update-goldens` 生成，
//   对字体版本（assets/fonts/NotoSansSC-VF.ttf）、Flutter 版本与平台
//   文本排版引擎敏感；在 linux CI 上直接比对很可能不匹配。
//   CI 暂不运行 golden 测试，等后续引入 --exclude-tags / 按平台跳过方案。
// - AuthPage 的品牌装饰有 4s 周期呼吸动画（repeat），不能 pumpAndSettle，
//   固定 pump 到确定相位后截图。
// - 字体通过 test/helpers/golden_fonts.dart 加载真实字体，避免默认 Ahem
//   字体把所有字形渲染成色块。
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/auth/presentation/pages/auth_page.dart';
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

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
  });

  setUp(() async {
    await getIt.reset();
    // LoginForm.initState 读取已保存凭据并探测一键登录；
    // golden 场景给空凭据、JVerify 不可用（内部 catch 静默）。
    final storage = MockStorageService();
    when(() => storage.getRememberPassword()).thenAnswer((_) async => false);
    when(() => storage.getSavedPhone()).thenAnswer((_) async => null);
    when(() => storage.getSavedPassword()).thenAnswer((_) async => null);
    getIt.registerSingleton<StorageService>(storage);
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('login 页 light 模式渲染基线', (tester) async {
    tester.view.physicalSize = const Size(750, 1624);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final authBloc = MockAuthBloc();
    when(() => authBloc.state).thenReturn(AuthInitial());
    when(() => authBloc.stream).thenAnswer((_) => const Stream.empty());

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        builder: (_, __) => BlocProvider<AuthBloc>.value(
          value: authBloc,
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
            home: const AuthPage(),
          ),
        ),
      ),
    );
    // 首帧布局 + 固定推进到呼吸动画 100ms 相位（确定性截图）。
    await tester.pump(const Duration(milliseconds: 100));

    await expectLater(
      find.byType(AuthPage),
      matchesGoldenFile('goldens/auth_page_light.png'),
    );

    // 释放呼吸动画 ticker，避免测试结束后残留活跃 Ticker。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, tags: 'golden');
}
