import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/device/domain/entities/config_schema.dart';
import 'package:inv_app/l10n/app_localizations.dart';

// ============================================================
// 设置分类定义（第 1 层 Dashboard → 第 2 层分类页）
// ============================================================

/// 设置分类：id + 图标 + 主题色 + 固定 param_key 映射
///
/// 映射中 schema 缺失的 key 渲染时跳过；schema 中不在映射的 key 忽略。
class SettingsCategory {
  final String id;
  final IconData icon;
  final Color color;
  final List<String> paramKeys;

  const SettingsCategory({
    required this.id,
    required this.icon,
    required this.color,
    required this.paramKeys,
  });

  /// 分类标题 l10n key（settings_cat_xxx）
  String get titleKey => 'settings_cat_$id';

  /// 分类描述 l10n key（settings_cat_xxx_desc）
  String get descKey => 'settings_cat_${id}_desc';
}

/// 8 大功能分类（顺序即 Dashboard 展示顺序）
const List<SettingsCategory> settingsCategories = [
  SettingsCategory(
    id: 'work_mode',
    icon: Icons.tune_rounded,
    color: Color(0xFF6366F1),
    paramKeys: [
      'set_output_priority',
      'set_ac_output_mode',
      'set_master_slave',
      'set_overload_use_city_power',
      'set_overload_restart',
      'set_high_temp_restart',
    ],
  ),
  SettingsCategory(
    id: 'battery',
    icon: Icons.battery_charging_full_rounded,
    color: Color(0xFF10B981),
    paramKeys: [
      'set_battery_type',
      'set_battery_capacity',
      'set_li_bat_material',
      'set_cell_serial_lifepo4',
      'set_cell_serial_li_nmc',
    ],
  ),
  SettingsCategory(
    id: 'charge',
    icon: Icons.bolt_rounded,
    color: Color(0xFFF59E0B),
    paramKeys: [
      'set_max_chg_curr',
      'set_max_charge_current',
      'set_ac_charge_current',
      'set_charge_time',
      'set_close_charge_time',
      'set_equalize_enable',
      'set_equalize_voltage',
      'set_equalize_time',
      'set_equalize_timeout',
      'set_equalize_interval',
      'set_equalize_activate',
    ],
  ),
  SettingsCategory(
    id: 'discharge',
    icon: Icons.electric_bolt_rounded,
    color: Color(0xFFEF4444),
    paramKeys: [
      'set_max_discharge_current',
      'set_low_volt_return_utl',
      'set_high_volt_return_bat',
      'set_recover_threshold_volt',
      'set_soc_cutoff',
      'set_soc_back_utl',
      'set_soc_back_bat',
    ],
  ),
  SettingsCategory(
    id: 'output',
    icon: Icons.power_rounded,
    color: Color(0xFF3B82F6),
    paramKeys: [
      'set_output_voltage',
      'set_output_frequency',
      'set_ac_volt_range',
    ],
  ),
  SettingsCategory(
    id: 'solar',
    icon: Icons.solar_power_rounded,
    color: Color(0xFFF9A825),
    paramKeys: ['set_solar_power_balance', 'set_charge_priority'],
  ),
  SettingsCategory(
    id: 'generator',
    icon: Icons.local_gas_station_rounded,
    color: Color(0xFF14B8A6),
    paramKeys: [
      'set_gen_start_voltage',
      'set_gen_stop_voltage',
      'set_soc_back_gen',
      'set_soc_close_gen',
    ],
  ),
  SettingsCategory(
    id: 'alarm',
    icon: Icons.notifications_active_rounded,
    color: Color(0xFFEC4899),
    paramKeys: [
      'set_buzzer',
      'set_alarm_control',
      'set_backlight_ctrl',
      'set_power_shutdown_alarm',
    ],
  ),
];

/// 按 id 查找分类
SettingsCategory? findSettingsCategory(String id) {
  for (final c in settingsCategories) {
    if (c.id == id) return c;
  }
  return null;
}

// ============================================================
// l10n 文案辅助（新 key 未入库时 l10n.str 返回 key 本身，做回退处理）
// ============================================================

/// 参数显示名：display_name_key 点号换下划线（config.set_xxx → config_set_xxx），
/// 无对应文案时回退 param_key
String configParamName(AppLocalizations l10n, ConfigParamSchema schema) {
  final key = schema.l10nNameKey;
  final text = l10n.str(key);
  return text == key ? schema.paramKey : text;
}

