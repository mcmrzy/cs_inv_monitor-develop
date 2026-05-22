import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';

class StationDetailPage extends StatefulWidget {
  final int stationId;

  const StationDetailPage({super.key, required this.stationId});

  @override
  State<StationDetailPage> createState() => _StationDetailPageState();
}

class _StationDetailPageState extends State<StationDetailPage> {
  StationDetailLoaded? _cachedState;

  @override
  void initState() {
    super.initState();
    context.read<StationBloc>().add(StationDetailRequested(stationId: widget.stationId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('电站详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => context.push('/station/${widget.stationId}/edit'),
          ),
        ],
      ),
      body: BlocBuilder<StationBloc, StationState>(
        builder: (context, state) {
          if (state is StationDetailLoaded) {
            _cachedState = state;
          }

          final displayState = _cachedState;

          if (displayState == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final station = displayState.station;
          if (station == null) {
            return const Center(child: Text('电站不存在'));
          }

          return RefreshIndicator(
              onRefresh: () async {
                context.read<StationBloc>().add(
                  StationDetailRequested(stationId: widget.stationId),
                );
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(16.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStationInfo(station),
                    SizedBox(height: 16.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('设备列表', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
                        TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('添加设备'),
                          onPressed: () => context.push('/add-device?station_id=${widget.stationId}'),
                        ),
                      ],
                    ),
                    if (displayState.devices.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.devices, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('暂无设备', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      )
                    else
                      ...displayState.devices.map((device) => _buildDeviceCard(device)),
                  ],
                ),
              ),
            );
        },
      ),
    );
  }

  Widget _buildStationInfo(dynamic station) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              station['name'] ?? '',
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                const Icon(Icons.location_on, size: 16, color: Colors.grey),
                SizedBox(width: 4.w),
                Expanded(
                  child: Text(
                    '${station['province'] ?? ''}${station['city'] ?? ''}${station['district'] ?? ''} ${station['address'] ?? ''}',
                    style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoItem('装机容量', '${station['capacity'] ?? 0}kW'),
                _buildInfoItem('组件数量', '${station['panel_count'] ?? 0}块'),
                _buildInfoItem('状态', station['status'] == 1 ? '运行中' : '离线'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: AppColors.primary)),
        SizedBox(height: 4.h),
        Text(label, style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
      ],
    );
  }

  Widget _buildDeviceCard(dynamic device) {
    return Card(
      margin: EdgeInsets.only(bottom: 8.h),
      child: ListTile(
        leading: Icon(
          Icons.solar_power,
          color: device['status'] == 1 ? AppColors.online : AppColors.offline,
        ),
        title: Text(device['sn'] ?? ''),
        subtitle: Text('型号: ${_emptyDash(device['model'])} | 功率: ${_emptyDashNum(device['rated_power'], 'W')}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/device/${device['sn']}'),
      ),
    );
  }

  String _emptyDash(dynamic val) {
    if (val == null) return '-';
    final s = val.toString().trim();
    if (s.isEmpty || s == '0' || s == '0.0' || s == '0.00') return '-';
    return s;
  }

  String _emptyDashNum(dynamic val, [String unit = '']) {
    if (val == null) return '-';
    final n = double.tryParse(val.toString()) ?? 0;
    if (n == 0) return '-';
    if (unit.isNotEmpty) return '${_fmtNum(val)}$unit';
    return _fmtNum(val);
  }

  String _fmtNum(dynamic val) {
    if (val == null) return '0';
    final n = double.tryParse(val.toString()) ?? 0;
    if (n == n.roundToDouble()) return n.toStringAsFixed(0);
    return n.toStringAsFixed(1);
  }
}
