/// 能源数据点 - 用于发电统计图表
class EnergyDataPoint {
  final String time; // 时间标签 (HH:mm / dd / MM)
  final double pvEnergy; // PV 发电量 (kWh)
  final double batteryCharge; // 电池充电量 (kWh)
  final double batteryDischarge; // 电池放电量 (kWh)
  final double inverterOutput; // 逆变器输出 (kWh)
  final double gridImport; // 电网输入 (kWh)
  final double gridExport; // 电网输出 (kWh)
  final double dailyPv; // 日累计光伏发电量 (kWh)
  final double dailyLoad; // 日累计用电量 (kWh)
  final double pvPower; // PV 实时功率 (W) - 仅小时模式
  final double batteryChargePower; // 电池充电功率 (W) - 仅小时模式
  final double batteryDischargePower; // 电池放电功率 (W) - 仅小时模式
  final double inverterPower; // 逆变器输出功率 (W) - 仅小时模式
  final double gridPower; // 电网净功率 (W) = gridImport - gridExport，仅小时模式

  const EnergyDataPoint({
    required this.time,
    this.pvEnergy = 0,
    this.batteryCharge = 0,
    this.batteryDischarge = 0,
    this.inverterOutput = 0,
    this.gridImport = 0,
    this.gridExport = 0,
    this.dailyPv = 0,
    this.dailyLoad = 0,
    this.pvPower = 0,
    this.batteryChargePower = 0,
    this.batteryDischargePower = 0,
    this.inverterPower = 0,
    this.gridPower = 0,
  });

  factory EnergyDataPoint.fromJson(Map<String, dynamic> json) {
    return EnergyDataPoint(
      time: json['time'] as String? ?? '',
      pvEnergy: (json['energy_produce'] as num?)?.toDouble() ?? 0,
      batteryCharge: (json['battery_charge'] as num?)?.toDouble() ?? 0,
      batteryDischarge: (json['battery_discharge'] as num?)?.toDouble() ?? 0,
      inverterOutput: (json['inverter_output'] as num?)?.toDouble() ?? 0,
      gridImport: (json['grid_import'] as num?)?.toDouble() ?? 0,
      gridExport: (json['grid_export'] as num?)?.toDouble() ?? 0,
      dailyPv: (json['daily_pv'] as num?)?.toDouble() ?? 0,
      dailyLoad: (json['daily_load'] as num?)?.toDouble() ?? 0,
    );
  }

  /// 从通用统计 API 响应创建（兼容现有 /stations/{id}/statistics 端点）
  ///
  /// 后端 hour 模式返回:
  ///   energy_produce / energy_consume → 平均功率 (W)
  ///   battery_charge / battery_discharge → 平均功率 (W)，正值充电，负值放电
  ///   daily_pv / daily_charge / daily_discharge / daily_load → 日累计电量 (kWh)
  ///
  /// 后端 day/month 模式返回:
  ///   energy_produce / battery_charge / battery_discharge → 日累计电量 (kWh)
  ///
  /// 前端统一：
  ///   *Power 字段 → 功率 (W)，仅 hour 模式有效，供功率折线图使用
  ///   pvEnergy / batteryCharge / batteryDischarge / inverterOutput → 电量 (kWh)
  factory EnergyDataPoint.fromStationStats(Map<String, dynamic> json) {
    // 原始功率值 (W) - 来自 hour 模式
    final rawPvPower = (json['energy_produce'] ?? 0).toDouble();
    final rawAcPower = (json['energy_consume'] ?? json['ac_power'] ?? 0).toDouble();
    final rawBattCharge = (json['battery_charge'] ?? 0).toDouble();
    final rawBattDischarge = (json['battery_discharge'] ?? 0).toDouble();

    final rawGridImport = (json['grid_import'] ?? 0).toDouble();
    final rawGridExport = (json['grid_export'] ?? json['feed_energy'] ?? 0).toDouble();

    // 日累计电量 (kWh) - 来自 hour 模式的 daily_* 或 day/month 模式的顶层字段
    final dailyPvKwh = (json['daily_pv'] as num?)?.toDouble() ?? 0;
    final dailyChargeKwh = (json['daily_charge'] as num?)?.toDouble() ?? 0;
    final dailyDischargeKwh = (json['daily_discharge'] as num?)?.toDouble() ?? 0;
    final dailyLoadKwh = (json['daily_load'] as num?)?.toDouble() ?? 0;

    // 判断是否有 daily_* 字段（区分 hour 模式 vs day/month 模式）
    // 用 key 是否存在来判断，而不是值是否 > 0（避免凌晨全为 0 时误判）
    final hasDailyFields = json.containsKey('daily_charge') ||
        json.containsKey('daily_discharge') || json.containsKey('daily_pv');

    // 电量 (kWh)：hour 模式用 daily_* 累计值；day/month 模式直接用顶层字段
    final pvEnergyKwh = hasDailyFields ? dailyPvKwh : rawPvPower;
    final battChargeKwh = hasDailyFields ? dailyChargeKwh : rawBattCharge;
    final battDischargeKwh = hasDailyFields ? dailyDischargeKwh : rawBattDischarge;
    final invOutputKwh = hasDailyFields ? dailyLoadKwh : rawAcPower;

    return EnergyDataPoint(
      time: json['time'] as String? ?? '',
      pvEnergy: pvEnergyKwh,
      batteryCharge: battChargeKwh,
      batteryDischarge: battDischargeKwh,
      inverterOutput: invOutputKwh,
      gridImport: rawGridImport,
      gridExport: rawGridExport,
      dailyPv: dailyPvKwh,
      dailyLoad: dailyLoadKwh,
      // 功率字段仅 hour 模式有效
      pvPower: hasDailyFields ? rawPvPower : 0,
      batteryChargePower: hasDailyFields ? rawBattCharge : 0,
      batteryDischargePower: hasDailyFields ? rawBattDischarge : 0,
      inverterPower: hasDailyFields ? rawAcPower : 0,
      gridPower: hasDailyFields ? (rawGridImport - rawGridExport) : 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'time': time,
        'energy_produce': pvEnergy,
        'battery_charge': batteryCharge,
        'battery_discharge': batteryDischarge,
        'inverter_output': inverterOutput,
        'grid_import': gridImport,
        'grid_export': gridExport,
      };
}

/// 能源汇总数据 - 用于 4 宫格概览卡片
class EnergySummary {
  final double pvTotal; // PV 总发电量
  final double batteryChargeTotal; // 电池总充电量
  final double batteryDischargeTotal; // 电池总放电量
  final double inverterOutputTotal; // 逆变器总输出
  final double gridImportTotal; // 电网总输入
  final double gridExportTotal; // 电网总输出
  final double? pvChange; // PV 环比变化 (%)
  final double? batteryChargeChange;
  final double? batteryDischargeChange;
  final double? inverterOutputChange;

