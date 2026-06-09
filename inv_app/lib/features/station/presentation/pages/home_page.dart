import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';

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

  static const _filters = ['全部', '正常', '告警', '离线'];
  static const _filterColors = [
    AppColors.primary,
    AppColors.successLight,
    AppColors.errorLight,
    AppColors.textHint,
  ];

  @override
  void initState() {
    super.initState();
    context.read<StationBloc>().add(StationSummaryRequested());
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  List<dynamic> _filterStations(List<dynamic> stations) {
    final q = _searchCtl.text.trim().toLowerCase();
    var list = stations;
    if (q.isNotEmpty) {
      list = list
          .where((s) =>
              (s['station_name'] ?? s['name'] ?? '')
                  .toString()
                  .toLowerCase()
                  .contains(q))
          .toList();
    }
    switch (_filterIndex) {
      case 1:
        list = list
            .where((s) =>
                (s['status'] ?? 1) == 1 &&
                (s['fault_count'] ?? 0) == 0 &&
                (s['online_count'] ?? 0) > 0)
            .toList();
      case 2:
        list = list.where((s) => (s['fault_count'] ?? 0) > 0).toList();
      case 3:
        list = list.where((s) => (s['status'] ?? 1) != 1 || (s['online_count'] ?? 0) == 0).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: BlocBuilder<StationBloc, StationState>(
        builder: (context, state) {
          if (state is StationSummaryLoaded) _cachedState = state;
          final ds = _cachedState;

          if (ds == null) {
            if (state is StationError) return _buildError(state.message);
            return Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary));
          }

          if (state is StationError && ds.stations.isEmpty) {
            return _buildError(state.message);
          }

          final filtered = _filterStations(ds.stations);

          return StyledRefreshIndicator(
            onRefresh: () async => context.read<StationBloc>().add(StationSummaryRequested()),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                _buildHeader(),
                if (_showSearch) _buildSearchBar(),
                _buildFilterCards(ds),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 8.h),
                    child: Row(
                      children: [
                        Text('${filtered.length} 个电站',
                            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                        const Spacer(),
                        if (_filterIndex > 0)
                          GestureDetector(
                            onTap: () => setState(() => _filterIndex = 0),
                            child: Text('清除筛选', style: TextStyle(fontSize: 12.sp, color: AppColors.primary)),
                          ),
                      ],
                    ),
                  ),
                ),
                if (filtered.isEmpty)
                  SliverToBoxAdapter(child: _buildEmpty())
                else
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                            (_, i) => _buildCard(filtered[i]),
                            childCount: filtered.length)),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          );
        },
      ),
    );
  }

  SliverToBoxAdapter _buildHeader() {
    return SliverToBoxAdapter(
      child: Container(
        padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 12.h,
            left: 20.w,
            right: 20.w,
            bottom: 8.h),
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('辰烁科技',
                    style: TextStyle(
                        fontSize: 22.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3)),
                SizedBox(height: 2.h),
                Text('光伏逆变器智能监控',
                    style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
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
      backgroundColor: Colors.transparent,
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
    return SliverToBoxAdapter(
      child: Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
        child: TextField(
          controller: _searchCtl,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          cursorColor: AppColors.primary,
          style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: '搜索电站名称',
            hintStyle: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
            prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.textHint),
            suffixIcon: _searchCtl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close_rounded, size: 18, color: AppColors.textHint),
                    onPressed: () {
                      _searchCtl.clear();
                      setState(() {});
                    })
                : null,
            filled: true,
            fillColor: AppColors.surfaceHover,
            contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: AppColors.primary, width: 1)),
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildFilterCards(dynamic state) {
    final stations = state.stations as List<dynamic>;
    final totalCount = stations.length;
    final normalCount = stations.where((s) => (s['status'] ?? 1) == 1 && (s['fault_count'] ?? 0) == 0 && (s['online_count'] ?? 0) > 0).length;
    final faultCount = stations.where((s) => (s['fault_count'] ?? 0) > 0).length;
    final offlineCount = stations.where((s) => (s['status'] ?? 1) != 1 || (s['online_count'] ?? 0) == 0).length;

    final values = [totalCount, normalCount, faultCount, offlineCount];

    return SliverToBoxAdapter(
      child: Container(
        color: Colors.white,
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
                        Text('${values[i]}',
                            style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w800,
                                color: _filterColors[i],
                                height: 1.1)),
                        SizedBox(height: 3.h),
                        Text(_filters[i],
                            style: TextStyle(
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w600,
                                color: active ? _filterColors[i] : AppColors.textHint)),
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

  Widget _buildCard(dynamic station) {
    final name = station['station_name'] ?? station['name'] ?? '';
    final id = station['station_id'] ?? station['id'] ?? 0;
    final faultCount = station['fault_count'] ?? 0;
    final todayEnergy = station['today_energy'] ?? 0;
    final totalEnergy = station['total_energy'] ?? 0;
    final status = station['status'] ?? 1;
    final deviceCount = station['device_count'] ?? 0;
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
    final addressText = '中国 ${addressParts.join(' ')}';

    final badgeColor = ok ? AppColors.badgeNormalText : (hasFault ? AppColors.badgeAlarmText : AppColors.badgeOfflineText);
    final badgeBg = ok ? AppColors.badgeNormalBg : (hasFault ? AppColors.badgeAlarmBg : AppColors.badgeOfflineBg);
    final badgeText = ok ? '正常' : (hasFault ? '告警' : '离线');

    return Padding(
      padding: EdgeInsets.only(bottom: 14.h),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(16.r),
          onTap: () => context.push('/station/$id'),
          child: Padding(
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
                  child: Icon(Icons.solar_power_rounded, size: 36.sp, color: AppColors.primary),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(name,
                                style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(6.r),
                            ),
                            child: Text(badgeText,
                                style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600, color: badgeColor)),
                          ),
                        ],
                      ),
                      SizedBox(height: 4.h),
                      Text(addressText,
                          style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      SizedBox(height: 10.h),
                      Row(
                        children: [
                          _energyItem(todayEnergy.toStringAsFixed(1), 'kWh', '今日发电'),
                          SizedBox(width: 24.w),
                          _energyItem(totalEnergy.toStringAsFixed(0), 'kWh', '累计发电'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _energyItem(String value, String unit, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.1),
              ),
              TextSpan(
                text: ' $unit',
                style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textHint),
              ),
            ],
          ),
        ),
        SizedBox(height: 2.h),
        Text(label, style: TextStyle(fontSize: 10.sp, color: AppColors.textHint)),
      ],
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 60.h),
      child: Column(
        children: [
          Container(
            width: 80.w,
            height: 80.w,
            decoration: BoxDecoration(
                color: AppColors.surfaceHover,
                borderRadius: BorderRadius.circular(20.r)),
            child: Icon(Icons.add_home_work_outlined, size: 36.sp, color: AppColors.textHint),
          ),
          SizedBox(height: 18.h),
          Text('还没有电站',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          SizedBox(height: 6.h),
          Text('点击右上角 + 创建',
              style: TextStyle(fontSize: 13.sp, color: AppColors.textHint)),
        ],
      ),
    );
  }

  Widget _buildError(String msg) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 44.sp, color: AppColors.textHint),
            SizedBox(height: 14.h),
            Text(msg,
                style: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
                textAlign: TextAlign.center),
            SizedBox(height: 16.h),
            OutlinedButton(
                onPressed: () => context.read<StationBloc>().add(StationSummaryRequested()),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
                child: const Text('重试')),
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

