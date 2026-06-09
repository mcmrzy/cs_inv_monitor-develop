import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inv_app/main.dart';

void main() {
  testWidgets('App starts without errors', (WidgetTester tester) async {
    await tester.pumpWidget(const InvApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
