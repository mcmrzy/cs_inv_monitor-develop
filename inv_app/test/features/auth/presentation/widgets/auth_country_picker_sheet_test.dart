import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/auth/presentation/widgets/auth_country_picker_sheet.dart';
import 'package:inv_app/l10n/app_localizations.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  testWidgets('filters countries by code and returns the selected country', (
    tester,
  ) async {
    Map<String, String>? picked;

    await pumpMinimalApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            picked = await showModalBottomSheet<Map<String, String>>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const AuthCountryPickerSheet(initialCode: 'CN'),
            );
          },
          child: const Text('OPEN'),
        ),
      ),
    );

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.text('中国 (CN)'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'jp');
    await tester.pumpAndSettle();

    expect(find.text('日本 (JP)'), findsOneWidget);
    expect(find.text('中国 (CN)'), findsNothing);

    await tester.tap(find.text('日本 (JP)'));
    await tester.pumpAndSettle();

    expect(picked, {'code': 'JP', 'name': '日本'});
  });

  testWidgets('filters countries by name and shows the empty state', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(
      const Locale('zh', 'CN'),
    );

    await pumpMinimalApp(
      tester,
      const AuthCountryPickerSheet(initialCode: 'CN'),
    );

    await tester.enterText(find.byType(TextField), '日本');
    await tester.pumpAndSettle();
    expect(find.text('日本 (JP)'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'not-a-country');
    await tester.pumpAndSettle();
    expect(find.text(l10n.str('auth_no_country_match')), findsOneWidget);
  });
}
