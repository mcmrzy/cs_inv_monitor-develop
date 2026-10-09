import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_history.dart';
import 'package:inv_app/features/ota/presentation/bloc/ota_bloc.dart';
import 'package:inv_app/features/ota/presentation/pages/ota_detail_page.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class _MockOtaBloc extends MockBloc<OtaEvent, OtaState> implements OtaBloc {}

void main() {
  test('history preserves explicit phase zero and legacy uncertainty', () {
    final history = DeviceFirmwareHistory.fromJson({
      'stage': 'installing',
      'stage_progress': 0,
      'progress': 70,
      'overall_progress': 70,
    });
    expect(history.stageProgress, 0);
    expect(history.overallProgress, 70);
    expect(
      DeviceFirmwareHistory.fromJson({'progress': 84}).stageProgress,
      isNull,
    );
  });

  for (final legacy in [false, true]) {
    for (final size in const [
      Size(320, 640),
      Size(390, 844),
      Size(1024, 768),
    ]) {
      testWidgets('phase and overall remain separate (legacy=$legacy) at $size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final bloc = _MockOtaBloc();
        addTearDown(bloc.close);
        whenListen(
          bloc,
          const Stream<OtaState>.empty(),
          initialState: OTAProgress.fromDetail({
            'status': 'upgrading',
            'stage': 'installing',
            if (!legacy) 'stage_progress': 0,
            'progress': legacy ? 84 : 70,
            if (!legacy) 'overall_progress': 70,
            'target_chip': 'dsp',
          }),
        );
        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (context, child) => MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: BlocProvider<OtaBloc>.value(
                value: bloc,
                child: const OTADetailPage(deviceSN: 'SN-001', taskId: 42),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text(legacy ? '--' : '0.0%'), findsOneWidget);
        expect(find.text(legacy ? '84.0%' : '70.0%'), findsOneWidget);
        expect(find.text('Overall progress'), findsOneWidget);
        expect(find.text('Installing'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
