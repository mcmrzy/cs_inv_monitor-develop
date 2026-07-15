import 'package:dartz/dartz.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/device_protocol/domain/entities/device_protocol_entities.dart';

abstract class DeviceProtocolRepository {
  Future<Either<Failure, CachedProtocolData<List<AlarmProtocolEvent>>>>
      getAlarmEvents(String sn);

  Future<Either<Failure, CachedProtocolData<DeviceParallelState>>>
      getParallelState(String sn);

  Future<Either<Failure, CachedProtocolData<List<ThreePhaseSample>>>>
      getThreePhase(String sn);
}
