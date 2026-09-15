import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:inv_app/core/services/app_update_service.dart';
import 'package:inv_app/features/profile/presentation/pages/about_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  final di = GetIt.instance;

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: '辰烁光伏',
      packageName: 'com.csergy.app1',
      version: '1.0.2',
      buildNumber: '12',
      buildSignature: '',
    );
    if (!di.isRegistered<Dio>()) {
      di.registerLazySingleton<Dio>(() => Dio());
    }
    if (!di.isRegistered<AppUpdateService>()) {
      di.registerLazySingleton<AppUpdateService>(() => AppUpdateService(di()));
    }
  });

  testWidgets(
      'renders a code-drawn energy hero with a check-update entry',
      (tester) async {
    await pumpMinimalApp(tester, const AboutPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('about-energy-hero')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('about-energy-hero')),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
    // 检查更新入口：分组标题与条目各渲染一次该文案
    expect(find.text('检查更新'), findsNWidgets(2));
    expect(find.text('当前版本: V1.0.2'), findsOneWidget);
  });
}