class _AddMenuSheet extends StatefulWidget {
  final void Function(String path) onNavigate;

  const _AddMenuSheet({required this.onNavigate});

  @override
  State<_AddMenuSheet> createState() => _AddMenuSheetState();
}

class _AddMenuSheetState extends State<_AddMenuSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  static const _items = [
    _MenuItemData(
      icon: Icons.add_home_work_outlined,
      color: AppColors.primary,
      title: '创建电站',
      subtitle: '添加新的光伏电站',
      path: '/station/create',
    ),
    _MenuItemData(
      icon: Icons.solar_power,
      color: AppColors.successLight,
      title: '添加设备',
      subtitle: '扫码或手动添加逆变器设备',
      path: '/add-device',
    ),
    _MenuItemData(
      icon: Icons.wifi,
      color: Color(0xFF8B5CF6),
      title: '设备配网',
      subtitle: '为逆变器设备配置WiFi网络',
      path: '/wifi-config',
    ),
  ];

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
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              SizedBox(height: 20.h),
              ...List.generate(_items.length, (i) {
                final item = _items[i];
                final start = i * 0.15;
                final end = (start + 0.6).clamp(0.0, 1.0);
                final animation = CurvedAnimation(
                  parent: _ctl,
                  curve: Interval(start, end, curve: Curves.easeOutCubic),
                );
                return Padding(
                  padding: EdgeInsets.only(bottom: 8.h),
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
              SizedBox(height: 12.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(_MenuItemData item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: () => widget.onNavigate(item.path),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 4.w),
          child: Row(
            children: [
              Container(
                width: 44.w,
                height: 44.w,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(item.icon, color: item.color),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        style: TextStyle(
                            fontSize: 16.sp, fontWeight: FontWeight.w600)),
                    SizedBox(height: 2.h),
                    Text(item.subtitle,
                        style: TextStyle(
                            fontSize: 12.sp, color: AppColors.textHint)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  size: 16, color: AppColors.textHint),
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
