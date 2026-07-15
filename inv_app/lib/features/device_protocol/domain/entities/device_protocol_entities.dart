import 'package:equatable/equatable.dart';

DateTime? _dateTime(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

int _integer(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

class AlarmProtocolEvent extends Equatable {
  const AlarmProtocolEvent({
    required this.id,
    required this.deviceSn,
    required this.source,
    required this.code,
    required this.level,
    required this.state,
    required this.eventTime,
    required this.receivedAt,
    this.activeAt,
    this.recoveredAt,
    this.dataHash = '',
  });

  final int id;
  final String deviceSn;
  final int source;
  final String code;
  final int level;
  final String state;
  final DateTime eventTime;
  final DateTime receivedAt;
  final DateTime? activeAt;
  final DateTime? recoveredAt;
  final String dataHash;

  bool get isActive => state == 'active';

  factory AlarmProtocolEvent.fromJson(Map<String, dynamic> json) {
    final eventTime = _dateTime(json['event_time']);
    final receivedAt = _dateTime(json['received_at']);
    if (eventTime == null || receivedAt == null) {
      throw const FormatException(
        'alarm event requires event_time and received_at',
      );
    }
    return AlarmProtocolEvent(
      id: _integer(json['id']),
      deviceSn: json['device_sn']?.toString() ?? '',
      source: _integer(json['source']),
      code: json['code']?.toString() ?? '',
      level: _integer(json['level']),
      state: json['state']?.toString() ?? '',
      eventTime: eventTime,
      receivedAt: receivedAt,
      activeAt: _dateTime(json['active_at']),
      recoveredAt: _dateTime(json['recovered_at']),
      dataHash: json['data_hash']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [
        id,
        deviceSn,
        source,
        code,
        level,
        state,
        eventTime,
        receivedAt,
        activeAt,
        recoveredAt,
        dataHash,
      ];
}

class ParallelMachine extends Equatable {
  const ParallelMachine({
    required this.id,
    required this.sn,
    required this.role,
    required this.power,
    required this.state,
    this.phase,
  });

  final int id;
  final String sn;
  final String role;
  final String? phase;
  final double power;
  final int state;

  factory ParallelMachine.fromJson(Map<String, dynamic> json) {
    return ParallelMachine(
      id: _integer(json['id']),
      sn: json['sn']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      phase: json['phase']?.toString(),
      power: _number(json['power']),
      state: _integer(json['state']),
    );
  }

  @override
  List<Object?> get props => [id, sn, role, phase, power, state];
}

class DeviceParallelState extends Equatable {
  const DeviceParallelState({
    required this.hasParallel,
    required this.enabled,
    required this.stationId,
    required this.masterSn,
    required this.mode,
    required this.count,
    required this.totalRatedPower,
    required this.totalActivePower,
    required this.syncState,
    required this.machines,
    this.reportedAt,
  });

  final bool hasParallel;
  final bool enabled;
  final int stationId;
  final String masterSn;
  final String mode;
  final int count;
  final double totalRatedPower;
  final double totalActivePower;
  final String syncState;
  final List<ParallelMachine> machines;
  final DateTime? reportedAt;

  /// A disabled topology is still a valid current state. The API's minimal
  /// no-state response only contains has_parallel/enabled=false.
  bool get hasReportedState =>
      stationId != 0 || masterSn.isNotEmpty || reportedAt != null;

  factory DeviceParallelState.fromJson(Map<String, dynamic> json) {
    final rawMachines = json['machines'];
    if (rawMachines != null && rawMachines is! List) {
      throw const FormatException('parallel machines is not an array');
    }
    final machines = (rawMachines as List?)?.map((item) {
          if (item is! Map) {
            throw const FormatException(
              'parallel machine is not an object',
            );
          }
          return ParallelMachine.fromJson(Map<String, dynamic>.from(item));
        }).toList(growable: false) ??
        const <ParallelMachine>[];
    return DeviceParallelState(
      hasParallel: json['has_parallel'] == true,
      enabled: json['enabled'] == true,
      stationId: _integer(json['station_id']),
      masterSn: json['master_sn']?.toString() ?? '',
      mode: json['mode']?.toString() ?? '',
      count: _integer(json['count']),
      totalRatedPower: _number(json['total_rated_power']),
      totalActivePower: _number(json['total_active_power']),
      syncState: json['sync_state']?.toString() ?? '',
      machines: machines,
      reportedAt: _dateTime(json['reported_at']),
    );
  }

  @override
  List<Object?> get props => [
        hasParallel,
        enabled,
        stationId,
        masterSn,
        mode,
        count,
        totalRatedPower,
        totalActivePower,
        syncState,
        machines,
        reportedAt,
      ];
}

class ThreePhaseSample extends Equatable {
  const ThreePhaseSample({
    required this.eventTime,
    required this.receivedAt,
    required this.voltage,
    required this.current,
    required this.activePower,
    required this.totalActivePower,
    required this.lineVoltage,
    required this.frequency,
    required this.voltageUnbalance,
    required this.currentUnbalance,
    this.dataHash = '',
  });

  final DateTime eventTime;
  final DateTime receivedAt;
  final List<double> voltage;
  final List<double> current;
  final List<double> activePower;
  final double totalActivePower;
  final List<double> lineVoltage;
  final double frequency;
  final double voltageUnbalance;
  final double currentUnbalance;
  final String dataHash;

  factory ThreePhaseSample.fromJson(Map<String, dynamic> json) {
    final eventTime = _dateTime(json['event_time']);
    final receivedAt = _dateTime(json['received_at']);
    if (eventTime == null || receivedAt == null) {
      throw const FormatException(
        'three-phase sample requires event_time and received_at',
      );
    }
    return ThreePhaseSample(
      eventTime: eventTime,
      receivedAt: receivedAt,
      voltage: [
        _number(json['voltage_l1']),
        _number(json['voltage_l2']),
        _number(json['voltage_l3']),
      ],
      current: [
        _number(json['current_l1']),
        _number(json['current_l2']),
        _number(json['current_l3']),
      ],
      activePower: [
        _number(json['active_power_l1']),
        _number(json['active_power_l2']),
        _number(json['active_power_l3']),
      ],
      totalActivePower: _number(json['total_active_power']),
      lineVoltage: [
        _number(json['line_voltage_l1l2']),
        _number(json['line_voltage_l2l3']),
        _number(json['line_voltage_l3l1']),
      ],
      frequency: _number(json['frequency']),
      voltageUnbalance: _number(json['voltage_unbalance']),
      currentUnbalance: _number(json['current_unbalance']),
      dataHash: json['data_hash']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [
        eventTime,
        receivedAt,
        voltage,
        current,
        activePower,
        totalActivePower,
        lineVoltage,
        frequency,
        voltageUnbalance,
        currentUnbalance,
        dataHash,
      ];
}

class CachedProtocolData<T> extends Equatable {
  const CachedProtocolData({
    required this.value,
    this.isFromCache = false,
    this.cachedAt,
  });

  final T value;
  final bool isFromCache;
  final DateTime? cachedAt;

  @override
  List<Object?> get props => [value, isFromCache, cachedAt];
}
