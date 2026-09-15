import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/onboarding/data/onboarding_storage.dart';
import 'package:inv_app/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorageService extends Mock implements StorageService {}

void main() {
  late _MockStorageService storage;

  setUp(() async {
    await getIt.reset();
    storage = _MockStorageService();
    getIt.registerSingleton<StorageService>(storage);
    when(
      () => storage.saveString(any(), any()),
    ).thenAnswer((_) async {});
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<GoRouter> pumpOnboarding(
    WidgetTester tester, {
    Size size = const Size(375, 812),
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/onboarding',
      initialExtra: '/target',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, __) => const OnboardingPage(),
        ),
        GoRoute(
          path: '/target',
          builder: (_, __) => const Scaffold(body: Text('target-page')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: ScreenUtilInit(
            designSize: const Size(375, 812),
            minTextAdapt: true,
            builder: (_, screenChild) => screenChild!,
            child: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  Image currentIllustration(WidgetTester tester) => tester.widget<Image>(
        find.descendant(
          of: find.byKey(const Key('onboarding-page-content')),
          matching: find.byType(Image),
        ),
      );

  String assetName(Image image) => (image.image as AssetImage).assetName;

  Future<void> nextPage(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('onboarding-primary-action')));
    await tester.pumpAndSettle();
  }

  testWidgets('三页使用统一小烁资产并更新固定底部进度', (tester) async {
    await pumpOnboarding(tester);

    expect(
      assetName(currentIllustration(tester)),
      CsergyAssets.xiaoshuoStation,
    );
    expect(find.byKey(const Key('onboarding-progress-0')), findsOneWidget);

    await nextPage(tester);
    expect(
      assetName(currentIllustration(tester)),
      CsergyAssets.xiaoshuoReminder,
    );
    expect(find.byKey(const Key('onboarding-progress-1')), findsOneWidget);

    await nextPage(tester);
    expect(
      assetName(currentIllustration(tester)),
      CsergyAssets.xiaoshuoWifiGuide,
    );
    expect(find.byKey(const Key('onboarding-progress-2')), findsOneWidget);
  });

  testWidgets('引导页使用 App 蓝色语义 token', (tester) async {
    await pumpOnboarding(tester);

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('onboarding-primary-action')),
    );
    final buttonContext = tester.element(
      find.byKey(const Key('onboarding-primary-action')),
    );
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{}),
      AppColor.primary(buttonContext),
    );

    final illustration = currentIllustration(tester);
    final illustrationContainer = tester.widget<Container>(
      find
          .ancestor(
            of: find.byWidget(illustration),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = illustrationContainer.decoration! as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors, <Color>[
      AppColor.primary(buttonContext).withValues(alpha: 0.16),
      AppColor.primarySoft(buttonContext),
    ]);
  });

  testWidgets('底部操作区在翻页时位置和高度保持稳定', (tester) async {
    await pumpOnboarding(tester);

    final firstRect = tester.getRect(
      find.byKey(const Key('onboarding-footer')),
    );
    await nextPage(tester);
    final secondRect = tester.getRect(
      find.byKey(const Key('onboarding-footer')),
    );
    await nextPage(tester);
    final thirdRect = tester.getRect(
      find.byKey(const Key('onboarding-footer')),
    );

    expect(secondRect, firstRect);
    expect(thirdRect, firstRect);
  });

  testWidgets('跳过会记录版本并进入原目标页', (tester) async {
    await pumpOnboarding(tester);

    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(find.text('target-page'), findsOneWidget);
    verify(
      () => storage.saveString(
        OnboardingStorage.keyLastSeenVersion,
        any(),
      ),
    ).called(1);
  });

  testWidgets('最后一页完成会记录版本并进入原目标页', (tester) async {
    await pumpOnboarding(tester);
    await nextPage(tester);
    await nextPage(tester);

    await tester.tap(find.byKey(const Key('onboarding-primary-action')));
    await tester.pumpAndSettle();

    expect(find.text('target-page'), findsOneWidget);
    verify(
      () => storage.saveString(
        OnboardingStorage.keyLastSeenVersion,
        any(),
      ),
    ).called(1);
  });

  testWidgets('偏好写入失败不阻塞进入目标页', (tester) async {
    when(
      () => storage.saveString(any(), any()),
    ).thenThrow(StateError('write failed'));
    await pumpOnboarding(tester);

    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(find.text('target-page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in <({String name, Size size, double scale})>[
    (name: '320x568', size: const Size(320, 568), scale: 1),
    (name: '横屏', size: const Size(812, 375), scale: 1),
    (name: '2倍字体', size: const Size(320, 568), scale: 2),
  ]) {
    testWidgets('${scenario.name} 三页均无布局溢出', (tester) async {
      await pumpOnboarding(
        tester,
        size: scenario.size,
        textScale: scenario.scale,
      );
      expect(tester.takeException(), isNull);

      await nextPage(tester);
      expect(tester.takeException(), isNull);

      await nextPage(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
