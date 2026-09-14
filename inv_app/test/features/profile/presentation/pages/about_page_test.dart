import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/profile/presentation/pages/about_page.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  testWidgets(
      'renders a code-drawn energy hero without mascot or update action',
      (tester) async {
    await pumpMinimalApp(tester, const AboutPage());

    expect(find.byKey(const Key('about-energy-hero')), findsOneWidget);
    expect(
        find.descendant(
          of: find.byKey(const Key('about-energy-hero')),
          matching: find.byType(Image),
        ),
        findsNothing);
    expect(find.text('检查更新'), findsNothing);
  });
}
