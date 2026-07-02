import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/ota/presentation/bloc/ota_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class FirmwareListPage extends StatelessWidget {
  final String sn;
  final String deviceModel;
  final String currentMainVersion;

  const FirmwareListPage({
    Key? key,
    required this.sn,
    required this.deviceModel,
    required this.currentMainVersion,
  }) : super(key: key);

  /// Compare version strings like "V3.0.2.20250601".
  /// Returns -1 if a < b, 0 if equal, 1 if a > b.
  int _compareVersions(String a, String b) {
    List<int> parseSegments(String v) {
      final cleaned = v.startsWith('V') || v.startsWith('v')
          ? v.substring(1)
          : v;
      return cleaned
          .split('.')
          .map((s) => int.tryParse(s) ?? 0)
          .toList();
    }

    final segA = parseSegments(a);
    final segB = parseSegments(b);
    final len = segA.length > segB.length ? segA.length : segB.length;
    for (int i = 0; i < len; i++) {
      final va = i < segA.length ? segA[i] : 0;
      final vb = i < segB.length ? segB[i] : 0;
      if (va < vb) return -1;
      if (va > vb) return 1;
    }
    return 0;
  }

  /// Normalize a possibly-composite version like
  /// "V1.2.3.20240510-V1.2.0.20260629" by taking the first sub-version.
  String _normalizeVersion(String v) {
    if (v.contains('-')) return v.split('-').first;
    return v;
  }

  bool _isRollback(String packageVersion) {
    if (currentMainVersion.isEmpty) return false;
    final current = _normalizeVersion(currentMainVersion);
    return _compareVersions(packageVersion, current) < 0;
  }

  bool _isCurrentVersion(String packageVersion) {
    if (currentMainVersion.isEmpty) return false;
    final current = _normalizeVersion(currentMainVersion);
    return _compareVersions(packageVersion, current) == 0;
  }

  void _requestList(BuildContext context) {
    context.read<OtaBloc>().add(
      OTAFirmwareListRequested(deviceModel: deviceModel, sn: sn),
    );
  }

  void _installPackage(BuildContext context, int packageId, String version) {
    if (_isRollback(version)) {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_rounded, color: AppColors.warning),
              SizedBox(width: 8.w),
              Text('警告', style: TextStyle(color: AppColors.warning)),
            ],
          ),
          content: Text(
            '即将安装一个较旧的固件版本（$version），可能导致设备功能异常。确定要继续吗？',
            style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
              child: Text('确定安装'),
            ),
          ],
        ),
      ).then((confirmed) {
        if (confirmed == true && context.mounted) {
          context.read<OtaBloc>().add(
            OTAFirmwareInstallRequested(sn: sn, packageId: packageId),
          );
        }
      });
    } else {
      context.read<OtaBloc>().add(
        OTAFirmwareInstallRequested(sn: sn, packageId: packageId),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50.h),
        child: AppBar(
          title: Text(
            '固件版本列表',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
          ),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20.sp),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: BlocConsumer<OtaBloc, OtaState>(
        listenWhen: (prev, curr) =>
            curr is OTATriggered || curr is OTAProgress || curr is OTAComplete,
        listener: (context, state) {
          // Once install is triggered, pop back to OTA page immediately.
          if (state is OTATriggered || state is OTAProgress || state is OTAComplete) {
            Navigator.pop(context);
          }
        },
        buildWhen: (prev, curr) =>
            curr is OTAFirmwareListLoading ||
            curr is OTAFirmwareListLoaded ||
            curr is OTAFirmwareListError ||
            curr is OTAFirmwareInstalling ||
            curr is OTATriggered,
        builder: (context, state) {
          // Initial kick
          if (state is OTAInitial || state is OTAUpToDate || state is OTAUpdateAvailable) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) _requestList(context);
            });
          }

          if (state is OTAFirmwareListLoading || state is OTAFirmwareInstalling) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    state is OTAFirmwareInstalling ? '正在安装固件...' : '正在加载固件列表...',
                    style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
                  ),
                ],
              ),
            );
          }

          if (state is OTAFirmwareListError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, size: 48.sp, color: AppColors.error),
                  SizedBox(height: 12.h),
                  Text(
                    l10n.translateError(state.message),
                    style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
                  ),
                  SizedBox(height: 20.h),
                  ElevatedButton(
                    onPressed: () => _requestList(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            );
          }

          if (state is OTAFirmwareListLoaded) {
            final packages = state.packages;
            if (packages.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 56.sp, color: AppColors.textHint),
                    SizedBox(height: 12.h),
                    Text(
                      '暂无可用的固件版本',
                      style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              );
            }
            return _buildPackageList(context, packages);
          }

          // Fallback — show loading
          return const Center(child: CircularProgressIndicator(strokeWidth: 3));
        },
      ),
    );
  }

  Widget _buildPackageList(BuildContext context, List<dynamic> packages) {
    return ListView(
      padding: EdgeInsets.all(16.w),
      children: [
        // Current version card
        if (currentMainVersion.isNotEmpty)
          Container(
            padding: EdgeInsets.all(14.w),
            margin: EdgeInsets.only(bottom: 16.h),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: AppColors.successLight.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 20.sp, color: AppColors.successLight),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '当前版本',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.successLight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        currentMainVersion,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.check_circle_rounded, size: 22.sp, color: AppColors.successLight),
              ],
            ),
          ),

        // Package cards
        ...packages.map((pkg) => _buildPackageCard(context, pkg)),
      ],
    );
  }

  Widget _buildPackageCard(BuildContext context, dynamic pkg) {
    final id = (pkg is Map) ? (pkg['id'] as int? ?? 0) : 0;
    final mainVersion = (pkg is Map) ? (pkg['main_version'] as String? ?? '') : '';
    final changelog = (pkg is Map) ? (pkg['changelog'] as String? ?? '') : '';
    final createdAtRaw = (pkg is Map) ? (pkg['created_at'] as String? ?? '') : '';
    final items = (pkg is Map && pkg['items'] is List)
        ? (pkg['items'] as List)
        : <dynamic>[];

    final isCurrent = _isCurrentVersion(mainVersion);
    final isRollbackVer = _isRollback(mainVersion);

    // Format date
    final dateStr = _formatDate(createdAtRaw);

    final borderColor = isCurrent
        ? AppColors.successLight.withValues(alpha: 0.5)
        : const Color(0xFFE5E7EB);

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: borderColor, width: isCurrent ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: version + current tag
          Row(
            children: [
              Expanded(
                child: Text(
                  mainVersion.isNotEmpty ? mainVersion : 'Unknown',
                  style: TextStyle(
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (isCurrent)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: AppColors.successLight.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    '当前版本',
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.successLight,
                    ),
                  ),
                ),
            ],
          ),

          // Chip versions
          if (items.isNotEmpty) ...[
            SizedBox(height: 10.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 6.h,
              children: items.map((item) {
                final chip = ((item is Map) ? (item['target_chip'] as String? ?? '') : '').toUpperCase();
                final fwVer = (item is Map) ? (item['firmware_version'] as String? ?? '-') : '-';
                return Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        chip.isNotEmpty ? chip : '?',
                        style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: 4.w),
                      Text(
                        fwVer,
                        style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          // Changelog
          if (changelog.isNotEmpty) ...[
            SizedBox(height: 10.h),
            Text(
              changelog,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.sp,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],

          // Footer: date + install button
          SizedBox(height: 12.h),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 14.sp, color: AppColors.textHint),
              SizedBox(width: 4.w),
              Text(
                dateStr,
                style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
              ),
              const Spacer(),
              if (!isCurrent)
                _buildInstallButton(context, id, mainVersion, isRollbackVer),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstallButton(BuildContext context, int packageId, String version, bool isRollbackVer) {
    final bgColor = isRollbackVer ? AppColors.warning : AppColors.primary;
    return GestureDetector(
      onTap: () => _installPackage(context, packageId, version),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Text(
          '安装此版本',
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) return '';
    // Try to parse ISO8601 / RFC3339 date and show date portion
    final dt = DateTime.tryParse(raw);
    if (dt != null) {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    // Fallback: return first 10 chars
    return raw.length > 10 ? raw.substring(0, 10) : raw;
  }
}
