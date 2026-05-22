import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/features/alarm/presentation/bloc/alarm_bloc.dart';

class AlarmDetailPage extends StatefulWidget {
  final int alarmId;

  const AlarmDetailPage({super.key, required this.alarmId});

  @override
  State<AlarmDetailPage> createState() => _AlarmDetailPageState();
}

class _AlarmDetailPageState extends State<AlarmDetailPage> {
  @override
  void initState() {
    super.initState();
    context.read<AlarmBloc>().add(AlarmDetailRequested(alarmId: widget.alarmId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('告警详情')),
      body: BlocBuilder<AlarmBloc, AlarmState>(
        builder: (context, state) {
          if (state is AlarmLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is AlarmError) {
            return Center(child: Text(state.message));
          }

          if (state is AlarmDetailLoaded) {
            final alarm = state.alarm;
            if (alarm == null) {
              return const Center(child: Text('告警不存在'));
            }

            return SingleChildScrollView(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alarm['fault_message'] ?? '告警信息',
                            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 16.h),
                          _buildRow('设备SN', alarm['device_sn'] ?? '-'),
                          _buildRow('故障码', alarm['fault_code'] ?? '-'),
                          _buildRow('故障详情', alarm['fault_detail'] ?? '-'),
                          _buildRow('告警等级', _levelText(alarm['alarm_level'])),
                          _buildRow('状态', alarm['status'] == 1 ? '已处理' : '未处理'),
                          _buildRow('发生时间', alarm['occurred_at']?.toString() ?? '-'),
                          _buildRow('恢复时间', alarm['recovered_at']?.toString() ?? '-'),
                          _buildRow('处理时间', alarm['handled_at']?.toString() ?? '-'),
                        ],
                      ),
                    ),
                  ),
                  if (alarm['status'] != 1) ...[
                    SizedBox(height: 16.h),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                        child: const Text('标记已处理'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }

          return const Center(child: Text('加载中...'));
        },
      ),
    );
  }

  String _levelText(dynamic level) {
    switch (level) {
      case 1:
        return '严重';
      case 2:
        return '重要';
      default:
        return '一般';
    }
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80.w,
            child: Text(label, style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 14.sp)),
          ),
        ],
      ),
    );
  }
}
