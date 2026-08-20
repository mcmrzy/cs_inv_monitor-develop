/// config v2 参数 schema 实体与工具函数
///
/// 数据来源：GET /devices/by-sn/{sn}/config-schema（device_config_schema 42 键）。
/// 值来源：GET /devices/by-sn/{sn}/control-state（desired 优先、reported 兜底）。
/// 注意：control-state 中的值已是工程单位（如 230.0 V），App 直接显示与写回，
/// 不做 scale 换算。
class ConfigParamSchema {
  /// 参数键名（如 set_output_priority）
  final String paramKey;

  /// 分组编码：general | application | hybrid | parallel
  final String groupCode;

  /// 子分组（charge / discharge / equalize / gen / soc 等，可空）
  final String? subGroup;

  /// 控件类型：number | enum | boolean
  final String controlType;

  /// 协议缩放系数（值已工程单位化，仅存档展示用，不参与换算）
  final double scale;

  /// 工程单位（V / A / Hz / % / min 等，可空）
  final String? unit;

  /// 数值型参数最小值
  final double? min;

  /// 数值型参数最大值
  final double? max;

  /// 枚举映射：{"0":"solar_first","1":"utility_first",...}
  final Map<String, String>? enumMap;

  /// 滑块步长（缺省时按 (max-min)/100 处理）
  final double? step;

  /// 权限编码（App 端暂不使用，保留）
  final String? permissionCode;

  /// 确认模式：'modal' 表示修改前需弹确认对话框，null 表示无需确认
  final String? confirmationMode;

  /// 显示名 i18n key（如 config.set_output_priority）
  final String displayNameKey;

  /// 排序序号
  final int sortOrder;

  /// 可见性联动条件：{"param":"set_battery_type","eq":0} 或 {"param":...,"ne":2}
  final Map<String, dynamic>? visibility;

  const ConfigParamSchema({
    required this.paramKey,
    required this.groupCode,
    this.subGroup,
    required this.controlType,
    this.scale = 1,
    this.unit,
    this.min,
    this.max,
    this.enumMap,
    this.step,
    this.permissionCode,
    this.confirmationMode,
    required this.displayNameKey,
    this.sortOrder = 0,
    this.visibility,
  });

  factory ConfigParamSchema.fromJson(Map<String, dynamic> json) {
    double? toDouble(dynamic v) => v is num ? v.toDouble() : null;
    Map<String, dynamic>? toMap(dynamic v) =>
        v is Map ? v.cast<String, dynamic>() : null;

    Map<String, String>? enumMap;
    final rawEnum = json['enum_map'];
    if (rawEnum is Map) {
      enumMap = rawEnum.map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    return ConfigParamSchema(
      paramKey: json['param_key']?.toString() ?? '',
      groupCode: json['group_code']?.toString() ?? 'general',
      subGroup: json['sub_group']?.toString(),
      controlType: json['control_type']?.toString() ?? 'number',
      scale: toDouble(json['scale']) ?? 1,
      unit: json['unit']?.toString(),
      min: toDouble(json['min']),
      max: toDouble(json['max']),
      enumMap: enumMap,
      step: toDouble(json['step']),
      permissionCode: json['permission_code']?.toString(),
      confirmationMode: json['confirmation_mode']?.toString(),
      displayNameKey:
          json['display_name_key']?.toString() ?? 'config.${json['param_key']}',
      sortOrder: (json['sort_order'] is num)
          ? (json['sort_order'] as num).toInt()
          : 0,
      visibility: toMap(json['visibility']),
    );
  }

  /// 是否需要修改前二次确认（modal）
  bool get needsModalConfirm => confirmationMode == 'modal';

  /// display_name_key（config.set_xxx）→ l10n key（config_set_xxx）
  String get l10nNameKey => displayNameKey.replaceAll('.', '_');

  /// 有效滑块步长：schema.step 优先，缺省用 (max-min)/100
  double get effectiveStep {
    if (step != null && step! > 0) return step!;
    if (min != null && max != null && max! > min!) return (max! - min!) / 100;
    return 1;
  }

  /// 枚举选项（按选项值数值升序）：[{key:'0', value:'solar_first'}, ...]
  List<ConfigEnumOption> get enumOptions {
    final map = enumMap;
    if (map == null || map.isEmpty) return const [];
    final entries = map.entries.toList()
      ..sort((a, b) {
        final ka = double.tryParse(a.key);
        final kb = double.tryParse(b.key);
        if (ka != null && kb != null) return ka.compareTo(kb);
        return a.key.compareTo(b.key);
      });
    return entries
        .map((e) => ConfigEnumOption(key: e.key, value: e.value))
        .toList();
  }
}

/// 枚举选项：key 为线上值（"0"/"1"...），value 为语义名（solar_first 等）
class ConfigEnumOption {
  final String key;
  final String value;

