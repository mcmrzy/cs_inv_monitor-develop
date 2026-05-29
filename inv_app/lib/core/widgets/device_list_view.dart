import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';

class DeviceFilterBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<String> filterLabels;
  final Color? backgroundColor;

  const DeviceFilterBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.filterLabels = const ['全部', '逆变器', '采集器', '储能'],
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? AppColors.background;
    return Container(
      color: bgColor,
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 10.h),
      child: Row(
        children: List.generate(filterLabels.length, (i) {
          final active = selectedIndex == i;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 3.w),
              child: GestureDetector(
                onTap: () => onSelected(i),
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 8.h),
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary.withValues(alpha: 0.1) : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(
                      color: active ? AppColors.primary.withValues(alpha: 0.4) : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Center(
                    child: Text(filterLabels[i],
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        color: active ? AppColors.primary : const Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class DeviceSearchBar extends StatefulWidget {
  final ValueChanged<String>? onSearchChanged;
  final String hintText;

  const DeviceSearchBar({
    super.key,
    this.onSearchChanged,
    this.hintText = '搜索序列号或型号',
  });

  @override
  State<DeviceSearchBar> createState() => _DeviceSearchBarState();
}

class _DeviceSearchBarState extends State<DeviceSearchBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
      child: TextField(
        controller: _controller,
        onChanged: widget.onSearchChanged,
        cursorColor: AppColors.primary,
        style: TextStyle(fontSize: 15.sp),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textHint),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textHint), onPressed: () { _controller.clear(); widget.onSearchChanged?.call(''); })
              : null,
          filled: true, fillColor: AppColors.surfaceHover,
          contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: const BorderSide(color: AppColors.primary, width: 1)),
        ),
      ),
    );
  }
}

class DeviceCard extends StatelessWidget {
  final Map<String, dynamic> device;

  const DeviceCard({super.key, required this.device});

  String _deviceType() {
    final model = (device['model'] ?? '').toString().toLowerCase();
    final sn = (device['sn'] ?? '').toString().toLowerCase();
    if (model.contains('battery') || model.contains('bms') || model.contains('储能') || sn.contains('batt')) return 'battery';
    if (model.contains('collect') || model.contains('采集') || model.contains('daq') || sn.contains('col')) return 'collector';
    return 'inv';
  }

  String _deviceTypeLabel(String type) {
    switch (type) {
      case 'inv': return '逆变器';
      case 'collector': return '采集器';
      case 'battery': return '储能设备';
      default: return '未知';
    }
  }

  void _showDeviceDetail(BuildContext context) {
    final sn = device['sn'] ?? '';
    context.push('/device/$sn');
  }

  String _extractString(List<String> keys) {
    for (final key in keys) {
      final val = device[key];
      if (val != null && val.toString().isNotEmpty) {
        return val.toString();
      }
    }
    return '--';
  }

