import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/features/ota/presentation/bloc/ota_bloc.dart';
import 'package:inv_app/core/errors/failures.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/test_data.dart';

void main() {
  late OtaBloc otaBloc;
  late MockOtaRepository mockOtaRepository;

  setUp(() {
    mockOtaRepository = MockOtaRepository();

    otaBloc = OtaBloc(repository: mockOtaRepository);
  });

  tearDown(() {
    otaBloc.close();
  });

  test('initial state is OTAInitial', () {
    expect(otaBloc.state, equals(OTAInitial()));
  });

  // ---------------------------------------------------------------------------
  // OTACheckRequested
  // ---------------------------------------------------------------------------
  group('OTACheckRequested', () {
    blocTest<OtaBloc, OtaState>(
      'emits [OTAUpdateAvailable] when update is available',
      build: () {
        when(() => mockOtaRepository.checkUpdate(any())).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'has_update': true,
            'version': '2.0.0',
          }),
        );
        return otaBloc;
      },
      act: (bloc) => bloc.add(const OTACheckRequested(sn: 'TEST_SN_1')),
      expect: () => [
        isA<OTAUpdateAvailable>(),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'emits [OTAUpToDate] when no update available',
      build: () {
        when(() => mockOtaRepository.checkUpdate(any())).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'has_update': false,
          }),
        );
        return otaBloc;
      },
      act: (bloc) => bloc.add(const OTACheckRequested(sn: 'TEST_SN_1')),
      expect: () => [
        isA<OTAUpToDate>(),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'emits [OTAError] on failure',
      build: () {
        when(() => mockOtaRepository.checkUpdate(any())).thenAnswer(
          (_) async =>
              left<Failure, Map<String, dynamic>>(createTestServerFailure()),
        );
        return otaBloc;
      },
      act: (bloc) => bloc.add(const OTACheckRequested(sn: 'TEST_SN_1')),
      expect: () => [
        isA<OTAError>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // OTATriggerRequested
  // ---------------------------------------------------------------------------
  group('OTATriggerRequested', () {
    blocTest<OtaBloc, OtaState>(
      'emits [OTATriggered] on success',
      build: () {
        when(() => mockOtaRepository.triggerOTA(any(), any())).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'task_id': 42,
          }),
        );
        when(() => mockOtaRepository.getDeviceOTAStatus(any(), taskId: any(named: 'taskId'))).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'status': 'in_progress',
            'progress': 0.0,
          }),
        );
        return otaBloc;
      },
      act: (bloc) => bloc.add(
        const OTATriggerRequested(sn: 'TEST_SN_1', packageId: 1),
      ),
      expect: () => [
        isA<OTATriggering>(),
        isA<OTATriggered>().having(
          (s) => s.taskId,
          'taskId',
          42,
        ),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'emits [OTAError] on failure',
      build: () {
        when(() => mockOtaRepository.triggerOTA(any(), any())).thenAnswer(
          (_) async =>
              left<Failure, Map<String, dynamic>>(createTestServerFailure()),
        );
        return otaBloc;
      },
      act: (bloc) => bloc.add(
        const OTATriggerRequested(sn: 'TEST_SN_1', packageId: 1),
      ),
      expect: () => [
        isA<OTATriggering>(),
        isA<OTAError>(),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'emits a consumable error when trigger fails from update available',
      build: () {
        when(() => mockOtaRepository.checkUpdate(any())).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'has_update': true,
            'version': '2.0.0',
          }),
        );
        when(() => mockOtaRepository.triggerOTA(any(), any())).thenAnswer(
          (_) async =>
              left<Failure, Map<String, dynamic>>(createTestServerFailure()),
        );
        return otaBloc;
      },
      act: (bloc) async {
        bloc.add(const OTACheckRequested(sn: 'TEST_SN_1'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(
          const OTATriggerRequested(sn: 'TEST_SN_1', packageId: 1),
        );
      },
      expect: () => [
        isA<OTAUpdateAvailable>(),
        isA<OTATriggering>(),
        isA<OTAError>(),
      ],
    );

    late Completer<Either<Failure, Map<String, dynamic>>> triggerCompleter;

    blocTest<OtaBloc, OtaState>(
      'coalesces rapid duplicate trigger events into one repository call',
      build: () {
        triggerCompleter =
            Completer<Either<Failure, Map<String, dynamic>>>();
        when(() => mockOtaRepository.triggerOTA(any(), any()))
            .thenAnswer((_) => triggerCompleter.future);
        when(() => mockOtaRepository.getDeviceOTAStatus(any(), taskId: any(named: 'taskId'))).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'status': 'in_progress',
            'progress': 0.0,
          }),
        );
        return otaBloc;
      },
      act: (bloc) async {
        const event = OTATriggerRequested(sn: 'TEST_SN_1', packageId: 1);
        bloc.add(event);
        bloc.add(event);
        await Future<void>.delayed(Duration.zero);
        verify(() => mockOtaRepository.triggerOTA(any(), any())).called(1);
        triggerCompleter.complete(
          right<Failure, Map<String, dynamic>>({'task_id': 42}),
        );
      },
      expect: () => [
        isA<OTATriggering>(),
        isA<OTATriggered>(),
      ],
    );
  });

  group('OTAPackageTriggerRequested', () {
    late Completer<Either<Failure, Map<String, dynamic>>> resendCompleter;

    blocTest<OtaBloc, OtaState>(
      'coalesces rapid duplicate resend events into one repository call',
      build: () {
        resendCompleter = Completer<Either<Failure, Map<String, dynamic>>>();
        when(() => mockOtaRepository.resendUpgradeCommand(any()))
            .thenAnswer((_) => resendCompleter.future);
        when(() => mockOtaRepository.getDeviceOTAStatus(any(), taskId: any(named: 'taskId'))).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'status': 'in_progress',
            'progress': 0.0,
          }),
        );
        return otaBloc;
      },
      act: (bloc) async {
        const event = OTAPackageTriggerRequested(sn: 'TEST_SN_1');
        bloc.add(event);
        bloc.add(event);
        await Future<void>.delayed(Duration.zero);
        verify(() => mockOtaRepository.resendUpgradeCommand(any())).called(1);
        resendCompleter.complete(
          right<Failure, Map<String, dynamic>>({'task_id': 42}),
        );
      },
      expect: () => [
        isA<OTATriggering>(),
        isA<OTATriggered>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // OTAProgressPollRequested
  // ---------------------------------------------------------------------------
  group('OTAProgressPollRequested', () {
    // 轮询事件需先触发升级（启动轮询定时器）才会被处理，
    // 以下用例统一先 trigger 再 poll

    blocTest<OtaBloc, OtaState>(
      'emits [OTAProgress] with current progress',
      build: () {
        when(() => mockOtaRepository.triggerOTA(any(), any())).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({'task_id': 1}),
        );
        when(() => mockOtaRepository.getDeviceOTAStatus(any(), taskId: any(named: 'taskId'))).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'status': 'in_progress',
            'progress': 50.0,
          }),
        );
        return otaBloc;
      },
      act: (bloc) async {
        bloc.add(const OTATriggerRequested(sn: 'TEST_SN_1', packageId: 1));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        bloc.add(const OTAProgressPollRequested(deviceSn: 'TEST_SN_1'));
      },
      expect: () => [
        isA<OTATriggering>(),
        isA<OTATriggered>(),
        isA<OTAProgress>().having(
          (s) => s.progress,
          'progress',
          50.0,
        ),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'emits [OTAProgress, OTAComplete] when status is completed',
      build: () {
        when(() => mockOtaRepository.triggerOTA(any(), any())).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({'task_id': 1}),
        );
        when(() => mockOtaRepository.getDeviceOTAStatus(any(), taskId: any(named: 'taskId'))).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'status': 'completed',
            'progress': 100.0,
          }),
        );
        return otaBloc;
      },
      act: (bloc) async {
        bloc.add(const OTATriggerRequested(sn: 'TEST_SN_1', packageId: 1));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        bloc.add(const OTAProgressPollRequested(deviceSn: 'TEST_SN_1'));
      },
      expect: () => [
        isA<OTATriggering>(),
        isA<OTATriggered>(),
        isA<OTAProgress>(),
        isA<OTAComplete>(),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'emits [OTAProgress, OTAError] when status is failed',
      build: () {
        when(() => mockOtaRepository.triggerOTA(any(), any())).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({'task_id': 1}),
        );
        when(() => mockOtaRepository.getDeviceOTAStatus(any(), taskId: any(named: 'taskId'))).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'status': 'failed',
            'progress': 30.0,
            'error_message': 'Download failed',
          }),
        );
        return otaBloc;
      },
      act: (bloc) async {
        bloc.add(const OTATriggerRequested(sn: 'TEST_SN_1', packageId: 1));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        bloc.add(const OTAProgressPollRequested(deviceSn: 'TEST_SN_1'));
      },
      expect: () => [
        isA<OTATriggering>(),
        isA<OTATriggered>(),
        isA<OTAProgress>(),
        isA<OTAError>().having(
          (s) => s.message,
          'message',
          'Download failed',
        ),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'tolerates a single poll failure without error state',
      build: () {
        when(() => mockOtaRepository.triggerOTA(any(), any())).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({'task_id': 1}),
        );
        when(() => mockOtaRepository.getDeviceOTAStatus(any(), taskId: any(named: 'taskId'))).thenAnswer(
          (_) async => left<Failure, Map<String, dynamic>>(
            createTestServerFailure(),
          ),
        );
        return otaBloc;
      },
      act: (bloc) async {
        bloc.add(const OTATriggerRequested(sn: 'TEST_SN_1', packageId: 1));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        bloc.add(const OTAProgressPollRequested(deviceSn: 'TEST_SN_1'));
      },
      // 单次失败容忍（弱网抖动），不进入错误态
      expect: () => [
        isA<OTATriggering>(),
        isA<OTATriggered>(),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'emits [OTAError] after consecutive poll failures reach threshold',
      build: () {
        when(() => mockOtaRepository.triggerOTA(any(), any())).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({'task_id': 1}),
        );
        when(() => mockOtaRepository.getDeviceOTAStatus(any(), taskId: any(named: 'taskId'))).thenAnswer(
          (_) async => left<Failure, Map<String, dynamic>>(
            createTestServerFailure(),
          ),
        );
        return otaBloc;
      },
      act: (bloc) async {
        bloc.add(const OTATriggerRequested(sn: 'TEST_SN_1', packageId: 1));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        // 连续失败达阈值（3 次）才进错误态
        for (var i = 0; i < 3; i++) {
          bloc.add(const OTAProgressPollRequested(deviceSn: 'TEST_SN_1'));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      },
      expect: () => [
        isA<OTATriggering>(),
        isA<OTATriggered>(),
        isA<OTAError>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // OTAProgressStartPollRequested
  // ---------------------------------------------------------------------------
  group('OTAProgressStartPollRequested', () {
    blocTest<OtaBloc, OtaState>(
      'queries immediately with the requested taskId',
      build: () {
        when(() => mockOtaRepository.getDeviceOTAStatus(any(),
                taskId: any(named: 'taskId')))
            .thenAnswer((_) async =>
                right<Failure, Map<String, dynamic>>({
                  'status': 'upgrading',
                  'progress': 40.0,
                }));
        return otaBloc;
      },
      act: (bloc) => bloc.add(const OTAProgressStartPollRequested(
        deviceSn: 'TEST_SN_1',
        taskId: 7,
      )),
      expect: () => [
        isA<OTAProgress>().having((s) => s.progress, 'progress', 40.0),
      ],
      verify: (_) {
        verify(() => mockOtaRepository.getDeviceOTAStatus('TEST_SN_1',
            taskId: 7)).called(1);
      },
    );

    blocTest<OtaBloc, OtaState>(
      'treats cancelled as a terminal state',
      build: () {
        when(() => mockOtaRepository.getDeviceOTAStatus(any(),
                taskId: any(named: 'taskId')))
            .thenAnswer((_) async =>
                right<Failure, Map<String, dynamic>>({
                  'status': 'cancelled',
                  'progress': 10.0,
                  'error_message': '',
                }));
        return otaBloc;
      },
      act: (bloc) => bloc.add(const OTAProgressStartPollRequested(
        deviceSn: 'TEST_SN_1',
        taskId: 7,
      )),
      expect: () => [
        isA<OTAProgress>(),
        isA<OTAError>().having((s) => s.message, 'message', 'Upgrade cancelled'),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'treats timeout as a terminal state',
      build: () {
        when(() => mockOtaRepository.getDeviceOTAStatus(any(),
                taskId: any(named: 'taskId')))
            .thenAnswer((_) async =>
                right<Failure, Map<String, dynamic>>({
                  'status': 'timeout',
                  'progress': 10.0,
                }));
        return otaBloc;
      },
      act: (bloc) => bloc.add(const OTAProgressStartPollRequested(
        deviceSn: 'TEST_SN_1',
        taskId: 7,
      )),
      expect: () => [
        isA<OTAProgress>(),
        isA<OTAError>().having((s) => s.message, 'message', 'Upgrade timed out'),
      ],
    );

    test('drops poll events while a request is already in flight', () async {
      final gate = Completer<void>();
      var calls = 0;
      when(() => mockOtaRepository.getDeviceOTAStatus(any(),
              taskId: any(named: 'taskId')))
          .thenAnswer((_) async {
        calls++;
        await gate.future;
        return right<Failure, Map<String, dynamic>>({
          'status': 'upgrading',
          'progress': 20.0,
        });
      });

      otaBloc.add(const OTAProgressStartPollRequested(
          deviceSn: 'TEST_SN_1', taskId: 7));
      // 等待首个请求真正进入 await
      await Future<void>.delayed(Duration.zero);
      otaBloc.add(const OTAProgressPollRequested(
          deviceSn: 'TEST_SN_1', taskId: 7));
      otaBloc.add(const OTAProgressPollRequested(
          deviceSn: 'TEST_SN_1', taskId: 7));
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(calls, 1);
    });

    test('discards results from a superseded polling session', () async {
      final first = Completer<Either<Failure, Map<String, dynamic>>>();
      when(() => mockOtaRepository.getDeviceOTAStatus(any(),
              taskId: any(named: 'taskId')))
          .thenAnswer((invocation) async {
        final taskId = invocation.namedArguments[#taskId] as int?;
        if (taskId == 1) return first.future;
        return right<Failure, Map<String, dynamic>>({
          'status': 'upgrading',
          'progress': 60.0,
        });
      });

      // 会话 A：请求挂起未返回
      otaBloc.add(
          const OTAProgressStartPollRequested(deviceSn: 'TEST_SN_1', taskId: 1));
      await Future<void>.delayed(Duration.zero);
      // 会话 B 覆盖会话 A
      otaBloc.add(
          const OTAProgressStartPollRequested(deviceSn: 'TEST_SN_1', taskId: 2));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // 会话 A 的迟到结果不应再影响状态
      first.complete(right<Failure, Map<String, dynamic>>({
        'status': 'completed',
        'progress': 100.0,
      }));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(otaBloc.state, isA<OTAProgress>());
      expect((otaBloc.state as OTAProgress).progress, 60.0);
      expect((otaBloc.state as OTAProgress).status, 'upgrading');
    });
  });

  // ---------------------------------------------------------------------------
  // OTAProgressStopPoll
  // ---------------------------------------------------------------------------
  group('OTAProgressStopPoll', () {
    blocTest<OtaBloc, OtaState>(
      'emits [OTAInitial] when stopping poll',
      build: () => otaBloc,
      act: (bloc) => bloc.add(const OTAProgressStopPoll()),
      expect: () => [
        isA<OTAInitial>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // OTAFirmwareListRequested
  // ---------------------------------------------------------------------------
  group('OTAFirmwareListRequested', () {
    blocTest<OtaBloc, OtaState>(
      'emits [OTAFirmwareListLoading, OTAFirmwareListLoaded] on success',
      build: () {
        when(
          () => mockOtaRepository.listUpgradePackages(
            model: any(named: 'model'),
          ),
        ).thenAnswer(
          (_) async => right<Failure, List<dynamic>>([
            {'id': 1, 'version': '2.0.0'},
          ]),
        );
        return otaBloc;
      },
      act: (bloc) => bloc.add(
        const OTAFirmwareListRequested(
          deviceModel: 'INV-5000',
          sn: 'TEST_SN_1',
        ),
      ),
      expect: () => [
        isA<OTAFirmwareListLoading>(),
        isA<OTAFirmwareListLoaded>(),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'emits [OTAFirmwareListLoading, OTAFirmwareListError] on failure',
      build: () {
        when(
          () => mockOtaRepository.listUpgradePackages(
            model: any(named: 'model'),
          ),
        ).thenAnswer(
          (_) async => left<Failure, List<dynamic>>(createTestServerFailure()),
        );
        return otaBloc;
      },
      act: (bloc) => bloc.add(
        const OTAFirmwareListRequested(
          deviceModel: 'INV-5000',
          sn: 'TEST_SN_1',
        ),
      ),
      expect: () => [
        isA<OTAFirmwareListLoading>(),
        isA<OTAFirmwareListError>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // OTAFirmwareInstallRequested
  // ---------------------------------------------------------------------------
  group('OTAFirmwareInstallRequested', () {
    late Completer<Either<Failure, Map<String, dynamic>>> installCompleter;

    blocTest<OtaBloc, OtaState>(
      'emits [OTAFirmwareInstalling, OTATriggered] on success',
      build: () {
        when(() => mockOtaRepository.installPackage(any(), any())).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'task_id': 99,
          }),
        );
        when(() => mockOtaRepository.getDeviceOTAStatus(any(), taskId: any(named: 'taskId'))).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'status': 'in_progress',
            'progress': 0.0,
          }),
        );
        return otaBloc;
      },
      act: (bloc) => bloc.add(
        const OTAFirmwareInstallRequested(sn: 'TEST_SN_1', packageId: 5),
      ),
      expect: () => [
        isA<OTAFirmwareInstalling>(),
        isA<OTATriggered>().having(
          (s) => s.taskId,
          'taskId',
          99,
        ),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'emits [OTAFirmwareInstalling, OTAError] on failure',
      build: () {
        when(() => mockOtaRepository.installPackage(any(), any())).thenAnswer(
          (_) async => left<Failure, Map<String, dynamic>>(
            createTestServerFailure(),
          ),
        );
        return otaBloc;
      },
      act: (bloc) => bloc.add(
        const OTAFirmwareInstallRequested(sn: 'TEST_SN_1', packageId: 5),
      ),
      expect: () => [
        isA<OTAFirmwareInstalling>(),
        isA<OTAError>(),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'coalesces rapid duplicate install events into one repository call',
      build: () {
        installCompleter =
            Completer<Either<Failure, Map<String, dynamic>>>();
        when(() => mockOtaRepository.installPackage(any(), any()))
            .thenAnswer((_) => installCompleter.future);
        when(() => mockOtaRepository.getDeviceOTAStatus(any(), taskId: any(named: 'taskId'))).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'status': 'in_progress',
            'progress': 0.0,
          }),
        );
        return otaBloc;
      },
      act: (bloc) async {
        const event =
            OTAFirmwareInstallRequested(sn: 'TEST_SN_1', packageId: 5);
        bloc.add(event);
        bloc.add(event);
        await Future<void>.delayed(Duration.zero);
        verify(() => mockOtaRepository.installPackage(any(), any())).called(1);
        installCompleter.complete(
          right<Failure, Map<String, dynamic>>({'task_id': 99}),
        );
      },
      expect: () => [
        isA<OTAFirmwareInstalling>(),
        isA<OTATriggered>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // LoadAvailablePackages
  // ---------------------------------------------------------------------------
  group('LoadAvailablePackages', () {
    blocTest<OtaBloc, OtaState>(
      'emits [OTAAvailablePackagesLoading, OTAAvailablePackagesLoaded] on success',
      build: () {
        when(() => mockOtaRepository.getAvailablePackages(any())).thenAnswer(
          (_) async => right<Failure, List<dynamic>>([
            {'id': 1, 'user_version': '2.0.0'},
          ]),
        );
        return otaBloc;
      },
      act: (bloc) => bloc.add(const LoadAvailablePackages(sn: 'TEST_SN_1')),
      expect: () => [
        isA<OTAAvailablePackagesLoading>(),
        isA<OTAAvailablePackagesLoaded>(),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'emits [OTAAvailablePackagesLoading, OTAAvailablePackagesError] on failure',
      build: () {
        when(() => mockOtaRepository.getAvailablePackages(any())).thenAnswer(
          (_) async => left<Failure, List<dynamic>>(createTestServerFailure()),
        );
        return otaBloc;
      },
      act: (bloc) => bloc.add(const LoadAvailablePackages(sn: 'TEST_SN_1')),
      expect: () => [
        isA<OTAAvailablePackagesLoading>(),
        isA<OTAAvailablePackagesError>(),
      ],
    );
  });
}
