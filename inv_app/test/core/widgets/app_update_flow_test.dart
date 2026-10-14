import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/app_update_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/widgets/app_update_flow.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/pump_app.dart';

class _MockAppUpdateService extends Mock implements AppUpdateService {}

void main() {
  late _MockAppUpdateService service;

  setUp(() async {
    await getIt.reset();
    service = _MockAppUpdateService();
    getIt.registerSingleton<AppUpdateService>(service);
    when(() => service.resolveCurrentVersionCode()).thenAnswer((_) async => 1);
  });

  tearDown(() async {
    await getIt.reset();
  });

  for (final hasUpdate in [false, true]) {
    testWidgets(
      'manual update check ignores response after caller is disposed '
      '(hasUpdate: $hasUpdate)',
      (tester) async {
        final response = Completer<AppUpdateInfo>();
        when(() => service.checkUpdate(1)).thenAnswer((_) => response.future);
        late BuildContext callerContext;
        await pumpMinimalApp(
          tester,
          Builder(
            builder: (context) {
              callerContext = context;
              return const SizedBox.shrink();
            },
          ),
        );

        final result = AppUpdateFlow.checkAndPrompt(callerContext);
        await tester.pump();
        verify(() => service.checkUpdate(1)).called(1);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(callerContext.mounted, isFalse);

        final expectation = expectLater(result, completion(isFalse));
        response.complete(AppUpdateInfo(hasUpdate: hasUpdate));
        await tester.pump();
        await expectation;
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
