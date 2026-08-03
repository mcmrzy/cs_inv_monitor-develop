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
                        : AppColor.border(context),
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(
                      color: active
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : AppColor.border(context),
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
                            : AppColors.textHint,
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
  final ValueChanged<String>? onUnbind;
  final ValueChanged<String>? onRebind;
  final ValueChanged<String>? onBind;
  final ValueChanged<String>? onDelete;
  final bool showUnbindButton;
  final bool enableReordering;

  const DeviceCard({
    super.key,
    required this.device,
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
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showDetail(BuildContext context) {
    final sn = widget.device['sn'] ?? '';
    Navigator.pushNamed(context, '/device/$sn');
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
                leading: Icon(Icons.link_off, color: AppColors.error),
                title: Text(l10n.unbind, style: TextStyle(color: AppColors.error)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _confirmUnbindDialog(context, sn);
                },
              ),
            if (widget.onDelete != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppColors.error),
                title: Text(l10n.deleteDevice, style: TextStyle(color: AppColors.error)),
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

    Widget cardContent = Padding(
      // margin 放在缩放外层：与电站卡片结构一致，按下时只缩放卡片本体
      padding: EdgeInsets.only(bottom: 12.h),
      child: GestureDetector(
        // 与电站卡片一致的手感：按下缩放、抬起恢复并跳转
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) {
          _controller.reverse();
          _showDetail(context);
        },
        onTapCancel: () => _controller.reverse(),
        // 拖动排序模式下长按由 ReorderableListView 接管；否则长按弹出操作菜单
        onLongPress: widget.enableReordering || !widget.showUnbindButton
            ? null
            : () => _showActions(context, sn),
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: AppColor.surfaceContainer(context),
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
                  // 拖动排序模式下长按被占用，提供菜单按钮入口
                  if (widget.enableReordering)
                    GestureDetector(
                      onTap: () => _showActions(context, sn),
                      child: Padding(
                        padding: EdgeInsets.only(left: 6.w),
                        child: Icon(Icons.more_horiz,
                            size: 20, color: AppColors.textHint),
                      ),
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
    ),
    );

    // ReorderableListView 在移动端默认用 ReorderableDelayedDragStartListener
    // 包裹整个 item（长按即拖动），无需额外的 LongPressDraggable。
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
            child: Text(l10n.unbind, style: TextStyle(color: AppColors.error)),
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
            child: Text(l10n.delete, style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && widget.onDelete != null) {
      widget.onDelete!(sn);
    }
  }
}

class DeviceListView extends StatefulWidget {
  final List<dynamic> devices;
  final bool showSearch;
  final bool whiteHeader;
  final List<String>? filterLabels;
  final String? emptyText;
  final double? bottomPadding;
  // 排序变化回调：传入新的 SN 顺序（仅 enableReordering 时触发）
  final ValueChanged<List<String>>? onDeviceChanged;
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
  // 拖动排序后的设备顺序：以本地状态持有，避免每次 build
  // 从 widget.devices 重新派生导致排序丢失
  late List<dynamic> _ordered;

  @override
  void initState() {
    super.initState();
    _ordered = List.of(widget.devices);
  }

  @override
  void didUpdateWidget(DeviceListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 设备集合（SN 集合）变化时重置本地顺序；
    // 拖动排序后父级刷新返回同集合数据时保持本地顺序
    if (!_sameSnSet(oldWidget.devices, widget.devices)) {
      _ordered = List.of(widget.devices);
    }
  }

  bool _sameSnSet(List<dynamic> a, List<dynamic> b) {
    if (a.length != b.length) return false;
    final sns = a.map((d) => d['sn']).toSet();
    return b.every((d) => sns.contains(d['sn']));
  }

  // 把过滤视图中的拖动结果同步回 _ordered：
  // 移动的元素插到锚点元素之前（移到末尾则插到最后一个元素之后）
  void _applyReorder(int oldIndex, int newIndex) {
    final filtered = _filterDevices(_ordered);
    final moved = filtered[oldIndex];
    final movedSn = (moved['sn'] ?? '').toString();
    _ordered.removeWhere((d) => (d['sn'] ?? '').toString() == movedSn);
    final afterRemove = List.of(filtered)..removeAt(oldIndex);
    final anchorSn =
        newIndex >= afterRemove.length
            ? (afterRemove.last['sn'] ?? '').toString()
            : (afterRemove[newIndex]['sn'] ?? '').toString();
    final anchorIdx =
        _ordered.indexWhere((d) => (d['sn'] ?? '').toString() == anchorSn);
    _ordered.insert(
      anchorIdx + (newIndex >= afterRemove.length ? 1 : 0),
      moved,
    );
  }

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
    final filtered = _filterDevices(_ordered);
    final headerBgColor =
        widget.whiteHeader ? AppColor.surfaceContainer(context) : AppColor.surface(context);
    final headerChipBgColor =
        widget.whiteHeader ? AppColor.surfaceContainer(context) : headerBgColor;

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
                      // 拖起时卡片浮起放大，让用户明确感知正在拖动排序
                      proxyDecorator: (child, index, animation) {
                        final curved = CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeInOut,
                        );
                        return AnimatedBuilder(
                          animation: curved,
                          builder: (_, __) => Transform.scale(
                            scale: 1 + 0.03 * curved.value,
                            child: Material(
                              color: AppColor.surfaceContainer(context),
                              elevation: 6 * curved.value,
                              borderRadius: BorderRadius.circular(16.r),
                              shadowColor:
                                  AppColors.primary.withValues(alpha: 0.4),
                              child: child,
                            ),
                          ),
                        );
                      },
                      onReorderItem: (oldIndex, newIndex) {
                        setState(() => _applyReorder(oldIndex, newIndex));
                        // 异步更新数据库排序字段
                        widget.onDeviceChanged?.call(
                          _ordered
                              .map((d) => (d['sn'] ?? '').toString())
                              .toList(),
                        );
                      },
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => DeviceCard(
                        key: ValueKey(filtered[i]['sn'] ?? i),
                        device: filtered[i],
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
