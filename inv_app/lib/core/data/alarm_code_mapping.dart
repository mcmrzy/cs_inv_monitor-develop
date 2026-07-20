class AlarmCodeEntry {
  final int code;
  final String nameZh;
  final String nameEn;
  final String description;
  final String possibleCause;
  final String suggestion;
  final String severity; // fault / warning / info / normal
  final List<String> tags;

  const AlarmCodeEntry({
    required this.code,
    required this.nameZh,
    required this.nameEn,
    required this.description,
    required this.possibleCause,
    required this.suggestion,
    required this.severity,
    required this.tags,
  });

  String getLocalizedName(String languageCode) {
    return languageCode == 'zh' ? nameZh : nameEn;
  }

  String getLocalizedDescription(String languageCode) {
    if (languageCode == 'zh') return description;
    return AlarmCodeMapping.englishDetails[code]?.description ?? nameEn;
  }

  String getLocalizedPossibleCause(String languageCode) {
    if (languageCode == 'zh') return possibleCause;
    return AlarmCodeMapping.englishDetails[code]?.possibleCause ?? nameEn;
  }

  String getLocalizedSuggestion(String languageCode) {
    if (languageCode == 'zh') return suggestion;
    return AlarmCodeMapping.englishDetails[code]?.suggestion ??
        'Contact your installer or service provider for support.';
  }

  factory AlarmCodeEntry.fromJson(Map<String, dynamic> json) {
    return AlarmCodeEntry(
      code: json['code'] as int,
      nameZh: json['nameZh'] as String,
      nameEn: json['nameEn'] as String,
      description: json['description'] as String,
      possibleCause: json['possibleCause'] as String,
      suggestion: json['suggestion'] as String,
      severity: json['severity'] as String,
      tags: (json['tags'] as List<dynamic>).cast<String>(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'nameZh': nameZh,
      'nameEn': nameEn,
      'description': description,
      'possibleCause': possibleCause,
      'suggestion': suggestion,
      'severity': severity,
      'tags': tags,
    };
  }
}

class AlarmEnglishDetails {
  final String description;
  final String possibleCause;
  final String suggestion;

  const AlarmEnglishDetails({
    required this.description,
    required this.possibleCause,
    required this.suggestion,
  });
}

class AlarmCodeMapping {
  static const Map<int, AlarmEnglishDetails> englishDetails = {
    0: AlarmEnglishDetails(
      description:
          'All alarms have cleared and the inverter has returned to normal operation.',
      possibleCause:
          'The condition that triggered the previous alarm is no longer present.',
      suggestion: 'No action is required. Continue monitoring the system.',
    ),
    1: AlarmEnglishDetails(
      description:
          'The inverter exceeded its safe internal temperature and reduced output or stopped to protect its components.',
      possibleCause:
          'High ambient temperature\nBlocked airflow or vents\nCooling fan failure\nSustained operation at full load\nPoor ventilation around the inverter',
      suggestion:
          'Improve ventilation and remove obstructions\nClean the vents and air passages\nCheck that the cooling fan runs normally\nReduce the load temporarily\nContact the installer if overheating continues',
    ),
    2: AlarmEnglishDetails(
      description:
          'Battery voltage exceeded the safe upper limit, so charging was stopped to protect the battery.',
      possibleCause:
          'Charging voltage is set too high\nBMS balancing is abnormal\nVoltage sensing is out of calibration\nCharging control circuit fault\nAged battery with increased internal resistance',
      suggestion:
          'Measure the actual battery voltage\nVerify charging settings against the battery specification\nCheck BMS balancing and cell voltages\nVerify voltage sensing accuracy\nContact the installer if the condition persists',
    ),
    3: AlarmEnglishDetails(
      description:
          'Battery voltage fell below the safe lower limit, so discharge was restricted to prevent deep discharge damage.',
      possibleCause:
          'Battery charge is depleted\nDischarge cutoff is set incorrectly\nBattery capacity has degraded\nA load is continuously draining the battery\nVoltage sensing is out of calibration',
      suggestion:
          'Reduce or disconnect loads and charge the battery\nCheck the discharge cutoff setting\nEvaluate battery state of health\nCheck for abnormal loads\nContact the installer to review the system settings',
    ),
    4: AlarmEnglishDetails(
      description:
          'Inverter output exceeded its rated capacity and overload protection was activated.',
      possibleCause:
          'Total load exceeds inverter capacity\nLoad sizing is unsuitable\nMotor startup current is too high\nSeveral high-power loads started together\nThe inverter is undersized',
      suggestion:
          'Disconnect nonessential loads\nCheck the total load against the inverter rating\nStagger high-power load startup\nConsider a higher-capacity inverter\nAsk the installer to review system sizing',
    ),
    5: AlarmEnglishDetails(
      description:
          'The internal DC bus voltage exceeded its safe range and may damage inverter components.',
      possibleCause:
          'PV input voltage is above the MPPT range\nMPPT control is abnormal\nDC bus capacitors have degraded\nA load disconnected suddenly\nInternal control circuit fault',
      suggestion:
          'Check that PV input voltage is within range\nCheck MPPT operation\nTemporarily reduce PV input power\nContact service if the voltage remains high\nHave the DC bus capacitors inspected',
    ),
    6: AlarmEnglishDetails(
      description:
          'The inverter temperature is approaching the protection threshold, so output may be reduced.',
      possibleCause:
          'High ambient temperature\nPartially blocked airflow\nCooling fan speed is low\nThermal interface material has degraded\nSustained high-power operation',
      suggestion:
          'Improve ventilation\nClean vents and air passages\nCheck cooling fan operation\nReduce power temporarily\nContact the installer if temperature remains high',
    ),
    7: AlarmEnglishDetails(
      description:
          'Battery state of charge is below the safe limit and continued discharge may shorten battery life.',
      possibleCause:
          'The battery has discharged for too long\nThe charging system is not working\nLoad demand is too high\nBattery capacity has degraded\nSOC calibration is inaccurate',
      suggestion:
          'Reduce loads and charge the battery\nCheck the charging system\nReview load sizing\nCalibrate battery SOC\nReplace the battery if capacity is severely degraded',
    ),
    8: AlarmEnglishDetails(
      description:
          'PV string input is too low, too high, or unstable, which can reduce power generation.',
      possibleCause:
          'Insufficient sunlight\nModules are shaded or dirty\nPV wiring is loose or open\nString configuration is incorrect\nMPPT module fault',
      suggestion:
          'Check sunlight conditions\nClean modules and remove shading\nInspect PV cables and terminals\nMeasure each string voltage\nContact the installer if the condition persists',
    ),
    9: AlarmEnglishDetails(
      description:
          'The voltage difference between battery cells exceeds the allowed range and may affect safety and performance.',
      possibleCause:
          'Uneven cell aging\nBMS balancing fault\nInternal leakage in an individual cell\nUneven battery cooling\nThe pack has not been balanced recently',
      suggestion:
          'Check BMS balancing\nRun a manual balancing cycle\nCheck battery cooling\nRecord and monitor individual cell voltages\nContact the installer if the difference keeps increasing',
    ),
    10: AlarmEnglishDetails(
      description:
          'The inverter completed startup checks and entered normal operation.',
      possibleCause: 'Normal initialization after the inverter was powered on.',
      suggestion: 'No action is required.',
    ),
    11: AlarmEnglishDetails(
      description:
          'The inverter entered standby, usually because PV input is insufficient or standby was selected manually.',
      possibleCause:
          'Sunlight is below the startup threshold\nPV input power is insufficient\nStandby was selected manually\nGrid conditions do not allow connection',
      suggestion:
          'Wait for sunlight to improve\nCheck PV string connections\nCheck grid status\nContact the installer if standby continues unexpectedly',
    ),
    12: AlarmEnglishDetails(
      description:
          'The inverter resumed grid-connected operation and is supplying power normally.',
      possibleCause:
          'The previous standby condition cleared and grid-connection requirements are now met.',
      suggestion: 'No action is required. Continue monitoring the system.',
    ),
  };

  static const Map<int, AlarmCodeEntry> mapping = {
    0: AlarmCodeEntry(
      code: 0,
      nameZh: '故障恢复，正常运行',
      nameEn: 'Alarm cleared, normal operation',
      description: '所有告警已清除，逆变器恢复正常运行状态。',
      possibleCause: '之前的故障条件已消除，系统自动恢复。',
      suggestion: '无需操作，系统已恢复正常运行。',
      severity: 'normal',
      tags: ['系统', '恢复'],
    ),
    1: AlarmCodeEntry(
      code: 1,
      nameZh: '逆变器过温保护',
      nameEn: 'Inverter over-temperature protection',
      description: '逆变器内部温度超过安全上限，逆变器已触发过温保护机制，自动降低输出功率或停机以保护内部元器件。',
      possibleCause:
          '1. 环境温度超过逆变器工作范围\n2. 散热风道堵塞或进风口被遮挡\n3. 散热风扇故障停转\n4. 长时间满载运行导致热量积聚\n5. 逆变器安装位置通风不良',
      suggestion:
          '1. 检查逆变器安装环境通风是否良好，确保周围无遮挡物\n2. 清理散热风道和进风口灰尘\n3. 确认散热风扇运转正常\n4. 避免逆变器长时间满载运行，适当降低负载\n5. 如持续过温，联系安装商检查安装条件',
      severity: 'fault',
      tags: ['逆变器', '温度', '保护'],
    ),
    2: AlarmCodeEntry(
      code: 2,
      nameZh: '电池过压保护',
      nameEn: 'Battery over-voltage protection',
      description: '检测到电池组电压超过安全工作范围上限，可能对电池造成永久性损伤，系统已停止充电以保护电池。',
      possibleCause:
          '1. 充电电压参数设置过高\n2. BMS均衡功能异常，导致单体电压偏高\n3. 电池电压采样校准偏差\n4. 充电控制回路故障\n5. 电池老化导致内阻增大，端电压偏高',
      suggestion:
          '1. 立即检查电池实际电压，确认是否确实过压\n2. 核对充电参数设置是否与电池规格匹配\n3. 检查BMS均衡状态及单体电压\n4. 使用万用表校验电池采样精度\n5. 如持续过压，联系安装商检查充电控制',
      severity: 'fault',
      tags: ['电池', '电压', '保护'],
    ),
    3: AlarmCodeEntry(
      code: 3,
      nameZh: '电池欠压保护',
      nameEn: 'Battery under-voltage protection',
      description: '检测到电池组电压低于安全工作范围下限，继续放电可能导致电池过放损伤，系统已限制放电。',
      possibleCause:
          '1. 电池电量耗尽，SOC过低\n2. 放电截止电压设置过大\n3. 电池老化容量严重衰减\n4. 负载持续消耗导致电压持续下降\n5. 电池电压采样校准偏差',
      suggestion:
          '1. 立即减少或断开负载，对电池进行充电\n2. 检查放电截止电压设置是否合理\n3. 评估电池健康状态(SOH)，必要时更换电池\n4. 检查是否存在异常放电负载\n5. 联系安装商检查系统配置',
      severity: 'fault',
      tags: ['电池', '电压', '保护'],
    ),
    4: AlarmCodeEntry(
      code: 4,
      nameZh: '输出过载保护',
      nameEn: 'Output overload protection',
      description: '逆变器输出功率超过额定功率，持续过载可能导致逆变器损坏，系统已触发过载保护。',
      possibleCause:
          '1. 负载总功率超过逆变器额定容量\n2. 系统设计不合理，负载匹配不当\n3. 电机类负载启动电流过大\n4. 多个大功率负载同时启动\n5. 逆变器额定功率选型偏小',
      suggestion:
          '1. 立即减少非必要负载\n2. 检查负载总功率是否超过逆变器额定功率\n3. 避免多个大功率负载同时启动\n4. 评估是否需要更换更大功率的逆变器\n5. 联系安装商重新评估系统配置',
      severity: 'fault',
      tags: ['逆变器', '过载', '保护'],
    ),
    5: AlarmCodeEntry(
      code: 5,
      nameZh: '直流母线过压',
      nameEn: 'DC bus over-voltage',
      description: '逆变器内部DC母线电压超过安全范围，可能导致内部元器件损坏，需立即排查。',
      possibleCause:
          '1. PV输入电压过高，超出MPPT范围\n2. 逆变器MPPT控制异常\n3. DC母线滤波电容老化\n4. 负载突然断开导致电压飙升\n5. 逆变器内部控制回路故障',
      suggestion:
          '1. 检查PV输入电压是否在正常范围内\n2. 检查逆变器MPPT跟踪是否正常\n3. 适当减少PV输入功率观察DC母线电压变化\n4. 如持续过压，联系售后服务检查内部控制回路\n5. 可能需要检查DC母线电容状态',
      severity: 'fault',
      tags: ['逆变器', 'DC母线', '电压'],
    ),
    6: AlarmCodeEntry(
      code: 6,
      nameZh: '逆变器温度过高',
      nameEn: 'Inverter temperature too high',
      description: '逆变器内部温度偏高，接近过温保护阈值，逆变器将降低输出功率以防止过温。',
      possibleCause:
          '1. 环境温度偏高\n2. 散热风道部分堵塞\n3. 散热风扇转速降低\n4. 导热硅脂老化导致散热效率下降\n5. 长时间高功率运行',
      suggestion:
          '1. 检查逆变器安装环境通风条件\n2. 清理散热风道和进风口\n3. 确认散热风扇运转正常\n4. 改善逆变器安装环境通风\n5. 如温度持续偏高，联系安装商检查散热系统',
      severity: 'warning',
      tags: ['逆变器', '温度'],
    ),
    7: AlarmCodeEntry(
      code: 7,
      nameZh: '电池SOC过低',
      nameEn: 'Battery SOC too low',
      description: '电池荷电状态（SOC）低于安全下限，继续放电可能导致电池过放，严重影响电池寿命。',
      possibleCause:
          '1. 长时间放电未及时充电\n2. 充电系统故障导致无法充电\n3. 负载消耗过大\n4. 电池容量衰减严重\n5. SOC校准偏差',
      suggestion:
          '1. 立即减少负载，对电池进行充电\n2. 检查充电系统是否正常工作\n3. 评估负载配置是否合理\n4. 进行电池SOC校准\n5. 如电池容量衰减严重，考虑更换电池',
      severity: 'warning',
      tags: ['电池', 'SOC'],
    ),
    8: AlarmCodeEntry(
      code: 8,
      nameZh: 'PV输入异常',
      nameEn: 'PV input abnormal',
      description: '光伏组串输入异常，可能是电压过低、过高或不稳定，影响正常发电。',
      possibleCause:
          '1. 光照强度不足，PV电压低于启动电压\n2. 光伏组件严重遮挡或积灰\n3. PV线缆连接不良或断路\n4. 组串配置不合理\n5. MPPT模块异常',
      suggestion:
          '1. 检查光照条件是否满足发电要求\n2. 清洁光伏组件表面，移除遮挡物\n3. 检查PV线缆和接线端子是否完好\n4. 测量各组串电压，确认配置正确\n5. 如持续异常，联系安装商检查系统',
      severity: 'warning',
      tags: ['PV', '输入'],
    ),
    9: AlarmCodeEntry(
      code: 9,
      nameZh: '电芯压差过大',
      nameEn: 'Cell voltage difference too large',
      description: '电池组内各电芯之间的电压差异超过允许范围，表明电池一致性变差，可能影响电池组性能和安全。',
      possibleCause:
          '1. 电芯老化程度不一致\n2. BMS均衡功能异常\n3. 个别电芯存在内部微短路\n4. 电池组散热不均匀\n5. 电池长期未进行均衡维护',
      suggestion:
          '1. 检查BMS均衡功能是否正常\n2. 执行手动均衡操作\n3. 检查电池组散热是否均匀\n4. 记录各电芯电压，跟踪压差变化趋势\n5. 如压差持续增大，联系安装商评估电池更换',
      severity: 'warning',
      tags: ['电池', '电芯', '均衡'],
    ),
    10: AlarmCodeEntry(
      code: 10,
      nameZh: '系统启动完成',
      nameEn: 'System startup completed',
      description: '逆变器系统启动流程已完成，各项自检通过，进入正常运行状态。',
      possibleCause: '逆变器上电后完成初始化自检。',
      suggestion: '无需操作，系统已正常启动。',
      severity: 'info',
      tags: ['系统', '启动'],
    ),
    11: AlarmCodeEntry(
      code: 11,
      nameZh: '进入待机模式',
      nameEn: 'Entering standby mode',
      description: '逆变器进入待机模式，通常由于光照不足、无PV输入或用户手动操作。',
      possibleCause: '1. 光照强度低于启动阈值\n2. PV输入功率不足\n3. 用户手动设置待机\n4. 电网异常导致无法并网',
      suggestion:
          '1. 等待光照条件改善，逆变器将自动恢复并网\n2. 检查PV组串连接是否正常\n3. 检查电网状态是否正常\n4. 如长时间待机，联系安装商检查系统',
      severity: 'info',
      tags: ['系统', '待机'],
    ),
    12: AlarmCodeEntry(
      code: 12,
      nameZh: '恢复并网运行',
      nameEn: 'Grid connection resumed',
      description: '逆变器已恢复并网运行，各项参数正常，开始向电网供电。',
      possibleCause: '之前的待机条件已消除，系统满足并网条件。',
      suggestion: '无需操作，系统已恢复并网运行。',
      severity: 'info',
      tags: ['系统', '并网'],
    ),
  };

  static AlarmCodeEntry? getEntry(int code) => mapping[code];

  static String getNameZh(int code) {
    final entry = mapping[code];
    return entry?.nameZh ?? '未知告警(code=$code)';
  }

  static String getLocalizedName(int code, String languageCode) {
    final entry = mapping[code];
    if (entry == null) {
      return languageCode == 'zh'
          ? '未知告警(code=$code)'
          : 'Unknown alarm(code=$code)';
    }
    return entry.getLocalizedName(languageCode);
  }

  static String getDescription(int code) {
    final entry = mapping[code];
    return entry?.description ?? '暂无该告警码的详细描述信息。';
  }

  static String getSuggestion(int code) {
    final entry = mapping[code];
    return entry?.suggestion ?? '请联系安装商或售后服务获取技术支持。';
  }

  static List<AlarmCodeEntry> search(String keyword) {
    final lowerKeyword = keyword.toLowerCase();
    return mapping.values.where((entry) {
      return entry.nameZh.contains(keyword) ||
          entry.nameEn.toLowerCase().contains(lowerKeyword) ||
          entry.description.contains(keyword) ||
          entry.possibleCause.contains(keyword) ||
          entry.suggestion.contains(keyword) ||
          entry.tags.any((tag) => tag.contains(keyword)) ||
          entry.code.toString().contains(keyword);
    }).toList();
  }

  static List<AlarmCodeEntry> getBySeverity(String severity) {
    return mapping.values.where((entry) => entry.severity == severity).toList();
  }
}
