import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/widgets/jiggle_once.dart';
import 'package:inv_app/core/widgets/pagination_bar.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
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
  // 非排序模式下长按卡片：弹出设备编辑页
  final ValueChanged<String>? onLongPressDevice;
  // 排序模式：长按由 ReorderableListView 接管为拖动
  final bool sortMode;

  const DeviceCard({
    super.key,
    required this.device,
    this.onLongPressDevice,
    this.sortMode = false,
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
    // 项目为 go_router（MaterialApp.router），必须用 context.push 而非 Navigator.pushNamed
    context.push('/device/$sn');
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
    final alias = (widget.device['alias'] ?? '').toString();
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
          // 排序模式下点击不跳详情（拖动手势由 ReorderableListView 接管）
          if (!widget.sortMode) _showDetail(context);
        },
        onTapCancel: () => _controller.reverse(),
        // 排序模式下长按由 ReorderableListView 接管为拖动；否则长按弹出编辑页
        onLongPress: widget.sortMode
            ? null
            : () => widget.onLongPressDevice?.call(sn),
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
                  // 设备名称：优先别名，回退 SN
                  Text(alias.isNotEmpty ? alias : sn,
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
                // 信息行统一为“标签左、值右”
                Padding(
                  padding: EdgeInsets.only(top: 4.h),
                  child: Row(children: [Text(l10n.ratedPowerLabel, style: TextStyle(fontSize: 13.sp, color: AppColors.textHint)), SizedBox(width: 12.w), Expanded(child: Text('${ratedPower.toStringAsFixed(0)} W', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600), textAlign: TextAlign.right))]),
                ),
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

    // 排序模式：buildDefaultDragHandles=false + ReorderableDragStartListener，
    // 按下即拖（无需长按），卡片 onTap 在排序模式下已为空操作，无手势冲突。
    return cardContent;
  }

  bool get hasAlarm {
    final alarmCode = widget.device['alarm_code'] ?? widget.device['fault_code'] ?? 0;
    final status = widget.device['status'] ?? 0;
    final isOnline = status == 1;
    final isFault = status == 2;
    return (isOnline || isFault) && alarmCode != 0 && alarmCode != '0' && alarmCode != '';
  }
}

class DeviceListView extends StatefulWidget {
  final List<dynamic> devices;
  final bool showSearch;
  final bool whiteHeader;
  final List<String>? filterLabels;
  final String? emptyText;
  final double? bottomPadding;
  // 排序变化回调：传入新的 SN 顺序（仅 sortMode 时触发）
  final ValueChanged<List<String>>? onDeviceChanged;
  // 非排序模式下长按卡片：弹出设备编辑页
  final ValueChanged<String>? onLongPressDevice;
  // 排序模式：启用 ReorderableListView 长按拖动
  final bool sortMode;
  // 下拉刷新回调：非空时非排序列表包 StyledRefreshIndicator 支持下拉刷新
  final Future<void> Function()? onRefresh;

  const DeviceListView({
    super.key,
    required this.devices,
    this.showSearch = true,
    this.whiteHeader = false,
    this.filterLabels,
    this.emptyText,
    this.bottomPadding = 100,
    this.onDeviceChanged,
    this.onLongPressDevice,
    this.sortMode = false,
    this.onRefresh,
  });

  @override
  State<DeviceListView> createState() => _DeviceListViewState();
}

class _DeviceListViewState extends State<DeviceListView> {
  int _deviceFilter = 0;
  String _searchQuery = '';
  // 非排序模式分页页码（1-based）；搜索/筛选/设备集合变化时重置为 1
  int _page = 1;
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
      // 设备集合变化（新增/删除/刷新）时回到第一页
      _page = 1;
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

  // 非排序列表：分页 + onRefresh 非空时用 StyledRefreshIndicator 包裹支持下拉刷新
  // （分页栏固定在列表底部，不随列表滚动）
  Widget _buildNonSortList(List<dynamic> paged, int pageCount, int safePage) {
    final listView = ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, (widget.bottomPadding ?? 100).h),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemCount: paged.length,
      itemBuilder: (_, i) => DeviceCard(
        key: ValueKey(paged[i]['sn'] ?? i),
        device: paged[i],
        onLongPressDevice: widget.onLongPressDevice,
        sortMode: widget.sortMode,
      ),
    );
    final content = Column(
      children: [
        Expanded(child: listView),
        // 超过一页才显示分页栏
        if (pageCount > 1)
          PaginationBar(
            currentPage: safePage,
            totalPages: pageCount,
            onPageChanged: (p) => setState(() => _page = p),
          ),
      ],
    );
    if (widget.onRefresh == null) return content;
    return StyledRefreshIndicator(
      color: AppColors.primary,
      onRefresh: widget.onRefresh!,
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filterDevices(_ordered);
    // 分页：每页 20 条；不足一页时整页展示（PaginationBar 自身也会兜底隐藏）
    final pageCount = filtered.isEmpty ? 1 : (filtered.length / 20).ceil();
    final safePage = _page.clamp(1, pageCount);
    final pageEnd = safePage * 20 < filtered.length ? safePage * 20 : filtered.length;
    final paged = pageCount <= 1
        ? filtered
        : filtered.sublist((safePage - 1) * 20, pageEnd);
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
                  onSearchChanged: (v) => setState(() {
                    _searchQuery = v;
                    _page = 1;
                  }),
                ),
              DeviceFilterBar(
                  selectedIndex: _deviceFilter,
                  onSelected: (i) => setState(() {
                    _deviceFilter = i;
                    _page = 1;
                  }),
                  filterLabels: widget.filterLabels,
                  backgroundColor: headerChipBgColor),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              // 空设备插画：无设备引导态（美术路由 empty-devices）
              ? XiaoshuoStatePanel(
                  asset: CsergyAssets.emptyDevice,
                  title: widget.emptyText ??
                      AppLocalizations.of(context)!.noDevices,
                  size: 168,
                )
              : widget.sortMode
                  ? ReorderableListView.builder(
                      physics: const BouncingScrollPhysics(),
                      buildDefaultDragHandles: false,
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
                      itemBuilder: (_, i) => ReorderableDragStartListener(
                        // key 必须挂在 itemBuilder 返回的顶层 widget 上（SDK 断言）
                        key: ValueKey(filtered[i]['sn'] ?? i),
                        index: i,
                        // 进入排序模式：错相位摇晃入场动画，
                        // 拖动/重排不重复触发（JiggleOnce 仅 active 变 true 时播放一次）
                        child: JiggleOnce(
                          active: widget.sortMode,
                          index: i,
                          child: DeviceCard(
                            device: filtered[i],
                            onLongPressDevice: widget.onLongPressDevice,
                            sortMode: widget.sortMode,
                          ),
                        ),
                      ),
                    )
                  : _buildNonSortList(paged, pageCount, safePage),
        ),
      ],
    );
  }
}
