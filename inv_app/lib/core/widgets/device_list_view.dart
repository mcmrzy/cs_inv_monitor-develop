import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

// 搜索栏组件
class DeviceSearchBar extends StatefulWidget {
  final ValueChanged<String>? onSearchChanged;
  final String? hintText;

  const DeviceSearchBar({
    super.key,
    this.onSearchChanged,
    this.hintText,
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
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
      child: TextField(
        controller: _controller,
        onChanged: widget.onSearchChanged,
        cursorColor: AppColors.primary,
        style: TextStyle(fontSize: 15.sp),
        decoration: InputDecoration(
          hintText: widget.hintText ?? l10n.searchDeviceHint,
          hintStyle: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textHint),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textHint),
                  onPressed: () {
                    _controller.clear();
                    widget.onSearchChanged?.call('');
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.surfaceHover,
          contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: const BorderSide(color: AppColors.primary, width: 1)),
        ),
      ),
    );
  }
}

class DeviceFilterBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<String>? filterLabels;
  final Color? backgroundColor;

  const DeviceFilterBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.filterLabels,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labels = filterLabels ??
        [
          l10n.allDevices,
          l10n.deviceTypeInverter,
          l10n.deviceTypeCollector,
          l10n.deviceTypeStorage,
        ];
    final bgColor = backgroundColor ?? AppColors.background;
    return Container(
      color: bgColor,
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 10.h),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = selectedIndex == i;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 3.w),
              child: GestureDetector(
                onTap: () => onSelected(i),
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 8.h),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(
                      color: active
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        color: active
                            ? AppColors.primary
                            : const Color(0xFF9CA3AF),
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

class DeviceCard extends StatefulWidget {
  final Map<String, dynamic> device;
  final VoidCallback? onDeviceChanged;
  final ValueChanged<String>? onUnbind;
  final ValueChanged<String>? onRebind;
  final ValueChanged<String>? onBind;
  final ValueChanged<String>? onDelete;
  final bool showUnbindButton;
  final bool enableReordering;

  const DeviceCard({
    super.key,
    required this.device,
    this.onDeviceChanged,
    this.onUnbind,
    this.onRebind,
    this.onBind,
    this.onDelete,
    this.showUnbindButton = true,
    this.enableReordering = false,
  });

  @override
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showDetail(BuildContext context) async {
    final sn = widget.device['sn'] ?? '';
    _controller.forward().then((_) => _controller.reverse().then((_) {
      Navigator.pushNamed(context, '/device/$sn');
    }));
  }

  // 显示设备动作菜单
  void _showActions(BuildContext context, String sn) {
    final l10n = AppLocalizations.of(context)!;
    final isBound = widget.device['station_id'] != null && widget.device['station_id'] != 0;
    
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40.w,
              height: 4.h,
              margin: EdgeInsets.only(top: 12.h),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            ListTile(
              leading: Icon(Icons.info_outline, color: AppColors.primary),
              title: Text(l10n.deviceDetail),
              onTap: () {
                Navigator.pop(ctx);
                _showDetail(context);
              },
            ),
            if (isBound && widget.onRebind != null)
              ListTile(
                leading: Icon(Icons.swap_horiz, color: AppColors.primary),
                title: Text(l10n.rebindDevice),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onRebind?.call(sn);
                },
              ),
            if (widget.showUnbindButton && widget.onUnbind != null)
              ListTile(
                leading: Icon(Icons.link_off, color: Colors.red),
                title: Text(l10n.unbind, style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _confirmUnbindDialog(context, sn);
                },
              ),
            if (widget.onDelete != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red),
                title: Text(l10n.deleteDevice, style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _confirmDeleteDialog(context, sn);
                },
              ),
            if (!isBound && widget.onBind != null)
              ListTile(
                leading: Icon(Icons.link, color: AppColors.successLight),
                title: Text(l10n.bindDevice),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onBind?.call(sn);
                },
              ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom),
          ],
        ),
      ),
    );
  }

  double _extractNum(String key) {
    final val = widget.device[key];
    return val is num ? val.toDouble() : 0.0;
  }

  String _extractString(List<String> keys) {
    for (final key in keys) {
      final val = widget.device[key];
      if (val != null && val.toString().isNotEmpty) {
        return val.toString();
      }
    }
    return '--';
  }

  String _getDeviceTypeLabel(AppLocalizations l10n) {
    final model =
        (widget.device['model'] ?? '').toString().toLowerCase();
    if (model.contains('battery') || model.contains('bms') ||
        model.contains('储能')) return l10n.deviceTypeStorage;
    if (model.contains('collect') || model.contains('采集'))
      return l10n.collector;
    return l10n.inverter;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sn = widget.device['sn'] ?? '';
    final status = widget.device['status'] ?? 0;
    final isOnline = status == 1;
    final isFault = status == 2;
    final badgeText = isFault
        ? l10n.fault
        : (hasAlarm ? l10n.alarm : (isOnline ? l10n.normal : l10n.offline));
    final badgeBg = isFault
        ? AppColors.badgeAlarmBg
        : (hasAlarm ? AppColors.badgeAlarmBg : isOnline ? AppColors.badgeNormalBg : AppColors.badgeOfflineBg);
    final badgeColor = isFault
        ? AppColors.badgeAlarmText
        : (hasAlarm ? AppColors.badgeAlarmText : isOnline ? AppColors.badgeNormalText : AppColors.badgeOfflineText);

    final model = _extractString(['model', 'model_name']);
    final firmwareArm = _extractString(['firmware_arm', 'fw_version']);
    final ratedPower = _extractNum('rated_power');

    Widget cardContent = GestureDetector(
      onTap: () => _showDetail(context),
      onLongPress: widget.showUnbindButton ? () => _showActions(context, sn) : null,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          margin: EdgeInsets.only(bottom: 12.h),
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8.w,
                    height: 8.w,
                    decoration: BoxDecoration(
                      color: isFault
                          ? AppColors.errorLight
                          : (isOnline ? AppColors.successLight : AppColors.textHint),
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Text(sn,
                      style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                    decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(6.r)),
                    child: Text(badgeText,
                        style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600, color: badgeColor)),
                  ),
                ],
              ),
              if (model != '--') ...[SizedBox(height: 4.h), Text(model, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary))],
              SizedBox(height: 12.h),
              Row(children: [Text(l10n.deviceTypeLabelKey, style: TextStyle(fontSize: 13.sp, color: AppColors.textHint)), SizedBox(width: 12.w), Expanded(child: Text(_getDeviceTypeLabel(l10n), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600), textAlign: TextAlign.right))]),
              if (ratedPower > 0)
                Row(children: [Text('${ratedPower.toStringAsFixed(0)} W', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)), SizedBox(width: 12.w), Text(l10n.ratedPowerLabel, style: TextStyle(fontSize: 13.sp, color: AppColors.textHint))]),
              if (firmwareArm != '--')
                Padding(
                  padding: EdgeInsets.only(top: 8.h),
                  child: Text('$firmwareArm', style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
                ),
            ],
          ),
        ),
      ),
    );

    if (widget.enableReordering) {
      return LongPressDraggable(
        data: sn,
        childWhenDragging: Opacity(opacity: 0.5, child: cardContent),
        feedback: Material(elevation: 4, child: CloneWidget(widget: cardContent)),
        child: cardContent,
      );
    }

    return cardContent;
  }

  bool get hasAlarm {
    final alarmCode = widget.device['alarm_code'] ?? widget.device['fault_code'] ?? 0;
    final status = widget.device['status'] ?? 0;
    final isOnline = status == 1;
    final isFault = status == 2;
    return (isOnline || isFault) && alarmCode != 0 && alarmCode != '0' && alarmCode != '';
  }

  // 解绑确认对话框
  Future<void> _confirmUnbindDialog(BuildContext context, String sn) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.unbind),
        content: Text('确认解绑该设备吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.unbind, style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && widget.onUnbind != null) {
      widget.onUnbind!(sn);
    }
  }

  // 删除确认对话框
  Future<void> _confirmDeleteDialog(BuildContext context, String sn) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteDevice),
        content: Text('确认删除该设备吗？删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete, style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && widget.onDelete != null) {
      widget.onDelete!(sn);
    }
  }
}

