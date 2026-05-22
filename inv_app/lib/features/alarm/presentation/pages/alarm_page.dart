import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/alarm/presentation/bloc/alarm_bloc.dart';

class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key});

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> {
  @override
  void initState() {
    super.initState();
    context.read<AlarmBloc>().add(const AlarmListRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('消息告警')),
      body: BlocBuilder<AlarmBloc, AlarmState>(
        builder: (context, state) {
          if (state is AlarmLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is AlarmError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(state.message),
                  TextButton(
                    onPressed: () => context.read<AlarmBloc>().add(const AlarmListRequested()),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }

          if (state is AlarmListLoaded) {
            if (state.alarms.isEmpty) {
              return ListView(
                children: [
                  SizedBox(height: 120.h),
                  const Center(
                    child: Column(
                      children: [
                        Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('暂无告警', style: TextStyle(color: Colors.grey, fontSize: 16)),
                      ],
                    ),
                  ),
                ],
              );
            }

            return RefreshIndicator(
              onRefresh: () async {
                context.read<AlarmBloc>().add(const AlarmListRequested());
              },
              child: ListView.builder(
                padding: EdgeInsets.all(12.w),
                itemCount: state.alarms.length,
                itemBuilder: (context, index) {
                  final alarm = state.alarms[index];
                  return _buildAlarmCard(alarm);
                },
              ),
            );
          }

          return const Center(child: Text('加载中...'));
        },
      ),
    );
  }

  Widget _buildAlarmCard(dynamic alarm) {
    Color levelColor;
    String levelText;
    switch (alarm['alarm_level']) {
      case 1:
        levelColor = Colors.red;
        levelText = '严重';
        break;
      case 2:
        levelColor = Colors.orange;
        levelText = '重要';
        break;
      default:
        levelColor = Colors.yellow;
        levelText = '一般';
    }

    return Card(
      margin: EdgeInsets.only(bottom: 8.h),
      child: InkWell(
        onTap: () => context.push('/alarm/${alarm['id']}'),
        borderRadius: BorderRadius.circular(12.r),
        child: Padding(
          padding: EdgeInsets.all(12.w),
          child: Row(
            children: [
              Container(
                width: 8.w,
                height: 8.w,
                decoration: BoxDecoration(
                  color: alarm['status'] == 1 ? Colors.grey : levelColor,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          alarm['fault_message'] ?? '告警',
                          style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w500),
                        ),
                        SizedBox(width: 8.w),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: levelColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                          child: Text(levelText, style: TextStyle(fontSize: 11.sp, color: levelColor)),
                        ),
                      ],
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      '设备: ${alarm['device_sn'] ?? '-'}  故障码: ${alarm['fault_code'] ?? '-'}',
                      style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