  double _extractNum(String key) {
    final val = device[key];
    if (val is num) return val.toDouble();
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final sn = device['sn'] ?? '';
    final type = _deviceType();
    final status = device['status'] ?? 0;
    final isOnline = status == 1;
    final alarmCode = device['alarm_code'] ?? device['fault_code'] ?? 0;
    final hasAlarm = isOnline && alarmCode != 0 && alarmCode != '0' && alarmCode != '';

    final model = _extractString(['model', 'model_name', 'device_model']);
    final firmwareArm = _extractString(['firmware_arm', 'firmware_version', 'firmware', 'fw_version']);
    final ratedPower = _extractNum('rated_power');

    final badgeText = hasAlarm ? '告警' : (isOnline ? '正常' : '离线');
    final badgeBg = hasAlarm ? AppColors.badgeAlarmBg : (isOnline ? AppColors.badgeNormalBg : AppColors.badgeOfflineBg);
    final badgeColor = hasAlarm ? AppColors.badgeAlarmText : (isOnline ? AppColors.badgeNormalText : AppColors.badgeOfflineText);

    return GestureDetector(
      onTap: () {
        _showDeviceDetail(context);
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8.w, height: 8.w,
                  decoration: BoxDecoration(
                    color: isOnline ? AppColors.successLight : AppColors.textHint,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 6.w),
                Text(sn, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                  child: Text(badgeText, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600, color: badgeColor)),
                ),
              ],
            ),
            if (model != '--') ...[
              SizedBox(height: 4.h),
              Padding(
                padding: EdgeInsets.only(left: 14.w),
                child: Text(model, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
              ),
            ],
            SizedBox(height: 12.h),
            _deviceInfoRow('设备类型', _deviceTypeLabel(type)),
            if (ratedPower > 0) _deviceInfoRow('额定功率', '${ratedPower.toStringAsFixed(0)} W'),
            if (type == 'battery') ..._buildBatteryExtras(),
            if (type == 'inv') ..._buildInverterExtras(),
            if (firmwareArm != '--') ...[
              Padding(
                padding: EdgeInsets.only(top: 8.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('ARM固件: $firmwareArm', style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _deviceInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13.sp, color: AppColors.textHint)),
          SizedBox(width: 12.w),
          Flexible(
            child: Text(
              value,
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBatteryExtras() {
    final soc = _extractNum('battery_soc');
    final soh = _extractNum('battery_soh');
    final chargeEnergy = _extractNum('daily_charge_energy');
    final dischargeEnergy = _extractNum('daily_discharge_energy');
    return [
      _deviceInfoRow('电池 SOC', soc > 0 ? '${soc.toStringAsFixed(0)}%' : '--%'),
      _deviceInfoRow('电池健康度', soh > 0 ? '${soh.toStringAsFixed(0)}%' : '--%'),
      _deviceInfoRow('当日充电量', chargeEnergy > 0 ? '${chargeEnergy.toStringAsFixed(2)} kWh' : '-- kWh'),
      _deviceInfoRow('当日放电量', dischargeEnergy > 0 ? '${dischargeEnergy.toStringAsFixed(2)} kWh' : '-- kWh'),
    ];
  }

  List<Widget> _buildInverterExtras() {
    final currentPower = _extractNum('current_power');
    final dailyEnergy = _extractNum('daily_energy');
    final acPower = _extractNum('ac_power');
    final dailyPV = _extractNum('daily_pv');

    final powerValue = acPower > 0 ? acPower : (currentPower > 0 ? currentPower : 0);
    final energyValue = dailyPV > 0 ? dailyPV : (dailyEnergy > 0 ? dailyEnergy : 0);

    return [
      _deviceInfoRow('当前功率', powerValue > 0 ? '${powerValue.toStringAsFixed(1)} W' : '--'),
      _deviceInfoRow('当日发电量', energyValue > 0 ? '${energyValue.toStringAsFixed(2)} kWh' : '--'),
    ];
  }
}

class DeviceListView extends StatefulWidget {
  final List<dynamic> devices;
  final bool showSearch;
  final bool whiteHeader;
  final List<String> filterLabels;
  final String emptyText;
  final double? bottomPadding;

  const DeviceListView({
    super.key,
    required this.devices,
    this.showSearch = true,
    this.whiteHeader = false,
    this.filterLabels = const ['全部', '逆变器', '采集器', '储能'],
    this.emptyText = '暂无设备',
    this.bottomPadding = 100,
  });

  @override
  State<DeviceListView> createState() => _DeviceListViewState();
}

class _DeviceListViewState extends State<DeviceListView> {
  int _deviceFilter = 0;
  String _searchQuery = '';

  List<dynamic> _filterDevices(List<dynamic> devices) {
    var list = devices;

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.trim().toLowerCase();
      list = list.where((d) {
        final sn = (d['sn'] ?? '').toString().toLowerCase();
        final model = (d['model'] ?? '').toString().toLowerCase();
        return sn.contains(query) || model.contains(query);
      }).toList();
    }

    if (_deviceFilter > 0) {
      list = list.where((d) {
        final t = _deviceType(d);
        switch (_deviceFilter) {
          case 1: return t == 'inv';
          case 2: return t == 'collector';
          case 3: return t == 'battery';
          default: return true;
        }
      }).toList();
    }

    return list;
  }

  String _deviceType(dynamic d) {
    final model = (d['model'] ?? '').toString().toLowerCase();
    final sn = (d['sn'] ?? '').toString().toLowerCase();
    if (model.contains('battery') || model.contains('bms') || model.contains('储能') || sn.contains('batt')) return 'battery';
    if (model.contains('collect') || model.contains('采集') || model.contains('daq') || sn.contains('col')) return 'collector';
    return 'inv';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filterDevices(widget.devices);

    final headerBgColor = widget.whiteHeader ? Colors.white : AppColors.background;
    final headerChipBgColor = widget.whiteHeader ? Colors.white : headerBgColor;

    return Column(
      children: [
        Container(
          color: headerBgColor,
          child: Column(
            children: [
              if (widget.showSearch)
                DeviceSearchBar(
                  onSearchChanged: (v) => setState(() => _searchQuery = v),
                ),
              DeviceFilterBar(
                selectedIndex: _deviceFilter,
                onSelected: (i) => setState(() => _deviceFilter = i),
                filterLabels: widget.filterLabels,
                backgroundColor: headerChipBgColor,
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(widget.emptyText, style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)),
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, (widget.bottomPadding ?? 100).h),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => DeviceCard(device: filtered[i]),
                ),
        ),
      ],
    );
  }
}
