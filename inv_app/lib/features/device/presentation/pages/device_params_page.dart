import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/param_confirm_dialog.dart';
import 'package:inv_app/features/device/domain/entities/device_param.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/device/presentation/widgets/device_param_text_control.dart';
import 'package:inv_app/features/device/presentation/widgets/device_param_write_dialog.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';

class DeviceParamsPage extends StatefulWidget {
  final String deviceIP;

  const DeviceParamsPage({super.key, required this.deviceIP});

  @override
  State<DeviceParamsPage> createState() => _DeviceParamsPageState();
}

class _DeviceParamsPageState extends State<DeviceParamsPage> {
  List<DeviceParam> _params = [];
  Map<String, dynamic> _originalValues = {};
  Map<String, dynamic> _modifiedValues = {};
  String _searchQuery = '';
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    context
        .read<DeviceBloc>()
        .add(DeviceLocalParamsRequested(deviceIP: widget.deviceIP));
  }

  List<DeviceParam> _parseParams(Map<String, dynamic> raw) {
    return raw.entries.map((entry) {
      final key = entry.key;
      final val = entry.value;
      if (val is Map<String, dynamic>) {
        return DeviceParam(
          key: key,
          label: val['label'] as String? ?? key,
          value: val['value'],
          minValue: val['minValue'] ?? val['min'],
          maxValue: val['maxValue'] ?? val['max'],
          unit: val['unit'] as String? ?? '',
          paramType: val['paramType'] as String? ?? _inferType(val['value']),
          options: (val['options'] as List<dynamic>?)
                  ?.map(
                    (o) => o is Map<String, dynamic>
                        ? ParamOption(
                            value: o['value'],
                            label: o['label'] as String? ?? '${o['value']}',
                          )
                        : ParamOption(value: o, label: '$o'),
                  )
                  .toList() ??
              [],
          isDangerous: val['isDangerous'] as bool? ?? false,
          description: val['description'] as String?,
        );
      }
      return DeviceParam(
        key: key,
        label: key,
        value: val,
        paramType: _inferType(val),
      );
    }).toList();
  }

  String _inferType(dynamic value) {
    if (value is bool) return 'bool';
    if (value is num) return 'number';
    return 'text';
  }

  Map<String, List<DeviceParam>> _groupParams(List<DeviceParam> params) {
    final groups = <String, List<DeviceParam>>{};
    for (final p in params) {
      final group = p.groupKey;
      groups.putIfAbsent(group, () => []).add(p);
    }
    return groups;
  }

  List<DeviceParam> _filterParams(List<DeviceParam> params) {
    if (_searchQuery.isEmpty) return params;
    final q = _searchQuery.toLowerCase();
    return params
        .where(
          (p) =>
              p.label.toLowerCase().contains(q) ||
              p.key.toLowerCase().contains(q),
        )
        .toList();
  }

  bool _isModified(String key) {
    if (!_modifiedValues.containsKey(key)) return false;
    return _modifiedValues[key] != _originalValues[key];
  }

  int get _modifiedCount {
    return _modifiedValues.entries
        .where((e) => e.value != _originalValues[e.key])
        .length;
  }

  void _onValueChanged(String key, dynamic newValue) {
    setState(() {
      _modifiedValues[key] = newValue;
    });
  }

  Future<void> _applyChanges() async {
    final changes = <String, MapEntry<dynamic, dynamic>>{};
    final dangerousKeys = <String>{};

    for (final entry in _modifiedValues.entries) {
      if (entry.value != _originalValues[entry.key]) {
        changes[entry.key] = MapEntry(_originalValues[entry.key], entry.value);
        final param = _params.firstWhere((p) => p.key == entry.key);
        if (param.isDangerous) {
          dangerousKeys.add(entry.key);
        }
      }
    }

    if (changes.isEmpty) return;

    final confirmed = await ParamConfirmDialog.show(
      context,
      changes: changes,
      dangerousKeys: dangerousKeys,
    );

    if (confirmed != true) return;

    setState(() => _isApplying = true);

    final paramsToWrite = <String, dynamic>{};
    for (final entry in _modifiedValues.entries) {
      if (entry.value != _originalValues[entry.key]) {
        paramsToWrite[entry.key] = entry.value;
      }
    }

    if (!mounted) return;
    context.read<DeviceBloc>().add(
          DeviceLocalParamsUpdateRequested(
            deviceIP: widget.deviceIP,
            params: paramsToWrite,
          ),
        );
  }

  void _showNumberEditDialog(DeviceParam param) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (_) => DeviceParamWriteDialog(
        param: param,
        cancelLabel: l10n.cancel,
        confirmLabel: l10n.confirm,
        onConfirm: (value) {
          if (!mounted) return;
          _onValueChanged(param.key, value);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.paramSettings)),
      body: BlocConsumer<DeviceBloc, DeviceState>(
        listener: (context, state) {
          if (state is DeviceParamsUpdateSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)!.paramSetSuccess),
                backgroundColor: AppColors.success,
                duration: const Duration(seconds: 2),
              ),
            );
            setState(() {
              _originalValues = Map.from(_modifiedValues);
              _modifiedValues = Map.from(_modifiedValues);
              _isApplying = false;
            });
          }
          if (state is DeviceError) {
            setState(() => _isApplying = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context)!.translateError(state.message),
                ),
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is DeviceLoading && _params.isEmpty) {
            return const PageSkeleton();
          }

          if (state is DeviceError && _params.isEmpty) {
            return Center(
              child: Text(
                AppLocalizations.of(context)!.translateError(state.message),
              ),
            );
          }

          if (state is DeviceParamsLoaded) {
            _params = _parseParams(state.params);
            _originalValues = {for (final p in _params) p.key: p.value};
            _modifiedValues = {for (final p in _params) p.key: p.value};
          }

          if (_params.isEmpty) {
            return Center(child: Text(AppLocalizations.of(context)!.noParams));
          }

          final filtered = _filterParams(_params);
          final grouped = _groupParams(filtered);
          final groupKeys = grouped.keys.toList();

          return Column(
            children: [
              // 搜索框：浅色圆角卡片容器
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
                child: Container(
                  height: 44.h,
                  decoration: BoxDecoration(
                    color: AppColor.surfaceHover(context),
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(
                      color: AppColor.outline(context).withValues(alpha: 0.4),
                    ),
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context)!.searchParams,
                      hintStyle: TextStyle(
                        fontSize: 14.sp,
                        color: AppColor.textHint(context),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 20.sp,
                        color: AppColor.textSecondary(context),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.clear,
                                size: 18.sp,
                                color: AppColor.textHint(context),
                              ),
                              onPressed: () =>
                                  setState(() => _searchQuery = ''),
                            )
                          : null,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 4.w, vertical: 10.h),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
              ),
              Expanded(
                child: StyledRefreshIndicator(
                  onRefresh: () async {
                    context.read<DeviceBloc>().add(
                          DeviceLocalParamsRequested(deviceIP: widget.deviceIP),
                        );
                  },
                  child: ListView.builder(
                    padding:
                        EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 24.h),
                    itemCount: groupKeys.length,
                    findChildIndexCallback: (key) {
                      if (key is! ValueKey<String>) return null;
                      final index = groupKeys.indexOf(key.value);
                      return index < 0 ? null : index;
                    },
                    itemBuilder: (context, index) {
                      final groupKey = groupKeys[index];
                      final groupParams = grouped[groupKey]!;
                      return _buildGroupTile(groupKey, groupParams);
                    },
                  ),
                ),
              ),
              if (_modifiedCount > 0) _buildBottomBar(),
            ],
          );
        },
      ),
    );
  }

  /// 分组卡片：圆角 16 白卡 + 细边框，组头含语义色图标容器 + 参数数量徽章
  Widget _buildGroupTile(String groupKey, List<DeviceParam> params) {
    final (icon, accent) = _groupStyle(groupKey);
    return Container(
      key: ValueKey(groupKey),
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: AppColor.outline(context).withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 组头：图标容器 + 组名 + 数量徽章
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 10.h),
            child: Row(
              children: [
                Container(
                  width: 34.w,
                  height: 34.w,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(icon, size: 19.sp, color: accent),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    _groupTitle(groupKey),
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColor.textPrimary(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    '${params.length}',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: AppColor.outline(context).withValues(alpha: 0.4),
          ),
          ...params.map((p) => _buildParamItem(p)).toList(),
        ],
      ),
    );
  }

  /// 分组语义色与图标：按分组 key 映射（pv/ac/battery/grid 等）
  (IconData, Color) _groupStyle(String groupKey) {
    switch (groupKey.toLowerCase()) {
      case 'pv':
        return (Icons.wb_sunny_outlined, AppColors.orange);
      case 'ac':
        return (Icons.bolt_rounded, AppColors.purple);
      case 'battery':
        return (Icons.battery_charging_full_rounded, AppColors.teal);
      case 'grid':
        return (Icons.grid_view_rounded, AppColors.blue);
      default:
        return (Icons.tune_rounded, AppColors.primary);
    }
  }

  /// 分组标题本地化（未知分组回退原始 key）
  String _groupTitle(String groupKey) {
    final l10n = AppLocalizations.of(context);
    switch (groupKey.toLowerCase()) {
      case 'pv':
        return l10n?.groupPvParams ?? 'PV Parameters';
      case 'ac':
        return l10n?.groupAcParams ?? 'AC Parameters';
      case 'battery':
        return l10n?.groupBatteryParams ?? 'Battery Parameters';
      case 'grid':
        return l10n?.grid ?? 'Grid';
      default:
        return groupKey;
    }
  }

  /// 参数项：危险参数整行浅红底 + 红色标识，修改态显示胶囊徽章
  Widget _buildParamItem(DeviceParam param) {
    final modified = _isModified(param.key);
    final currentValue = _modifiedValues[param.key] ?? param.value;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      key: ValueKey(param.key),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: param.isDangerous
            ? AppColors.error.withValues(alpha: 0.04)
            : null,
        border: Border(
          top: BorderSide(
            color: AppColor.outline(context).withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (param.isDangerous) ...[
                Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.error,
                  size: 16.sp,
                ),
                SizedBox(width: 4.w),
              ],
              Expanded(
                child: Text(
                  param.label,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: param.isDangerous
                        ? AppColors.error
                        : AppColor.textPrimary(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (modified)
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: AppColor.primary(context).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Text(
                    l10n.paramModified,
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: AppColor.primary(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          if (param.description != null) ...[
            SizedBox(height: 2.h),
            Text(
              param.description!,
              style: TextStyle(
                fontSize: 11.sp,
                color: AppColor.textSecondary(context),
              ),
            ),
          ],
          SizedBox(height: 8.h),
          _buildParamControl(param, currentValue),
        ],
      ),
    );
  }

  Widget _buildParamControl(
    DeviceParam param,
    dynamic currentValue,
  ) {
    switch (param.paramType) {
      case 'number':
        return _buildNumberControl(param, currentValue);
      case 'enum':
        return _buildEnumControl(param, currentValue);
      case 'bool':
        return _buildBoolControl(param, currentValue);
      case 'text':
        return DeviceParamTextControl(
          key: ValueKey(param.key),
          param: param,
          value: currentValue,
          onChanged: (key, value) => _onValueChanged(key, value),
        );
      default:
        return _buildNumberControl(param, currentValue);
    }
  }

  Widget _buildNumberControl(DeviceParam param, dynamic currentValue) {
    final modified = _isModified(param.key);
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Text(
                '${currentValue ?? '-'}',
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                  color: modified
                      ? AppColor.primary(context)
                      : AppColor.textPrimary(context),
                ),
              ),
              if (param.unit.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(left: 5.w),
                  child: Text(
                    param.unit,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColor.textSecondary(context),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 编辑胶囊按钮
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10.r),
            onTap: () => _showNumberEditDialog(param),
            child: Container(
              padding:
                  EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: AppColor.primarySoft(context),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit_outlined,
                    size: 14.sp,
                    color: AppColor.primary(context),
                  ),
                  SizedBox(width: 4.w),
                  Text(
                    l10n.edit,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColor.primary(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEnumControl(DeviceParam param, dynamic currentValue) {
    if (param.options.length <= 4) {
      return Wrap(
        spacing: 6.w,
        runSpacing: 6.h,
        children: param.options.map((opt) {
          final selected = opt.value == currentValue;
          return ChoiceChip(
            label: Text(opt.label, style: TextStyle(fontSize: 12.sp)),
            selected: selected,
            onSelected: (_) => _onValueChanged(param.key, opt.value),
            selectedColor: AppColor.primarySoft(context),
            labelStyle: TextStyle(
              fontSize: 12.sp,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? AppColor.primary(context)
                  : AppColor.textSecondary(context),
            ),
            side: BorderSide(
              color: selected
                  ? AppColor.primary(context).withValues(alpha: 0.4)
                  : AppColor.outline(context).withValues(alpha: 0.5),
            ),
          );
        }).toList(),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: AppColor.surfaceHover(context),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: DropdownButton<dynamic>(
        value: currentValue,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        icon: Icon(
          Icons.arrow_drop_down,
          color: AppColor.textSecondary(context),
        ),
        style: TextStyle(
          fontSize: 13.sp,
          color: AppColor.textPrimary(context),
        ),
        items: param.options
            .map(
              (opt) => DropdownMenuItem<dynamic>(
                value: opt.value,
                child: Text(opt.label, style: TextStyle(fontSize: 13.sp)),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v != null) _onValueChanged(param.key, v);
        },
      ),
    );
  }

  Widget _buildBoolControl(DeviceParam param, dynamic currentValue) {
    final val = currentValue is bool
        ? currentValue
        : currentValue == 1 || currentValue == '1' || currentValue == 'true';
    return Row(
      children: [
        Text(
          val
              ? AppLocalizations.of(context)!.paramOn
              : AppLocalizations.of(context)!.paramOff,
          style: TextStyle(
            fontSize: 14.sp,
            color: val
                ? AppColors.success
                : AppColor.textSecondary(context),
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Switch(
          value: val,
          onChanged: (v) => _onValueChanged(param.key, v),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16.r,
            offset: Offset(0, -4.h),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 已修改数量徽章
            Expanded(
              child: Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: AppColor.primarySoft(context),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 16.sp,
                      color: AppColor.primary(context),
                    ),
                    SizedBox(width: 6.w),
                    Flexible(
                      child: Text(
                        l10n.paramModifiedCount('$_modifiedCount'),
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: AppColor.primary(context),
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 12.w),
            // 品牌渐变胶囊应用按钮
            SizedBox(
              height: 44.h,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(22.r),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1565C0), Color(0xFF2196F3)],
                    ),
                    borderRadius: BorderRadius.circular(22.r),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1565C0).withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22.r),
                    onTap: _isApplying ? null : _applyChanges,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24.w),
                      child: Center(
                        child: _isApplying
                            ? SizedBox(
                                width: 18.w,
                                height: 18.w,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                l10n.applyChanges,
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
