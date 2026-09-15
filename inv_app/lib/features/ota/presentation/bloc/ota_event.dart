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

/// 旧调用兼容：单 ID 触发
class OTATriggerRequested extends OtaEvent {
  final String sn;
  final int packageId;

  const OTATriggerRequested({required this.sn, required this.packageId});

  @override
  List<Object?> get props => [sn, packageId];
}

/// 新契约：按 firmware_ids 批量触发升级
class OTAFirmwareTriggerRequested extends OtaEvent {
  final String sn;
  final List<int> firmwareIds;
  final String idempotencyKey;
  final String? forceReason;

  const OTAFirmwareTriggerRequested({
    required this.sn,
    required this.firmwareIds,
    required this.idempotencyKey,
    this.forceReason,
  });

  @override
  List<Object?> get props => [sn, firmwareIds, idempotencyKey, forceReason];
}

/// 按 firmware_id 回滚
class OTAFirmwareRollbackRequested extends OtaEvent {
  final String sn;
  final int firmwareId;
  final String idempotencyKey;
  final String? forceReason;

  const OTAFirmwareRollbackRequested({
    required this.sn,
    required this.firmwareId,
    required this.idempotencyKey,
    this.forceReason,
  });

  @override
  List<Object?> get props => [sn, firmwareId, idempotencyKey, forceReason];
}

class OTAProgressPollRequested extends OtaEvent {
  final String deviceSn;
  final int? taskId;
  final int? generation;

  const OTAProgressPollRequested({
    required this.deviceSn,
    this.taskId,
    this.generation,
  });

  @override
  List<Object?> get props => [deviceSn, taskId, generation];
}

/// Starts a polling session and queries once immediately.
/// Used by the detail page, whose Bloc has no pre-existing timer.
class OTAProgressStartPollRequested extends OtaEvent {
  final String deviceSn;
  final int? taskId;

  const OTAProgressStartPollRequested({
    required this.deviceSn,
    this.taskId,
  });

  @override
  List<Object?> get props => [deviceSn, taskId];
}

class OTAProgressStopPoll extends OtaEvent {
  const OTAProgressStopPoll();
}

/// 加载设备固件总览
class OTAFirmwareOverviewRequested extends OtaEvent {
  final String sn;

  const OTAFirmwareOverviewRequested({required this.sn});

  @override
  List<Object?> get props => [sn];
}

/// 加载设备已发布固件资源
class OTAFirmwareResourcesRequested extends OtaEvent {
  final String sn;
  final String? targetChip;

  const OTAFirmwareResourcesRequested({
    required this.sn,
    this.targetChip,
  });

  @override
  List<Object?> get props => [sn, targetChip];
}
