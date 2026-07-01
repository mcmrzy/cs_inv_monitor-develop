import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/mqtt_service.dart';
import 'package:inv_app/core/entities/device_model_field.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class DeviceRealtimePage extends StatefulWidget {
  final String sn;
  final String type;

  const DeviceRealtimePage({super.key, required this.sn, required this.type});

  @override
  State<DeviceRealtimePage> createState() => _DeviceRealtimePageState();
}

class _DeviceRealtimePageState extends State<DeviceRealtimePage> {
  Map<String, dynamic> _realtimeData = {};
  List<DeviceModelField> _modelFields = [];
  bool _online = false;
  bool _loading = true;
  String? _error;
  String? _modelName;
  StreamSubscription? _statusSub;

  // 分组定义（颜色和图标）
  static const _groupStyles = {
    'ac_params': {'icon': Icons.bolt_rounded, 'color': Color(0xFF8B5CF6)},
    'pv_params': {'icon': Icons.wb_sunny_outlined, 'color': Color(0xFFF59E0B)},
    'battery_params': {'icon': Icons.battery_charging_full, 'color': Color(0xFF10B981)},
    'system_status': {'icon': Icons.info_outline_rounded, 'color': Color(0xFF06B6D4)},
    'energy_stats': {'icon': Icons.show_chart_rounded, 'color': Color(0xFF3B82F6)},
    'device_info': {'icon': Icons.device_hub_rounded, 'color': Color(0xFF6B7280)},
    'control_cmd': {'icon': Icons.tune_rounded, 'color': Color(0xFFEF4444)},
  };

