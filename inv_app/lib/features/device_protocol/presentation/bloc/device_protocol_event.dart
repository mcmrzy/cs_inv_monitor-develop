part of 'device_protocol_bloc.dart';

sealed class DeviceProtocolEvent extends Equatable {
  const DeviceProtocolEvent();

  @override
  List<Object?> get props => [];
}

class DeviceProtocolRequested extends DeviceProtocolEvent {
  const DeviceProtocolRequested(this.sn);

  final String sn;

  @override
  List<Object?> get props => [sn];
}
