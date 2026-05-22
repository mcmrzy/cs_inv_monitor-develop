import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchCtl = TextEditingController();
  final _debouncer = _Debouncer(milliseconds: 200);
  StationSummaryLoaded? _cachedState;
  int _filterIndex = 0;
  bool _showSearch = false;

  static const _filters = ['全部', '正常', '故障', '断连'];

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
      list = list.where((s) => (s['station_name'] ?? s['name'] ?? '').toString().toLowerCase().contains(q)).toList();
    }
    switch (_filterIndex) {
      case 1: list = list.where((s) => (s['status'] ?? 1) == 1 && (s['fault_count'] ?? 0) == 0).toList();
      case 2: list = list.where((s) => (s['fault_count'] ?? 0) > 0).toList();
      case 3: list = list.where((s) => (s['status'] ?? 1) != 1).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: BlocBuilder<StationBloc, StationState>(
        builder: (context, state) {
          if (state is StationSummaryLoaded) _cachedState = state;
          final ds = _cachedState;

          if (ds == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF5B9BD5)));

          if (state is StationError && ds.stations.isEmpty) return _buildError(state.message);

          final filtered = _filterStations(ds.stations);

          return RefreshIndicator(
            color: const Color(0xFF5B9BD5),
            onRefresh: () async => context.read<StationBloc>().add(StationSummaryRequested()),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                _buildHeader(),
                if (_showSearch) _buildSearchBar(),
                _buildSummary(ds),
                _buildFilterChips(),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 4.h),
                    child: Row(
                      children: [
                        Text('${filtered.length} 个电站', style: TextStyle(fontSize: 12.sp, color: const Color(0xFF9CA3AF))),
                        const Spacer(),
                        if (_filterIndex > 0)
                          GestureDetector(
                            onTap: () => setState(() => _filterIndex = 0),
                            child: Text('清除筛选', style: TextStyle(fontSize: 12.sp, color: const Color(0xFF5B9BD5))),
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
                    sliver: SliverList(delegate: SliverChildBuilderDelegate((_, i) => _buildCard(filtered[i]), childCount: filtered.length)),
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
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12.h, left: 20.w, right: 20.w, bottom: 8.h),
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('辰烁科技', style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w700, color: const Color(0xFF1F2937), letterSpacing: -0.3)),
                SizedBox(height: 2.h),
                Text('光伏逆变器智能监控', style: TextStyle(fontSize: 11.sp, color: const Color(0xFF9CA3AF))),
              ],
            ),
            Row(
              children: [
                _hdrBtn(Icons.search_rounded, () => setState(() { _showSearch = !_showSearch; if (!_showSearch) _searchCtl.clear(); })),
                SizedBox(width: 10.w),
                _hdrBtn(Icons.add_rounded, () => context.push('/station/create')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hdrBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38.w, height: 38.w,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Icon(icon, size: 20.sp, color: const Color(0xFF6B7280)),
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
          cursorColor: const Color(0xFF5B9BD5),
          style: TextStyle(fontSize: 14.sp, color: const Color(0xFF374151)),
          decoration: InputDecoration(
            hintText: '搜索电站名称',
            hintStyle: TextStyle(fontSize: 14.sp, color: const Color(0xFFD1D5DB)),
            prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF9CA3AF)),
            suffixIcon: _searchCtl.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF9CA3AF)), onPressed: () { _searchCtl.clear(); setState(() {}); })
                : null,
            filled: true, fillColor: const Color(0xFFF3F4F6),
            contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: const BorderSide(color: Color(0xFF5B9BD5), width: 1)),
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildSummary(dynamic state) {
    final s = state.summary as Map<String, dynamic>? ?? {};
    final items = [
      ('设备总数', '${s['device_count'] ?? 0}', Icons.dns_outlined),
      ('当前在线', '${s['online_count'] ?? 0}', Icons.wifi_outlined),
      ('故障告警', '${s['fault_count'] ?? 0}', Icons.info_outline),
      ('今日发电\nkWh', (s['today_energy'] ?? 0.0).toStringAsFixed(1), Icons.bolt_outlined),
    ];

    return SliverToBoxAdapter(
      child: Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
        child: Row(
          children: items.map((e) => Expanded(child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 3.w),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 14.h),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFB),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Column(
                children: [
                  Icon(e.$3, size: 20.sp, color: const Color(0xFF5B9BD5)),
                  SizedBox(height: 6.h),
                  Text(e.$2, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: const Color(0xFF1F2937), height: 1.1)),
                  SizedBox(height: 3.h),
                  Text(e.$1, style: TextStyle(fontSize: 10.sp, color: const Color(0xFF9CA3AF), height: 1.3), textAlign: TextAlign.center),
                ],
              ),
            ),
          ))).toList(),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildFilterChips() {
    return SliverToBoxAdapter(
      child: Container(
        color: Colors.white,
        padding: EdgeInsets.only(bottom: 2.h),
        child: SizedBox(
          height: 38.h,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            itemCount: _filters.length,
            separatorBuilder: (_, __) => SizedBox(width: 8.w),
            itemBuilder: (_, i) {
              final active = _filterIndex == i;
              return GestureDetector(
                onTap: () => setState(() => _filterIndex = active ? 0 : i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFFEFF6FF) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(19.r),
                    border: Border.all(color: active ? const Color(0xFF5B9BD5).withValues(alpha: 0.4) : const Color(0xFFE5E7EB), width: 1),
                  ),
                  child: Center(
                    child: Text(_filters[i], style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: active ? const Color(0xFF5B9BD5) : const Color(0xFF6B7280))),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCard(dynamic station) {
    final name = station['station_name'] ?? station['name'] ?? '';
    final id = station['station_id'] ?? station['id'] ?? 0;
    final capacity = station['capacity'] ?? 0;
    final deviceCount = station['device_count'] ?? 0;
    final faultCount = station['fault_count'] ?? 0;
    final todayEnergy = station['today_energy'] ?? 0;
    final todayIncome = station['today_income'] ?? 0;
    final status = station['status'] ?? 1;
    final onlineCount = station['online_count'] ?? 0;

    final ok = status == 1 && faultCount == 0;
    final hasFault = faultCount > 0;

    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        shadowColor: const Color(0x08000000),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () => context.push('/station/$id'),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 40.w, height: 40.w,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Icon(Icons.solar_power_rounded, size: 20.sp, color: const Color(0xFF5B9BD5)),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: const Color(0xFF1F2937)), maxLines: 1, overflow: TextOverflow.ellipsis),
                          SizedBox(height: 3.h),
                          Text('$capacity kW · $deviceCount台设备 · 在线$onlineCount', style: TextStyle(fontSize: 11.sp, color: const Color(0xFF9CA3AF))),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                      decoration: BoxDecoration(
                        color: ok ? const Color(0xFFECFDF5) : (hasFault ? const Color(0xFFFEF2F2) : const Color(0xFFF3F4F6)),
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Text(ok ? '正常' : (hasFault ? '故障' : '离线'), style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600, color: ok ? const Color(0xFF10B981) : (hasFault ? const Color(0xFFEF4444) : const Color(0xFF9CA3AF)))),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                Container(height: 0.5, color: const Color(0xFFF3F4F6)),
                SizedBox(height: 10.h),
                Row(
                  children: [
                    _item(Icons.bolt_rounded, '${todayEnergy.toStringAsFixed(1)} kWh'),
                    SizedBox(width: 16.w),
                    _item(Icons.payments_outlined, '¥${todayIncome.toStringAsFixed(2)}'),
                    const Spacer(),
                    Text('查看详情', style: TextStyle(fontSize: 11.sp, color: const Color(0xFF9CA3AF))),
                    SizedBox(width: 2.w),
                    Icon(Icons.chevron_right_rounded, size: 16.sp, color: const Color(0xFFD1D5DB)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13.sp, color: const Color(0xFF9CA3AF)),
        SizedBox(width: 4.w),
        Text(text, style: TextStyle(fontSize: 12.sp, color: const Color(0xFF6B7280))),
      ],
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 60.h),
      child: Column(
        children: [
          Container(
            width: 80.w, height: 80.w,
            decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(20.r)),
            child: Icon(Icons.add_home_work_outlined, size: 36.sp, color: const Color(0xFFD1D5DB)),
          ),
          SizedBox(height: 18.h),
          Text('还没有电站', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: const Color(0xFF6B7280))),
          SizedBox(height: 6.h),
          Text('点击右上角 + 创建', style: TextStyle(fontSize: 13.sp, color: const Color(0xFFD1D5DB))),
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
            Icon(Icons.cloud_off_rounded, size: 44.sp, color: const Color(0xFFD1D5DB)),
            SizedBox(height: 14.h),
            Text(msg, style: TextStyle(fontSize: 13.sp, color: const Color(0xFF9CA3AF)), textAlign: TextAlign.center),
            SizedBox(height: 16.h),
            OutlinedButton(onPressed: () => context.read<StationBloc>().add(StationSummaryRequested()), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF5B9BD5)), child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _Debouncer {
  final int milliseconds;
  Timer? _timer;
  _Debouncer({required this.milliseconds});
  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }
}