  // 英文 key 到 l10n 显示名的映射
  String _localizedGroupName(String groupName) {
    final l10n = AppLocalizations.of(context)!;
    switch (groupName) {
      case 'ac_params':
        return l10n.groupAcParams;
      case 'pv_params':
        return l10n.groupPvParams;
      case 'battery_params':
        return l10n.groupBatteryParams;
      case 'system_status':
        return l10n.groupSystemStatus;
      case 'energy_stats':
        return l10n.groupEnergyStats;
      case 'device_info':
        return l10n.groupDeviceInfo;
      case 'control_cmd':
        return l10n.groupControlCmd;
      default:
        return l10n.groupOther;
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchDeviceDetail();
    _listenOnlineStatus();
  }

  void _listenOnlineStatus() {
    try {
      final mqtt = getIt<MQTTService>();
      _statusSub = mqtt.statusStream
          .where((status) => true) // 接收所有状态更新
          .listen((status) {
        if (mounted) {
          setState(() {
            _online = status.online;
          });
        }
      });
    } catch (_) {
      // MQTT 服务未初始化时忽略
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchDeviceDetail() async {
    try {
      final dio = getIt<Dio>();
      final res = await dio.get('/devices/${widget.sn}');
      if (res.statusCode == 200 && mounted) {
        final data = res.data['data'] as Map<String, dynamic>? ?? {};

        // 解析 realtime_data
        final realtimeRaw = data['realtime_data'] as Map<String, dynamic>? ?? {};
        Map<String, dynamic> flatData = {};

        // realtime_data 可能是嵌套结构（ac/pv/energy 对象），展平它
        // 数据结构可能是 {"ac": {"power": 2319}} 或 {"ac": {"data": {...}, "timestamp": ...}}
        realtimeRaw.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            // 检查是否有 data 子字段（新格式）
            if (value.containsKey('data') && value['data'] is Map<String, dynamic>) {
              final innerData = value['data'] as Map<String, dynamic>;
              innerData.forEach((subKey, subValue) {
                final flatKey = '${key}_$subKey';
                flatData[flatKey] = subValue;
              });
            } else {
              // 旧格式：直接嵌套
              value.forEach((subKey, subValue) {
                final flatKey = '${key}_$subKey';
                flatData[flatKey] = subValue;
              });
            }
          } else {
            flatData[key] = value;
          }
        });

        // 解析 model_fields
        final fieldsRaw = data['model_fields'] as List<dynamic>? ?? [];
        final fields = fieldsRaw
            .map((e) => DeviceModelField.fromJson(e as Map<String, dynamic>))
            .where((f) => f.isShow) // 只显示 is_show=true 的字段
            .toList();

        setState(() {
          _realtimeData = flatData;
          _modelFields = fields;
          _online = data['online_status']?['online'] == true || data['device']?['status'] == 1;
          _modelName = data['device']?['model'] as String?;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context)!.failedToLoad;
          _loading = false;
        });
      }
    }
  }

  /// 根据 field_key 前缀推断分组名（当数据库 group_name 为空时使用）
  String _inferGroupFromFieldKey(String fieldKey) {
    if (fieldKey.startsWith('ac_')) return 'ac_params';
    if (fieldKey.startsWith('pv_')) return 'pv_params';
    if (fieldKey.startsWith('batt_') || fieldKey.startsWith('battery_')) return 'battery_params';
    if (fieldKey.startsWith('energy_') || fieldKey.startsWith('daily_') || fieldKey.startsWith('total_')) return 'energy_stats';
    if (fieldKey.startsWith('sys_') || fieldKey.startsWith('state') || fieldKey.startsWith('work_') || fieldKey.startsWith('fault_') || fieldKey.startsWith('internal_') || fieldKey.startsWith('temp_')) return 'system_status';
    if (fieldKey.startsWith('load_')) return 'ac_params';
    if (fieldKey.startsWith('meter_')) return 'ac_params';
    return 'device_info';
  }

  /// 按 group_name 分组字段（group_name 为空时根据 field_key 前缀推断）
  Map<String, List<DeviceModelField>> _groupByField() {
    final groups = <String, List<DeviceModelField>>{};
    for (final field in _modelFields) {
      final group = field.groupName.isNotEmpty ? field.groupName : _inferGroupFromFieldKey(field.fieldKey);
      groups.putIfAbsent(group, () => []).add(field);
    }
    // 按 sort 排序每个组内的字段
    for (final list in groups.values) {
      list.sort((a, b) => a.sort.compareTo(b.sort));
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50.h),
        child: AppBar(
          title: Text(
            l10n.deviceDetail,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17.sp),
          ),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                setState(() => _loading = true);
                _fetchDeviceDetail();
              },
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 44.sp, color: AppColors.textHint),
          SizedBox(height: 12.h),
          Text(_error!, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
          SizedBox(height: 16.h),
          OutlinedButton(
            onPressed: () {
              setState(() { _loading = true; _error = null; });
              _fetchDeviceDetail();
            },
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final groups = _groupByField();

    return RefreshIndicator(
      onRefresh: _fetchDeviceDetail,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 40.h),
        children: [
          // 顶部状态卡片
          _buildStatusCard(),
          SizedBox(height: 12.h),
          // 参数设置入口
          _buildSettingsEntry(),
          SizedBox(height: 16.h),
          // 动态分组
          ...groups.entries.map((entry) => _buildGroupCard(entry.key, entry.value)),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final l10n = AppLocalizations.of(context)!;
    final sn = widget.sn;
    final model = _modelName ?? '';

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: AppColor.heroCard(context),
      child: Row(
        children: [
          Container(
            width: 48.w,
            height: 48.w,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(Icons.solar_power_rounded, size: 28.w, color: Colors.white),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sn, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                if (model.isNotEmpty)
                  Text(model, style: TextStyle(fontSize: 12.sp, color: Colors.white70)),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: _online ? AppColors.online : AppColors.offline,
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Text(
              _online ? l10n.online : l10n.offline,
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsEntry() {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () => context.push('/device/${widget.sn}/settings'),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        decoration: AppColor.card(context),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(Icons.tune_rounded, size: 20.sp, color: AppColors.primary),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.paramSettings,
                    style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    l10n.settingsEntryDesc,
                    style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20.sp, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(String groupName, List<DeviceModelField> fields) {
    final style = _groupStyles[groupName] ?? {'icon': Icons.device_hub, 'color': AppColors.primary};
    final icon = style['icon'] as IconData;
    final color = style['color'] as Color;
    final displayName = _localizedGroupName(groupName);

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: AppColor.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 组标题
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 14.w, 16.w, 8.w),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(6.w),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Icon(icon, size: 16.sp, color: color),
                ),
                SizedBox(width: 10.w),
                Text(displayName, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          // 字段列表
          ...fields.map((field) => _buildFieldRow(field)),
        ],
      ),
    );
  }

  Widget _buildFieldRow(DeviceModelField field) {
    final value = _realtimeData[field.fieldKey];
    final displayValue = _formatFieldValue(value, field);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(field.fieldName, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayValue,
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              if (field.unit.isNotEmpty) ...[
                SizedBox(width: 4.w),
                Text(field.unit, style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatFieldValue(dynamic value, DeviceModelField field) {
    if (value == null) return '--';

    switch (field.fieldType) {
      case 'float':
        if (value is num) return value.toStringAsFixed(1);
        return value.toString();
      case 'int':
        if (value is num) return value.toInt().toString();
        return value.toString();
      case 'bool':
        final l10n = AppLocalizations.of(context)!;
        return value == true || value == 1 || value == 'true' ? l10n.yesLabel : l10n.noLabel;
      default:
        return value.toString();
    }
  }
}