class CloneWidget extends StatelessWidget {
  final Widget widget;
  const CloneWidget({super.key, required this.widget});
  @override
  Widget build(BuildContext context) => widget;
}

class DeviceListView extends StatefulWidget {
  final List<dynamic> devices;
  final bool showSearch;
  final bool whiteHeader;
  final List<String>? filterLabels;
  final String? emptyText;
  final double? bottomPadding;
  final VoidCallback? onDeviceChanged;
  final ValueChanged<String>? onUnbind;
  final ValueChanged<String>? onRebind;
  final ValueChanged<String>? onBind;
  final ValueChanged<String>? onDelete;
  final bool showUnbindButton;
  final bool enableReordering;

  const DeviceListView({
    super.key,
    required this.devices,
    this.showSearch = true,
    this.whiteHeader = false,
    this.filterLabels,
    this.emptyText,
    this.bottomPadding = 100,
    this.onDeviceChanged,
    this.onUnbind,
    this.onRebind,
    this.onBind,
    this.onDelete,
    this.showUnbindButton = true,
    this.enableReordering = false,
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
          case 1:
            return t == 'inv';
          case 2:
            return t == 'collector';
          case 3:
            return t == 'battery';
          default:
            return true;
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
              DeviceFilterBar(selectedIndex: _deviceFilter, onSelected: (i) => setState(() => _deviceFilter = i),
                  filterLabels: widget.filterLabels, backgroundColor: headerChipBgColor),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(child: Text(widget.emptyText ?? AppLocalizations.of(context)!.noDevices, style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)))
              : widget.enableReordering
                  ? ReorderableListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, (widget.bottomPadding ?? 100).h),
                      onReorderItem: (oldIndex, newIndex) {
                        setState(() {
                          final device = filtered.removeAt(oldIndex);
                          filtered.insert(newIndex, device);
                        });
                        // 异步更新数据库排序字段
                        if (widget.onDeviceChanged != null) {
                          widget.onDeviceChanged!();
                        }
                      },
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => DeviceCard(
                        key: ValueKey(filtered[i]['sn'] ?? i),
                        device: filtered[i],
                        onDeviceChanged: widget.onDeviceChanged,
                        onUnbind: widget.onUnbind,
                        onRebind: widget.onRebind,
                        onBind: widget.onBind,
                        onDelete: widget.onDelete,
                        showUnbindButton: widget.showUnbindButton,
                        enableReordering: widget.enableReordering,
                      ),
                    )
                  : ListView.builder(
                      physics: BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, (widget.bottomPadding ?? 100).h),
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => DeviceCard(
                        key: ValueKey(filtered[i]['sn'] ?? i),
                        device: filtered[i],
                        onDeviceChanged: widget.onDeviceChanged,
                        onUnbind: widget.onUnbind,
                        onRebind: widget.onRebind,
                        onBind: widget.onBind,
                        onDelete: widget.onDelete,
                        showUnbindButton: widget.showUnbindButton,
                        enableReordering: widget.enableReordering,
                      ),
                    ),
        ),
      ],
    );
  }
}
