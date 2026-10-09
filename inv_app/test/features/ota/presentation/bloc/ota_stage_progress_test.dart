import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/ota/presentation/bloc/ota_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:inv_app/core/errors/failures.dart';
import '../../../../helpers/mock_providers.dart';

void main() {
  test(
      'phase and target transitions restart stall timer; 100 waits for success',
      () async {
    var now = DateTime(2026, 10, 9);
    var data = <String, dynamic>{
      'status': 'upgrading',
      'stage': 'transferring',
      'stage_progress': 100,
      'progress': 99,
      'target_chip': 'arm',
    };
    final repository = MockOtaRepository();
    when(
      () => repository.getDeviceOTAStatus(any(), taskId: any(named: 'taskId')),
    ).thenAnswer((_) async => right<Failure, Map<String, dynamic>>(data));
    final bloc = OtaBloc(repository: repository, now: () => now);
    final states = <OtaState>[];
    final subscription = bloc.stream.listen(states.add);
    Future<void> drain() =>
        Future<void>.delayed(const Duration(milliseconds: 10));
    bloc.add(const OTAProgressStartPollRequested(deviceSn: 'SN', taskId: 42));
    await drain();
    expect(bloc.state, isA<OTAProgress>());
    expect(states.whereType<OTAComplete>(), isEmpty);
    now = now.add(const Duration(minutes: 4));
    data = {...data, 'stage': 'verifying'};
    bloc.add(const OTAProgressPollRequested(deviceSn: 'SN', taskId: 42));
    await drain();
    now = now.add(const Duration(minutes: 4));
    data = {...data, 'target_chip': 'dsp'};
    bloc.add(const OTAProgressPollRequested(deviceSn: 'SN', taskId: 42));
    await drain();
    expect(bloc.state, isA<OTAProgress>());
    now = now.add(const Duration(minutes: 4));
    bloc.add(const OTAProgressPollRequested(deviceSn: 'SN', taskId: 42));
    await drain();
    expect(bloc.state, isA<OTAProgress>());
    now = now.add(const Duration(minutes: 2));
    bloc.add(const OTAProgressPollRequested(deviceSn: 'SN', taskId: 42));
    await drain();
    expect(bloc.state, isA<OTAError>());
    await subscription.cancel();
    await bloc.close();
  });

  test('explicit stage zero overrides legacy weighted percent', () {
    final progress = OTAProgress.fromDetail({
      'status': 'upgrading',
      'stage': 'installing',
      'stage_progress': 0,
      'progress': 70,
      'overall_progress': 70,
      'target_chip': 'dsp',
    });
    expect(progress.progress, 0);
    expect(progress.stageProgress, 0);
    expect(progress.overallProgress, 70);
    expect(progress.stage, 'installing');
    expect(progress.targetChip, 'dsp');
  });

  test('legacy ESP and collector reports retain their raw percentage', () {
    for (final chip in ['esp', 'arm', 'dsp', 'bms']) {
      final progress = OTAProgress.fromDetail({
        'status': 'upgrading',
        'stage': 'installing',
        'progress': 84,
        'target_chip': chip,
      });
      expect(progress.progress, 84);
      expect(progress.stageProgress, isNull);
      expect(progress.overallProgress, 84);
    }
  });

  test('task selects active phase instead of completed or pending chip', () {
    final progress = OTAProgress.fromDetail({
      'status': 'upgrading',
      'progress': 56,
      'overall_progress': 56,
      'items': [
        {'status': 'success', 'target_chip': 'arm', 'progress': 100},
        {
          'status': 'upgrading',
          'stage': 'verifying',
          'stage_progress': 0,
          'progress': 70,
          'target_chip': 'dsp',
        },
        {'status': 'pending', 'target_chip': 'esp', 'progress': 0},
      ],
    });
    expect(progress.progress, 0);
    expect(progress.stage, 'verifying');
    expect(progress.targetChip, 'dsp');
    expect(progress.overallProgress, 56);
  });
}
