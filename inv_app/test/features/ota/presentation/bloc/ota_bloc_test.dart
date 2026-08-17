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
        when(() => mockOtaRepository.getDeviceOTAStatus(any())).thenAnswer(
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
        isA<OTAError>(),
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
        when(() => mockOtaRepository.getDeviceOTAStatus(any())).thenAnswer(
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
        when(() => mockOtaRepository.getDeviceOTAStatus(any())).thenAnswer(
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
        when(() => mockOtaRepository.getDeviceOTAStatus(any())).thenAnswer(
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
        when(() => mockOtaRepository.getDeviceOTAStatus(any())).thenAnswer(
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
        isA<OTATriggered>(),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'emits [OTAError] after consecutive poll failures reach threshold',
      build: () {
        when(() => mockOtaRepository.triggerOTA(any(), any())).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({'task_id': 1}),
        );
        when(() => mockOtaRepository.getDeviceOTAStatus(any())).thenAnswer(
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
        isA<OTATriggered>(),
        isA<OTAError>(),
      ],
    );
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
    blocTest<OtaBloc, OtaState>(
      'emits [OTAFirmwareInstalling, OTATriggered] on success',
      build: () {
        when(() => mockOtaRepository.installPackage(any(), any())).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'task_id': 99,
          }),
        );
        when(() => mockOtaRepository.getDeviceOTAStatus(any())).thenAnswer(
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
