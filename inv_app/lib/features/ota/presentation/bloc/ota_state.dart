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

/// 升级命令正在提交，尚未获得服务端 task_id。
class OTATriggering extends OtaState {
  const OTATriggering();
}

class OTATriggered extends OtaState {
  final int taskId;
  final List<OtaTriggerTask> tasks;

  const OTATriggered({required this.taskId, this.tasks = const []});

  @override
  List<Object?> get props => [taskId, tasks];
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

/// 固件总览加载中
class OTAFirmwareOverviewLoading extends OtaState {}

/// 固件总览加载成功
class OTAFirmwareOverviewLoaded extends OtaState {
  final DeviceFirmwareOverview overview;

  const OTAFirmwareOverviewLoaded({required this.overview});

  @override
  List<Object?> get props => [overview];
}

/// 固件总览加载失败
class OTAFirmwareOverviewError extends OtaState {
  final String message;

  const OTAFirmwareOverviewError({required this.message});

  @override
  List<Object?> get props => [message];
}

/// 固件资源列表加载中
class OTAFirmwareResourcesLoading extends OtaState {}

/// 固件资源列表加载成功
class OTAFirmwareResourcesLoaded extends OtaState {
  final List<FirmwareResource> resources;

  const OTAFirmwareResourcesLoaded({required this.resources});

  @override
  List<Object?> get props => [resources];
}

/// 固件资源列表加载失败
class OTAFirmwareResourcesError extends OtaState {
  final String message;

  const OTAFirmwareResourcesError({required this.message});

  @override
  List<Object?> get props => [message];
}

/// 兼容别名：固件安装中（旧 UI 引用）
class OTAFirmwareInstalling extends OtaState {
  final int packageId;

  const OTAFirmwareInstalling({required this.packageId});

  @override
  List<Object?> get props => [packageId];
}
