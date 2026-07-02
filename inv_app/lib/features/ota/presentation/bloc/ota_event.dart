part of 'ota_bloc.dart';

abstract class OtaEvent extends Equatable {
  const OtaEvent();

  @override
  List<Object?> get props => [];
}

class OTACheckRequested extends OtaEvent {
  final String sn;

  const OTACheckRequested({required this.sn});

  @override
  List<Object?> get props => [sn];
}

class OTATriggerRequested extends OtaEvent {
  final String sn;
  final int firmwareId;

  const OTATriggerRequested({required this.sn, required this.firmwareId});

  @override
  List<Object?> get props => [sn, firmwareId];
}

class OTAProgressPollRequested extends OtaEvent {
  final String deviceSn;

  const OTAProgressPollRequested({required this.deviceSn});

  @override
  List<Object?> get props => [deviceSn];
}

class OTAProgressStopPoll extends OtaEvent {
  const OTAProgressStopPoll();
}

/// Admin already pushed command; skip trigger API and start polling directly.
class OTAPackageTriggerRequested extends OtaEvent {
  final String sn;
  const OTAPackageTriggerRequested({required this.sn});

  @override
  List<Object?> get props => [sn];
}

class OTAFirmwareListRequested extends OtaEvent {
  final String deviceModel;
  final String sn;

  const OTAFirmwareListRequested({required this.deviceModel, required this.sn});

  @override
  List<Object?> get props => [deviceModel, sn];
}

class OTAFirmwareInstallRequested extends OtaEvent {
  final String sn;
  final int packageId;

  const OTAFirmwareInstallRequested({required this.sn, required this.packageId});

  @override
  List<Object?> get props => [sn, packageId];
}

