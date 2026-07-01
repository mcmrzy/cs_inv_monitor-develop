part of 'ota_bloc.dart';

abstract class OtaState extends Equatable {
  const OtaState();

  @override
  List<Object?> get props => [];
}

class OTAInitial extends OtaState {}

class OTALoading extends OtaState {}

class OTAUpToDate extends OtaState {
  final Map<String, dynamic> info;

  const OTAUpToDate({this.info = const {}});

  @override
  List<Object?> get props => [info];
}

class OTAUpdateAvailable extends OtaState {
  final Map<String, dynamic> info;

  const OTAUpdateAvailable({required this.info});

  @override
  List<Object?> get props => [info];
}

class OTATriggered extends OtaState {
  final int taskId;

  const OTATriggered({required this.taskId});

  @override
  List<Object?> get props => [taskId];
}

class OTAProgress extends OtaState {
  final double progress;
  final String status;
  final Map<String, dynamic> detail;

  const OTAProgress({
    required this.progress,
    required this.status,
    required this.detail,
  });

  @override
  List<Object?> get props => [progress, status, detail];
}

class OTAComplete extends OtaState {}

class OTAError extends OtaState {
  final String message;

  const OTAError({required this.message});

  @override
  List<Object?> get props => [message];
}


