import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/profile/presentation/pages/operation_history_page.dart';

void main() {
  testWidgets('unknown operation colors follow light and dark themes',
      (tester) async {
    late Color lightSource;
    late Color lightResult;
    late Color darkSource;
    late Color darkResult;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Builder(
          builder: (context) {
            lightSource = OpLogItem.sourceColor(context, 'unknown');
            lightResult = OpLogItem.resultColor(context, 'unknown');
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(lightSource, isNot(equals(Colors.transparent)));
    expect(lightResult, isNot(equals(Colors.transparent)));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) {
            darkSource = OpLogItem.sourceColor(context, 'unknown');
            darkResult = OpLogItem.resultColor(context, 'unknown');
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(darkSource, isNot(equals(Colors.transparent)));
    expect(darkResult, isNot(equals(Colors.transparent)));
  });
}
