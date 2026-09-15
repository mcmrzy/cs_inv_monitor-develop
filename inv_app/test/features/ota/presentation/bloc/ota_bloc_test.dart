import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/features/ota/domain/entities/device_firmware_overview.dart';
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
  // OTAFirmwareTriggerRequested
  // ---------------------------------------------------------------------------
  group('OTAFirmwareTriggerRequested', () {
    blocTest<OtaBloc, OtaState>(
      'emits [OTATriggered] on success with tasks',
      build: () {
        when(
          () => mockOtaRepository.triggerFirmware(
            any(),
            any(),
            idempotencyKey: any(named: 'idempotencyKey'),
            forceReason: any(named: 'forceReason'),
          ),
        ).thenAnswer(
          (_) async => right<Failure, List<OtaTriggerTask>>([
            const OtaTriggerTask(
              taskId: 42,
              firmwareId: 7,
              targetChip: 'arm',
              version: '2.0.0',
              status: 'pending',
            ),
          ]),
        );
        when(() => mockOtaRepository.getDeviceOTAStatus(any(),
                taskId: any(named: 'taskId')))
            .thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'status': 'in_progress',
            'progress': 0.0,
          }),
        );
        return otaBloc;
      },
      act: (bloc) => bloc.add(const OTAFirmwareTriggerRequested(
        sn: 'TEST_SN_1',
        firmwareIds: [7],
        idempotencyKey: 'key-1',
      )),
      expect: () => [
        isA<OTATriggering>(),
        isA<OTATriggered>().having((s) => s.taskId, 'taskId', 42),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'emits [OTAError] on failure',
      build: () {
        when(
          () => mockOtaRepository.triggerFirmware(
            any(),
            any(),
            idempotencyKey: any(named: 'idempotencyKey'),
            forceReason: any(named: 'forceReason'),
          ),
        ).thenAnswer(
          (_) async => left<Failure, List<OtaTriggerTask>>(
              createTestServerFailure()),
        );
        return otaBloc;
      },
      act: (bloc) => bloc.add(const OTAFirmwareTriggerRequested(
        sn: 'TEST_SN_1',
        firmwareIds: [7],
        idempotencyKey: 'key-1',
      )),
      expect: () => [
        isA<OTATriggering>(),
        isA<OTAError>(),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'coalesces rapid duplicate trigger events into one repository call',
      build: () {
        when(
          () => mockOtaRepository.triggerFirmware(
            any(),
            any(),
            idempotencyKey: any(named: 'idempotencyKey'),
            forceReason: any(named: 'forceReason'),
          ),
        ).thenAnswer(
          (_) async => right<Failure, List<OtaTriggerTask>>([
            const OtaTriggerTask(
              taskId: 42,
              firmwareId: 7,
              targetChip: 'arm',
              version: '2.0.0',
              status: 'pending',
            ),
          ]),
        );
        when(() => mockOtaRepository.getDeviceOTAStatus(any(),
                taskId: any(named: 'taskId')))
            .thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'status': 'in_progress',
            'progress': 0.0,
          }),
        );
        return otaBloc;
      },
      act: (bloc) async {
        const event = OTAFirmwareTriggerRequested(
          sn: 'TEST_SN_1',
          firmwareIds: [7],
          idempotencyKey: 'key-1',
        );
        bloc.add(event);
        bloc.add(event);
        await Future<void>.delayed(Duration.zero);
        verify(
          () => mockOtaRepository.triggerFirmware(
            any(),
            any(),
            idempotencyKey: any(named: 'idempotencyKey'),
            forceReason: any(named: 'forceReason'),
          ),
        ).called(1);
      },
      expect: () => [
        isA<OTATriggering>(),
        isA<OTATriggered>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // OTAFirmwareRollbackRequested
  // ---------------------------------------------------------------------------
  group('OTAFirmwareRollbackRequested', () {
    blocTest<OtaBloc, OtaState>(
      'emits [OTATriggered] on success',
      build: () {
        when(
          () => mockOtaRepository.rollbackFirmware(
            any(),
            any(),
            idempotencyKey: any(named: 'idempotencyKey'),
            forceReason: any(named: 'forceReason'),
          ),
        ).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'task_id': 99,
          }),
        );
        when(() => mockOtaRepository.getDeviceOTAStatus(any(),
                taskId: any(named: 'taskId')))
            .thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'status': 'in_progress',
            'progress': 0.0,
          }),
        );
        return otaBloc;
      },
      act: (bloc) => bloc.add(const OTAFirmwareRollbackRequested(
        sn: 'TEST_SN_1',
        firmwareId: 3,
        idempotencyKey: 'rb-1',
      )),
      expect: () => [
        isA<OTATriggering>(),
        isA<OTATriggered>().having((s) => s.taskId, 'taskId', 99),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // OTAProgressStartPollRequested / poll
  // ---------------------------------------------------------------------------
  group('OTAProgress polling', () {
    blocTest<OtaBloc, OtaState>(
      'emits [OTAProgress, OTAComplete] when status completes',
      build: () {
        var call = 0;
        when(() => mockOtaRepository.getDeviceOTAStatus(any(),
                taskId: any(named: 'taskId')))
            .thenAnswer((_) async {
          call++;
          if (call == 1) {
            return right<Failure, Map<String, dynamic>>({
              'status': 'downloading',
              'progress': 50.0,
            });
          }
          return right<Failure, Map<String, dynamic>>({
            'status': 'completed',
            'progress': 100.0,
          });
        });
        return otaBloc;
      },
      act: (bloc) => bloc.add(
        const OTAProgressStartPollRequested(deviceSn: 'TEST_SN_1', taskId: 1),
      ),
      wait: const Duration(milliseconds: 2500),
      expect: () => [
        isA<OTAProgress>(),
        isA<OTAProgress>(),
        isA<OTAComplete>(),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'emits [OTAProgress, OTAError] when status fails',
      build: () {
        when(() => mockOtaRepository.getDeviceOTAStatus(any(),
                taskId: any(named: 'taskId')))
            .thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'status': 'failed',
            'progress': 30.0,
            'error_message': 'flash write error',
          }),
        );
        return otaBloc;
      },
      act: (bloc) => bloc.add(
        const OTAProgressStartPollRequested(deviceSn: 'TEST_SN_1', taskId: 1),
      ),
      expect: () => [
        isA<OTAProgress>(),
        isA<OTAError>().having(
          (s) => s.message,
          'message',
          'flash write error',
        ),
      ],
    );
  });

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
  // OTAFirmwareOverviewRequested
  // ---------------------------------------------------------------------------
  group('OTAFirmwareOverviewRequested', () {
    final overview = DeviceFirmwareOverview(
      deviceSn: 'TEST_SN_1',
      deviceModel: 'CS-10K',
      isOnline: true,
      modules: [
        FirmwareModuleOverview(
          target: 'arm',
          currentVersion: '1.0.0',
          latestFirmwareId: 5,
          latestVersion: '1.1.0',
          versionState: 'outdated',
          updateAvailable: true,
        ),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'emits [OTAFirmwareOverviewLoading, OTAFirmwareOverviewLoaded]',
      build: () {
        when(() => mockOtaRepository.getFirmwareOverview(any()))
            .thenAnswer((_) async => right(overview));
        return otaBloc;
      },
      act: (bloc) =>
          bloc.add(const OTAFirmwareOverviewRequested(sn: 'TEST_SN_1')),
      expect: () => [
        isA<OTAFirmwareOverviewLoading>(),
        isA<OTAFirmwareOverviewLoaded>(),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'emits [OTAFirmwareOverviewLoading, OTAFirmwareOverviewError]',
      build: () {
        when(() => mockOtaRepository.getFirmwareOverview(any())).thenAnswer(
          (_) async =>
              left<Failure, DeviceFirmwareOverview>(createTestServerFailure()),
        );
        return otaBloc;
      },
      act: (bloc) =>
          bloc.add(const OTAFirmwareOverviewRequested(sn: 'TEST_SN_1')),
      expect: () => [
        isA<OTAFirmwareOverviewLoading>(),
        isA<OTAFirmwareOverviewError>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // OTAFirmwareResourcesRequested
  // ---------------------------------------------------------------------------
  group('OTAFirmwareResourcesRequested', () {
    blocTest<OtaBloc, OtaState>(
      'emits [OTAFirmwareResourcesLoading, OTAFirmwareResourcesLoaded]',
      build: () {
        when(() => mockOtaRepository.getFirmwareResources(
              any(),
              targetChip: any(named: 'targetChip'),
            )).thenAnswer(
          (_) async => right<Failure, List<FirmwareResource>>([
            const FirmwareResource(
              id: 1,
              model: 'CS-10K',
              version: '2.0.0',
              fileUrl: 'https://example.com/fw.bin',
              targetChip: 'arm',
            ),
          ]),
        );
        return otaBloc;
      },
      act: (bloc) =>
          bloc.add(const OTAFirmwareResourcesRequested(sn: 'TEST_SN_1')),
      expect: () => [
        isA<OTAFirmwareResourcesLoading>(),
        isA<OTAFirmwareResourcesLoaded>(),
      ],
    );

    blocTest<OtaBloc, OtaState>(
      'emits [OTAFirmwareResourcesLoading, OTAFirmwareResourcesError]',
      build: () {
        when(() => mockOtaRepository.getFirmwareResources(
              any(),
              targetChip: any(named: 'targetChip'),
            )).thenAnswer(
          (_) async =>
              left<Failure, List<FirmwareResource>>(createTestServerFailure()),
        );
        return otaBloc;
      },
      act: (bloc) =>
          bloc.add(const OTAFirmwareResourcesRequested(sn: 'TEST_SN_1')),
      expect: () => [
        isA<OTAFirmwareResourcesLoading>(),
        isA<OTAFirmwareResourcesError>(),
      ],
    );
  });
}
