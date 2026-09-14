import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/profile/presentation/pages/about_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: '辰烁光伏',
      packageName: 'com.csergy.app1',
      version: '1.0.2',
      buildNumber: '12',
      buildSignature: '',
    );
  });

  testWidgets('keeps the code-drawn hero free of character artwork',
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
    expect(find.text('检查更新'), findsNothing);
    expect(find.text('V1.0.2'), findsOneWidget);
  });
}