/// 枚举选项文案：l10n.str('config_enum_' + 语义值)，无则 humanize 原值
String configEnumOptionLabel(AppLocalizations l10n, String enumValue) {
  final key = 'config_enum_$enumValue';
  final text = l10n.str(key);
  if (text != key) return text;
  return humanizeEnumValue(enumValue);
}

/// humanize：下划线转空格并逐词首字母大写（LiFePO4 等无下划线原样返回）
String humanizeEnumValue(String raw) {
  if (!raw.contains('_')) return raw;
  return raw
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// group_code 分组标题（general/application/hybrid/parallel）
String configGroupTitle(AppLocalizations l10n, String groupCode) {
  final key = 'config_group_$groupCode';
  final text = l10n.str(key);
  return text == key ? groupCode : text;
}

/// 取某枚举参数的当前值文案（Dashboard 摘要用），无值返回 null
String? configEnumSummaryText(
  AppLocalizations l10n,
  Map<String, ConfigParamSchema> schemaMap,
  Map<String, dynamic> values,
  String paramKey,
) {
  final schema = schemaMap[paramKey];
  final value = values[paramKey];
  if (schema == null || value == null) return null;
  for (final opt in schema.enumOptions) {
    if (opt.key == value.toString()) {
      return configEnumOptionLabel(l10n, opt.value);
    }
  }
  return value.toString();
}

/// 取某数值参数的当前值文案（含单位，Dashboard 摘要用），无值返回 null
String? configNumberSummaryText(
  Map<String, ConfigParamSchema> schemaMap,
  Map<String, dynamic> values,
  String paramKey,
) {
  final schema = schemaMap[paramKey];
  final value = values[paramKey];
  if (schema == null || value is! num) return null;
  return formatConfigNumber(value, schema);
}

/// 取某布尔参数的开/关文案（Dashboard 摘要用），无值返回 null
String? configBoolSummaryText(
  AppLocalizations l10n,
  Map<String, dynamic> values,
  String paramKey,
) {
  final value = values[paramKey];
  if (value == null) return null;
  return configBoolIsOn(value) ? l10n.paramOn : l10n.paramOff;
}

// ============================================================
// 参数控件（第 2 层分类页 / 第 3 层高级参数页共用）
// ============================================================

/// 单个参数的卡片式控件：标题行 + number(Slider) / enum(ChoiceChip) / boolean(Switch)
///
/// [onRequestChange] 只是「请求修改」，是否纳入待提交由页面决定
/// （页面负责 confirmation_mode=='modal' 的确认弹窗）。
class ConfigParamControl extends StatelessWidget {
  final ConfigParamSchema schema;

  /// 当前工作值（含未应用的修改）
  final dynamic value;

  /// 是否相对原始值已修改
  final bool modified;

  /// 是否禁用交互
  final bool disabled;

  /// 危险操作红色描边
  final bool dangerous;

  final ValueChanged<dynamic> onRequestChange;

  const ConfigParamControl({
    super.key,
    required this.schema,
    required this.value,
    required this.modified,
    required this.onRequestChange,
    this.disabled = false,
    this.dangerous = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4.r,
            offset: Offset(0, 1.h),
          ),
        ],
        border: dangerous
            ? Border.all(color: AppColors.error.withValues(alpha: 0.3))
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabelRow(l10n, theme),
            SizedBox(height: 10.h),
            _buildControl(l10n, theme),
          ],
        ),
      ),
    );
  }

  /// 标题行：危险图标 + 名称 + modal 提示 + 已修改徽标
  Widget _buildLabelRow(AppLocalizations l10n, ThemeData theme) {
    return Row(
      children: [
        if (dangerous)
          Padding(
            padding: EdgeInsets.only(right: 6.w),
            child: Icon(
              Icons.warning_amber_rounded,
              color: AppColors.error,
              size: 16.sp,
            ),
          ),
        Expanded(
          child: Text(
            configParamName(l10n, schema),
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: dangerous ? AppColors.error : theme.colorScheme.onSurface,
            ),
          ),
        ),
        if (schema.needsModalConfirm)
          Padding(
            padding: EdgeInsets.only(right: 6.w),
            // modal 确认提示图标：表示点击修改前会先弹确认框
            child: Icon(
              Icons.touch_app_rounded,
              size: 14.sp,
              color: AppColors.textHint,
            ),
          ),
        if (modified)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4.r),
            ),
            child: Text(
              l10n.paramModified,
              style: TextStyle(
                fontSize: 10.sp,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildControl(AppLocalizations l10n, ThemeData theme) {
    switch (schema.controlType) {
      case 'enum':
        return _buildEnum(l10n, theme);
      case 'boolean':
        return _buildSwitch(l10n, theme);
      default:
        return _buildNumber(theme);
    }
  }

  // ==================== number：Slider + 大号当前值 ====================

  Widget _buildNumber(ThemeData theme) {
    final min = schema.min;
    final max = schema.max;
    final decimals = configDecimalsForStep(schema.step);

    // schema 无 min/max 时退化为只读展示
    if (min == null || max == null || max <= min) {
      return Text(
        value is num ? formatConfigNumber(value as num, schema) : '-',
        style: TextStyle(
          fontSize: 16.sp,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
      );
    }

    final current = value is num ? (value as num).toDouble() : min;
    final clamped = current.clamp(min, max);
    final divisions = ((max - min) / schema.effectiveStep).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatConfigNumber(current, schema),
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
            color: modified ? AppColors.primary : theme.colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 4.h),
        Slider(
          value: clamped,
          min: min,
          max: max,
          divisions: divisions > 0 ? divisions : null,
          label: clamped.toStringAsFixed(decimals),
          onChanged: disabled
              ? null
              : (v) => onRequestChange(configNumberForWrite(v, schema)),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              formatConfigNumber(min, schema),
              style: TextStyle(
                fontSize: 11.sp,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              formatConfigNumber(max, schema),
              style: TextStyle(
                fontSize: 11.sp,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==================== enum：ChoiceChip 横排 / 竖排 ====================

  Widget _buildEnum(AppLocalizations l10n, ThemeData theme) {
    final options = schema.enumOptions;
    if (options.isEmpty) {
      return Text(
        value?.toString() ?? '-',
        style: TextStyle(fontSize: 14.sp, color: theme.colorScheme.onSurface),
      );
    }

    void select(ConfigEnumOption opt) {
      onRequestChange(configEnumForWrite(opt.key, value));
    }

    // 选项 ≤4 个用 ChoiceChip 横排；否则竖排列表
    if (options.length <= 4) {
      return Wrap(
        spacing: 8.w,
        runSpacing: 8.h,
        children: options.map((opt) {
          final selected = opt.key == value.toString();
          return ChoiceChip(
            label: Text(
              configEnumOptionLabel(l10n, opt.value),
              style: TextStyle(fontSize: 13.sp),
            ),
            selected: selected,
            onSelected: disabled ? null : (_) => select(opt),
            selectedColor: theme.colorScheme.primaryContainer,
          );
        }).toList(),
      );
    }

    // 竖排单选列表（选项 >4 个，当前 schema 未触发，预留兼容）
    return Column(
      children: [
        for (final opt in options)
          InkWell(
            borderRadius: BorderRadius.circular(8.r),
            onTap: disabled ? null : () => select(opt),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Row(
                children: [
                  Icon(
                    opt.key == value.toString()
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    size: 20.sp,
                    color: opt.key == value.toString()
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Text(
                      configEnumOptionLabel(l10n, opt.value),
                      style: TextStyle(fontSize: 14.sp),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ==================== boolean：Switch 行 ====================

  Widget _buildSwitch(AppLocalizations l10n, ThemeData theme) {
    final on = configBoolIsOn(value);
    return Row(
      children: [
        Text(
          on ? l10n.paramOn : l10n.paramOff,
          style: TextStyle(
            fontSize: 14.sp,
            color: on ? AppColors.success : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Switch(
          value: on,
          onChanged: disabled
              ? null
              : (v) => onRequestChange(configBoolForWrite(v, value)),
        ),
      ],
    );
  }
}

// ============================================================
// 底部应用条（分类页 / 高级参数页共用）
// ============================================================

/// 悬浮底部栏：「N 项修改」+ 应用按钮
class ConfigApplyBar extends StatelessWidget {
  final int modifiedCount;
  final bool applying;
  final VoidCallback onApply;

  const ConfigApplyBar({
    super.key,
    required this.modifiedCount,
    required this.applying,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8.r,
            offset: Offset(0, -2.h),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.paramModifiedCount('$modifiedCount'),
                style: TextStyle(
                  fontSize: 13.sp,
                  color: AppColor.textSecondary(context),
                ),
              ),
            ),
            FilledButton(
              onPressed: applying ? null : onApply,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              ),
              child: applying
                  ? SizedBox(
                      width: 18.w,
                      height: 18.w,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(l10n.applyChanges),
            ),
          ],
        ),
      ),
    );
  }
}
