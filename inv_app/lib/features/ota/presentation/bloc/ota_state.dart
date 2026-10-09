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
  /// Compatibility primary value; only [stageProgress] proves a phase percent.
  final double progress;
  final String status;
  final Map<String, dynamic> detail;
  final String stage;
  final String targetChip;
  final double? stageProgress;
  final double? overallProgress;

  const OTAProgress({
    required this.progress,
    required this.status,
    required this.detail,
    this.stage = '',
    this.targetChip = '',
    this.stageProgress,
    this.overallProgress,
  });

  factory OTAProgress.fromDetail(Map<String, dynamic> data) {
    Map<String, dynamic> active = data;
    final items = data['items'];
    if (items is List) {
      final records = items
          .whereType<Map>()
          .map(
            (item) => Map<String, dynamic>.from(item),
          )
          .toList();
      for (final statuses in const [
        ['downloading', 'upgrading', 'transferring', 'verifying', 'installing'],
        ['pending'],
        ['failed', 'cancelled', 'success'],
      ]) {
        final matching =
            records.where((item) => statuses.contains(item['status']));
        if (matching.isNotEmpty) {
          active = matching.first;
          break;
        }
      }
    }
    final rawStage = (active['stage'] ?? '').toString();
    final stage = switch (rawStage) {
      'receiving' => 'transferring',
      'writing' || 'upgrading' => 'installing',
      '' => (active['status'] ?? data['status'] ?? '').toString(),
      _ => rawStage,
    };
    double? percent(dynamic value) => value is num && value.isFinite
        ? value.toDouble().clamp(0.0, 100.0)
        : null;
    return OTAProgress(
      progress:
          percent(active['stage_progress']) ?? percent(active['progress']) ?? 0,
      status: (data['status'] ?? '').toString(),
      detail: data,
      stage: stage,
      targetChip: (active['target_chip'] ?? active['target'] ?? '').toString(),
      stageProgress: percent(active['stage_progress']),
      overallProgress:
          percent(data['overall_progress']) ?? percent(data['progress']),
    );
  }

  @override
  List<Object?> get props => [
        progress,
        status,
        detail,
        stage,
        targetChip,
        stageProgress,
        overallProgress,
      ];
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
