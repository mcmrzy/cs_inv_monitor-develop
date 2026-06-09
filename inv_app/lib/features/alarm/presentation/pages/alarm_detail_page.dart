import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/data/alarm_code_mapping.dart';
import 'package:inv_app/core/services/contact_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/features/alarm/presentation/bloc/alarm_bloc.dart';

class AlarmDetailPage extends StatefulWidget {
  final int alarmId;

  const AlarmDetailPage({super.key, required this.alarmId});

  @override
  State<AlarmDetailPage> createState() => _AlarmDetailPageState();
}

class _AlarmDetailPageState extends State<AlarmDetailPage> {
  final ContactService _contactService = ContactService();
  AlarmState? _cachedState;

  @override
  void initState() {
    super.initState();
    context.read<AlarmBloc>().add(AlarmDetailRequested(alarmId: widget.alarmId));
  }

  int _parseFaultCode(dynamic faultCode) {
    if (faultCode == null) return -1;
    if (faultCode is int) return faultCode;
    final str = faultCode.toString();
    if (str.startsWith('0x') || str.startsWith('0X')) {
      return int.tryParse(str.substring(2), radix: 16) ?? -1;
    }
    return int.tryParse(str) ?? -1;
  }

  String _severityLabel(String severity) {
    switch (severity) {
      case 'critical':
        return '严重';
      case 'warning':
        return '警告';
      case 'info':
        return '信息';
      default:
        return '未知';
    }
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'critical':
        return AppColors.error;
      case 'warning':
        return AppColors.warning;
      case 'info':
        return AppColors.info;
      default:
        return AppColors.textHint;
    }
  }

  String _levelToSeverity(dynamic level) {
    switch (level) {
      case 1:
        return 'critical';
      case 2:
        return 'warning';
      default:
        return 'info';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('故障诊断')),
      body: BlocBuilder<AlarmBloc, AlarmState>(
        builder: (context, state) {
          if (state is AlarmDetailLoaded) {
            _cachedState = state;
          }
          if (state is AlarmError && _cachedState != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(state.message), duration: const Duration(seconds: 2)),
                );
              }
            });
          }

          if (_cachedState is AlarmDetailLoaded) {
            final alarm = (_cachedState as AlarmDetailLoaded).alarm;
            if (alarm == null) {
              return const Center(child: Text('告警不存在'));
            }

            final faultCode = _parseFaultCode(alarm['fault_code']);
            final alarmEntry = AlarmCodeMapping.getEntry(faultCode);
            final severity = alarmEntry?.severity ?? _levelToSeverity(alarm['alarm_level']);
            final severityColor = _severityColor(severity);
            final isHandled = alarm['status'] == 1;

            return _buildDetailContent(alarm, faultCode, alarmEntry, severity, severityColor, isHandled);
          }

          if (state is AlarmError) {
            return Center(child: Text(state.message));
          }

          return _buildSkeletonBody();
        },
      ),
    );
  }

  Widget _buildSkeletonBody() {
    return ListView(
      padding: EdgeInsets.all(16.w),
      children: const [
        SkeletonDetailSection(),
        SkeletonDetailSection(),
        SkeletonDetailSection(),
        SkeletonDetailSection(),
        SkeletonDetailSection(),
        SkeletonDetailSection(),
      ],
    );
  }

  Widget _buildDetailContent(dynamic alarm, int faultCode, dynamic alarmEntry, String severity, Color severityColor, bool isHandled) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSeverityTag(severity, severityColor),
                SizedBox(height: 12.h),
                _buildAlarmCodeCard(alarm, faultCode, alarmEntry),
                SizedBox(height: 12.h),
                _buildDescriptionCard(alarmEntry),
                SizedBox(height: 12.h),
                _buildPossibleCauseCard(alarmEntry),
                SizedBox(height: 12.h),
                _buildSuggestionCard(alarmEntry),
                SizedBox(height: 12.h),
                _buildDeviceInfoCard(alarm),
                SizedBox(height: 12.h),
                _buildTimeInfoCard(alarm, isHandled),
                if (!isHandled) ...[
                  SizedBox(height: 20.h),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        context.read<AlarmBloc>().add(
                              AlarmMarkReadRequested(alarmIds: [widget.alarmId]),
                            );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                      ),
                      child: Text('标记已处理', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
                SizedBox(height: 16.h),
              ],
            ),
          ),
        ),
        _buildContactButtons(alarm),
      ],
    );
  }

  Widget _buildSeverityTag(String severity, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18.sp, color: color),
          SizedBox(width: 6.w),
          Text(
            _severityLabel(severity),
            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildAlarmCodeCard(dynamic alarm, int faultCode, AlarmCodeEntry? entry) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, size: 20.sp, color: AppColors.primary),
                SizedBox(width: 8.w),
                Text('告警码', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ],
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                  child: Text(
                    '0x${faultCode.toRadixString(16).toUpperCase()}',
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AppColors.primary, fontFamily: 'monospace'),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry?.nameZh ?? alarm['fault_message'] ?? '未知告警',
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                      if (entry != null) ...[
                        SizedBox(height: 2.h),
                        Text(
                          entry.nameEn,
                          style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionCard(AlarmCodeEntry? entry) {
    final description = entry?.description ?? '暂无该告警码的详细描述信息。';
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.description_outlined, size: 20.sp, color: AppColors.primary),
                SizedBox(width: 8.w),
                Text('告警描述', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ],
            ),
            SizedBox(height: 12.h),
            Text(description, style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary, height: 1.6)),
          ],
        ),
      ),
    );
  }

  Widget _buildPossibleCauseCard(AlarmCodeEntry? entry) {
    final causes = (entry?.possibleCause ?? '').split('\n').where((s) => s.trim().isNotEmpty).toList();
    if (causes.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.search, size: 20.sp, color: AppColors.warning),
                SizedBox(width: 8.w),
                Text('可能原因', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ],
            ),
            SizedBox(height: 12.h),
            ...causes.map((cause) => Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 4.h),
                    child: Icon(Icons.arrow_right, size: 16.sp, color: AppColors.warning),
                  ),
                  SizedBox(width: 4.w),
                  Expanded(
                    child: Text(cause.trim(), style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, height: 1.5)),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(AlarmCodeEntry? entry) {
    final suggestions = (entry?.suggestion ?? '请联系安装商或售后服务获取技术支持。').split('\n').where((s) => s.trim().isNotEmpty).toList();

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.build_outlined, size: 20.sp, color: AppColors.success),
                SizedBox(width: 8.w),
                Text('建议处理措施', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ],
            ),
            SizedBox(height: 12.h),
            ...List.generate(suggestions.length, (index) {
              return Padding(
                padding: EdgeInsets.only(bottom: 10.h),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22.w,
                      height: 22.w,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(11.r),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.success),
                        ),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(suggestions[index].trim(), style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, height: 1.5)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfoCard(dynamic alarm) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices, size: 20.sp, color: AppColors.primary),
                SizedBox(width: 8.w),
                Text('设备信息', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ],
            ),
            SizedBox(height: 12.h),
            _buildInfoRow('设备SN', alarm['device_sn'] ?? '-'),
            _buildInfoRow('设备型号', alarm['device_model'] ?? '-'),
            _buildInfoRow('固件版本', alarm['firmware_version'] ?? '-'),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeInfoCard(dynamic alarm, bool isHandled) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.access_time, size: 20.sp, color: AppColors.primary),
                SizedBox(width: 8.w),
                Text('时间信息', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: isHandled ? AppColors.success.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                  child: Text(
                    isHandled ? '已处理' : '未处理',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: isHandled ? AppColors.success : AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            _buildInfoRow('发生时间', alarm['occurred_at']?.toString() ?? '-'),
            _buildInfoRow('恢复时间', alarm['recovered_at']?.toString() ?? '-'),
            _buildInfoRow('处理时间', alarm['handled_at']?.toString() ?? '-'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80.w,
            child: Text(label, style: TextStyle(fontSize: 13.sp, color: AppColors.textHint)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _buildContactButtons(dynamic alarm) {
    final installerPhone = alarm?['installer_phone'] as String?;

    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  if (installerPhone != null && installerPhone.isNotEmpty) {
                    _contactService.makePhoneCall(installerPhone);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('暂无安装商联系方式')),
                    );
                  }
                },
                icon: Icon(Icons.phone, size: 18.sp),
                label: Text('联系安装商', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                ),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  _contactService.makePhoneCall('400-888-8888');
                },
                icon: Icon(Icons.headset_mic, size: 18.sp),
                label: Text('联系客服', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r),
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
