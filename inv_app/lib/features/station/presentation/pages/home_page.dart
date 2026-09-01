import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/realtime_data_service.dart';
import 'package:inv_app/core/services/network_status_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/widget_update_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/widgets/jiggle_once.dart';
import 'package:inv_app/core/widgets/pagination_bar.dart';
import 'package:inv_app/core/widgets/pressable_gesture_detector.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/features/station/presentation/models/station_list_presentation.dart';
import 'package:inv_app/features/onboarding/data/setup_guide_storage.dart';
import 'package:inv_app/core/services/data_cache_service.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
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
  // 电站列表分页页码（1-based）；搜索/筛选切换时重置为 1
  int _stationPage = 1;
  // 电站拖动排序模式：由长按面板“电站排序”入口开启
  bool _stationSortMode = false;
  // 电站列表滚动控制器：翻页后跳回列表顶部
  final ScrollController _stationListController = ScrollController();
  // 排序模式下的本地电站顺序（完成时提交后端）
  List<dynamic>? _sortStations;
  StreamSubscription<dynamic>? _statusSub;
  StreamSubscription<dynamic>? _alarmSub;

  /// 首启向导：本会话只提示一次，避免反复弹出
  bool _setupGuidePrompted = false;
  final _setupGuideStorage = SetupGuideStorage();

  List<String> get _filters {
    final l10n = AppLocalizations.of(context)!;
    return [l10n.all, l10n.normal, l10n.fault, l10n.offline];
  }

  // 改为实例 getter：textHint 需 context 语义取色（支持暗色模式），
  // static 字段无法访问 context
  List<Color> get _filterColors => [
    AppColors.primary,
    AppColors.successLight,
    AppColors.errorLight,
    AppColor.textHint(context),
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

  /// 将电站聚合数据推送到桌面小组件（统计 + 能量流）
  ///
  /// 后端 summary 为 camelCase 聚合字段（兼容 snake_case），
  /// 数值统一格式化两位小数，避免超长小数撑破小组件布局。
  void _pushStationWidgets(StationSummaryLoaded state) {
    final s = state.summary;

    String fmt(dynamic v) {
      final d = (v is num) ? v.toDouble() : (double.tryParse('$v') ?? 0);
      return d.toStringAsFixed(2);
    }

    // 统计小组件：累计发电 / 今日收益 / 设备在线
    unawaited(
      WidgetUpdateService.updateStatsWidget(
        totalKwh: fmt(s['totalGeneration'] ?? s['total_energy']),
        todayIncome: fmt(s['totalIncome'] ?? s['total_income']),
        deviceOnline: '${s['onlineDevices'] ?? s['online_count'] ?? 0}',
        deviceTotal: '${s['totalDevices'] ?? s['device_count'] ?? 0}',
      ),
    );

    // 能量流小组件：今日发电 / 当前功率 / 本月发电
    unawaited(
      WidgetUpdateService.updateEnergyFlowWidget(
        todayKwh: fmt(s['todayGeneration'] ?? s['today_energy']),
        currentPower: fmt(s['total_power']),
        monthKwh: fmt(s['monthGeneration'] ?? s['month_energy']),
      ),
    );

    // 电站概览小组件：今日发电 / 设备在线 / 当前功率（数据与统计/能量流同源）
    unawaited(
      WidgetUpdateService.updateStationWidget(
        todayKwh: fmt(s['todayGeneration'] ?? s['today_energy']),
        deviceOnline: '${s['onlineDevices'] ?? s['online_count'] ?? 0}',
        deviceTotal: '${s['totalDevices'] ?? s['device_count'] ?? 0}',
        currentPower: fmt(s['total_power']),
      ),
    );
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _alarmSub?.cancel();
    _searchCtl.dispose();
    _stationListController.dispose();
    super.dispose();
  }

  List<dynamic> _filterStations(List<dynamic> stations) {
    return StationListPresentation.filter(
      stations,
      query: _searchCtl.text,
      filterIndex: _filterIndex,
    );
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
      _stationPage = 1;
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
            AppToast.show(context, AppLocalizations.of(context)!.stationOrderSaved, type: ToastType.success);
            context.read<StationBloc>().add(StationSummaryRequested());
          }
          // 统计刷新：将聚合数据推送到桌面小组件（统计 + 能量流）
          if (state is StationSummaryLoaded && !state.isFromCache) {
            _pushStationWidgets(state);
          }
          // 首启向导：登录后无电站且未完成过向导时弹出
          if (state is StationSummaryLoaded &&
              state.stations.isEmpty &&
              !_setupGuidePrompted) {
            _setupGuidePrompted = true;
            unawaited(_maybeShowSetupGuide());
          }
        },
        builder: (context, state) {
          final l10n = AppLocalizations.of(context)!;
          if (state is StationSummaryLoaded) _cachedState = state;
          final ds = _cachedState;

          if (ds == null) {
            if (state is StationError && state is! StationActionError) {
              return _buildOfflineFallback();
            }
            return const SkeletonHomePage();
          }

          if (state is StationError &&
              state is! StationActionError &&
              ds.stations.isEmpty) {
            return _buildOfflineFallback();
          }

          final filtered = _filterStations(ds.stations);
          // 分页：每页 10 条；不足一页时整页展示（分页栏仅在多页时渲染）
          final stationPageCount = filtered.isEmpty
              ? 1
              : (filtered.length / 10).ceil();
          final safeStationPage = _stationPage.clamp(1, stationPageCount);
          final stationPageEnd = safeStationPage * 10 < filtered.length
              ? safeStationPage * 10
              : filtered.length;
          final pagedStations = stationPageCount <= 1
              ? filtered
              : filtered.sublist(
                  (safeStationPage - 1) * 10,
                  stationPageEnd,
                );
          final isFromCache = ds.isFromCache;

          return Column(
            children: [
              Expanded(
                child: StyledRefreshIndicator(
                  onRefresh: () async => context
                      .read<StationBloc>()
                      .add(StationSummaryRequested()),
                  child: CustomScrollView(
                    controller: _stationListController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      _buildHeader(),
                      if (_showSearch) _buildSearchBar(),
                      _buildFilterCards(ds),
                      // 离线提示（统一横幅）：电站筛选下方、「还有 x 个电站」上方
                      SliverToBoxAdapter(
                        child: _HomeOfflineNotice(
                          fromCache: isFromCache,
                          onRetry: () => context
                              .read<StationBloc>()
                              .add(StationSummaryRequested()),
                        ),
                      ),
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
                                  color: AppColor.textHint(context),
                                ),
                                SizedBox(width: 4.w),
                                Expanded(
                                  child: Text(
                                    l10n.sortModeHint,
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      color: AppColor.textHint(context),
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
                                    color: AppColor.textSecondary(context),
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
                        // 排序模式：直接拖动电站卡片（关闭长按起拖，按下即拖）
                        SliverPadding(
                          padding: EdgeInsets.symmetric(horizontal: 16.w),
                          sliver: SliverToBoxAdapter(
                            child: ReorderableListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              buildDefaultDragHandles: false,
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
                                        context,
                                      ),
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
                              onReorderItem: (oldIndex, newIndex) {
                                // onReorderItem 的 newIndex 已自动排除移动项，无需手动 -1
                                setState(() {
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
                                return ReorderableDragStartListener(
                                  // key 必须挂在 itemBuilder 返回的顶层 widget 上（SDK 断言）
                                  key: ValueKey(id),
                                  index: i,
                                  // 进入排序模式：错相位摇晃入场动画，
                                  // 拖动/重排不重复触发（JiggleOnce 仅 active 变 true 时播放一次）
                                  child: JiggleOnce(
                                    active: _stationSortMode,
                                    index: i,
                                    child: Container(
                                      child: _buildCard(s, sortMode: true),
                                    ),
                                  ),
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
                              (_, i) => _buildCard(pagedStations[i]),
                              childCount: pagedStations.length,
                            ),
                          ),
                        ),
                      // 超过一页才显示分页栏
                      if (stationPageCount > 1)
                        SliverToBoxAdapter(
                          child: PaginationBar(
                            currentPage: safeStationPage,
                            totalPages: stationPageCount,
                            onPageChanged: (p) {
                              setState(() => _stationPage = p);
                              // 翻页后跳回列表顶部，避免停留在上一页滚动位置
                              if (_stationListController.hasClients) {
                                _stationListController.jumpTo(0);
                              }
                            },
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
                    color: AppColor.textPrimary(context),
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  l10n.pvInverterMonitor,
                  style: TextStyle(fontSize: 11.sp, color: AppColor.textHint(context)),
                ),
              ],
            ),
            Row(
              children: [
                _hdrBtn(Icons.search_rounded, () {
                  setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) _searchCtl.clear();
                    _stationPage = 1;
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
          color: AppColor.surfaceHover(context),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Icon(icon, size: 20.sp, color: AppColor.textSecondary(context)),
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
          onChanged: (_) => setState(() => _stationPage = 1),
          cursorColor: AppColors.primary,
          style: TextStyle(fontSize: 14.sp, color: AppColor.textPrimary(context)),
          decoration: InputDecoration(
            hintText: l10n.searchStation,
            hintStyle: TextStyle(fontSize: 14.sp, color: AppColor.textHint(context)),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 20,
              color: AppColor.textHint(context),
            ),
            suffixIcon: _searchCtl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColor.textHint(context),
                    ),
                    onPressed: () {
                      _searchCtl.clear();
                      setState(() => _stationPage = 1);
                    },
                  )
                : null,
            filled: true,
            fillColor: AppColor.surfaceHover(context),
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
    final values = StationListPresentation.counts(stations).asList;

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
                  onTap: () => setState(() {
                    _filterIndex = active ? 0 : i;
                    _stationPage = 1;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.symmetric(vertical: 10.h),
                    decoration: BoxDecoration(
                      color: active
                          ? _filterColors[i].withValues(alpha: 0.1)
                          : AppColor.surfaceHover(context),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(
                        color: active
                            ? _filterColors[i].withValues(alpha: 0.4)
                            : AppColor.divider(context),
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
                                active ? _filterColors[i] : AppColor.textHint(context),
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
    final ok = StationListPresentation.isNormal(station);
    final hasFault = StationListPresentation.hasFault(station);
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
      isScrollControlled: true,
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
        onManageDevices: () {
          Navigator.pop(ctx);
          // 直达电站详情页设备管理 Tab
          context.push('/station/$id?tab=devices');
        },
      ),
    );
  }

  /// 首启向导触发：未完成过才弹出（跳过/完成后不再打扰）
  Future<void> _maybeShowSetupGuide() async {
    final done = await _setupGuideStorage.isDone();
    if (done || !mounted) return;
    context.push('/setup-guide');
  }

  Widget _buildEmpty() {
    final l10n = AppLocalizations.of(context)!;
    // 小烁展示光伏模型插画：无电站引导态（美术路由 C2/empty-stations）
    return XiaoshuoStatePanel(
      asset: CsergyAssets.xiaoshuoStation,
      title: l10n.noStations,
      message: l10n.tapPlusToCreate,
      size: 180,
      padding: EdgeInsets.symmetric(vertical: 48.h),
    );
  }

  /// 无可用数据（无缓存且请求失败）时的离线兜底：仍渲染完整页面框架，
  /// 数据区展示空态引导 + 离线横幅提示，避免整页“网络加载失败”错误页
  Widget _buildOfflineFallback() {
    final empty = const StationSummaryLoaded(
      stations: [],
      summary: {},
      isFromCache: true,
    );
    return Column(
      children: [
        Expanded(
          child: StyledRefreshIndicator(
            onRefresh: () async => context
                .read<StationBloc>()
                .add(StationSummaryRequested()),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                _buildHeader(),
                _buildFilterCards(empty),
                // 离线提示（统一横幅）：筛选下方、空态引导上方
                SliverToBoxAdapter(
                  child: _HomeOfflineNotice(
                    fromCache: true,
                    onRetry: () => context
                        .read<StationBloc>()
                        .add(StationSummaryRequested()),
                  ),
                ),
                SliverToBoxAdapter(child: _buildEmpty()),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 首页统一离线提示横幅
///
/// 替代原来互相冲突的两个横幅（顶部 OfflineBanner「无网络连接」与
/// 缓存数据 OfflineDataBanner）：网络断开或数据来自本地缓存时显示，
/// 位置在电站筛选与「还有 x 个电站」行之间，合并断网提示、缓存数据
/// 说明与重试入口为一张卡片。
class _HomeOfflineNotice extends StatefulWidget {
  /// 当前数据是否来自本地缓存
  final bool fromCache;

  /// 重试（重新请求电站汇总数据）
  final VoidCallback onRetry;

  const _HomeOfflineNotice({required this.fromCache, required this.onRetry});

  @override
  State<_HomeOfflineNotice> createState() => _HomeOfflineNoticeState();
}

class _HomeOfflineNoticeState extends State<_HomeOfflineNotice> {
  late final NetworkStatusService _networkService;
  StreamSubscription<bool>? _statusSub;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _networkService = getIt<NetworkStatusService>();
    _offline = _networkService.isOffline;
    _statusSub = _networkService.statusStream.listen((isOnline) {
      if (mounted) {
        setState(() => _offline = !isOnline);
      }
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // guest 离网模式：不访问云端是预期行为，隐藏「加载失败/离线」横幅
    // （未登录请求必然 401 走缓存兜底，横幅会以「加载失败」常驻误导用户）
    if (getIt<ConnectionModeService>().isGuestLocalMode) {
      return const SizedBox.shrink();
    }
    // 网络正常且非缓存数据：无需提示
    if (!_offline && !widget.fromCache) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    // 断网：显示缓存数据 / 功能受限提示；联网但缓存兜底（请求失败）：加载失败
    final title = _offline ? l10n.offlineStatus : l10n.loadFailed;
    final subtitle = _offline
        ? (widget.fromCache ? l10n.noNetworkCached : l10n.offlineHint)
        : '';

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: AppColors.warningSoft,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColors.warningBorder, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(
              _offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
              size: 16.sp,
              color: AppColors.warningStrong,
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warningText,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    SizedBox(height: 2.h),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColors.warningText.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: 8.w),
            GestureDetector(
              onTap: widget.onRetry,
              child: Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(
                  l10n.retry,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warningText,
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
            color: AppColor.surfaceHover(context),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Icon(widget.icon, size: 20.sp, color: AppColor.textSecondary(context)),
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
  final VoidCallback onManageDevices;

  const _StationActionSheet({
    required this.name,
    required this.addressText,
    required this.onEdit,
    required this.onAddDevice,
    required this.onSort,
    required this.onManageDevices,
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
                  borderRadius: BorderRadius.circular(12.r),
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.08),
                      color.withValues(alpha: 0.18),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
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
                        color: AppColor.textPrimary(context),
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColor.textHint(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14.sp,
                color: AppColor.textHint(context),
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
        // 小屏/大字体下可滚动，避免取消按钮溢出（内容不超限时视觉不变）
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
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
                            color: AppColor.textPrimary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          widget.addressText,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColor.textHint(context),
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
              Divider(height: 1, color: AppColor.divider(context)),
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
              _animatedItem(
                3,
                _buildActionItem(
                  icon: Icons.link_off_rounded,
                  color: AppColors.error,
                  title: l10n.str('remove_device'),
                  subtitle: l10n.deviceManagement,
                  onTap: widget.onManageDevices,
                ),
              ),
              SizedBox(height: 14.h),
              _animatedItem(
                4,
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
                          color: AppColor.textSecondary(context),
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
      child: PressableGestureDetector(
        // 长按 300ms 达成（与设备/通知卡片手感一致，比默认 500ms 更灵敏）
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
              CsergyAssets.stationDefaultImage,
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
                          color: AppColor.textPrimary(context),
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
                    color: AppColor.textHint(context),
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
                    color: AppColor.textPrimary(context),
                    height: 1.1,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w500,
                    color: AppColor.textHint(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          label,
          style: TextStyle(fontSize: 10.sp, color: AppColor.textHint(context)),
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
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 平铺菜单项（无分组容器）
                  ...List.generate(_items.length, (i) {
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
                  SizedBox(height: 14.h),
                  // 取消按钮（对齐 DeviceActionSheet 取消按钮样式）
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
                            color: AppColor.textSecondary(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                width: 44.w,
                height: 44.w,
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
                        color: AppColor.textHint(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14.sp,
                color: AppColor.textHint(context),
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
