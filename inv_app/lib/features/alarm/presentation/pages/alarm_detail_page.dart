import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/data/alarm_code_mapping.dart';
import 'package:inv_app/core/services/contact_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/features/alarm/presentation/bloc/alarm_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

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

  String _severityLabel(String severity, AppLocalizations l10n) {
    switch (severity) {
      case 'fault':
        return l10n.severe;
      case 'warning':
        return l10n.warningLevel;
      case 'info':
        return l10n.infoLevel;
      case 'normal':
        return '正常';
      default:
        return l10n.unknown;
    }
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'fault':
        return AppColors.error;
      case 'warning':
        return AppColors.warning;
      case 'info':
        return AppColors.info;
      case 'normal':
        return AppColors.success;
      default:
        return AppColors.textHint;
    }
  }

  String _levelToSeverity(dynamic level) {
    switch (level) {
      case 3:
        return 'fault';
      case 2:
        return 'warning';
      case 1:
        return 'info';
      default:
        return 'normal'; // code=0
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.faultDiagnosis)),
      body: BlocBuilder<AlarmBloc, AlarmState>(
        builder: (context, state) {
          if (state is AlarmDetailLoaded) {
            _cachedState = state;
          }
          if (state is AlarmError && _cachedState != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.translateError(state.message)), duration: const Duration(seconds: 2)),
                );
              }
            });
          }

          if (_cachedState is AlarmDetailLoaded) {
            final alarm = (_cachedState as AlarmDetailLoaded).alarm;
            if (alarm == null) {
              return Center(child: Text(l10n.alarmNotFound));
            }

            final faultCode = _parseFaultCode(alarm['fault_code']);
            final alarmEntry = AlarmCodeMapping.getEntry(faultCode);
            final severity = alarmEntry?.severity ?? _levelToSeverity(alarm['alarm_level']);
            final severityColor = _severityColor(severity);
            final isHandled = alarm['status'] == 1;

            return _buildDetailContent(alarm, faultCode, alarmEntry, severity, severityColor, isHandled, l10n);
          }

          if (state is AlarmError) {
            return Center(child: Text(l10n.translateError(state.message)));
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

  Widget _buildDetailContent(dynamic alarm, int faultCode, dynamic alarmEntry, String severity, Color severityColor, bool isHandled, AppLocalizations l10n) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部状态卡片
                _buildStatusHeader(severity, severityColor, isHandled, l10n),
                SizedBox(height: 16.h),
                
                // 告警信息卡片
                _buildAlarmInfoCard(alarm, faultCode, alarmEntry, l10n),
                SizedBox(height: 12.h),
                
                // 详细信息区域
                if (alarmEntry != null) ...[
                  _buildDescriptionSection(alarmEntry, l10n),
                  SizedBox(height: 12.h),
                  _buildCausesSection(alarmEntry, l10n),
                  SizedBox(height: 12.h),
                  _buildSuggestionsSection(alarmEntry, l10n),
                  SizedBox(height: 12.h),
                ],
                
                // 设备信息
                _buildDeviceInfoSection(alarm, l10n),
                SizedBox(height: 12.h),
                
                // 时间信息
                _buildTimeInfoSection(alarm, isHandled, l10n),
                
                // 处理按钮（仅未处理时显示）
                if (!isHandled) ...[
                  SizedBox(height: 24.h),
                  _buildMarkReadButton(l10n),
                ],
                SizedBox(height: 80.h), // 为底部按钮留出空间
              ],
            ),
          ),
        ),
        _buildContactButtons(alarm, l10n),
      ],
    );
  }

  // ==================== 顶部状态卡片 ====================
  Widget _buildStatusHeader(String severity, Color color, bool isHandled, AppLocalizations l10n) {
    IconData iconData;
    String statusText;
    
    switch (severity) {
      case 'fault':
        iconData = Icons.error_outline;
        statusText = l10n.severe;
        break;
      case 'warning':
        iconData = Icons.warning_amber_rounded;
        statusText = l10n.warningLevel;
        break;
      case 'info':
        iconData = Icons.info_outline;
        statusText = l10n.infoLevel;
        break;
      case 'normal':
        iconData = Icons.check_circle_outline;
        statusText = '正常';
        break;
      default:
        iconData = Icons.notifications_none;
        statusText = l10n.general;
    }
    
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.15),
            color.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(iconData, size: 32.sp, color: color),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  isHandled ? l10n.processed : l10n.unprocessed,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            isHandled ? Icons.check_circle : Icons.circle_outlined,
            size: 24.sp,
            color: isHandled ? AppColors.success : AppColors.textHint,
          ),
        ],
      ),
    );
  }

  // ==================== 告警信息卡片 ====================
  Widget _buildAlarmInfoCard(dynamic alarm, int faultCode, AlarmCodeEntry? entry, AppLocalizations l10n) {
    final alarmName = entry?.getLocalizedName(Localizations.localeOf(context).languageCode) ?? alarm['fault_message'] ?? l10n.unknownAlarm;
    
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 20.sp, color: AppColors.primary),
              SizedBox(width: 8.w),
              Text(
                l10n.alarmInfo,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Text(
            alarmName,
            style: TextStyle(
              fontSize: 17.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
          SizedBox(height: 12.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${l10n.faultCodeLabel}: ',
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '$faultCode',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 描述区域 ====================
  Widget _buildDescriptionSection(AlarmCodeEntry entry, AppLocalizations l10n) {
    return _buildSectionCard(
      icon: Icons.description_outlined,
      iconColor: AppColors.blue,
      title: l10n.alarmDescription,
      content: Text(
        entry.description,
        style: TextStyle(
          fontSize: 14.sp,
          color: AppColors.textSecondary,
          height: 1.7,
        ),
      ),
    );
  }

  // ==================== 可能原因区域 ====================
  Widget _buildCausesSection(AlarmCodeEntry entry, AppLocalizations l10n) {
    final causes = entry.possibleCause.split('\n').where((s) => s.trim().isNotEmpty).toList();
    if (causes.isEmpty) return const SizedBox.shrink();

    return _buildSectionCard(
      icon: Icons.search,
      iconColor: AppColors.warning,
      title: l10n.possibleCauses,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: causes.map((cause) => Padding(
          padding: EdgeInsets.only(bottom: 10.h),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: EdgeInsets.only(top: 4.h),
                width: 6.w,
                height: 6.w,
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  cause.trim(),
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.textSecondary,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }

  // ==================== 建议措施区域 ====================
  Widget _buildSuggestionsSection(AlarmCodeEntry entry, AppLocalizations l10n) {
    final suggestions = entry.suggestion.split('\n').where((s) => s.trim().isNotEmpty).toList();

    return _buildSectionCard(
      icon: Icons.build_outlined,
      iconColor: AppColors.success,
      title: l10n.suggestedActions,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(suggestions.length, (index) => Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24.w,
                height: 24.w,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6.r),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  suggestions[index].trim(),
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.textSecondary,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        )),
      ),
    );
  }

  // ==================== 通用 Section Card ====================
  Widget _buildSectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget content,
  }) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20.sp, color: iconColor),
              SizedBox(width: 8.w),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          content,
        ],
      ),
    );
  }

  // ==================== 设备信息区域 ====================
  Widget _buildDeviceInfoSection(dynamic alarm, AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.devices, size: 20.sp, color: AppColors.primary),
              SizedBox(width: 8.w),
              Text(
                l10n.deviceInfo,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          _buildInfoRow(l10n.deviceSn, alarm['device_sn'] ?? '-'),
          _buildInfoRow(l10n.deviceModel, alarm['device_model'] ?? '-'),
          _buildInfoRow(l10n.firmwareVersion, alarm['firmware_version'] ?? '-'),
        ],
      ),
    );
  }

  // ==================== 时间信息区域 ====================
  Widget _buildTimeInfoSection(dynamic alarm, bool isHandled, AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.access_time, size: 20.sp, color: AppColors.primary),
              SizedBox(width: 8.w),
              Text(
                l10n.timeInfo,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: isHandled ? AppColors.success.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6.r),
                  border: Border.all(
                    color: isHandled ? AppColors.success.withValues(alpha: 0.3) : AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  isHandled ? l10n.processed : l10n.unprocessed,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: isHandled ? AppColors.success : AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          _buildInfoRow(l10n.occurrenceTime, alarm['occurred_at']?.toString() ?? '-'),
          _buildInfoRow(l10n.recoveryTime, alarm['recovered_at']?.toString() ?? '-'),
          _buildInfoRow(l10n.processTime, alarm['handled_at']?.toString() ?? '-'),
        ],
      ),
    );
  }

  // ==================== 处理按钮 ====================
  Widget _buildMarkReadButton(AppLocalizations l10n) {
    return BlocBuilder<AlarmBloc, AlarmState>(
      builder: (context, state) {
        final isLoading = state is AlarmLoading;
        
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : () async {
              try {
                context.read<AlarmBloc>().add(
                  AlarmMarkReadRequested(alarmIds: [widget.alarmId]),
                );
                
                await Future.delayed(const Duration(milliseconds: 300));
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.white, size: 20.sp),
                          SizedBox(width: 10.w),
                          Text(
                            l10n.markProcessedSuccess,
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: AppColors.success,
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.translateError(e.toString())),
                      backgroundColor: AppColors.error,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
            icon: isLoading 
              ? SizedBox(
                  width: 18.sp,
                  height: 18.sp,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Icon(Icons.check_circle_outline, size: 20.sp),
            label: Text(
              isLoading ? l10n.processing : l10n.markProcessed,
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 14.h),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90.w,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColors.textHint,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactButtons(dynamic alarm, AppLocalizations l10n) {
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
                      SnackBar(content: Text(l10n.noInstallerContact)),
                    );
                  }
                },
                icon: Icon(Icons.phone, size: 18.sp),
                label: Text(l10n.contactInstaller, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
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
                label: Text(l10n.contactService, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
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
