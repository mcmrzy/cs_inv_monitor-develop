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
    context.read<OtaBloc>().add(const OTAFirmwareListRequested());
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
              state is OTAUpToDate ||
              state is OTAFirmwareListLoaded;
          if (hasContent) {
            // 有更新可用时，不被固件列表状态覆盖
            if (state is OTAFirmwareListLoaded && _cachedState is OTAUpdateAvailable) {
              // 保留 OTAUpdateAvailable 状态
            } else {
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
            return _buildUpToDate();
          }
          if (_cachedState is OTAFirmwareListLoaded) {
            return _buildFirmwareList(_cachedState as OTAFirmwareListLoaded);
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
    final l10n = AppLocalizations.of(context)!;
    final info = state.info;
    final firmwareId = info['firmware_id'] as int? ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreDownloadState(firmwareId));
    final latestVersion = info['version'] as String? ?? l10n.unknown;
    final currentVersion = info['current_version'] as String? ?? '';
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
                Text(l10n.str('latest_version_label', {'version': latestVersion}), style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                if (currentVersion.isNotEmpty)
                  Text(l10n.str('current_version_label', {'version': currentVersion}), style: TextStyle(fontSize: 13.sp, color: AppColors.textHint)),
              ],
            ),
          ),
          SizedBox(height: 24.h),
          SizedBox(
            width: double.infinity,
            height: 48.h,
            child: ElevatedButton(
              onPressed: _triggering ? null : () {
                setState(() => _triggering = true);
                context.read<OtaBloc>().add(OTATriggerRequested(sn: widget.deviceSN, firmwareId: firmwareId));
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
        ],
      ),
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

  Widget _buildFirmwareList(OTAFirmwareListLoaded state) {
    final l10n = AppLocalizations.of(context)!;
    final firmwares = state.firmwares;

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
          SizedBox(height: 16.h),
          Text(l10n.firmwareList, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          SizedBox(height: 8.h),
          Expanded(
            child: firmwares.isEmpty
                ? Center(child: Text(l10n.noFirmware, style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)))
                : ListView.builder(
                    itemCount: firmwares.length,
                    itemBuilder: (context, index) {
                      final fw = firmwares[index] as Map<String, dynamic>;
                      final firmwareId = fw['id'] as int? ?? 0;
                      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreDownloadState(firmwareId));
                      final version = fw['version'] as String? ?? l10n.unknown;
                      final downloadUrl = fw['download_url'] as String? ?? '';
                      final fileName = fw['file_name'] as String? ?? 'firmware_$firmwareId.bin';
                      final size = fw['size'] as int? ?? 0;
                      final sizeStr = size > 0 ? '${(size / 1024 / 1024).toStringAsFixed(1)} MB' : '';

                      return Padding(
                        padding: EdgeInsets.only(bottom: 8.h),
                        child: _buildFirmwareItem(firmwareId, version, downloadUrl, fileName, sizeStr),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFirmwareItem(int firmwareId, String version, String downloadUrl, String fileName, String sizeStr) {
    final l10n = AppLocalizations.of(context)!;
    final isDownloaded = _downloadedCache[firmwareId] ?? false;
    final isDownloading = _downloadingIds.contains(firmwareId);
    final progress = _downloadingProgress[firmwareId] ?? 0.0;

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36.w,
                height: 36.w,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(Icons.description_rounded, size: 18.sp, color: AppColors.primary),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('v$version', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    if (sizeStr.isNotEmpty)
                      Text(sizeStr, style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
                  ],
                ),
              ),
              if (isDownloaded)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 12.sp, color: AppColors.successLight),
                      SizedBox(width: 3.w),
                      Text(l10n.downloaded, style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: AppColors.successLight)),
                    ],
                  ),
                ),
            ],
          ),
          if (isDownloading) ...[
            SizedBox(height: 8.h),
            ClipRRect(
              borderRadius: BorderRadius.circular(6.r),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                minHeight: 4.h,
                backgroundColor: const Color(0xFFE5E7EB),
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              progress > 0 ? '${l10n.downloading} ${(progress * 100).toStringAsFixed(0)}%' : '${l10n.downloading}...',
              style: TextStyle(fontSize: 10.sp, color: AppColors.primary),
            ),
          ],
          SizedBox(height: 10.h),
          Row(
            children: [
              if (!isDownloaded && !isDownloading)
                Expanded(
                  child: SizedBox(
                    height: 36.h,
                    child: OutlinedButton(
                      onPressed: downloadUrl.isNotEmpty ? () => _startPreDownload(firmwareId, downloadUrl, fileName) : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(l10n.preDownload, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              if (isDownloaded) ...[
                Expanded(
                  child: SizedBox(
                    height: 36.h,
                    child: ElevatedButton(
                      onPressed: () {
                        context.push(
                          '/ota/${widget.deviceSN}/local?ip=192.168.4.1&firmware_id=$firmwareId&firmware_url=${Uri.encodeComponent(downloadUrl)}&firmware_file_name=${Uri.encodeComponent(fileName)}',
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                        elevation: 0,
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(l10n.localUpgrade, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUpToDate() {
    final l10n = AppLocalizations.of(context)!;
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
    final percent = (state.progress * 100).toStringAsFixed(0);
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
          Text('${l10n.str('status_prefix')}: ${state.status}', style: TextStyle(fontSize: 13.sp, color: AppColors.textHint)),
          SizedBox(height: 24.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(8.r),
            child: LinearProgressIndicator(
              value: state.progress > 0 ? state.progress : null,
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
