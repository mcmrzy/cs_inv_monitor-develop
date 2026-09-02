import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/alarm/presentation/bloc/alarm_bloc.dart';
import 'package:inv_app/features/alarm/presentation/pages/alarm_page.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/pump_app.dart';

class _MockAlarmBloc extends MockBloc<AlarmEvent, AlarmState>
    implements AlarmBloc {}

void main() {
  late _MockAlarmBloc alarmBloc;

  setUp(() {
    alarmBloc = _MockAlarmBloc();
  });

  testWidgets('empty alarm list remains pull-to-refreshable', (tester) async {
    const loaded = AlarmListLoaded(alarms: [], total: 0);
    final states = StreamController<AlarmState>();
    addTearDown(states.close);
    whenListen(
      alarmBloc,
      states.stream,
      initialState: loaded,
    );

    await pumpApp(tester, const AlarmPage(), alarmBloc: alarmBloc);
    clearInteractions(alarmBloc);

    // 下拉刷新需要带速度的 fling 才会触发 RefreshIndicator
    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    verify(() => alarmBloc.add(const AlarmListRequested())).called(1);
    states.add(loaded);
    await tester.pumpAndSettle();
  });

  testWidgets('an error is not shown again after an unrelated rebuild',
      (tester) async {
    final states = StreamController<AlarmState>();
    addTearDown(states.close);
    const loaded = AlarmListLoaded(alarms: [], total: 0);
    whenListen(alarmBloc, states.stream, initialState: loaded);

    await pumpApp(tester, const AlarmPage(), alarmBloc: alarmBloc);

    const message = 'alarm refresh unavailable';
    states.add(const AlarmError(message: message));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(message), findsOneWidget);

    // 无关重建（非错误的状态变化）不应再次弹出错误提示：
    // 提示由 listener 触发一次，随 SnackBar 时长自动消失。
    // 注意：一次 pump 推进过长时间会让 SnackBar 的消失动画在同一帧内
    // 无法完成，需分段推进时间。
    states.add(const AlarmListLoaded(alarms: [], total: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(message), findsNothing);
  });
}
