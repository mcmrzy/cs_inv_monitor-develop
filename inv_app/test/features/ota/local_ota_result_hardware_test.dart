import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/ota/data/datasources/local_ota_result_sync_queue.dart';
import 'package:inv_app/features/ota/data/datasources/ota_remote_data_source.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repository extends Mock implements OtaRepository {}

class _Dio extends Mock implements Dio {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('failed result preserves exact firmware ID across restart and retry',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = _Repository();
    when(() => repository.reportLocalOTAResult(
              sn: 'SN',
              targetChip: 'arm',
              newVersion: '1.2.0',
              firmwareId: 42,
            ))
        .thenAnswer(
            (_) async => const Left(ServerFailure('incompatible hardware')));
    final queue = LocalOtaResultSyncQueue(
        repository: repository, sharedPreferences: prefs);
    await queue.enqueue(
        sn: 'SN', targetChip: 'arm', newVersion: '1.2.0', firmwareId: 42);
    await Future<void>.delayed(Duration.zero);
    expect(queue.pendingCount, 1);
    final stored =
        jsonDecode(prefs.getString('local_ota_result_sync_queue_v1')!) as List;
    expect(stored.single['firmware_id'], 42);
    await queue.dispose();

    when(() => repository.reportLocalOTAResult(
          sn: 'SN',
          targetChip: 'arm',
          newVersion: '1.2.0',
          firmwareId: 42,
        )).thenAnswer((_) async => const Right(<String, dynamic>{}));
    final restarted = LocalOtaResultSyncQueue(
        repository: repository, sharedPreferences: prefs);
    await restarted.flush();
    expect(restarted.pendingCount, 0);
    verify(() => repository.reportLocalOTAResult(
          sn: 'SN',
          targetChip: 'arm',
          newVersion: '1.2.0',
          firmwareId: 42,
        )).called(2);
    await restarted.dispose();
  });

  test('legacy pending result remains readable without firmware ID', () {
    final item = PendingLocalOtaResult.fromJson({
      'sn': 'SN',
      'target_chip': 'arm',
      'new_version': '1.2.0',
    });
    expect(item, isNotNull);
    expect(item!.firmwareId, isNull);
    expect(item.toJson().containsKey('firmware_id'), isFalse);
  });

  test('local result sends actual firmware ID in API payload', () async {
    final dio = _Dio();
    when(() => dio.post<dynamic>(any(), data: any(named: 'data')))
        .thenAnswer((_) async => Response<dynamic>(
              requestOptions: RequestOptions(path: '/'),
              data: {'code': 0},
            ));
    await OtaRemoteDataSource(dio).reportLocalOTAResult(
      sn: 'SN',
      targetChip: 'arm',
      newVersion: '1.2.0',
      firmwareId: 42,
    );
    final sent = verify(() => dio.post<dynamic>(
          '/ota/devices/SN/local-ota-result',
          data: captureAny(named: 'data'),
        )).captured.single as Map;
    expect(sent['firmware_id'], 42);
  });
}
