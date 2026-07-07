import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/firmware_download_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/features/ota/presentation/bloc/ota_bloc.dart';
import 'package:inv_app/features/ota/presentation/pages/firmware_list_page.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OTAPage extends StatefulWidget {
  final String deviceSN;

  const OTAPage({super.key, required this.deviceSN});

  @override
  State<OTAPage> createState() => _OTAPageState();
}

class _OTAPageState extends State<OTAPage> {
  final FirmwareDownloadService _downloadService = FirmwareDownloadService(
    getIt<Dio>(),
    getIt<SharedPreferences>(),
  );

  final Map<int, bool> _downloadedCache = {};
  final Map<int, double> _downloadingProgress = {};
  final Set<int> _downloadingIds = {};

  OtaState? _cachedState;
  bool _triggering = false;
  final Set<int> _checkedDownloadIds = {};

  @override
  void initState() {
    super.initState();
    context.read<OtaBloc>().add(OTACheckRequested(sn: widget.deviceSN));
  }

  Future<void> _restoreDownloadState(int firmwareId) async {
    if (_checkedDownloadIds.contains(firmwareId)) return;
    _checkedDownloadIds.add(firmwareId);
    final downloaded = await _downloadService.isFirmwareDownloaded(firmwareId);
    if (downloaded && mounted) {
      setState(() => _downloadedCache[firmwareId] = true);
    }
  }

  @override
  void dispose() {
    _downloadService.dispose();
    super.dispose();
  }

