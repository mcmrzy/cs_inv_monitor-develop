import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/param_confirm_dialog.dart';
import 'package:inv_app/features/device/domain/entities/device_param.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';

class DeviceParamsPage extends StatefulWidget {
  final String deviceSN;

  const DeviceParamsPage({super.key, required this.deviceSN});

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
    context.read<DeviceBloc>().add(DeviceParamsRequested(sn: widget.deviceSN));
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
                  ?.map((o) => o is Map<String, dynamic>
                      ? ParamOption(value: o['value'], label: o['label'] as String? ?? '${o['value']}')
                      : ParamOption(value: o, label: '$o'))
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
        .where((p) => p.label.toLowerCase().contains(q) || p.key.toLowerCase().contains(q))
        .toList();
  }

  bool _isModified(String key) {
    if (!_modifiedValues.containsKey(key)) return false;
    return _modifiedValues[key] != _originalValues[key];
  }

  int get _modifiedCount {
    return _modifiedValues.entries.where((e) => e.value != _originalValues[e.key]).length;
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
          DeviceParamWriteAndReadbackRequested(sn: widget.deviceSN, params: paramsToWrite),
        );
  }

  void _showNumberEditDialog(DeviceParam param) {
    final controller = TextEditingController(text: '${param.value}');
    final minVal = param.minValue is num ? (param.minValue as num).toDouble() : 0.0;
    final maxVal = param.maxValue is num ? (param.maxValue as num).toDouble() : 100.0;
    double sliderVal = (param.value is num ? (param.value as num).toDouble() : minVal).clamp(minVal, maxVal);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
              title: Text(param.label),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (param.description != null)
                    Padding(
                      padding: EdgeInsets.only(bottom: 8.h),
                      child: Text(
                        param.description!,
                        style: TextStyle(fontSize: 12.sp, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  if (maxVal - minVal <= 200 && (maxVal - minVal) > 1)
                    Row(
                      children: [
                        Text('${minVal.toInt()}', style: TextStyle(fontSize: 12.sp)),
                        Expanded(
                          child: Slider(
                            value: sliderVal.clamp(minVal, maxVal),
                            min: minVal,
                            max: maxVal,
                            divisions: ((maxVal - minVal) ~/ 1).clamp(1, 200),
                            label: sliderVal.toStringAsFixed(0),
                            onChanged: (v) {
                              setDialogState(() => sliderVal = v);
                              controller.text = v.toStringAsFixed(0);
                            },
                          ),
                        ),
                        Text('${maxVal.toInt()}', style: TextStyle(fontSize: 12.sp)),
                      ],
                    ),
                  SizedBox(height: 8.h),
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: '$minVal ~ $maxVal',
                      suffixText: param.unit,
                    ),
                    onChanged: (v) {
                      final parsed = double.tryParse(v);
                      if (parsed != null) {
                        setDialogState(() => sliderVal = parsed.clamp(minVal, maxVal));
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final val = num.tryParse(controller.text);
                    if (val != null) {
                      _onValueChanged(param.key, val);
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showReadbackResult(DeviceParamReadbackResult state) {
    if (state.mismatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('参数设置成功'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 2),
        ),
      );
      setState(() {
        _originalValues = Map.from(_modifiedValues);
        _modifiedValues = Map.from(_modifiedValues);
        _isApplying = false;
      });
    } else {
      setState(() => _isApplying = false);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
          title: Row(
            children: [
              Icon(Icons.warning_amber, color: AppColors.warning, size: 24.sp),
              SizedBox(width: 8.w),
              const Text('回读不一致'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '以下参数写入值与回读值不一致，请确认设备是否正确执行：',
                style: TextStyle(fontSize: 13.sp),
              ),
              SizedBox(height: 12.h),
              ...state.mismatches.map((key) {
                final written = state.writtenParams[key];
                final readback = state.readbackParams[key];
                return Container(
                  margin: EdgeInsets.only(bottom: 6.h),
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(key, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
                            SizedBox(height: 2.h),
                            Row(
                              children: [
                                Text('写入: $written', style: TextStyle(fontSize: 11.sp, color: AppColors.primary)),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4.w),
                                  child: Icon(Icons.arrow_forward, size: 12.sp),
                                ),
                                Text('回读: $readback', style: TextStyle(fontSize: 11.sp, color: AppColors.warning)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('参数设置')),
      body: BlocConsumer<DeviceBloc, DeviceState>(
        listener: (context, state) {
          if (state is DeviceParamReadbackResult) {
            _showReadbackResult(state);
          }
          if (state is DeviceError) {
            setState(() => _isApplying = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message), backgroundColor: AppColors.error),
            );
          }
        },
        builder: (context, state) {
          if (state is DeviceLoading && _params.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is DeviceError && _params.isEmpty) {
            return Center(child: Text(state.message));
          }

          if (state is DeviceParamsLoaded) {
            _params = _parseParams(state.params);
            _originalValues = {for (final p in _params) p.key: p.value};
            _modifiedValues = {for (final p in _params) p.key: p.value};
          }

          if (_params.isEmpty) {
            return const Center(child: Text('暂无参数'));
          }

          final filtered = _filterParams(_params);
          final grouped = _groupParams(filtered);
          final groupKeys = grouped.keys.toList();

          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 4.h),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '搜索参数...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              Expanded(
                child: StyledRefreshIndicator(
                  onRefresh: () async {
                    context.read<DeviceBloc>().add(DeviceParamsRequested(sn: widget.deviceSN));
                  },
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                    itemCount: groupKeys.length,
                    itemBuilder: (context, index) {
                      final groupKey = groupKeys[index];
                      final groupParams = grouped[groupKey]!;
                      return _buildGroupTile(theme, groupKey, groupParams);
                    },
                  ),
                ),
              ),
              if (_modifiedCount > 0) _buildBottomBar(theme),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGroupTile(ThemeData theme, String groupKey, List<DeviceParam> params) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
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
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        title: Text(
          groupKey,
          style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700),
        ),
        children: params.map((p) => _buildParamItem(theme, p)).toList(),
      ),
    );
  }

  Widget _buildParamItem(ThemeData theme, DeviceParam param) {
    final modified = _isModified(param.key);
    final currentValue = _modifiedValues[param.key] ?? param.value;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 0.5),
          left: param.isDangerous
              ? BorderSide(color: AppColors.error.withValues(alpha: 0.6), width: 3)
              : BorderSide.none,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (param.isDangerous)
                        Padding(
                          padding: EdgeInsets.only(right: 4.w),
                          child: Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 16.sp),
                        ),
                      Flexible(
                        child: Text(
                          param.label,
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w500,
                            color: param.isDangerous ? AppColors.error : theme.colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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
                      '已修改',
                      style: TextStyle(fontSize: 10.sp, color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            if (param.description != null)
              Padding(
                padding: EdgeInsets.only(top: 2.h),
                child: Text(
                  param.description!,
                  style: TextStyle(fontSize: 11.sp, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            SizedBox(height: 6.h),
            _buildParamControl(theme, param, currentValue),
          ],
        ),
      ),
    );
  }

  Widget _buildParamControl(ThemeData theme, DeviceParam param, dynamic currentValue) {
    switch (param.paramType) {
      case 'number':
        return _buildNumberControl(theme, param, currentValue);
      case 'enum':
        return _buildEnumControl(theme, param, currentValue);
      case 'bool':
        return _buildBoolControl(theme, param, currentValue);
      case 'text':
        return _buildTextControl(theme, param, currentValue);
      default:
        return _buildNumberControl(theme, param, currentValue);
    }
  }

  Widget _buildNumberControl(ThemeData theme, DeviceParam param, dynamic currentValue) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Text(
                '${currentValue ?? '-'}',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: _isModified(param.key) ? AppColors.primary : theme.colorScheme.onSurface,
                ),
              ),
              if (param.unit.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(left: 4.w),
                  child: Text(
                    param.unit,
                    style: TextStyle(fontSize: 12.sp, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.edit, size: 20.sp, color: theme.colorScheme.primary),
          onPressed: () => _showNumberEditDialog(param),
          style: IconButton.styleFrom(
            backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            minimumSize: Size(36.w, 36.w),
          ),
        ),
      ],
    );
  }

  Widget _buildEnumControl(ThemeData theme, DeviceParam param, dynamic currentValue) {
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
            selectedColor: theme.colorScheme.primaryContainer,
          );
        }).toList(),
      );
    }

    return DropdownButton<dynamic>(
      value: currentValue,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      items: param.options
          .map((opt) => DropdownMenuItem<dynamic>(
                value: opt.value,
                child: Text(opt.label, style: TextStyle(fontSize: 13.sp)),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) _onValueChanged(param.key, v);
      },
    );
  }

  Widget _buildBoolControl(ThemeData theme, DeviceParam param, dynamic currentValue) {
    final val = currentValue is bool ? currentValue : currentValue == 1 || currentValue == '1' || currentValue == 'true';
    return Row(
      children: [
        Text(
          val ? '开启' : '关闭',
          style: TextStyle(
            fontSize: 14.sp,
            color: val ? AppColors.success : theme.colorScheme.onSurfaceVariant,
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

  Widget _buildTextControl(ThemeData theme, DeviceParam param, dynamic currentValue) {
    final controller = TextEditingController(text: '${currentValue ?? ''}');
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: '输入${param.label}',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      ),
      style: TextStyle(fontSize: 14.sp),
      onChanged: (v) => _onValueChanged(param.key, v),
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
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
                '已修改 $_modifiedCount 项参数',
                style: TextStyle(fontSize: 13.sp, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            FilledButton(
              onPressed: _isApplying ? null : _applyChanges,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
              ),
              child: _isApplying
                  ? SizedBox(
                      width: 18.w,
                      height: 18.w,
                      child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('应用修改'),
            ),
          ],
        ),
      ),
    );
  }
}
