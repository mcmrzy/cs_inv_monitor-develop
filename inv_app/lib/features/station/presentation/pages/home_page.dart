import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/realtime_data_service.dart';
import 'package:inv_app/core/services/network_status_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/core/widgets/offline_banner.dart';
import 'package:inv_app/core/services/data_cache_service.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchCtl = TextEditingController();
  StationSummaryLoaded? _cachedState;
  int _filterIndex = 0;
  bool _showSearch = false;
  // 电站拖动排序模式：由长按面板“电站排序”入口开启
  bool _stationSortMode = false;
  // 排序模式下的本地电站顺序（完成时提交后端）
  List<dynamic>? _sortStations;
  StreamSubscription<dynamic>? _statusSub;
  StreamSubscription<dynamic>? _alarmSub;

  List<String> get _filters {
    final l10n = AppLocalizations.of(context)!;
    return [l10n.all, l10n.normal, l10n.fault, l10n.offline];
  }

  static const _filterColors = [
    AppColors.primary,
    AppColors.successLight,
    AppColors.errorLight,
    AppColors.textHint,
  ];

  @override
  void initState() {
    super.initState();
    // Eagerly load cached data to avoid skeleton flash when offline
    _loadCachedDataIfAvailable();
    context.read<StationBloc>().add(StationSummaryRequested());
    final realtimeService = getIt<RealtimeDataService>();
    _statusSub = realtimeService.statusStream.listen((_) {
      if (mounted) {
        context.read<StationBloc>().add(StationSummaryRequested());
      }
    });
    _alarmSub = realtimeService.alarmStream.listen((_) {
      if (mounted) {
        context.read<StationBloc>().add(StationSummaryRequested());
      }
    });
  }

  void _loadCachedDataIfAvailable() {
    try {
      final dataCacheService = getIt<DataCacheService>();
      final cached = dataCacheService.load(DataCacheService.stationSummary);
      if (cached != null && cached is Map<String, dynamic>) {
        final stations = (cached['stations'] as List?) ?? [];
        final summary = (cached['summary'] as Map<String, dynamic>?) ?? {};
        if (stations.isNotEmpty) {
          _cachedState = StationSummaryLoaded(
            stations: stations,
            summary: summary,
            // 缓存仅用于快速渲染避免骨架屏闪烁；只有当前已知离线时才
            // 提示“无网络，显示缓存数据”，网络正常时等实时数据返回后自然覆盖
            isFromCache: getIt<NetworkStatusService>().isOffline,
          );
        }
      }
    } catch (_) {
      // Cache service not available, ignore
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _alarmSub?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  List<dynamic> _filterStations(List<dynamic> stations) {
    final q = _searchCtl.text.trim().toLowerCase();
    var list = stations;
    if (q.isNotEmpty) {
      list = list
          .where(
            (s) => (s['station_name'] ?? s['name'] ?? '')
                .toString()
                .toLowerCase()
                .contains(q),
          )
          .toList();
    }
    switch (_filterIndex) {
      case 1:
        list = list
            .where(
              (s) =>
                  (s['status'] ?? 1) == 1 &&
                  (s['fault_count'] ?? 0) == 0 &&
                  (s['online_count'] ?? 0) > 0,
            )
            .toList();
      case 2:
        list = list.where((s) => (s['fault_count'] ?? 0) > 0).toList();
      case 3:
        list = list
            .where(
              (s) => (s['status'] ?? 1) != 1 || (s['online_count'] ?? 0) == 0,
            )
            .toList();
    }
    return list;
  }

  // 进入电站排序模式：清空过滤/搜索，基于全量列表拖动
  void _enterStationSortMode() {
    final ds = _cachedState;
    if (ds == null) return;
    setState(() {
      _stationSortMode = true;
      _filterIndex = 0;
      _showSearch = false;
      _searchCtl.clear();
      _sortStations = List.of(ds.stations);
    });
  }

  // 完成排序：提交电站 ID 顺序并退出排序模式
  void _finishStationSortMode() {
    final order = (_sortStations ?? [])
        .map((s) => ((s['station_id'] ?? s['id'] ?? 0) as num).toInt())
        .toList();
    setState(() {
      _stationSortMode = false;
      _sortStations = null;
    });
    if (order.isNotEmpty) {
      context
          .read<StationBloc>()
          .add(StationReorderRequested(stationOrder: order));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: BlocConsumer<StationBloc, StationState>(
        listener: (context, state) {
          if (state is StationReorderSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text(AppLocalizations.of(context)!.stationOrderSaved),
              ),
            );
            context.read<StationBloc>().add(StationSummaryRequested());
          }
        },
        builder: (context, state) {
          final l10n = AppLocalizations.of(context)!;
          if (state is StationSummaryLoaded) _cachedState = state;
          final ds = _cachedState;

          if (ds == null) {
            if (state is StationError) return _buildError(state.message);
            return const SkeletonHomePage();
          }

          if (state is StationError && ds.stations.isEmpty) {
            return _buildError(state.message);
          }

          final filtered = _filterStations(ds.stations);
          final isFromCache = ds.isFromCache;

          return Column(
            children: [
              const OfflineBanner(),
              Expanded(
                child: StyledRefreshIndicator(
                  onRefresh: () async => context
                      .read<StationBloc>()
                      .add(StationSummaryRequested()),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (isFromCache)
                        SliverToBoxAdapter(
                          child: SafeArea(
                            bottom: false,
                            child: OfflineDataBanner(
                              onRetry: () => context
                                  .read<StationBloc>()
                                  .add(StationSummaryRequested()),
                            ),
                          ),
                        ),
                      _buildHeader(),
                      if (_showSearch) _buildSearchBar(),
                      _buildFilterCards(ds),
                      // 排序模式：提示 + 完成横条；否则电站数量行
                      if (_stationSortMode)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding:
                                EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 8.h),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.swap_vert_rounded,
                                  size: 13.sp,
                                  color: AppColors.textHint,
                                ),
                                SizedBox(width: 4.w),
                                Expanded(
                                  child: Text(
                                    l10n.sortModeHint,
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      color: AppColors.textHint,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _finishStationSortMode,
                                  child: Text(
                                    l10n.finishSorting,
                                    style: TextStyle(
                                      fontSize: 13.sp,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverToBoxAdapter(
                          child: Padding(
                            padding:
                                EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 8.h),
                            child: Row(
                              children: [
                                Text(
                                  l10n.str(
                                    'station_count',
                                    {'count': '${filtered.length}'},
                                  ),
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const Spacer(),
                                if (_filterIndex > 0)
                                  GestureDetector(
                                    onTap: () =>
                                        setState(() => _filterIndex = 0),
                                    child: Text(
                                      l10n.clearFilter,
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      if (_stationSortMode)
                        // 排序模式：长按拖动电站卡片（浮起效果与设备一致）
                        SliverPadding(
                          padding: EdgeInsets.symmetric(horizontal: 16.w),
                          sliver: SliverToBoxAdapter(
                            child: ReorderableListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
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
                                      color: AppColor.surfaceContainer(
                                          context),
                                      elevation: 6 * curved.value,
                                      borderRadius:
                                          BorderRadius.circular(16.r),
                                      shadowColor: AppColors.primary
                                          .withValues(alpha: 0.4),
                                      child: child,
                                    ),
                                  ),
                                );
                              },
                              onReorder: (oldIndex, newIndex) {
                                setState(() {
                                  if (newIndex > oldIndex) newIndex -= 1;
                                  final item =
                                      _sortStations!.removeAt(oldIndex);
                                  _sortStations!.insert(newIndex, item);
                                });
                              },
                              itemCount: _sortStations?.length ?? 0,
                              itemBuilder: (_, i) {
                                final s = _sortStations![i];
                                final id =
                                    s['station_id'] ?? s['id'] ?? i;
                                return Container(
                                  key: ValueKey(id),
                                  child: _buildCard(s, sortMode: true),
                                );
                              },
                            ),
                          ),
                        )
                      else if (filtered.isEmpty)
                        SliverToBoxAdapter(child: _buildEmpty())
                      else
                        SliverPadding(
                          padding: EdgeInsets.symmetric(horizontal: 16.w),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => _buildCard(filtered[i]),
                              childCount: filtered.length,
                            ),
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  SliverToBoxAdapter _buildHeader() {
    final l10n = AppLocalizations.of(context)!;
    return SliverToBoxAdapter(
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 12.h,
          left: 20.w,
          right: 20.w,
          bottom: 8.h,
        ),
        color: AppColor.surfaceContainer(context),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.brandName,
                  style: TextStyle(
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  l10n.pvInverterMonitor,
                  style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
                ),
              ],
            ),
            Row(
              children: [
                _hdrBtn(Icons.search_rounded, () {
                  setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) _searchCtl.clear();
                  });
                }),
                SizedBox(width: 10.w),
                _AnimatedHdrBtn(
                  icon: Icons.add_rounded,
                  onTap: () => _showAddMenu(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddMenuSheet(
        onNavigate: (path) {
          Navigator.pop(ctx);
          context.push(path);
        },
      ),
    );
  }

  Widget _hdrBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38.w,
        height: 38.w,
        decoration: BoxDecoration(
          color: AppColors.surfaceHover,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Icon(icon, size: 20.sp, color: AppColors.textSecondary),
      ),
    );
  }

  SliverToBoxAdapter _buildSearchBar() {
    final l10n = AppLocalizations.of(context)!;
    return SliverToBoxAdapter(
      child: Container(
        color: AppColor.surfaceContainer(context),
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
        child: TextField(
          controller: _searchCtl,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          cursorColor: AppColors.primary,
          style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: l10n.searchStation,
            hintStyle: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 20,
              color: AppColors.textHint,
            ),
            suffixIcon: _searchCtl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.textHint,
                    ),
                    onPressed: () {
                      _searchCtl.clear();
                      setState(() {});
                    },
                  )
                : null,
            filled: true,
            fillColor: AppColors.surfaceHover,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: const BorderSide(color: AppColors.primary, width: 1),
            ),
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildFilterCards(dynamic state) {
    final stations = state.stations as List<dynamic>;
    final totalCount = stations.length;
    final normalCount = stations
        .where(
          (s) =>
              (s['status'] ?? 1) == 1 &&
              (s['fault_count'] ?? 0) == 0 &&
              (s['online_count'] ?? 0) > 0,
        )
        .length;
    final faultCount =
        stations.where((s) => (s['fault_count'] ?? 0) > 0).length;
    final offlineCount = stations
        .where((s) => (s['status'] ?? 1) != 1 || (s['online_count'] ?? 0) == 0)
        .length;

    final values = [totalCount, normalCount, faultCount, offlineCount];

    return SliverToBoxAdapter(
      child: Container(
        color: AppColor.surfaceContainer(context),
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
        child: Row(
          children: List.generate(4, (i) {
            final active = _filterIndex == i;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 3.w),
                child: GestureDetector(
                  onTap: () => setState(() => _filterIndex = active ? 0 : i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.symmetric(vertical: 10.h),
                    decoration: BoxDecoration(
                      color: active
                          ? _filterColors[i].withValues(alpha: 0.1)
                          : AppColors.surfaceHover,
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(
                        color: active
                            ? _filterColors[i].withValues(alpha: 0.4)
                            : AppColors.divider,
                        width: active ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${values[i]}',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w800,
                            color: _filterColors[i],
                            height: 1.1,
                          ),
                        ),
                        SizedBox(height: 3.h),
                        Text(
                          _filters[i],
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                            color:
                                active ? _filterColors[i] : AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildCard(dynamic station, {bool sortMode = false}) {
    final l10n = AppLocalizations.of(context)!;
    final name = station['station_name'] ?? station['name'] ?? '';
    final id = station['station_id'] ?? station['id'] ?? 0;
    final faultCount = station['fault_count'] ?? 0;
    final todayEnergy = (station['today_energy'] ?? 0).toDouble();
    final totalEnergy = (station['total_energy'] ?? 0).toDouble();
    final status = station['status'] ?? 1;
    final onlineCount = station['online_count'] ?? 0;

    final ok = status == 1 && faultCount == 0 && onlineCount > 0;
    final hasFault = faultCount > 0;
    final province = station['province'] ?? '';
    final city = station['city'] ?? '';
    final district = station['district'] ?? '';
    final addressParts = <String>[];
    if (province is String && province.isNotEmpty) addressParts.add(province);
    if (city is String && city.isNotEmpty) addressParts.add(city);
    if (district is String && district.isNotEmpty) addressParts.add(district);
    final addressText = '${l10n.china} ${addressParts.join(' ')}';

    final badgeColor = ok
        ? AppColors.badgeNormalText
        : (hasFault ? AppColors.badgeAlarmText : AppColors.badgeOfflineText);
    final badgeBg = ok
        ? AppColors.badgeNormalBg
        : (hasFault ? AppColors.badgeAlarmBg : AppColors.badgeOfflineBg);
    final badgeText = ok ? l10n.normal : (hasFault ? l10n.fault : l10n.offline);

    return _StationCard(
      name: name,
      id: id,
      faultCount: faultCount,
      todayEnergy: todayEnergy,
      totalEnergy: totalEnergy,
      addressText: addressText,
      badgeText: badgeText,
      badgeColor: badgeColor,
      badgeBg: badgeBg,
      onTap: sortMode ? () {} : () => context.push('/station/$id'),
      onLongPress:
          sortMode ? () {} : () => _showStationMenu(context, station),
    );
  }

  void _showStationMenu(BuildContext context, dynamic station) {
    final l10n = AppLocalizations.of(context)!;
    final id = station['station_id'] ?? station['id'] ?? 0;
    final name = station['station_name'] ?? station['name'] ?? '';
    final province = station['province'] ?? '';
    final city = station['city'] ?? '';
    final district = station['district'] ?? '';
    final addressParts = <String>[];
    if (province is String && province.isNotEmpty) addressParts.add(province);
    if (city is String && city.isNotEmpty) addressParts.add(city);
    if (district is String && district.isNotEmpty) addressParts.add(district);
    final addressText = '${l10n.china} ${addressParts.join(' ')}';

    showModalBottomSheet(
      context: context,
      builder: (ctx) => _StationActionSheet(
        name: name,
        addressText: addressText,
        onEdit: () {
          Navigator.pop(ctx);
          context.push('/station/$id/edit');
        },
        onAddDevice: () {
          Navigator.pop(ctx);
          context.push('/add-device?station_id=$id');
        },
        onSort: () {
          Navigator.pop(ctx);
          _enterStationSortMode();
        },
      ),
    );
  }

  Widget _buildEmpty() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 60.h),
      child: Column(
        children: [
          Container(
            width: 80.w,
            height: 80.w,
            decoration: BoxDecoration(
              color: AppColors.surfaceHover,
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Icon(
              Icons.add_home_work_outlined,
              size: 36.sp,
              color: AppColors.textHint,
            ),
          ),
          SizedBox(height: 18.h),
          Text(
            l10n.noStations,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            l10n.tapPlusToCreate,
            style: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String msg) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 44.sp,
              color: AppColors.textHint,
            ),
            SizedBox(height: 14.h),
            Text(
              l10n.translateError(msg),
              style: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16.h),
            OutlinedButton(
              onPressed: () =>
                  context.read<StationBloc>().add(StationSummaryRequested()),
              style:
                  OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedHdrBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _AnimatedHdrBtn({required this.icon, required this.onTap});

  @override
  State<_AnimatedHdrBtn> createState() => _AnimatedHdrBtnState();
}

class _AnimatedHdrBtnState extends State<_AnimatedHdrBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _ctl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctl.forward(),
      onTapUp: (_) {
        _ctl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 38.w,
          height: 38.w,
          decoration: BoxDecoration(
            color: AppColors.surfaceHover,
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Icon(widget.icon, size: 20.sp, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

// 长按电站卡片弹出的操作菜单：电站信息头 + 操作项（带逐项入场动画）
class _StationActionSheet extends StatefulWidget {
  final String name;
  final String addressText;
  final VoidCallback onEdit;
  final VoidCallback onAddDevice;
  final VoidCallback onSort;

  const _StationActionSheet({
    required this.name,
    required this.addressText,
    required this.onEdit,
    required this.onAddDevice,
    required this.onSort,
  });

  @override
  State<_StationActionSheet> createState() => _StationActionSheetState();
}

class _StationActionSheetState extends State<_StationActionSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  // 逐项入场动画（淡入 + 上移），间隔 0.15
  Widget _animatedItem(int i, Widget child) {
    final start = i * 0.15;
    final end = (start + 0.7).clamp(0.0, 1.0);
    final animation = CurvedAnimation(
      parent: _ctl,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.2),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
          child: Row(
            children: [
              Container(
                width: 44.w,
                height: 44.w,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(icon, color: color, size: 22.sp),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14.sp,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 电站信息头
              Row(
                children: [
                  Container(
                    width: 48.w,
                    height: 48.w,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14.r),
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.08),
                          AppColors.primary.withValues(alpha: 0.18),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(
                      Icons.solar_power,
                      size: 24.sp,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          widget.addressText,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColors.textHint,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),
              const Divider(height: 1, color: AppColors.divider),
              SizedBox(height: 6.h),
              _animatedItem(
                0,
                _buildActionItem(
                  icon: Icons.edit_outlined,
                  color: AppColors.primary,
                  title: l10n.editStation,
                  subtitle: l10n.editStationHint,
                  onTap: widget.onEdit,
                ),
              ),
              _animatedItem(
                1,
                _buildActionItem(
                  icon: Icons.add_circle_outline,
                  color: AppColors.successLight,
                  title: l10n.addDevice,
                  subtitle: l10n.scanOrManualAdd,
                  onTap: widget.onAddDevice,
                ),
              ),
              _animatedItem(
                2,
                _buildActionItem(
                  icon: Icons.swap_vert_rounded,
                  color: AppColors.primary,
                  title: l10n.sortStations,
                  subtitle: l10n.sortModeHint,
                  onTap: widget.onSort,
                ),
              ),
              SizedBox(height: 14.h),
              _animatedItem(
                3,
                Material(
                  color: AppColor.surfaceHover(context),
                  borderRadius: BorderRadius.circular(14.r),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14.r),
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 48.h,
                      alignment: Alignment.center,
                      child: Text(
                        l10n.cancel,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StationCard extends StatefulWidget {
  final String name;
  final int id;
  final int faultCount;
  final double todayEnergy;
  final double totalEnergy;
  final String addressText;
  final String badgeText;
  final Color badgeColor;
  final Color badgeBg;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _StationCard({
    required this.name,
    required this.id,
    required this.faultCount,
    required this.todayEnergy,
    required this.totalEnergy,
    required this.addressText,
    required this.badgeText,
    required this.badgeColor,
    required this.badgeBg,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_StationCard> createState() => _StationCardState();
}

class _StationCardState extends State<_StationCard>
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 14.h),
      child: GestureDetector(
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) {
          _controller.reverse();
          widget.onTap();
        },
        onTapCancel: () => _controller.reverse(),
        onLongPress: widget.onLongPress,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Hero(
            tag: 'station_${widget.id}',
            child: Material(
              color: AppColor.surfaceContainer(context),
              borderRadius: BorderRadius.circular(16.r),
              // 注意：不使用 InkWell（空 onTap 会赢得手势竞技场，
              // 导致外层 GestureDetector 的 onTapUp 被取消、点击跳转失效）
              child: _buildCardContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardContent() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72.w,
            height: 72.w,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14.r),
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.08),
                  AppColors.primary.withValues(alpha: 0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Image.asset(
              'assets/images/solar_panel.png',
              width: 56.w,
              height: 56.w,
              fit: BoxFit.contain,
            ),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.name,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8.w,
                        vertical: 3.h,
                      ),
                      decoration: BoxDecoration(
                        color: widget.badgeBg,
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Text(
                        widget.badgeText,
                        style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600,
                          color: widget.badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4.h),
                Text(
                  widget.addressText,
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: AppColors.textHint,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 10.h),
                Row(
                  children: [
                    Expanded(
                      child: _energyItem(
                        widget.todayEnergy.toStringAsFixed(1),
                        'kWh',
                        l10n.todayGeneration,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: _energyItem(
                        widget.totalEnergy.toStringAsFixed(0),
                        'kWh',
                        l10n.totalGeneration,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _energyItem(String value, String unit, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.1,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          label,
          style: TextStyle(fontSize: 10.sp, color: AppColors.textHint),
        ),
      ],
    );
  }
}

class _AddMenuSheet extends StatefulWidget {
  final void Function(String path) onNavigate;

  const _AddMenuSheet({required this.onNavigate});

  @override
  State<_AddMenuSheet> createState() => _AddMenuSheetState();
}

class _AddMenuSheetState extends State<_AddMenuSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  List<_MenuItemData> get _items {
    final l10n = AppLocalizations.of(context)!;
    return [
      _MenuItemData(
        icon: Icons.add_home_work_outlined,
        color: AppColors.primary,
        title: l10n.createStation,
        subtitle: l10n.addNewPvStation,
        path: '/station/create',
      ),
      _MenuItemData(
        icon: Icons.solar_power,
        color: AppColors.successLight,
        title: l10n.addDevice,
        subtitle: l10n.scanOrManualAdd,
        path: '/add-device',
      ),
      _MenuItemData(
        icon: Icons.wifi,
        color: AppColors.purple,
        title: l10n.wifiConfig,
        subtitle: l10n.configWifiForDevice,
        path: '/wifi-config',
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..forward();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 分组卡片：浅色圆角容器 + 白色圆角菜单项
              Container(
                decoration: BoxDecoration(
                  color: AppColor.surfaceHover(context),
                  borderRadius: BorderRadius.circular(16.r),
                ),
                padding: EdgeInsets.all(8.w),
                child: Column(
                  children: List.generate(_items.length, (i) {
                    final item = _items[i];
                    final start = i * 0.15;
                    final end = (start + 0.6).clamp(0.0, 1.0);
                    final animation = CurvedAnimation(
                      parent: _ctl,
                      curve: Interval(start, end, curve: Curves.easeOutCubic),
                    );
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: i < _items.length - 1 ? 8.h : 0,
                      ),
                      child: FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.3),
                            end: Offset.zero,
                          ).animate(animation),
                          child: _buildItem(item),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(_MenuItemData item) {
    return Material(
      color: AppColor.surfaceContainer(context),
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: () => widget.onNavigate(item.path),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
          child: Row(
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(item.icon, color: item.color, size: 20.sp),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColor.textPrimary(context),
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14.sp,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItemData {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String path;

  const _MenuItemData({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.path,
  });
}
