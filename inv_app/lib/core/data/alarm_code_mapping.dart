class AlarmCodeEntry {
  final int code;
  final String nameZh;
  final String nameEn;
  final String description;
  final String possibleCause;
  final String suggestion;
  final String severity;
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

class AlarmCodeMapping {
  static const Map<int, AlarmCodeEntry> mapping = {
    0x0001: AlarmCodeEntry(
      code: 0x0001,
      nameZh: '电网过压',
      nameEn: 'AC grid over voltage',
      description: '检测到交流电网电压超过逆变器允许的最大工作电压范围，逆变器将自动断开与电网的连接以保护设备安全。',
      possibleCause: '1. 电网电压异常升高\n2. 变压器输出电压设置过高\n3. 电网负荷突然减小导致电压升高\n4. 线缆阻抗过小导致末端电压偏高\n5. 逆变器电压采样校准偏差',
      suggestion: '1. 使用万用表测量实际电网电压，确认是否确实过压\n2. 联系电力公司确认电网电压是否在正常范围\n3. 检查逆变器交流侧接线是否牢固\n4. 如持续过压，联系安装商调整逆变器电压保护参数\n5. 必要时更换变压器抽头位置',
      severity: 'critical',
      tags: ['电网', '电压', '保护'],
    ),
    0x0002: AlarmCodeEntry(
      code: 0x0002,
      nameZh: '电网欠压',
      nameEn: 'AC grid under voltage',
      description: '检测到交流电网电压低于逆变器允许的最低工作电压范围，逆变器将自动断开与电网的连接以保护设备安全。',
      possibleCause: '1. 电网电压异常降低\n2. 电网负荷突然增大导致电压骤降\n3. 交流线缆过长或截面积不足导致压降过大\n4. 交流侧接线端子松动或氧化\n5. 逆变器电压采样校准偏差',
      suggestion: '1. 使用万用表测量实际电网电压，确认是否确实欠压\n2. 检查交流线缆截面积是否符合要求\n3. 检查交流侧接线端子是否紧固\n4. 联系电力公司确认电网供电是否正常\n5. 如持续欠压，联系安装商检查线路压降',
      severity: 'critical',
      tags: ['电网', '电压', '保护'],
    ),
    0x0004: AlarmCodeEntry(
      code: 0x0004,
      nameZh: '电网过频',
      nameEn: 'AC grid over frequency',
      description: '检测到交流电网频率超过逆变器允许的最高工作频率范围，逆变器将自动断开与电网的连接以保护设备安全。',
      possibleCause: '1. 电网频率异常升高\n2. 电网负荷突变导致频率波动\n3. 小型孤岛电网中发电量过剩\n4. 逆变器频率采样异常',
      suggestion: '1. 使用频率表测量实际电网频率\n2. 联系电力公司确认电网频率是否正常\n3. 检查逆变器是否在孤岛状态下运行\n4. 如频率持续异常，暂停逆变器运行并联系安装商',
      severity: 'critical',
      tags: ['电网', '频率', '保护'],
    ),
    0x0008: AlarmCodeEntry(
      code: 0x0008,
      nameZh: '电网欠频',
      nameEn: 'AC grid under frequency',
      description: '检测到交流电网频率低于逆变器允许的最低工作频率范围，逆变器将自动断开与电网的连接以保护设备安全。',
      possibleCause: '1. 电网频率异常降低\n2. 电网负荷过重导致频率下降\n3. 发电机组出力不足\n4. 逆变器频率采样异常',
      suggestion: '1. 使用频率表测量实际电网频率\n2. 联系电力公司确认电网供电是否正常\n3. 检查电网是否存在过载情况\n4. 如频率持续异常，暂停逆变器运行并联系安装商',
      severity: 'critical',
      tags: ['电网', '频率', '保护'],
    ),
    0x0010: AlarmCodeEntry(
      code: 0x0010,
      nameZh: 'PV过压',
      nameEn: 'PV over voltage',
      description: '检测到光伏组串输入电压超过逆变器允许的最大直流输入电压，可能导致逆变器损坏，需立即处理。',
      possibleCause: '1. 光伏组串串联组件数量过多\n2. 环境温度过低导致开路电压升高\n3. 光照强度突然增大\n4. PV接线错误导致组串电压叠加',
      suggestion: '1. 立即断开PV输入，检查组串配置\n2. 核对组件开路电压和温度系数计算最大电压\n3. 确认组串串联数量不超过逆变器最大输入电压\n4. 如组串配置错误，重新调整组串连接方式\n5. 联系安装商进行现场检查',
      severity: 'critical',
      tags: ['PV', '电压', '保护'],
    ),
    0x0020: AlarmCodeEntry(
      code: 0x0020,
      nameZh: 'PV欠压',
      nameEn: 'PV under voltage',
      description: '检测到光伏组串输入电压低于逆变器最低启动电压，逆变器无法正常工作。',
      possibleCause: '1. 光照强度不足\n2. 光伏组件严重遮挡或积灰\n3. PV线缆连接不良或断路\n4. 光伏组件损坏或老化\n5. 组串并联数量不足',
      suggestion: '1. 检查光照条件是否满足发电要求\n2. 清洁光伏组件表面，移除遮挡物\n3. 检查PV线缆和接线端子是否完好\n4. 测量各组串电压，排查损坏组件\n5. 如电压持续偏低，联系安装商检查系统设计',
      severity: 'warning',
      tags: ['PV', '电压'],
    ),
    0x0040: AlarmCodeEntry(
      code: 0x0040,
      nameZh: '电池过压',
      nameEn: 'Battery over voltage',
      description: '检测到电池组电压超过安全工作范围的上限，可能对电池造成永久性损伤，需立即停止充电。',
      possibleCause: '1. 充电电压设置过高\n2. BMS均衡功能异常\n3. 电池采样校准偏差\n4. 充电控制回路故障\n5. 电池老化导致内阻增大',
      suggestion: '1. 立即停止充电，检查电池实际电压\n2. 核对充电参数设置是否正确\n3. 检查BMS均衡状态\n4. 使用万用表校验电池采样精度\n5. 如持续过压，联系安装商检查充电控制',
      severity: 'critical',
      tags: ['电池', '电压', '保护'],
    ),
    0x0080: AlarmCodeEntry(
      code: 0x0080,
      nameZh: '电池欠压',
      nameEn: 'Battery under voltage',
      description: '检测到电池组电压低于安全工作范围的下限，继续放电可能导致电池过放损伤。',
      possibleCause: '1. 电池电量耗尽\n2. 放电深度设置过大\n3. 电池老化容量衰减\n4. 负载持续消耗导致电压持续下降\n5. 电池采样校准偏差',
      suggestion: '1. 立即停止放电，对电池进行充电\n2. 检查放电截止电压设置是否合理\n3. 评估电池健康状态，必要时更换电池\n4. 检查是否存在异常放电负载\n5. 联系安装商检查系统配置',
      severity: 'warning',
      tags: ['电池', '电压', '保护'],
    ),
    0x0100: AlarmCodeEntry(
      code: 0x0100,
      nameZh: '电池过温',
      nameEn: 'Battery over temperature',
      description: '检测到电池温度超过安全工作温度上限，继续充放电可能导致热失控风险，需立即停止充放电。',
      possibleCause: '1. 环境温度过高\n2. 电池散热系统故障\n3. 大电流充放电导致发热\n4. 电池内部短路\n5. 温度传感器故障',
      suggestion: '1. 立即停止充放电操作\n2. 检查电池安装环境通风散热是否良好\n3. 确认散热风扇或空调是否正常工作\n4. 等待电池温度降至安全范围后恢复运行\n5. 如温度异常升高，联系安装商排查电池安全',
      severity: 'critical',
      tags: ['电池', '温度', '保护'],
    ),
    0x0200: AlarmCodeEntry(
      code: 0x0200,
      nameZh: '电池低温',
      nameEn: 'Battery under temperature',
      description: '检测到电池温度低于安全工作温度下限，低温下充放电可能导致电池性能下降和损伤。',
      possibleCause: '1. 环境温度过低\n2. 电池加热系统故障\n3. 电池安装在无保温措施的室外\n4. 极端低温天气',
      suggestion: '1. 暂停充放电操作，等待温度回升\n2. 检查电池加热系统是否正常工作\n3. 考虑为电池增加保温措施\n4. 如长期低温环境，联系安装商评估电池选型',
      severity: 'warning',
      tags: ['电池', '温度'],
    ),
    0x0400: AlarmCodeEntry(
      code: 0x0400,
      nameZh: '逆变器过温',
      nameEn: 'Inverter over temperature',
      description: '检测到逆变器内部温度超过安全工作温度上限，逆变器将降低输出功率或停机以保护内部元器件。',
      possibleCause: '1. 环境温度过高\n2. 逆变器散热风道堵塞\n3. 长时间满载运行\n4. 散热风扇故障\n5. 逆变器安装位置通风不良',
      suggestion: '1. 检查逆变器安装环境通风是否良好\n2. 清理散热风道和进风口灰尘\n3. 确认散热风扇运转正常\n4. 避免逆变器长时间满载运行\n5. 如持续过温，联系安装商检查安装条件',
      severity: 'critical',
      tags: ['逆变器', '温度', '保护'],
    ),
    0x0800: AlarmCodeEntry(
      code: 0x0800,
      nameZh: '逆变器过载',
      nameEn: 'Inverter overload',
      description: '逆变器输出功率超过额定功率，持续过载可能导致逆变器损坏，需降低负载或检查系统配置。',
      possibleCause: '1. 负载功率超过逆变器额定容量\n2. 系统设计不合理，负载匹配不当\n3. 电机类负载启动电流过大\n4. 多个负载同时启动\n5. 逆变器额定功率选型偏小',
      suggestion: '1. 立即减少非必要负载\n2. 检查负载总功率是否超过逆变器额定功率\n3. 避免多个大功率负载同时启动\n4. 评估是否需要更换更大功率的逆变器\n5. 联系安装商重新评估系统配置',
      severity: 'critical',
      tags: ['逆变器', '过载', '保护'],
    ),
    0x1000: AlarmCodeEntry(
      code: 0x1000,
      nameZh: '短路保护',
      nameEn: 'Short circuit protection',
      description: '检测到输出侧短路，逆变器已触发短路保护机制，立即切断输出以防止设备损坏和火灾风险。',
      possibleCause: '1. 输出线缆短路\n2. 接线端子短路\n3. 负载内部短路\n4. 线缆绝缘层破损导致短路\n5. 异物导致接线端子短接',
      suggestion: '1. 立即断开逆变器所有输出连接\n2. 逐段检查输出线缆绝缘状况\n3. 检查接线端子是否有异物或烧蚀痕迹\n4. 使用绝缘电阻测试仪检测线路绝缘\n5. 排除短路故障后方可重新启动逆变器\n6. 如无法排查，联系安装商或售后服务',
      severity: 'critical',
      tags: ['逆变器', '短路', '保护'],
    ),
    0x2000: AlarmCodeEntry(
      code: 0x2000,
      nameZh: '漏流保护',
      nameEn: 'Leakage current protection',
      description: '检测到系统漏电流超过安全阈值，可能存在绝缘故障，存在触电风险，需立即排查。',
      possibleCause: '1. 线缆绝缘层破损或老化\n2. 接线端子受潮或进水\n3. 组件边框接地不良\n4. 逆变器内部绝缘异常\n5. 雷击导致绝缘损坏',
      suggestion: '1. 立即断开逆变器运行\n2. 检查所有线缆绝缘状况\n3. 检查接线盒和端子是否受潮\n4. 使用绝缘电阻测试仪检测系统绝缘\n5. 排除漏电故障后方可重新启动\n6. 联系安装商进行专业绝缘检测',
      severity: 'critical',
      tags: ['安全', '漏电', '保护'],
    ),
    0x4000: AlarmCodeEntry(
      code: 0x4000,
      nameZh: '接地故障',
      nameEn: 'Ground fault',
      description: '检测到系统接地异常，可能存在接地线断开或接地电阻过大，影响系统安全运行。',
      possibleCause: '1. 接地线断开或松动\n2. 接地电阻过大\n3. 接地线腐蚀\n4. 接地系统设计不合理\n5. 土壤电阻率过高',
      suggestion: '1. 检查接地线连接是否牢固\n2. 测量接地电阻是否符合规范要求\n3. 检查接地线是否有腐蚀或断裂\n4. 如接地电阻过大，增加接地极或改善接地条件\n5. 联系安装商进行接地系统检测',
      severity: 'critical',
      tags: ['安全', '接地', '保护'],
    ),
    0x8000: AlarmCodeEntry(
      code: 0x8000,
      nameZh: '通信故障',
      nameEn: 'Communication error',
      description: '逆变器与外部设备（如监控模块、BMS等）之间的通信中断或异常，无法正常交换数据。',
      possibleCause: '1. 通信线缆断开或接触不良\n2. 通信参数配置错误（波特率、地址等）\n3. 通信线缆受到电磁干扰\n4. 通信模块硬件故障\n5. 外部设备未上电或故障',
      suggestion: '1. 检查通信线缆连接是否正常\n2. 核对通信参数配置是否一致\n3. 检查通信线缆是否远离强电线路\n4. 尝试重新上电恢复通信\n5. 如通信持续异常，联系安装商检查通信模块',
      severity: 'warning',
      tags: ['通信', '故障'],
    ),
    0x00010001: AlarmCodeEntry(
      code: 0x00010001,
      nameZh: '电池SOC过低',
      nameEn: 'Battery SOC too low',
      description: '电池荷电状态（SOC）低于安全下限，继续放电可能导致电池过放，严重影响电池寿命。',
      possibleCause: '1. 长时间放电未及时充电\n2. 充电系统故障导致无法充电\n3. 负载消耗过大\n4. 电池容量衰减严重\n5. SOC校准偏差',
      suggestion: '1. 立即减少负载，对电池进行充电\n2. 检查充电系统是否正常工作\n3. 评估负载配置是否合理\n4. 进行电池SOC校准\n5. 如电池容量衰减严重，考虑更换电池',
      severity: 'warning',
      tags: ['电池', 'SOC'],
    ),
    0x00010002: AlarmCodeEntry(
      code: 0x00010002,
      nameZh: '电池充放过流',
      nameEn: 'Battery charge/discharge over current',
      description: '电池充放电电流超过安全允许范围，可能导致电池发热、损伤甚至安全事故。',
      possibleCause: '1. 充放电电流设置过大\n2. 负载突变导致电流激增\n3. BMS电流保护功能异常\n4. 逆变器充放电控制故障\n5. 电池内阻异常',
      suggestion: '1. 立即降低充放电功率\n2. 检查充放电电流限制设置\n3. 排查是否存在突变负载\n4. 检查BMS电流保护参数\n5. 联系安装商检查充放电控制策略',
      severity: 'critical',
      tags: ['电池', '电流', '保护'],
    ),
    0x00010004: AlarmCodeEntry(
      code: 0x00010004,
      nameZh: '电芯压差过大',
      nameEn: 'Cell voltage difference too large',
      description: '电池组内各电芯之间的电压差异超过允许范围，表明电池一致性变差，可能影响电池组性能和安全。',
      possibleCause: '1. 电芯老化程度不一致\n2. BMS均衡功能异常\n3. 个别电芯存在内部微短路\n4. 电池组散热不均匀\n5. 电池长期未进行均衡维护',
      suggestion: '1. 检查BMS均衡功能是否正常\n2. 执行手动均衡操作\n3. 检查电池组散热是否均匀\n4. 记录各电芯电压，跟踪压差变化趋势\n5. 如压差持续增大，联系安装商评估电池更换',
      severity: 'warning',
      tags: ['电池', '电芯', '均衡'],
    ),
    0x00010008: AlarmCodeEntry(
      code: 0x00010008,
      nameZh: 'BMS通信断开',
      nameEn: 'BMS communication lost',
      description: '逆变器与电池管理系统（BMS）之间的通信中断，无法获取电池状态信息，为保护电池安全将限制充放电。',
      possibleCause: '1. BMS通信线缆断开或松动\n2. BMS未上电或已关机\n3. 通信线缆受到干扰\n4. BMS通信模块故障\n5. 通信协议不匹配',
      suggestion: '1. 检查BMS供电是否正常\n2. 检查通信线缆连接是否牢固\n3. 确认通信协议和参数配置一致\n4. 尝试重启BMS和逆变器\n5. 如通信持续中断，联系安装商检查BMS',
      severity: 'critical',
      tags: ['电池', 'BMS', '通信'],
    ),
    0x00010010: AlarmCodeEntry(
      code: 0x00010010,
      nameZh: '电池绝缘故障',
      nameEn: 'Battery insulation fault',
      description: '检测到电池系统绝缘电阻低于安全阈值，存在漏电风险，可能危及人身安全。',
      possibleCause: '1. 电池外壳破损导致绝缘下降\n2. 电池接线端子受潮\n3. 电池线缆绝缘层破损\n4. 电池内部电解液泄漏\n5. 环境湿度过高',
      suggestion: '1. 立即停止电池充放电\n2. 使用绝缘电阻测试仪检测绝缘状况\n3. 检查电池外壳和接线端子\n4. 检查环境湿度是否过高\n5. 排除绝缘故障后方可恢复运行\n6. 联系安装商或电池厂家进行专业检测',
      severity: 'critical',
      tags: ['电池', '绝缘', '安全'],
    ),
    0x00020001: AlarmCodeEntry(
      code: 0x00020001,
      nameZh: 'DC母线过压',
      nameEn: 'DC bus over voltage',
      description: '逆变器内部DC母线电压超过安全范围，可能导致内部元器件损坏，需立即排查。',
      possibleCause: '1. PV输入电压过高\n2. 逆变器MPPT控制异常\n3. DC母线电容老化\n4. 负载突然断开导致电压飙升\n5. 逆变器内部控制回路故障',
      suggestion: '1. 检查PV输入电压是否在正常范围\n2. 检查逆变器MPPT跟踪是否正常\n3. 减少PV输入功率观察DC母线电压\n4. 如持续过压，联系售后服务检查内部控制',
      severity: 'critical',
      tags: ['逆变器', 'DC母线', '电压'],
    ),
    0x00020002: AlarmCodeEntry(
      code: 0x00020002,
      nameZh: 'DC母线欠压',
      nameEn: 'DC bus under voltage',
      description: '逆变器内部DC母线电压低于正常工作范围，可能导致逆变器无法正常输出。',
      possibleCause: '1. PV输入功率不足\n2. 电池电量不足\n3. DC母线电容故障\n4. 逆变器内部损耗过大\n5. 负载功率超过输入功率',
      suggestion: '1. 检查PV输入是否正常\n2. 检查电池电量和电压\n3. 减少负载功率\n4. 如持续欠压，联系售后服务检查内部电路',
      severity: 'warning',
      tags: ['逆变器', 'DC母线', '电压'],
    ),
    0x00020004: AlarmCodeEntry(
      code: 0x00020004,
      nameZh: '散热器过温',
      nameEn: 'Heat sink over temperature',
      description: '逆变器散热器温度超过安全阈值，可能影响功率器件寿命，逆变器将降低输出功率。',
      possibleCause: '1. 环境温度过高\n2. 散热风道堵塞\n3. 散热风扇故障\n4. 导热硅脂老化失效\n5. 长时间高功率运行',
      suggestion: '1. 检查散热风道是否畅通\n2. 清理散热器灰尘\n3. 确认散热风扇运转正常\n4. 改善逆变器安装环境通风\n5. 如持续过温，联系售后服务检查散热系统',
      severity: 'warning',
      tags: ['逆变器', '温度', '散热'],
    ),
    0x00020008: AlarmCodeEntry(
      code: 0x00020008,
      nameZh: '风扇故障',
      nameEn: 'Fan failure',
      description: '逆变器散热风扇异常，无法正常运转，将导致逆变器散热能力下降，可能触发过温保护。',
      possibleCause: '1. 风扇电机损坏\n2. 风扇电源线松动或断开\n3. 风扇轴承卡死\n4. 风扇被异物卡住\n5. 风扇驱动电路故障',
      suggestion: '1. 检查风扇是否有异物阻挡\n2. 听风扇是否有异常噪音\n3. 尝试手动拨动风扇确认是否卡死\n4. 检查风扇电源线连接\n5. 如风扇损坏，联系售后服务更换风扇',
      severity: 'warning',
      tags: ['逆变器', '风扇', '散热'],
    ),
    0x00020010: AlarmCodeEntry(
      code: 0x00020010,
      nameZh: 'EEPROM错误',
      nameEn: 'EEPROM error',
      description: '逆变器内部EEPROM存储器读写异常，可能导致参数丢失或配置错误。',
      possibleCause: '1. EEPROM芯片损坏\n2. 读写时断电导致数据损坏\n3. 电磁干扰导致数据错误\n4. EEPROM寿命耗尽\n5. 内部通信异常',
      suggestion: '1. 尝试重启逆变器恢复\n2. 检查逆变器参数是否丢失\n3. 重新配置逆变器参数\n4. 如反复出现EEPROM错误，联系售后服务\n5. 可能需要更换EEPROM芯片或主板',
      severity: 'warning',
      tags: ['逆变器', '存储', '硬件'],
    ),
    0x00020020: AlarmCodeEntry(
      code: 0x00020020,
      nameZh: 'SPI通信错误',
      nameEn: 'SPI communication error',
      description: '逆变器内部SPI总线通信异常，可能导致内部模块间数据交换失败，影响逆变器正常运行。',
      possibleCause: '1. SPI总线连接异常\n2. 电磁干扰导致通信错误\n3. SPI从设备故障\n4. 内部电源不稳定\n5. 软件协议异常',
      suggestion: '1. 尝试重启逆变器\n2. 检查逆变器固件版本是否为最新\n3. 如有固件更新，尝试升级固件\n4. 如持续出现，联系售后服务检查内部电路',
      severity: 'warning',
      tags: ['逆变器', '通信', '硬件'],
    ),
    0x00020040: AlarmCodeEntry(
      code: 0x00020040,
      nameZh: 'ADC采样异常',
      nameEn: 'ADC sampling error',
      description: '逆变器内部模数转换器（ADC）采样异常，可能导致电压、电流等关键参数测量不准确。',
      possibleCause: '1. ADC参考电压异常\n2. 采样通道故障\n3. 电磁干扰影响采样精度\n4. ADC芯片损坏\n5. 采样电路元件老化',
      suggestion: '1. 尝试重启逆变器\n2. 对比逆变器显示值与万用表测量值\n3. 如测量偏差较大，暂停运行\n4. 联系售后服务检查ADC采样电路\n5. 可能需要更换主板',
      severity: 'critical',
      tags: ['逆变器', '采样', '硬件'],
    ),
    0x00020080: AlarmCodeEntry(
      code: 0x00020080,
      nameZh: '继电器故障',
      nameEn: 'Relay fault',
      description: '逆变器内部继电器异常，可能导致无法正常并网或断开，影响系统安全运行。',
      possibleCause: '1. 继电器触点粘连\n2. 继电器线圈故障\n3. 继电器驱动电路异常\n4. 继电器机械结构卡死\n5. 继电器寿命到期',
      suggestion: '1. 尝试重启逆变器\n2. 检查继电器吸合和释放是否正常\n3. 如继电器粘连，切勿强行并网\n4. 联系售后服务更换继电器\n5. 可能需要更换主板或继电器模块',
      severity: 'critical',
      tags: ['逆变器', '继电器', '硬件'],
    ),
    0x00020100: AlarmCodeEntry(
      code: 0x00020100,
      nameZh: '固件校验失败',
      nameEn: 'Firmware checksum error',
      description: '逆变器固件完整性校验失败，可能由于固件损坏或升级中断导致，逆变器可能无法正常启动。',
      possibleCause: '1. 固件升级过程中断电\n2. 固件升级过程中通信中断\n3. 固件文件损坏\n4. Flash存储器故障\n5. 固件版本不兼容',
      suggestion: '1. 尝试重新进行固件升级\n2. 确保升级过程中电源稳定\n3. 确保升级过程中通信稳定\n4. 使用正确版本的固件文件\n5. 如反复校验失败，联系售后服务\n6. 可能需要通过串口进行底层固件恢复',
      severity: 'critical',
      tags: ['逆变器', '固件', '升级'],
    ),
  };

  static AlarmCodeEntry? getEntry(int code) => mapping[code];

  static String getNameZh(int code) {
    final entry = mapping[code];
    return entry?.nameZh ?? '未知告警(0x${code.toRadixString(16).toUpperCase()})';
  }

  static String getLocalizedName(int code, String languageCode) {
    final entry = mapping[code];
    if (entry == null) {
      return languageCode == 'zh'
          ? '未知告警(0x${code.toRadixString(16).toUpperCase()})'
          : 'Unknown alarm(0x${code.toRadixString(16).toUpperCase()})';
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
          '0x${entry.code.toRadixString(16).toLowerCase()}'.contains(lowerKeyword) ||
          entry.code.toString().contains(keyword);
    }).toList();
  }

  static List<AlarmCodeEntry> getBySeverity(String severity) {
    return mapping.values.where((entry) => entry.severity == severity).toList();
  }
}
