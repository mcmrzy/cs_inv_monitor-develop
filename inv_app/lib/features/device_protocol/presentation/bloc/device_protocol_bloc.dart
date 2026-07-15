import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/device_protocol/domain/entities/device_protocol_entities.dart';
import 'package:inv_app/features/device_protocol/domain/repositories/device_protocol_repository.dart';

part 'device_protocol_event.dart';
part 'device_protocol_state.dart';

class DeviceProtocolBloc
    extends Bloc<DeviceProtocolEvent, DeviceProtocolState> {
  DeviceProtocolBloc({required this.repository})
      : super(const DeviceProtocolInitial()) {
    on<DeviceProtocolRequested>(_onRequested);
  }

  final DeviceProtocolRepository repository;

  Future<void> _onRequested(
    DeviceProtocolRequested event,
    Emitter<DeviceProtocolState> emit,
  ) async {
    emit(const DeviceProtocolLoading());

    // The futures are created before awaiting, so all three independent
    // endpoints are requested concurrently while preserving strong types.
    final alarmsFuture = repository.getAlarmEvents(event.sn);
    final parallelFuture = repository.getParallelState(event.sn);
    final threePhaseFuture = repository.getThreePhase(event.sn);

    final alarms = await alarmsFuture;
    final parallel = await parallelFuture;
    final threePhase = await threePhaseFuture;

    emit(
      DeviceProtocolLoaded(
        alarms: _listSection(alarms),
        parallel: _parallelSection(parallel),
        threePhase: _listSection(threePhase),
      ),
    );
  }

  ProtocolSection<List<T>> _listSection<T>(
    Either<Failure, CachedProtocolData<List<T>>> result,
  ) {
    return result.fold(
      ProtocolSection<List<T>>.failure,
      (data) => ProtocolSection<List<T>>.success(
        data.value,
        empty: data.value.isEmpty,
        isFromCache: data.isFromCache,
        cachedAt: data.cachedAt,
      ),
    );
  }

  ProtocolSection<DeviceParallelState> _parallelSection(
    Either<Failure, CachedProtocolData<DeviceParallelState>> result,
  ) {
    return result.fold(
      ProtocolSection<DeviceParallelState>.failure,
      (data) => ProtocolSection<DeviceParallelState>.success(
        data.value,
        empty: !data.value.hasParallel && !data.value.hasReportedState,
        isFromCache: data.isFromCache,
        cachedAt: data.cachedAt,
      ),
    );
  }
}