  Future<void> _startPreDownload(int firmwareId, String url, String fileName) async {
    setState(() {
      _downloadingIds.add(firmwareId);
      _downloadingProgress[firmwareId] = 0.0;
    });

    _downloadService.downloadProgressStream.listen((progress) {
      if (_downloadingIds.contains(firmwareId) && mounted) {
        setState(() {
          _downloadingProgress[firmwareId] = progress;
        });
      }
    });

    try {
      await _downloadService.downloadFirmware(
        url: url,
        fileName: fileName,
        firmwareId: firmwareId,
      );
      if (mounted) {
        setState(() {
          _downloadedCache[firmwareId] = true;
          _downloadingIds.remove(firmwareId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadingIds.remove(firmwareId);
        });
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.str('pre_download_failed', {'error': '$e'})), backgroundColor: AppColors.error),
        );
      }
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
          title: Text(l10n.otaTitle, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
        ),
      ),
      body: BlocBuilder<OtaBloc, OtaState>(
        builder: (context, state) {
          final hasContent = state is OTAUpdateAvailable ||
              state is OTAUpToDate;
          if (hasContent) {
            {
              _cachedState = state;
            }
          }
          if (state is OTATriggered || state is OTAProgress || state is OTAComplete) {
            _triggering = false;
          }
          if (state is OTAError && _cachedState != null) {
            _triggering = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppLocalizations.of(context)!.translateError(state.message)), duration: const Duration(seconds: 2)),
                );
              }
            });
          }

          // 升级进行中或已完成
          if (state is OTAProgress) {
            return _buildProgress(state);
          }
          if (state is OTAComplete) {
            return _buildComplete();
          }
          if (state is OTATriggered) {
            return _buildTriggering();
          }

          if (_cachedState is OTAUpdateAvailable) {
            return _buildUpdateAvailable(_cachedState as OTAUpdateAvailable);
          }
          if (_cachedState is OTAUpToDate) {
            return _buildUpToDate(_cachedState as OTAUpToDate);
          }
          if (state is OTAError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, size: 48.sp, color: AppColors.error),
                  SizedBox(height: 12.h),
                  Text(AppLocalizations.of(context)!.translateError(state.message), style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
                  SizedBox(height: 20.h),
                  ElevatedButton(
                    onPressed: () {
                      context.read<OtaBloc>().add(OTACheckRequested(sn: widget.deviceSN));
                    },
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

          return _buildSkeletonBody();
        },
      ),
    );
  }

  Widget _buildSkeletonBody() {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonCard(height: 72),
          SizedBox(height: 16.h),
          const SkeletonCard(height: 120),
          SizedBox(height: 16.h),
          SkeletonBox(width: 80.w, height: 14.h),
          SizedBox(height: 8.h),
          Expanded(
            child: ListView.builder(
              itemCount: 3,
              itemBuilder: (context, index) => const SkeletonCard(height: 80),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateAvailable(OTAUpdateAvailable state) {
    final info = state.info;
    final upgradeMode = info['upgrade_mode'] as String? ?? 'single';
    if (upgradeMode == 'package') {
      return _buildPackageUpdateAvailable(info);
    }
    return _buildSingleUpdateAvailable(info);
  }

  Widget _buildSingleUpdateAvailable(Map<String, dynamic> info) {
    final l10n = AppLocalizations.of(context)!;
    final firmwareId = info['firmware_id'] as int? ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreDownloadState(firmwareId));
    final latestVersion = info['version'] as String? ?? l10n.unknown;
    final currentVersion = info['current_version'] as String? ?? '';
    final targetChip = (info['target_chip'] as String? ?? '').toUpperCase();
    final downloadUrl = info['download_url'] as String? ?? '';
    final fileName = info['file_name'] as String? ?? 'firmware_$firmwareId.bin';

    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.white,
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
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(Icons.devices_rounded, size: 18.sp, color: AppColors.primary),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.currentDevice, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      SizedBox(height: 2.h),
                      Text(widget.deviceSN, style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.system_update_rounded, size: 20.sp, color: AppColors.primary),
                    SizedBox(width: 8.w),
                    Text(l10n.newVersionFound, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ],
                ),
                SizedBox(height: 8.h),
                Text('${l10n.str('latest_version_label', {'version': latestVersion})}${targetChip.isNotEmpty ? ' ($targetChip)' : ''}', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                if (currentVersion.isNotEmpty)
                  Text('${l10n.str('current_version_label', {'version': currentVersion})}${targetChip.isNotEmpty ? ' ($targetChip)' : ''}', style: TextStyle(fontSize: 13.sp, color: AppColors.textHint)),
              ],
            ),
          ),
          // 芯片固件版本明细
          if ((info['firmware_esp'] as String? ?? '').isNotEmpty ||
              (info['firmware_dsp'] as String? ?? '').isNotEmpty ||
              (info['firmware_bms'] as String? ?? '').isNotEmpty) ...[  SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 4.h),
                    child: Text('芯片固件版本', style: TextStyle(fontSize: 12.sp, color: AppColors.textHint, fontWeight: FontWeight.w500)),
                  ),
                  _buildChipVersionRow('ESP', info['firmware_esp'] as String? ?? ''),
                  if ((info['firmware_dsp'] as String? ?? '').isNotEmpty)
                    _buildChipVersionRow('DSP', info['firmware_dsp'] as String? ?? ''),
                  if ((info['firmware_bms'] as String? ?? '').isNotEmpty)
                    _buildChipVersionRow('BMS', info['firmware_bms'] as String? ?? ''),
                ],
              ),
            ),
          ],
          SizedBox(height: 24.h),
          SizedBox(
            width: double.infinity,
            height: 48.h,
            child: ElevatedButton(
              onPressed: _triggering ? null : () {
                setState(() => _triggering = true);
                // 使用 package_id 触发升级（后端已改为 package_id）
                context.read<OtaBloc>().add(OTATriggerRequested(sn: widget.deviceSN, packageId: firmwareId));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _triggering ? AppColors.textHint : AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                elevation: 0,
              ),
              child: _triggering
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(l10n.startUpgrade, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
            ),
          ),
          SizedBox(height: 12.h),
          _buildPreDownloadButton(firmwareId, downloadUrl, fileName),
          // 查看可用升级包入口
          Padding(
            padding: EdgeInsets.only(top: 12.h),
            child: Center(
              child: TextButton.icon(
                onPressed: () {
                  final deviceModel = info['device_model'] as String? ?? '';
                  final mainVer = info['current_main_version'] as String? ??
                      info['current_version'] as String? ?? '';
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BlocProvider.value(
                        value: context.read<OtaBloc>(),
                        child: FirmwareListPage(
                          sn: widget.deviceSN,
                          deviceModel: deviceModel,
                          currentMainVersion: mainVer,
                        ),
                      ),
                    ),
                  );
                },
                icon: Icon(Icons.history_rounded, size: 16.sp),
                label: Text('查看可用升级包', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500)),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageUpdateAvailable(Map<String, dynamic> info) {
    final l10n = AppLocalizations.of(context)!;
    final mainVersion = info['main_version'] as String? ?? l10n.unknown;
    final currentMainVersion = info['current_main_version'] as String? ?? '';
    final firmwareId = info['firmware_id'] as int? ?? 0;
    final chipsToUpgrade = (info['chips_to_upgrade'] as List?) ?? [];
    final changelog = info['changelog'] as String? ?? '';
    
    // 从chips_to_upgrade中提取下载信息用于预下载
    String downloadUrl = '';
    String fileName = 'firmware_$firmwareId.bin';
    
    if (chipsToUpgrade.isNotEmpty) {
      final firstChip = chipsToUpgrade[0] as Map<String, dynamic>;
      downloadUrl = firstChip['download_url'] as String? ?? '';
      final chipName = firstChip['chip'] ?? 'firmware';
      final target = firstChip['target'] ?? '';
      fileName = '${chipName}_$target.bin';
    }

    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device info card
          Container(
            padding: EdgeInsets.all(16.w),
            width: double.infinity, // 确保占满宽度
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14.r),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 36.w, height: 36.w,
                  decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10.r)),
                  child: Icon(Icons.devices_rounded, size: 18.sp, color: AppColors.primary),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.currentDevice, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      SizedBox(height: 2.h),
                      Text(widget.deviceSN, style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),
          // Version update card
          Container(
            padding: EdgeInsets.all(16.w),
            width: double.infinity, // 确保占满宽度
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.system_update_rounded, size: 20.sp, color: AppColors.primary),
                    SizedBox(width: 8.w),
                    Text(l10n.newVersionFound, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ],
                ),
                SizedBox(height: 8.h),
                Text(l10n.str('latest_version_label', {'version': mainVersion}), style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                if (currentMainVersion.isNotEmpty)
                  Text(l10n.str('current_version_label', {'version': currentMainVersion}), style: TextStyle(fontSize: 13.sp, color: AppColors.textHint)),
              ],
            ),
          ),
          // Chips to upgrade
          if (chipsToUpgrade.isNotEmpty) ...[  SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.str('chips_to_upgrade_label'), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  SizedBox(height: 8.h),
                  ...chipsToUpgrade.map((chip) {
                    final chipName = (chip['chip'] as String? ?? '').toUpperCase();
                    final current = chip['current'] as String? ?? '-';
                    final target = chip['target'] as String? ?? '-';
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 2.h),
                      child: Row(
                        children: [
                          _buildChipTag(label: chipName, color: AppColors.primary),
                          SizedBox(width: 8.w),
                          Text('$current → $target', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
          // 当前固件版本摘要
          if ((info['firmware_esp'] as String? ?? '').isNotEmpty ||
              (info['firmware_dsp'] as String? ?? '').isNotEmpty ||
              (info['firmware_bms'] as String? ?? '').isNotEmpty) ...[  SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 4.h),
                    child: Text('当前固件版本', style: TextStyle(fontSize: 12.sp, color: AppColors.textHint, fontWeight: FontWeight.w500)),
                  ),
                  _buildChipVersionRow('ESP', info['firmware_esp'] as String? ?? ''),
                  if ((info['firmware_dsp'] as String? ?? '').isNotEmpty)
                    _buildChipVersionRow('DSP', info['firmware_dsp'] as String? ?? ''),
                  if ((info['firmware_bms'] as String? ?? '').isNotEmpty)
                    _buildChipVersionRow('BMS', info['firmware_bms'] as String? ?? ''),
                ],
              ),
            ),
          ],
          // Changelog
          if (changelog.isNotEmpty) ...[  SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.all(12.w),
              width: double.infinity, // 确保占满宽度
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.str('changelog'), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  SizedBox(height: 4.h),
                  Text(changelog, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
          SizedBox(height: 24.h),
          SizedBox(
            width: double.infinity,
            height: 48.h,
            child: ElevatedButton(
              onPressed: _triggering ? null : () {
                setState(() => _triggering = true);
                context.read<OtaBloc>().add(OTAPackageTriggerRequested(sn: widget.deviceSN));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _triggering ? AppColors.textHint : AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                elevation: 0,
              ),
              child: _triggering
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(l10n.startUpgrade, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
            ),
          ),
          SizedBox(height: 12.h),
          _buildPreDownloadButton(firmwareId, downloadUrl, fileName),
          // 查看可用升级包入口
          Padding(
            padding: EdgeInsets.only(top: 12.h),
            child: Center(
              child: TextButton.icon(
                onPressed: () {
                  final deviceModel = info['device_model'] as String? ?? '';
                  final mainVer = info['current_main_version'] as String? ?? '';
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BlocProvider.value(
                        value: context.read<OtaBloc>(),
                        child: FirmwareListPage(
                          sn: widget.deviceSN,
                          deviceModel: deviceModel,
                          currentMainVersion: mainVer,
                        ),
                      ),
                    ),
                  );
                },
                icon: Icon(Icons.history_rounded, size: 16.sp),
                label: Text('查看可用升级包', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500)),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 状态文本本地化映射
  String _localizedStatus(String status, AppLocalizations l10n) {
    switch (status) {
      case 'pending':
        return l10n.str('pending');
      case 'downloading':
        return l10n.str('downloading');
      case 'transferring':
        return l10n.str('transferring');
      case 'verifying':
        return l10n.str('verifying');
      case 'upgrading':
        return l10n.str('upgrading');
      case 'success':
      case 'completed':
        return l10n.str('done');
      case 'failed':
        return l10n.str('failure');
      default:
        return status;
    }
  }

  /// Simple tag widget for chip names
  Widget _buildChipTag({required String label, required Color color}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4.r),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _buildPreDownloadButton(int firmwareId, String downloadUrl, String fileName) {
    final l10n = AppLocalizations.of(context)!;
    final isDownloaded = _downloadedCache[firmwareId] ?? false;
    final isDownloading = _downloadingIds.contains(firmwareId);
    final progress = _downloadingProgress[firmwareId] ?? 0.0;

    if (isDownloaded) {
      return Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: AppColors.successLight.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 16.sp, color: AppColors.successLight),
                SizedBox(width: 6.w),
                Text(l10n.downloaded, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.successLight)),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    context.push(
                      '/ota/${widget.deviceSN}/local?ip=192.168.4.1&firmware_id=$firmwareId&firmware_url=${Uri.encodeComponent(downloadUrl)}&firmware_file_name=${Uri.encodeComponent(fileName)}',
                    );
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(l10n.localUpgrade, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (isDownloading) {
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8.r),
            child: LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              minHeight: 6.h,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            progress > 0 ? l10n.str('pre_downloading_percent', {'percent': (progress * 100).toStringAsFixed(0)}) : '${l10n.preDownloading}...',
            style: TextStyle(fontSize: 12.sp, color: AppColors.primary),
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 44.h,
      child: OutlinedButton(
        onPressed: downloadUrl.isNotEmpty ? () => _startPreDownload(firmwareId, downloadUrl, fileName) : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        ),
        child: Text(l10n.preDownloadFirmware, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildChipVersionRow(String chipName, String version) {
    if (version.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: 4.h),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4.r),
            ),
            child: Text(chipName, style: TextStyle(fontSize: 11.sp, color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
          SizedBox(width: 8.w),
          Text(version, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildUpToDate(OTAUpToDate state) {
    final l10n = AppLocalizations.of(context)!;
    // Prefer current_main_version (from CheckUpdate no-update response);
    // fall back to current_version for backward compatibility.
    final currentVersion = (state.info['current_main_version'] as String? ??
        state.info['current_version'] as String? ?? '');
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14.r),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 36.w,
                  height: 36.w,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(Icons.devices_rounded, size: 18.sp, color: AppColors.primary),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.currentDevice, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      SizedBox(height: 2.h),
                      Text(widget.deviceSN, style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (currentVersion.isNotEmpty) ...[          SizedBox(height: 16.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Text(l10n.str('current_version_label', {'version': currentVersion}),
                  style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
            ),
          ],
          // 芯片固件版本明细
          if ((state.info['firmware_esp'] as String? ?? '').isNotEmpty ||
              (state.info['firmware_dsp'] as String? ?? '').isNotEmpty ||
              (state.info['firmware_bms'] as String? ?? '').isNotEmpty) ...[  SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 4.h),
                    child: Text('芯片固件版本', style: TextStyle(fontSize: 12.sp, color: AppColors.textHint, fontWeight: FontWeight.w500)),
                  ),
                  _buildChipVersionRow('ESP', state.info['firmware_esp'] as String? ?? ''),
                  if ((state.info['firmware_dsp'] as String? ?? '').isNotEmpty)
                    _buildChipVersionRow('DSP', state.info['firmware_dsp'] as String? ?? ''),
                  if ((state.info['firmware_bms'] as String? ?? '').isNotEmpty)
                    _buildChipVersionRow('BMS', state.info['firmware_bms'] as String? ?? ''),
                ],
              ),
            ),
          ],
          SizedBox(height: 16.h),
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: AppColors.successLight.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 20.sp, color: AppColors.successLight),
                SizedBox(width: 8.w),
                Text(l10n.alreadyLatest, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.successLight)),
              ],
            ),
          ),
          // 查看可用升级包入口
          Padding(
            padding: EdgeInsets.only(top: 16.h),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final deviceModel = state.info['device_model'] as String? ?? '';
                  final mainVer = state.info['current_main_version'] as String? ??
                      state.info['current_version'] as String? ?? '';
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BlocProvider.value(
                        value: context.read<OtaBloc>(),
                        child: FirmwareListPage(
                          sn: widget.deviceSN,
                          deviceModel: deviceModel,
                          currentMainVersion: mainVer,
                        ),
                      ),
                    ),
                  );
                },
                icon: Icon(Icons.history_rounded, size: 18.sp),
                label: Text('查看可用升级包', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTriggering() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.primary)),
          SizedBox(height: 16.h),
          Text(l10n.sendingUpgradeCommand, style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildProgress(OTAProgress state) {
    final l10n = AppLocalizations.of(context)!;
    final percent = state.progress.clamp(0.0, 100.0).toStringAsFixed(0);
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: 40.h),
          Icon(Icons.system_update_rounded, size: 64.sp, color: AppColors.primary),
          SizedBox(height: 24.h),
          Text(l10n.deviceUpgrading, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 8.h),
          Text('${l10n.str('status_prefix')}: ${_localizedStatus(state.status, l10n)}', style: TextStyle(fontSize: 13.sp, color: AppColors.textHint)),
          SizedBox(height: 24.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(8.r),
            child: LinearProgressIndicator(
              value: state.progress > 0 ? state.progress.clamp(0.0, 100.0) / 100.0 : null,
              minHeight: 8.h,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          SizedBox(height: 8.h),
          Text('$percent%', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700, color: AppColors.primary)),
          SizedBox(height: 40.h),
        ],
      ),
    );
  }

  Widget _buildComplete() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 64.sp, color: AppColors.successLight),
          SizedBox(height: 16.h),
          Text(l10n.upgradeComplete, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 24.h),
          ElevatedButton(
            onPressed: () {
              context.read<OtaBloc>().add(OTACheckRequested(sn: widget.deviceSN));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            ),
            child: Text(l10n.back),
          ),
        ],
      ),
    );
  }
}

