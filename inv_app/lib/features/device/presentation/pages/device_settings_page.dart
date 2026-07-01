import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/widgets/param_confirm_dialog.dart';
import 'package:inv_app/features/device/domain/entities/device_setting_config.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class DeviceSettingsPage extends StatefulWidget {
  final String sn;

  const DeviceSettingsPage({super.key, required this.sn});

  @override
  State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic> _originalValues = {};
  Map<String, dynamic> _modifiedValues = {};
  bool _isOnline = false;
  bool _loading = true;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: settingGroups.length, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    final dio = getIt<Dio>();

    // 并行获取在线状态和参数
    bool online = false;
    Map<String, dynamic> params = {};

    try {
      final deviceRes = await dio.get('/devices/${widget.sn}');
      final data = deviceRes.data['data'] as Map<String, dynamic>? ?? {};
      online = data['online_status']?['online'] == true ||
          data['device']?['status'] == 1;
    } catch (_) {}

    try {
      final res = await dio.post('/devices/${widget.sn}/control',
          data: {'command': 'get_params'});
      final d = res.data['data'] ?? res.data['params'] ?? res.data ?? {};
      if (d is Map<String, dynamic>) params = d;
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isOnline = online;
        _originalValues = Map.from(params);
        _modifiedValues = Map.from(params);
        _loading = false;
      });
      if (params.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.settingReadSuccess),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 1),
        ));
      }
    }
  }

  int get _modifiedCount {
    return _modifiedValues.entries
        .where((e) => e.value != _originalValues[e.key])
        .length;
  }

  bool _isModified(String key) {
    return _modifiedValues.containsKey(key) &&
        _modifiedValues[key] != _originalValues[key];
  }

  void _onValueChanged(String key, dynamic newValue) {
    setState(() {
      _modifiedValues[key] = newValue;
    });
  }

  Future<void> _applyChanges() async {
    final l10n = AppLocalizations.of(context)!;
    final changes = <String, MapEntry<dynamic, dynamic>>{};
    final dangerousKeys = <String>{};

    for (final entry in _modifiedValues.entries) {
      if (entry.value != _originalValues[entry.key]) {
        // 使用本地化标签名作为显示名
        final item = deviceSettingItems
            .where((i) => i.key == entry.key)
            .firstOrNull;
        final label = item != null ? l10n.settingLabel(item.labelKey) : entry.key;
        changes[label] = MapEntry(_originalValues[entry.key], entry.value);
        if (item?.isDangerous == true) {
          dangerousKeys.add(label);
        }
      }
    }
    if (changes.isEmpty) return;

    final confirmed = await ParamConfirmDialog.show(context,
        changes: changes, dangerousKeys: dangerousKeys);
    if (confirmed != true) return;

    setState(() => _isApplying = true);

    try {
      final dio = getIt<Dio>();
      final paramsToWrite = <String, dynamic>{};
      for (final entry in _modifiedValues.entries) {
        if (entry.value != _originalValues[entry.key]) {
          paramsToWrite[entry.key] = entry.value;
        }
      }
      await dio.post('/devices/${widget.sn}/control', data: {
        'command': 'set_params',
        'params': paramsToWrite,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.settingSetSuccess),
          backgroundColor: AppColors.success,
        ));
        setState(() {
          _originalValues = Map.from(_modifiedValues);
          _isApplying = false;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.settingSetFailed),
          backgroundColor: AppColors.error,
        ));
        setState(() => _isApplying = false);
      }
    }
  }

  Future<void> _sendSingleCommand(String command) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final dio = getIt<Dio>();
      await dio.post('/devices/${widget.sn}/control',
          data: {'command': command, 'params': {}});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.commandSent),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.settingSetFailed),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  void _showDangerousConfirm(String labelKey, String confirmKey, String command,
      {Map<String, dynamic>? params}) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24.sp),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(l10n.settingForceConfirmTitle,
                  style: TextStyle(fontSize: 16.sp)),
            ),
          ],
        ),
        content: Text(l10n.str(confirmKey),
            style: TextStyle(fontSize: 14.sp)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              if (params != null) {
                // Switch 类型：设置参数值
                _onValueChanged(command, params['value']);
              } else {
                // Button 类型：发送单命令
                _sendSingleCommand(command);
              }
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  // ==================== 渲染 ====================

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.paramSettings,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17.sp)),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, size: 22.sp),
            onPressed: _loading ? null : () => setState(() {
              _loading = true;
              _fetchData();
            }),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 离线警告条
                if (!_isOnline) _buildOfflineBanner(l10n),
                // Tab 栏
                _buildTabBar(theme, l10n),
                // Tab 内容
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: settingGroups
                        .map((g) => _buildTabContent(g, l10n, theme))
                        .toList(),
                  ),
                ),
                // 底部浮动栏
                if (_modifiedCount > 0 && _isOnline) _buildBottomBar(l10n),
              ],
            ),
    );
  }

  Widget _buildOfflineBanner(AppLocalizations l10n) {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, size: 18.w, color: AppColors.warning),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(l10n.deviceOfflineWarning,
                style: TextStyle(fontSize: 12.sp, color: AppColors.warning)),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(ThemeData theme, AppLocalizations l10n) {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
        indicatorColor: theme.colorScheme.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 13.sp),
        dividerColor: Colors.transparent,
        tabs: settingGroups.map((g) {
          String title;
          switch (g.key) {
            case 'charge_discharge':
              title = l10n.tabChargeDischarge;
              break;
            case 'work_mode':
              title = l10n.tabWorkMode;
              break;
            case 'advanced':
              title = l10n.tabAdvanced;
              break;
            default:
              title = g.key;
          }
          return Tab(text: title);
        }).toList(),
      ),
    );
  }

  Widget _buildTabContent(
      SettingGroup group, AppLocalizations l10n, ThemeData theme) {
    final items =
        deviceSettingItems.where((i) => i.groupKey == group.key).toList();

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      children: [
        // 高级设置提示
        if (group.key == 'advanced')
          Container(
            margin: EdgeInsets.only(bottom: 12.h),
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 18.w, color: AppColors.error),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(l10n.settingAdvancedHint,
                      style: TextStyle(
                          fontSize: 12.sp, color: AppColors.error)),
                ),
              ],
            ),
          ),
        // 参数列表
        ...items.map((item) => _buildSettingItem(item, l10n, theme)),
        SizedBox(height: 80.h), // 底部留白
      ],
    );
  }

  Widget _buildSettingItem(
      DeviceSettingItem item, AppLocalizations l10n, ThemeData theme) {
    final currentValue = _modifiedValues[item.key];
    final modified = _isModified(item.key);
    final disabled = !_isOnline;

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
        border: item.isDangerous
            ? Border.all(color: AppColors.error.withValues(alpha: 0.3))
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标签行
            Row(
              children: [
                if (item.isDangerous)
                  Padding(
                    padding: EdgeInsets.only(right: 6.w),
                    child: Icon(Icons.warning_amber_rounded,
                        color: AppColors.error, size: 16.sp),
                  ),
                Expanded(
                  child: Text(
                    l10n.settingLabel(item.labelKey),
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color: item.isDangerous
                          ? AppColors.error
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (modified)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                    child: Text(l10n.paramModified,
                        style: TextStyle(
                            fontSize: 10.sp,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            SizedBox(height: 10.h),
            // 控件
            _buildControl(item, currentValue, disabled, l10n, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildControl(DeviceSettingItem item, dynamic currentValue,
      bool disabled, AppLocalizations l10n, ThemeData theme) {
    switch (item.controlType) {
      case SettingControlType.switchToggle:
        return _buildSwitch(item, currentValue, disabled, l10n);
      case SettingControlType.slider:
        return _buildSlider(item, currentValue, disabled, theme);
      case SettingControlType.numberInput:
        return _buildNumberInput(item, currentValue, disabled, theme, l10n);
      case SettingControlType.enumChoice:
        return _buildEnumChoice(item, currentValue, disabled, l10n, theme);
      case SettingControlType.button:
        return _buildButton(item, disabled, l10n);
    }
  }

  // ==================== Switch ====================

  Widget _buildSwitch(DeviceSettingItem item, dynamic currentValue,
      bool disabled, AppLocalizations l10n) {
    final val = currentValue is bool
        ? currentValue
        : currentValue == 1 || currentValue == '1' || currentValue == 'true' || currentValue == true;
    return Row(
      children: [
        Text(
          val ? l10n.paramOn : l10n.paramOff,
          style: TextStyle(
            fontSize: 14.sp,
            color: val ? AppColors.success : AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Switch(
          value: val,
          onChanged: disabled
              ? null
              : (v) {
                  if (item.isDangerous) {
                    final confirmKey = item.key == 'force_charge'
                        ? 'setting_force_charge_confirm'
                        : 'setting_force_discharge_confirm';
                    _showDangerousConfirm(
                        item.labelKey, confirmKey, item.key,
                        params: {'value': v});
                  } else {
                    _onValueChanged(item.key, v);
                  }
                },
        ),
      ],
    );
  }

  // ==================== Slider ====================

  Widget _buildSlider(DeviceSettingItem item, dynamic currentValue,
      bool disabled, ThemeData theme) {
    final minVal = item.min ?? 0;
    final maxVal = item.max ?? 100;
    double val = (currentValue is num ? currentValue.toDouble() : minVal)
        .clamp(minVal, maxVal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${val.toInt()}${item.unit ?? ''}',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: _isModified(item.key)
                    ? AppColors.primary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        SizedBox(height: 4.h),
        Slider(
          value: val,
          min: minVal,
          max: maxVal,
          divisions: maxVal > minVal ? (maxVal - minVal).toInt() : null,
          label: val.toInt().toString(),
          onChanged: disabled ? null : (v) => _onValueChanged(item.key, v.toInt()),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${minVal.toInt()}${item.unit ?? ''}',
                style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
            Text('${maxVal.toInt()}${item.unit ?? ''}',
                style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
          ],
        ),
      ],
    );
  }

  // ==================== NumberInput ====================

  Widget _buildNumberInput(DeviceSettingItem item, dynamic currentValue,
      bool disabled, ThemeData theme, AppLocalizations l10n) {
    final displayVal = currentValue ?? '-';

    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Text('$displayVal',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: _isModified(item.key)
                        ? AppColors.primary
                        : theme.colorScheme.onSurface,
                  )),
              if (item.unit != null)
                Padding(
                  padding: EdgeInsets.only(left: 4.w),
                  child: Text(item.unit!,
                      style: TextStyle(
                          fontSize: 12.sp,
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.edit, size: 20.sp, color: theme.colorScheme.primary),
          onPressed: disabled ? null : () => _showNumberEditDialog(item, l10n),
          style: IconButton.styleFrom(
            backgroundColor:
                theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            minimumSize: Size(36.w, 36.w),
          ),
        ),
      ],
    );
  }

  void _showNumberEditDialog(DeviceSettingItem item, AppLocalizations l10n) {
    final minVal = item.min ?? 0;
    final maxVal = item.max ?? 100000;
    final currentVal = _modifiedValues[item.key];
    final controller = TextEditingController(text: '${currentVal ?? minVal}');
    double sliderVal =
        (currentVal is num ? currentVal.toDouble() : minVal).clamp(minVal, maxVal);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
          title: Text(l10n.settingLabel(item.labelKey)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${sliderVal.toInt()} ${item.unit ?? ''}',
                  style: TextStyle(
                      fontSize: 24.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
              SizedBox(height: 16.h),
              if (maxVal - minVal <= 200 && maxVal - minVal > 1)
                Slider(
                  value: sliderVal,
                  min: minVal,
                  max: maxVal,
                  divisions: (maxVal - minVal).toInt(),
                  label: sliderVal.toInt().toString(),
                  onChanged: (v) {
                    setDialogState(() => sliderVal = v);
                    controller.text = v.toInt().toString();
                  },
                ),
              SizedBox(height: 8.h),
              TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: false),
                decoration: InputDecoration(
                  hintText: '${minVal.toInt()} ~ ${maxVal.toInt()}',
                  suffixText: item.unit,
                ),
                onChanged: (v) {
                  final parsed = double.tryParse(v);
                  if (parsed != null) {
                    setDialogState(
                        () => sliderVal = parsed.clamp(minVal, maxVal));
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final val = num.tryParse(controller.text);
                if (val != null) {
                  _onValueChanged(item.key, val);
                  Navigator.pop(ctx);
                }
              },
              child: Text(l10n.confirm),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== EnumChoice ====================

  Widget _buildEnumChoice(DeviceSettingItem item, dynamic currentValue,
      bool disabled, AppLocalizations l10n, ThemeData theme) {
    final options = item.options ?? [];
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: options.map((opt) {
        final selected = opt.value.toString() == currentValue.toString();
        return ChoiceChip(
          label: Text(l10n.enumLabel(opt.labelKey),
              style: TextStyle(fontSize: 13.sp)),
          selected: selected,
          onSelected: disabled
              ? null
              : (_) => _onValueChanged(item.key, opt.value),
          selectedColor: theme.colorScheme.primaryContainer,
        );
      }).toList(),
    );
  }

  // ==================== Button ====================

  Widget _buildButton(
      DeviceSettingItem item, bool disabled, AppLocalizations l10n) {
    return OutlinedButton.icon(
      icon: Icon(Icons.restart_alt_rounded, size: 18.sp),
      label: Text(l10n.settingRestartBtn),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.error,
        side: const BorderSide(color: AppColors.error),
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
      ),
      onPressed: disabled
          ? null
          : () => _showDangerousConfirm(item.labelKey,
              'setting_restart_confirm', item.commandKey ?? 'restart'),
    );
  }

  // ==================== 底部栏 ====================

  Widget _buildBottomBar(AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
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
                l10n.paramModifiedCount('$_modifiedCount'),
                style: TextStyle(
                    fontSize: 13.sp, color: AppColors.textSecondary),
              ),
            ),
            FilledButton(
              onPressed: _isApplying ? null : _applyChanges,
              style: FilledButton.styleFrom(
                padding:
                    EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.r)),
              ),
              child: _isApplying
                  ? SizedBox(
                      width: 18.w,
                      height: 18.w,
                      child: const CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(l10n.applyChanges),
            ),
          ],
        ),
      ),
    );
  }
}
