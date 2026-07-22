/// 设备参数设置配置定义
///
/// 通过静态配置列表驱动 UI 渲染，定义 App 端暴露给用户的控制参数。
enum SettingControlType {
  switchToggle,
  slider,
  numberInput,
  enumChoice,
  button,
}

class SettingOption {
  final String value;
  final String labelKey;

  const SettingOption({required this.value, required this.labelKey});
}

class DeviceSettingItem {
  /// 参数键名，对应后端字段名
  final String key;

  /// 国际化 key
  final String labelKey;

  /// 分组标识: 'charge_discharge' | 'work_mode' | 'advanced'
  final String groupKey;

  /// 控件类型
  final SettingControlType controlType;

  /// Slider / NumberInput 最小值
  final double? min;

  /// Slider / NumberInput 最大值
  final double? max;

  /// 单位显示
  final String? unit;

  /// 危险操作标记
  final bool isDangerous;

  /// Enum 类型选项列表
  final List<SettingOption>? options;

  /// Button 类型的单命令 key
  final String? commandKey;

  const DeviceSettingItem({
    required this.key,
    required this.labelKey,
    required this.groupKey,
    required this.controlType,
    this.min,
    this.max,
    this.unit,
    this.isDangerous = false,
    this.options,
    this.commandKey,
  });
}

/// Tab 分组定义
class SettingGroup {
  final String key;
  final String labelKey;
  final String icon;

  const SettingGroup({
    required this.key,
    required this.labelKey,
    required this.icon,
  });
}

/// 参数分组列表（决定 Tab 顺序）
const List<SettingGroup> settingGroups = [
  SettingGroup(
    key: 'charge_discharge',
    labelKey: 'tab_charge_discharge',
    icon: 'battery',
  ),
  SettingGroup(key: 'work_mode', labelKey: 'tab_work_mode', icon: 'mode'),
  SettingGroup(key: 'advanced', labelKey: 'tab_advanced', icon: 'advanced'),
];

/// 全部参数配置列表
const List<DeviceSettingItem> deviceSettingItems = [
  // ==================== Tab 1: 充放电设置 ====================
  DeviceSettingItem(
    key: 'charge_control',
    labelKey: 'setting_charge_control',
    groupKey: 'charge_discharge',
    controlType: SettingControlType.switchToggle,
  ),
  DeviceSettingItem(
    key: 'charge_power_pct',
    labelKey: 'setting_charge_power_pct',
    groupKey: 'charge_discharge',
    controlType: SettingControlType.slider,
    min: 0,
    max: 100,
    unit: '%',
  ),
  DeviceSettingItem(
    key: 'discharge_power_pct',
    labelKey: 'setting_discharge_power_pct',
    groupKey: 'charge_discharge',
    controlType: SettingControlType.slider,
    min: 0,
    max: 100,
    unit: '%',
  ),
  DeviceSettingItem(
    key: 'soc_limit',
    labelKey: 'setting_soc_limit',
    groupKey: 'charge_discharge',
    controlType: SettingControlType.slider,
    min: 0,
    max: 100,
    unit: '%',
  ),
  DeviceSettingItem(
    key: 'gridtied_cutoff_soc',
    labelKey: 'setting_gridtied_cutoff_soc',
    groupKey: 'charge_discharge',
    controlType: SettingControlType.slider,
    min: 0,
    max: 100,
    unit: '%',
  ),
  DeviceSettingItem(
    key: 'offgrid_cutoff_soc',
    labelKey: 'setting_offgrid_cutoff_soc',
    groupKey: 'charge_discharge',
    controlType: SettingControlType.slider,
    min: 0,
    max: 100,
    unit: '%',
  ),
  DeviceSettingItem(
    key: 'ac_charge_enable',
    labelKey: 'setting_ac_charge_enable',
    groupKey: 'charge_discharge',
    controlType: SettingControlType.switchToggle,
  ),
  DeviceSettingItem(
    key: 'ac_charge_power_pct',
    labelKey: 'setting_ac_charge_power_pct',
    groupKey: 'charge_discharge',
    controlType: SettingControlType.slider,
    min: 0,
    max: 100,
    unit: '%',
  ),

  // ==================== Tab 2: 工作模式 ====================
  DeviceSettingItem(
    key: 'system_type',
    labelKey: 'setting_system_type',
    groupKey: 'work_mode',
    controlType: SettingControlType.enumChoice,
    options: [
      SettingOption(value: 'grid_tied', labelKey: 'enum_grid_tied'),
      SettingOption(value: 'off_grid', labelKey: 'enum_off_grid'),
      SettingOption(value: 'hybrid', labelKey: 'enum_hybrid'),
    ],
  ),
  DeviceSettingItem(
    key: 'offgrid_frequency',
    labelKey: 'setting_offgrid_frequency',
    groupKey: 'work_mode',
    controlType: SettingControlType.enumChoice,
    unit: 'Hz',
    options: [
      SettingOption(value: '50', labelKey: '50 Hz'),
      SettingOption(value: '60', labelKey: '60 Hz'),
    ],
  ),
  DeviceSettingItem(
    key: 'anti_backflow',
    labelKey: 'setting_anti_backflow',
    groupKey: 'work_mode',
    controlType: SettingControlType.switchToggle,
  ),
  DeviceSettingItem(
    key: 'battery_type',
    labelKey: 'setting_battery_type',
    groupKey: 'work_mode',
    controlType: SettingControlType.enumChoice,
    options: [
      SettingOption(value: 'lead_acid', labelKey: 'enum_lead_acid'),
      SettingOption(value: 'lithium_iron', labelKey: 'enum_lithium_iron'),
      SettingOption(value: 'lithium_ternary', labelKey: 'enum_lithium_ternary'),
    ],
  ),
  DeviceSettingItem(
    key: 'battery_priority',
    labelKey: 'setting_battery_priority',
    groupKey: 'work_mode',
    controlType: SettingControlType.switchToggle,
  ),
  DeviceSettingItem(
    key: 'grid_max_input_power',
    labelKey: 'setting_grid_max_input_power',
    groupKey: 'work_mode',
    controlType: SettingControlType.numberInput,
    min: 0,
    max: 100000,
    unit: 'W',
  ),

  // ==================== Tab 3: 高级设置 ====================
  DeviceSettingItem(
    key: 'active_power_pct',
    labelKey: 'setting_active_power_pct',
    groupKey: 'advanced',
    controlType: SettingControlType.slider,
    min: 0,
    max: 100,
    unit: '%',
  ),
  DeviceSettingItem(
    key: 'force_charge',
    labelKey: 'setting_force_charge',
    groupKey: 'advanced',
    controlType: SettingControlType.switchToggle,
    isDangerous: true,
  ),
  DeviceSettingItem(
    key: 'force_discharge',
    labelKey: 'setting_force_discharge',
    groupKey: 'advanced',
    controlType: SettingControlType.switchToggle,
    isDangerous: true,
  ),
  DeviceSettingItem(
    key: 'restart',
    labelKey: 'setting_restart',
    groupKey: 'advanced',
    controlType: SettingControlType.button,
    isDangerous: true,
    commandKey: 'restart',
  ),
];