  const ConfigEnumOption({required this.key, required this.value});
}

/// group_code 展示顺序（高级参数页分组渲染用）
const List<String> configGroupOrder = [
  'general',
  'application',
  'hybrid',
  'parallel',
];

/// 合并 control-state（编辑值）：desired 优先，缺失用 reported 兜底。
/// 用于输入框当前值与修改基线（展示"下发意图"，与 Web 端 getEditValue 对齐）。
Map<String, dynamic> mergeControlState(Map<String, dynamic> state) {
  final desired = state['desired'];
  final reported = state['reported'];
  return {
    if (reported is Map) ...reported.cast<String, dynamic>(),
    if (desired is Map) ...desired.cast<String, dynamic>(),
  };
}

/// 合并 control-state（展示值）：reported 优先，缺失用 desired 兜底。
/// 用于分类摘要等"设备真实值"展示（读取设备配置后不被旧 desired 遮蔽，
/// 与 Web 端 getSummaryValue 对齐）。
Map<String, dynamic> mergeControlStateReportedFirst(Map<String, dynamic> state) {
  final desired = state['desired'];
  final reported = state['reported'];
  return {
    if (desired is Map) ...desired.cast<String, dynamic>(),
    if (reported is Map) ...reported.cast<String, dynamic>(),
  };
}

/// 可见性联动判断：
/// visibility={"param":"X","eq":v} → 仅当 X 当前值 == v 显示；
/// visibility={"param":"X","ne":v} → 仅当 X 当前值 != v 显示。
/// 值比较采用字符串化比较，兼容 int/double/string 混合类型。
bool configParamVisible(
  ConfigParamSchema schema,
  Map<String, dynamic> values,
) {
  final vis = schema.visibility;
  if (vis == null) return true;
  final depKey = vis['param'];
  if (depKey is! String) return true;
  final current = values[depKey];
  if (current == null) return false;
  if (vis.containsKey('eq')) {
    return current.toString() == vis['eq'].toString();
  }
  if (vis.containsKey('ne')) {
    return current.toString() != vis['ne'].toString();
  }
  return true;
}

/// 数值显示小数位：step>=1 显示整数；step>=0.1 显示 1 位；否则 2 位
int configDecimalsForStep(double? step) {
  if (step == null || step >= 1) return 0;
  if (step >= 0.1) return 1;
  return 2;
}

/// 数值格式化为显示文本（含单位），如 230.0 V / 50 Hz
String formatConfigNumber(num value, ConfigParamSchema schema) {
  final decimals = configDecimalsForStep(schema.step);
  final text = value.toStringAsFixed(decimals);
  final unit = (schema.unit == null || schema.unit!.isEmpty) ? '' : ' ${schema.unit}';
  return '$text$unit';
}

/// 数值写回：整数步长写 int，小数步长按精度取 double
dynamic configNumberForWrite(double value, ConfigParamSchema schema) {
  final decimals = configDecimalsForStep(schema.step);
  if (decimals == 0) return value.round();
  return double.parse(value.toStringAsFixed(decimals));
}

/// 布尔写回：保持与原值相同的 JSON 类型（bool 或 0/1）
dynamic configBoolForWrite(bool value, dynamic original) {
  if (original is bool) return value;
  return value ? 1 : 0;
}

/// 枚举写回：保持与原值相同的 JSON 类型（num 或 string）
dynamic configEnumForWrite(String optionKey, dynamic original) {
  if (original is num) {
    return int.tryParse(optionKey) ?? optionKey;
  }
  return optionKey;
}

/// 判断某参数当前值是否为布尔「开」（兼容 bool / 1 / '1' / 'true'）
bool configBoolIsOn(dynamic value) {
  if (value is bool) return value;
  final s = value.toString();
  return s == '1' || s == 'true';
}
