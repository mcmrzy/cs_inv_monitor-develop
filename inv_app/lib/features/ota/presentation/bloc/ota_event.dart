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
  final int taskId;

  const OTAProgressPollRequested({required this.taskId});

  @override
  List<Object?> get props => [taskId];
}

class OTAProgressStopPoll extends OtaEvent {
  const OTAProgressStopPoll();
}

class OTAHistoryRequested extends OtaEvent {
  final String sn;
  final int page;

  const OTAHistoryRequested({required this.sn, this.page = 1});

  @override
  List<Object?> get props => [sn, page];
}

class OTAFirmwareListRequested extends OtaEvent {
  final int page;
  final int pageSize;

  const OTAFirmwareListRequested({this.page = 1, this.pageSize = 20});

  @override
  List<Object?> get props => [page, pageSize];
}
