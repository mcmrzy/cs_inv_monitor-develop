part of 'device_protocol_bloc.dart';

enum ProtocolSectionStatus { data, empty, forbidden, error }

class ProtocolSection<T> extends Equatable {
  const ProtocolSection._({
    required this.status,
    this.value,
    this.message,
    this.isFromCache = false,
    this.cachedAt,
  });

  factory ProtocolSection.success(
    T value, {
    bool empty = false,
    bool isFromCache = false,
    DateTime? cachedAt,
  }) {
    return ProtocolSection._(
      status: empty ? ProtocolSectionStatus.empty : ProtocolSectionStatus.data,
      value: value,
      isFromCache: isFromCache,
      cachedAt: cachedAt,
    );
  }

  factory ProtocolSection.failure(Failure failure) {
    return ProtocolSection._(
      status: failure is ForbiddenFailure
          ? ProtocolSectionStatus.forbidden
          : ProtocolSectionStatus.error,
      message: failure.message,
    );
  }

  final ProtocolSectionStatus status;
  final T? value;
  final String? message;
  final bool isFromCache;
  final DateTime? cachedAt;

  @override
  List<Object?> get props => [status, value, message, isFromCache, cachedAt];
}

sealed class DeviceProtocolState extends Equatable {
  const DeviceProtocolState();

  @override
  List<Object?> get props => [];
}

class DeviceProtocolInitial extends DeviceProtocolState {
  const DeviceProtocolInitial();
}

class DeviceProtocolLoading extends DeviceProtocolState {
  const DeviceProtocolLoading();
}

class DeviceProtocolLoaded extends DeviceProtocolState {
  const DeviceProtocolLoaded({
    required this.alarms,
    required this.parallel,
    required this.threePhase,
  });

  final ProtocolSection<List<AlarmProtocolEvent>> alarms;
  final ProtocolSection<DeviceParallelState> parallel;
  final ProtocolSection<List<ThreePhaseSample>> threePhase;

  @override
  List<Object?> get props => [alarms, parallel, threePhase];
}
