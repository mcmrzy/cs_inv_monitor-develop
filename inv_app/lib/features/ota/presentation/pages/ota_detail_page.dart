import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/ota/presentation/bloc/ota_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';

class OTADetailPage extends StatefulWidget {
  final String deviceSN;
  final int taskId;

  const OTADetailPage({
    super.key,
    required this.deviceSN,
    required this.taskId,
  });

  @override
  State<OTADetailPage> createState() => _OTADetailPageState();
}

class _OTADetailPageState extends State<OTADetailPage> {
  @override
  void initState() {
    super.initState();
    context
        .read<OtaBloc>()
        .add(OTAProgressPollRequested(deviceSn: widget.deviceSN));
  }

  String _statusText(String status, AppLocalizations l10n) {
    switch (status) {
      case 'downloading':
        return l10n.downloading;
      case 'transferring':
        return l10n.transferring;
      case 'verifying':
        return l10n.verifying;
      case 'upgrading':
        return l10n.upgrading;
      case 'completed':
        return l10n.done;
      case 'failed':
        return l10n.failure;
      default:
        return status;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'downloading':
        return Icons.download_rounded;
      case 'transferring':
        return Icons.swap_vert_rounded;
      case 'verifying':
        return Icons.verified_user_rounded;
      case 'upgrading':
        return Icons.system_update_rounded;
      case 'completed':
        return Icons.check_circle_rounded;
      case 'failed':
        return Icons.error_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return AppColors.successLight;
      case 'failed':
        return AppColors.error;
      case 'downloading':
      case 'transferring':
      case 'verifying':
      case 'upgrading':
        return AppColors.primary;
      default:
        return AppColor.textHint(context);
    }
  }

  bool _canCancel(String status) {
    return status == 'downloading' || status == 'transferring';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(
        title: Text(
          l10n.upgradeDetail,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColor.surfaceContainer(context),
        foregroundColor: AppColor.textPrimary(context),
      ),
      body: BlocBuilder<OtaBloc, OtaState>(
        builder: (context, state) {
          if (state is OTAProgress) {
            final color = _statusColor(state.status);
            return Padding(
              padding: EdgeInsets.all(16.w),
              child: Column(
                children: [
                  _buildDeviceInfoCard(l10n),
                  SizedBox(height: 16.h),
                  _buildProgressCard(state, color, l10n),
                  SizedBox(height: 16.h),
                  _buildStatusSteps(state.status, l10n),
                  if (_canCancel(state.status)) ...[
                    SizedBox(height: 24.h),
                    _buildCancelButton(l10n),
                  ],
                ],
              ),
            );
          }

          if (state is OTAComplete) {
            return Padding(
              padding: EdgeInsets.all(16.w),
              child: Column(
                children: [
                  _buildDeviceInfoCard(l10n),
                  SizedBox(height: 16.h),
                  _buildCompleteCard(l10n),
                ],
              ),
            );
          }

          if (state is OTAError) {
            return Padding(
              padding: EdgeInsets.all(16.w),
              child: Column(
                children: [
                  _buildDeviceInfoCard(l10n),
                  SizedBox(height: 16.h),
                  _buildFailedCard(state, l10n),
                ],
              ),
            );
          }

          if (state is OTALoading) {
            return const PageSkeleton();
          }

          return Center(child: Text(l10n.loadingData));
        },
      ),
    );
  }

  Widget _buildDeviceInfoCard(AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: AppColor.primarySoft(context),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(
              Icons.devices_rounded,
              size: 18.sp,
              color: AppColors.primary,
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.deviceLabel,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColor.textPrimary(context),
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  widget.deviceSN,
                  style: TextStyle(fontSize: 12.sp, color: AppColor.textHint(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(
    OTAProgress state,
    Color color,
    AppLocalizations l10n,
  ) {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(_statusIcon(state.status), size: 48.sp, color: color),
          SizedBox(height: 12.h),
          Text(
            _statusText(state.status, l10n),
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          SizedBox(height: 20.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(8.r),
            child: LinearProgressIndicator(
              value: state.progress / 100.0,
              minHeight: 10.h,
              backgroundColor: AppColor.border(context),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          SizedBox(height: 10.h),
          Text(
            '${state.progress.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.w700,
              color: AppColor.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSteps(String currentStatus, AppLocalizations l10n) {
    final steps = ['downloading', 'transferring', 'verifying', 'upgrading'];
    final currentIndex = steps.indexOf(currentStatus);

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: steps.asMap().entries.map((entry) {
          final index = entry.key;
          final step = entry.value;
          final isCompleted = currentIndex > index;
          final isCurrent = currentIndex == index;
          final isPending = currentIndex < index;

          Color stepColor;
          if (isCompleted) {
            stepColor = AppColors.successLight;
          } else if (isCurrent) {
            stepColor = AppColors.primary;
          } else {
            stepColor = AppColor.textHint(context);
          }

          return Row(
            children: [
              Container(
                width: 28.w,
                height: 28.w,
                decoration: BoxDecoration(
                  color: stepColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: stepColor, width: 2),
                ),
                child: isCompleted
                    ? Icon(Icons.check, size: 14.sp, color: stepColor)
                    : Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: stepColor,
                          ),
                        ),
                      ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  _statusText(step, l10n),
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    color:
                        isPending ? AppColor.textHint(context) : AppColor.textPrimary(context),
                  ),
                ),
              ),
              if (isCurrent)
                SizedBox(
                  width: 14.w,
                  height: 14.w,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: stepColor,
                  ),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCancelButton(AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      height: 48.h,
      child: OutlinedButton(
        onPressed: () => _confirmExitWhileUpgrading(l10n),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        ),
        child: Text(
          // 设备协议无取消命令：退出页面仅停止本地轮询，升级仍在后台进行，
          // 文案如实表达语义，避免用户误以为已取消升级
          l10n.str('ota_exit_page'),
          style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// 退出前二次确认：提示升级不会被中断
  Future<void> _confirmExitWhileUpgrading(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.str('ota_exit_page')),
        content: Text(l10n.str('ota_exit_page_hint')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context.read<OtaBloc>().add(const OTAProgressStopPoll());
      Navigator.of(context).pop();
    }
  }

  Widget _buildCompleteCard(AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 小烁成功动作插画：升级完成态（美术路由 C5/ota-success）
          Image.asset(
            CsergyAssets.xiaoshuoSuccess,
            width: 108.w,
            height: 108.w,
            fit: BoxFit.contain,
          ),
          SizedBox(height: 12.h),
          Text(
            l10n.upgradeCompleted,
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w700,
              color: AppColor.textPrimary(context),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            l10n.firmwareUpdatedSuccess,
            style: TextStyle(fontSize: 14.sp, color: AppColor.textSecondary(context)),
          ),
          SizedBox(height: 24.h),
          SizedBox(
            width: double.infinity,
            height: 48.h,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.successLight,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                elevation: 0,
              ),
              child: Text(
                l10n.done,
                style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailedCard(OTAError state, AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 小烁警告动作插画：升级失败态（美术路由 C6/ota-failure）
          Image.asset(
            CsergyAssets.xiaoshuoWarning,
            width: 108.w,
            height: 108.w,
            fit: BoxFit.contain,
          ),
          SizedBox(height: 12.h),
          Text(
            l10n.upgradeFailedTitle,
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w700,
              color: AppColor.textPrimary(context),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            l10n.translateError(state.message),
            style: TextStyle(fontSize: 14.sp, color: AppColor.textSecondary(context)),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24.h),
          SizedBox(
            width: double.infinity,
            height: 48.h,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                elevation: 0,
              ),
              child: Text(
                l10n.back,
                style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}