  const EnergySummary({
    this.pvTotal = 0,
    this.batteryChargeTotal = 0,
    this.batteryDischargeTotal = 0,
    this.inverterOutputTotal = 0,
    this.gridImportTotal = 0,
    this.gridExportTotal = 0,
    this.pvChange,
    this.batteryChargeChange,
    this.batteryDischargeChange,
    this.inverterOutputChange,
  });

  factory EnergySummary.fromDataPoints(List<EnergyDataPoint> points) {
    return EnergySummary(
      pvTotal: points.fold(0, (sum, p) => sum + p.pvEnergy),
      batteryChargeTotal: points.fold(0, (sum, p) => sum + p.batteryCharge),
      batteryDischargeTotal: points.fold(0, (sum, p) => sum + p.batteryDischarge),
      inverterOutputTotal: points.fold(0, (sum, p) => sum + p.inverterOutput),
      gridImportTotal: points.fold(0, (sum, p) => sum + p.gridImport),
      gridExportTotal: points.fold(0, (sum, p) => sum + p.gridExport),
    );
  }

  /// 根据周期计算汇总（日模式用最后点的累计值，月/年模式求和）
  factory EnergySummary.fromDataPointsWithPeriod(List<EnergyDataPoint> points, String period) {
    if (points.isEmpty) return const EnergySummary();
    if (period == 'day') {
      // 日模式（hour 数据）：每个数据点的 pvEnergy/batteryCharge 等已是日累计 kWh，
      // 取最后一个点即可（累计值随时间递增）
      final last = points.last;
      return EnergySummary(
        pvTotal: last.dailyPv,
        batteryChargeTotal: last.batteryCharge,
        batteryDischargeTotal: last.batteryDischarge,
        inverterOutputTotal: last.dailyLoad,
        gridImportTotal: last.gridImport,
        gridExportTotal: last.gridExport,
      );
    }
    // 月/年模式：求和
    return EnergySummary(
      pvTotal: points.fold(0.0, (sum, p) => sum + p.pvEnergy),
      batteryChargeTotal: points.fold(0.0, (sum, p) => sum + p.batteryCharge),
      batteryDischargeTotal: points.fold(0.0, (sum, p) => sum + p.batteryDischarge),
      inverterOutputTotal: points.fold(0.0, (sum, p) => sum + p.inverterOutput),
      gridImportTotal: points.fold(0.0, (sum, p) => sum + p.gridImport),
      gridExportTotal: points.fold(0.0, (sum, p) => sum + p.gridExport),
    );
  }
}
