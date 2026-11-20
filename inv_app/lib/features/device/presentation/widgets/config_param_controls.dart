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
    icon: Icons.battery_charging_full_outlined,
    color: AppColors.teal,
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
    icon: Icons.bolt_outlined,
    color: AppColors.orange,
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
    icon: Icons.battery_alert_outlined,
    color: AppColors.purple,
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
    icon: Icons.power_outlined,
    color: AppColors.blue,
    paramKeys: [
      'set_output_voltage',
      'set_output_frequency',
      'set_ac_volt_range',
      'set_modbus_power_saving',
      'set_modbus_auto_frequency',
    ],
  ),
  SettingsCategory(
    id: 'solar',
    icon: Icons.solar_power_outlined,
    color: Color(0xFFF9A825),
    paramKeys: ['set_solar_power_balance', 'set_charge_priority'],
  ),
  SettingsCategory(
    id: 'generator',
    icon: Icons.local_gas_station_outlined,
    color: AppColors.teal,
    paramKeys: [
      'set_gen_start_voltage',
      'set_gen_stop_voltage',
      'set_soc_back_gen',
      'set_soc_close_gen',
    ],
  ),
  SettingsCategory(
    id: 'alarm',
    icon: Icons.notifications_outlined,
    color: Color(0xFFEC4899),
    paramKeys: [
      'set_buzzer',
      'set_alarm_control',
      'set_backlight_ctrl',
      'set_power_shutdown_alarm',
      'set_modbus_input_change_alarm',
      'set_modbus_battery_open_alarm',
      'set_modbus_inverter_mute',
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
  if (RegExp(r'^\d+(?:\.\d+)?\s*(?:%|V|A|Hz|min)$').hasMatch(enumValue)) {
    return enumValue;
  }
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
  return _configEnumValueText(l10n, schema.enumOptions, value);
}

String _configEnumValueText(
  AppLocalizations l10n,
  Iterable<ConfigEnumOption> options,
  Object value,
) {
  final key = value.toString();
  for (final option in options) {
    if (option.key == key) return configEnumOptionLabel(l10n, option.value);
  }
  return key;
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

/// 参数标题和与参数类型对应的控件，电流使用档位选择。
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
  final bool compact;

  /// 设置目录的详情使用参数名和当前值并排的列表行。
  final bool embedded;

  final Set<num>? currentCommandValues;

  final ValueChanged<dynamic> onRequestChange;

  const ConfigParamControl({
    super.key,
    required this.schema,
    required this.value,
    required this.modified,
    required this.onRequestChange,
    this.disabled = false,
    this.dangerous = false,
    this.compact = false,
    this.embedded = false,
    this.currentCommandValues,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    if (embedded) return _buildListRow(context, l10n, theme);

    if (compact) {
      final label = _buildLabelRow(l10n, theme);
      if (schema.controlType == 'boolean') {
        final on = configBoolIsOn(value);
        return Row(
          children: [
            Expanded(child: label),
            if (value == null) const Text('—'),
            Semantics(
              label: configParamName(l10n, schema),
              child: Switch(
                value: on,
                onChanged: disabled
                    ? null
                    : (v) => onRequestChange(configBoolForWrite(v, value)),
              ),
            ),
          ],
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label,
            const SizedBox(height: 6),
            _buildControl(context, l10n, theme),
          ],
        ),
      );
    }

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
        padding: EdgeInsets.symmetric(
          horizontal: 16.w,
          vertical: 12.h,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabelRow(l10n, theme),
            SizedBox(height: 10.h),
            _buildControl(context, l10n, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildListRow(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    final label = _buildLabelRow(l10n, theme);
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      color: modified
          ? AppColor.primary(context)
          : AppColor.textSecondary(context),
      fontWeight: FontWeight.w600,
    );
    Widget control;
    VoidCallback? onTap;
    if (schema.controlType == 'boolean') {
      control = value == null && disabled
          ? Text('—', style: valueStyle)
          : Semantics(
              label: configParamName(l10n, schema),
              child: Switch(
                value: configBoolIsOn(value),
                onChanged: disabled
                    ? null
                    : (on) => onRequestChange(configBoolForWrite(on, value)),
              ),
            );
    } else if (schema.isCurrent) {
      control = _buildCurrentPicker(context, l10n, theme);
    } else {
      final isEnum = schema.controlType == 'enum';
      final options = schema.enumOptions;
      final min = schema.min;
      final max = schema.max;
      final editable = !disabled &&
          (isEnum
              ? options.isNotEmpty
              : min != null && max != null && max > min);
      final display = switch (value) {
        null => '—',
        final current when isEnum => _configEnumValueText(l10n, options, current),
        final num current => formatConfigNumber(current, schema),
        final current => current.toString(),
      };
      control = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(display, textAlign: TextAlign.end, style: valueStyle),
          ),
          if (editable) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColor.textSecondary(context),
              size: 18,
            ),
          ],
        ],
      );
      if (editable) onTap = () => _editListValue(context, l10n);
    }

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            Expanded(flex: 3, child: label),
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: control,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editListValue(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    dynamic draft = value;
    final selected = await showDialog<Object>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          scrollable: true,
          title: Text(configParamName(l10n, schema)),
          content: SizedBox(
            width: 320,
            child: ConfigParamControl(
              schema: schema,
              value: draft,
              modified: false,
              compact: compact,
              onRequestChange: (selection) => setState(() => draft = selection),
            )._buildControl(context, l10n, Theme.of(context)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: draft == value
                  ? null
                  : () => Navigator.pop(dialogContext, draft),
              child: Text(l10n.confirm),
            ),
          ],
        ),
      ),
    );
    if (selected != null && context.mounted) onRequestChange(selected);
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

  Widget _buildControl(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    if (schema.isCurrent && schema.controlType != 'boolean') {
      return _buildCurrentPicker(context, l10n, theme);
    }
    switch (schema.controlType) {
      case 'enum':
        return _buildEnum(l10n, theme);
      case 'boolean':
        return _buildSwitch(l10n, theme);
      default:
        return _buildNumber(context, theme);
    }
  }

  Widget _buildCurrentPicker(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    final commandValues = currentCommandValues;
    final labels = <num, String>{};
    for (final option in schema.enumOptions) {
      final amps = num.tryParse(option.key);
      if (amps == null || !amps.isFinite) continue;
      labels[amps] = configEnumOptionLabel(l10n, option.value);
    }

    final hasExplicitValues =
        schema.enumMap?.isNotEmpty == true || commandValues != null;
    final explicitValues = (labels.isNotEmpty
            ? labels.keys.where((amps) => commandValues?.contains(amps) ?? true)
            : commandValues ?? const <num>{})
        .toList()
      ..sort();
    final lower = schema.min;
    final upper = schema.max;
    final step = schema.step;
    final intervals = !hasExplicitValues &&
            schema.controlType == 'number' &&
            lower != null &&
            lower.isFinite &&
            upper != null &&
            upper.isFinite &&
            step != null &&
            step.isFinite &&
            step > 0
        ? (upper - lower) / step
        : -1.0;
    final count = hasExplicitValues
        ? explicitValues.length
        : intervals.isFinite && intervals >= 0
            ? (intervals + 1e-9).floor() + 1
            : 0;
    final current = num.tryParse(value?.toString() ?? '');

    String label(num amps) {
      final amount = amps == amps.truncateToDouble() ? amps.toInt() : amps;
      return labels[amps] ?? '$amount A';
    }

    final display = current != null && current.isFinite ? label(current) : '—';
    if (count == 0) {
      return Text(
        display,
        style:
            embedded ? theme.textTheme.bodyMedium : theme.textTheme.titleMedium,
      );
    }

    return OutlinedButton.icon(
      style: embedded
          ? OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsetsDirectional.only(start: 10, end: 6),
              foregroundColor: AppColor.primary(context),
              backgroundColor: disabled ? null : AppColor.primarySoft(context),
              side: BorderSide.none,
            )
          : null,
      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
      iconAlignment: IconAlignment.end,
      label: Text(display),
      onPressed: disabled
          ? null
          : () async {
              final selected = await showModalBottomSheet<num>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (sheetContext) => FractionallySizedBox(
                  heightFactor: 0.6,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Text(
                            configParamName(l10n, schema),
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: count,
                            itemBuilder: (_, index) {
                              final amps = hasExplicitValues
                                  ? explicitValues[index]
                                  : num.parse(
                                      (lower! + index * step!)
                                          .toStringAsPrecision(15),
                                    );
                              return ListTile(
                                title: Text(label(amps)),
                                selected: current == amps,
                                selectedColor: AppColor.primary(sheetContext),
                                selectedTileColor:
                                    AppColor.primarySoft(sheetContext),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                trailing: current == amps
                                    ? const Icon(Icons.check_rounded)
                                    : null,
                                onTap: () => Navigator.pop(sheetContext, amps),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
              if (selected != null && selected != current && context.mounted) {
                onRequestChange(selected);
              }
            },
    );
  }

  // ==================== number：Slider + 大号当前值 ====================

  Widget _buildNumber(BuildContext context, ThemeData theme) {
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

    final hasValue = value is num && (value as num).isFinite;
    final current = hasValue ? (value as num).toDouble() : min;
    final clamped = current.clamp(min, max);
    final divisions = ((max - min) / schema.effectiveStep).round();
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final number = Text(
      compact && !hasValue ? '—' : formatConfigNumber(current, schema),
      style: TextStyle(
        fontSize: compact ? 22.sp : 18.sp,
        fontWeight: FontWeight.w700,
        color:
            modified ? AppColor.primary(context) : theme.colorScheme.onSurface,
      ),
    );
    final canStep = !disabled && hasValue;
    final stepperStyle = IconButton.styleFrom(
      foregroundColor: AppColor.primary(context),
      backgroundColor: AppColor.primarySoft(context),
      disabledBackgroundColor: AppColor.surfaceHover(context),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact)
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 4,
              children: [
                number,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      style: stepperStyle,
                      tooltip: zh ? '减少' : 'Decrease',
                      onPressed: canStep && clamped > min
                          ? () => onRequestChange(
                                configNumberForWrite(
                                  (clamped - schema.effectiveStep)
                                      .clamp(min, max),
                                  schema,
                                ),
                              )
                          : null,
                      icon: const Icon(Icons.remove, size: 20),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      style: stepperStyle,
                      tooltip: zh ? '增加' : 'Increase',
                      onPressed: canStep && clamped < max
                          ? () => onRequestChange(
                                configNumberForWrite(
                                  (clamped + schema.effectiveStep)
                                      .clamp(min, max),
                                  schema,
                                ),
                              )
                          : null,
                      icon: const Icon(Icons.add, size: 20),
                    ),
                  ],
                ),
              ],
            ),
          )
        else
          number,
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

    if (options.length > 8) {
      final reportedKey = value?.toString();
      return DropdownButton<String>(
        isExpanded: true,
        menuMaxHeight: 320,
        value: options.any((option) => option.key == reportedKey)
            ? reportedKey
            : null,
        hint: Text(l10n.str('no_data')),
        items: [
          for (final option in options)
            DropdownMenuItem(
              value: option.key,
              child: Text(configEnumOptionLabel(l10n, option.value)),
            ),
        ],
        onChanged: disabled
            ? null
            : (key) {
                if (key != null) {
                  onRequestChange(configEnumForWrite(key, value));
                }
              },
      );
    }

    // Keep short option lists visible without opening a menu.
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
                minimumSize: const Size(144, 52),
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
