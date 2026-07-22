import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/firmware_download_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/ota/presentation/bloc/ota_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirmwareListPage extends StatefulWidget {
  final String sn;
  final String deviceModel;
  final String currentMainVersion;

  const FirmwareListPage({
    super.key,
    required this.sn,
    required this.deviceModel,
    required this.currentMainVersion,
  });

  @override
  State<FirmwareListPage> createState() => _FirmwareListPageState();
}

class _FirmwareListPageState extends State<FirmwareListPage> {
  final FirmwareDownloadService _downloadService = FirmwareDownloadService(
    getIt<Dio>(),
    getIt<SharedPreferences>(),
  );

  // 跟踪每个package的下载状态
  final Map<int, bool> _downloadedCache = {};
  final Map<int, double> _downloadingProgress = {};
  final Set<int> _downloadingIds = {};
  final Set<int> _checkedDownloadIds = {};

  @override
  void initState() {
    super.initState();
    _requestList();
  }

  @override
  void dispose() {
    _downloadService.dispose();
    super.dispose();
  }

  void _requestList() {
    context.read<OtaBloc>().add(
          LoadAvailablePackages(sn: widget.sn),
        );
  }

  /// 恢复升级包的下载状态（从 SharedPreferences 持久化记录中检查）
  Future<void> _restorePackageDownloadState(dynamic pkg) async {
    final packageId = (pkg is Map) ? (pkg['id'] as int? ?? 0) : 0;
    if (_checkedDownloadIds.contains(packageId)) return;
    _checkedDownloadIds.add(packageId);

    final chips = (pkg is Map && pkg['chips'] is List)
        ? (pkg['chips'] as List)
        : (pkg is Map && pkg['items'] is List)
            ? (pkg['items'] as List)
            : <dynamic>[];

    if (chips.isEmpty) return;

    bool allDownloaded = true;
    for (final chip in chips) {
      if (chip is Map) {
        final firmwareId = chip['firmware_id'] as int? ?? 0;
        if (firmwareId > 0) {
          final downloaded =
              await _downloadService.isFirmwareDownloaded(firmwareId);
          if (!downloaded) {
            allDownloaded = false;
            break;
          }
        }
      }
    }

    if (allDownloaded && mounted) {
      setState(() {
        _downloadedCache[packageId] = true;
      });
    }
  }

  /// 预下载升级包中的所有固件
  Future<void> _preDownloadPackage(dynamic pkg) async {
    // 后端返回chips字段，前端也兼容items字段
    final chips = (pkg is Map && pkg['chips'] is List)
        ? (pkg['chips'] as List)
        : (pkg is Map && pkg['items'] is List)
            ? (pkg['items'] as List)
            : <dynamic>[];

    if (chips.isEmpty) {
      debugPrint('[PreDownload] No chips found in package: $pkg');
      return;
    }

    final packageId = (pkg is Map) ? (pkg['id'] as int? ?? 0) : 0;

    setState(() {
      _downloadingIds.add(packageId);
      _downloadingProgress[packageId] = 0.0;
    });

    _downloadService.downloadProgressStream.listen((progress) {
      if (_downloadingIds.contains(packageId) && mounted) {
        setState(() {
          _downloadingProgress[packageId] = progress;
        });
      }
    });

    try {
      int downloadedCount = 0;
      final totalItems = chips.length;

      for (final chip in chips) {
        if (chip is Map) {
          final firmwareId = chip['firmware_id'] as int? ?? 0;
          final downloadUrl = chip['download_url'] as String? ?? '';
          final chipName = chip['target_chip'] as String? ?? 'firmware';
          final version = chip['firmware_version'] as String? ?? '';
          final fileName = '${chipName}_$version.bin';

          debugPrint(
            '[PreDownload] Chip: $chipName, firmwareId: $firmwareId, url: $downloadUrl',
          );

          if (firmwareId > 0 && downloadUrl.isNotEmpty) {
            // 检查是否已下载
            final alreadyDownloaded =
                await _downloadService.isFirmwareDownloaded(firmwareId);
            if (!alreadyDownloaded) {
              await _downloadService.downloadFirmware(
                url: downloadUrl,
                fileName: fileName,
                firmwareId: firmwareId,
                expectedSize: (chip['file_size'] as num?)?.toInt(),
                expectedSha256: chip['file_sha256'] as String?,
              );
            }
            downloadedCount++;

            // 更新进度
            if (mounted) {
              setState(() {
                _downloadingProgress[packageId] = downloadedCount / totalItems;
              });
            }
          } else {
            debugPrint(
              '[PreDownload] Skipping chip $chipName: invalid firmwareId or downloadUrl',
            );
          }
        }
      }

      if (mounted) {
        setState(() {
          _downloadedCache[packageId] = true;
          _downloadingIds.remove(packageId);
        });

        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.str('downloaded')),
            backgroundColor: AppColors.successLight,
          ),
        );
      }
    } catch (e) {
      debugPrint('[PreDownload] Error: $e');
      if (mounted) {
        setState(() {
          _downloadingIds.remove(packageId);
        });

        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.str('pre_download_failed', {'error': '$e'})),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Compare version strings like "V3.0.2.20250601".
  /// Returns -1 if a < b, 0 if equal, 1 if a > b.
  int _compareVersions(String a, String b) {
    List<int> parseSegments(String v) {
      final cleaned =
          v.startsWith('V') || v.startsWith('v') ? v.substring(1) : v;
      return cleaned.split('.').map((s) => int.tryParse(s) ?? 0).toList();
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
    if (widget.currentMainVersion.isEmpty) return false;
    final current = _normalizeVersion(widget.currentMainVersion);
    return _compareVersions(packageVersion, current) < 0;
  }

  bool _isCurrentVersion(String packageVersion) {
    if (widget.currentMainVersion.isEmpty) return false;
    final current = _normalizeVersion(widget.currentMainVersion);
    return _compareVersions(packageVersion, current) == 0;
  }

  void _installPackage(BuildContext context, int packageId, String version) {
    final l10n = AppLocalizations.of(context)!;
    if (_isRollback(version)) {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning_rounded, color: AppColors.warning),
              SizedBox(width: 8.w),
              Text(
                l10n.warningLevel,
                style: const TextStyle(color: AppColors.warning),
              ),
            ],
          ),
          content: Text(
            l10n.oldVersionWarning(version),
            style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
              child: Text(l10n.confirmInstall),
            ),
          ],
        ),
      ).then((confirmed) {
        if (confirmed == true && context.mounted) {
          // 使用 package_id 触发升级 (POST /ota/trigger)
          context.read<OtaBloc>().add(
                OTATriggerRequested(sn: widget.sn, packageId: packageId),
              );
        }
      });
    } else {
      // 使用 package_id 触发升级 (POST /ota/trigger)
      context.read<OtaBloc>().add(
            OTATriggerRequested(sn: widget.sn, packageId: packageId),
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
            l10n.firmwareList,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
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
          if (state is OTATriggered ||
              state is OTAProgress ||
              state is OTAComplete) {
            Navigator.pop(context);
          }
        },
        buildWhen: (prev, curr) =>
            curr is OTAAvailablePackagesLoading ||
            curr is OTAAvailablePackagesLoaded ||
            curr is OTAAvailablePackagesError ||
            curr is OTAFirmwareInstalling ||
            curr is OTATriggered,
        builder: (context, state) {
          // Initial kick
          if (state is OTAInitial ||
              state is OTAUpToDate ||
              state is OTAUpdateAvailable) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) _requestList();
            });
          }

          if (state is OTAAvailablePackagesLoading ||
              state is OTAFirmwareInstalling) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    state is OTAFirmwareInstalling
                        ? l10n.installingFirmware
                        : l10n.loadingUpgradeList,
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          if (state is OTAAvailablePackagesError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 48.sp,
                    color: AppColors.error,
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    l10n.translateError(state.message),
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 20.h),
                  ElevatedButton(
                    onPressed: () => _requestList(),
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

          if (state is OTAAvailablePackagesLoaded) {
            final packages = state.packages;
            if (packages.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 56.sp,
                      color: AppColors.textHint,
                    ),
                    SizedBox(height: 12.h),
                    Text(
                      l10n.noUpgradesAvailable,
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: AppColors.textSecondary,
                      ),
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
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: EdgeInsets.all(16.w),
      children: [
        // Current version card
        if (widget.currentMainVersion.isNotEmpty)
          Container(
            padding: EdgeInsets.all(14.w),
            margin: EdgeInsets.only(bottom: 16.h),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(
                color: AppColors.successLight.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 20.sp,
                  color: AppColors.successLight,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.currentVersionLabel,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.successLight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        widget.currentMainVersion,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.check_circle_rounded,
                  size: 22.sp,
                  color: AppColors.successLight,
                ),
              ],
            ),
          ),

        // Package cards
        ...packages.map((pkg) => _buildPackageCard(context, pkg)),
      ],
    );
  }

  Widget _buildPackageCard(BuildContext context, dynamic pkg) {
    final l10n = AppLocalizations.of(context)!;
    final id = (pkg is Map) ? (pkg['id'] as int? ?? 0) : 0;
    // 优先使用 user_version，回退到 main_version
    final userVersion =
        (pkg is Map) ? (pkg['user_version'] as String? ?? '') : '';
    final mainVersion =
        (pkg is Map) ? (pkg['main_version'] as String? ?? '') : '';
    final displayVersion = userVersion.isNotEmpty ? userVersion : mainVersion;
    // 优先使用 user_changelog，回退到 changelog
    final userChangelog =
        (pkg is Map) ? (pkg['user_changelog'] as String? ?? '') : '';
    final changelog = (pkg is Map) ? (pkg['changelog'] as String? ?? '') : '';
    final displayChangelog =
        userChangelog.isNotEmpty ? userChangelog : changelog;
    final isForce = (pkg is Map) ? (pkg['is_force'] as bool? ?? false) : false;
    final createdAtRaw =
        (pkg is Map) ? (pkg['created_at'] as String? ?? '') : '';
    // 后端返回chips字段，前端也兼容items字段
    final items = (pkg is Map && pkg['chips'] is List)
        ? (pkg['chips'] as List)
        : (pkg is Map && pkg['items'] is List)
            ? (pkg['items'] as List)
            : <dynamic>[];

    final isCurrent = _isCurrentVersion(displayVersion);
    final isRollbackVer = _isRollback(displayVersion);

    // Format date
    final dateStr = _formatDate(createdAtRaw);

    final borderColor = isCurrent
        ? AppColors.successLight.withValues(alpha: 0.5)
        : const Color(0xFFE5E7EB);

    // 在 build 过程中触发异步状态恢复（仅执行一次）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restorePackageDownloadState(pkg);
    });

    // 检查下载状态
    final isDownloaded = _downloadedCache[id] ?? false;
    final isDownloading = _downloadingIds.contains(id);
    final downloadProgress = _downloadingProgress[id] ?? 0.0;

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
          // Header: version + badges
          Row(
            children: [
              Expanded(
                child: Text(
                  displayVersion.isNotEmpty ? displayVersion : 'Unknown',
                  style: TextStyle(
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (isForce)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  margin: EdgeInsets.only(right: 6.w),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    l10n.forceUpgrade,
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                ),
              if (isCurrent)
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: AppColors.successLight.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    l10n.currentVersionLabel,
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
                final chip = ((item is Map)
                        ? (item['target_chip'] as String? ?? '')
                        : '')
                    .toUpperCase();
                final fwVer = (item is Map)
                    ? (item['firmware_version'] as String? ?? '-')
                    : '-';
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
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          // Changelog (user_changelog)
          if (displayChangelog.isNotEmpty) ...[
            SizedBox(height: 10.h),
            Text(
              displayChangelog,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.sp,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],

          // Footer: date + buttons
          SizedBox(height: 12.h),
          Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 14.sp,
                color: AppColors.textHint,
              ),
              SizedBox(width: 4.w),
              Text(
                dateStr,
                style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
              ),
              const Spacer(),
              if (!isCurrent) ...[
                // 预下载/本地安装按钮
                if (isDownloading)
                  SizedBox(
                    width: 80.w,
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4.r),
                          child: LinearProgressIndicator(
                            value:
                                downloadProgress > 0 ? downloadProgress : null,
                            minHeight: 4.h,
                            backgroundColor: const Color(0xFFE5E7EB),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.primary,
                            ),
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          downloadProgress > 0
                              ? '${(downloadProgress * 100).toStringAsFixed(0)}%'
                              : l10n.downloading,
                          style: TextStyle(
                            fontSize: 10.sp,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (isDownloaded)
                  GestureDetector(
                    onTap: () => _navigateToLocalOTA(pkg),
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        color: AppColors.successLight,
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        l10n.localUpgrade,
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => _preDownloadPackage(pkg),
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(8.r),
                        border: Border.all(color: AppColors.primary),
                      ),
                      child: Text(
                        l10n.preDownload,
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                SizedBox(width: 8.w),
                // 安装按钮
                _buildInstallButton(context, id, displayVersion, isRollbackVer),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstallButton(
    BuildContext context,
    int packageId,
    String version,
    bool isRollbackVer,
  ) {
    final l10n = AppLocalizations.of(context)!;
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
          l10n.installThisVersion,
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

  /// 跳转到本地OTA安装页面
  void _navigateToLocalOTA(dynamic pkg) {
    final chips = (pkg is Map && pkg['chips'] is List)
        ? (pkg['chips'] as List)
        : (pkg is Map && pkg['items'] is List)
            ? (pkg['items'] as List)
            : <dynamic>[];

    if (chips.isEmpty) return;

    final validChips = chips.where((chip) {
      if (chip is! Map) return false;
      final firmwareId = chip['firmware_id'] as int? ?? 0;
      final downloadUrl = chip['download_url'] as String? ?? '';
      return firmwareId > 0 && downloadUrl.isNotEmpty;
    }).toList();

    if (validChips.isEmpty) return;

    if (validChips.length == 1) {
      _jumpToLocalOTA(validChips[0] as Map);
    } else {
      _showChipSelectionDialog(validChips);
    }
  }

  /// 执行实际的路由跳转到 LocalOTAPage
  void _jumpToLocalOTA(Map chip) {
    final firmwareId = chip['firmware_id'] as int? ?? 0;
    final downloadUrl = chip['download_url'] as String? ?? '';
    final chipName = chip['target_chip'] as String? ?? 'firmware';
    final version = chip['firmware_version'] as String? ?? '';
    final fileName = '${chipName}_$version.bin';

    final route = Uri(
      path: '/ota/${widget.sn}/local',
      queryParameters: {
        'ip': '192.168.4.1',
        'firmware_id': '$firmwareId',
        'firmware_url': downloadUrl,
        'firmware_file_name': fileName,
        'target_chip': chipName.toLowerCase(),
        'firmware_version': version,
        'file_sha256': chip['file_sha256'] as String? ?? '',
        'security_version':
            '${(chip['security_version'] as num?)?.toInt() ?? 0}',
        'release_signature': chip['release_signature'] as String? ?? '',
      },
    ).toString();
    context.push(route);
  }

  /// 显示芯片选择对话框
  void _showChipSelectionDialog(List<dynamic> validChips) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            l10n.selectFirmware,
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: validChips.map((chip) {
              final chipMap = chip as Map;
              final chipName =
                  (chipMap['target_chip'] as String? ?? '').toUpperCase();
              final fwVer = chipMap['firmware_version'] as String? ?? '-';
              return ListTile(
                leading: Container(
                  width: 36.w,
                  height: 36.w,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Center(
                    child: Text(
                      chipName.isNotEmpty ? chipName.substring(0, 1) : '?',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  chipName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14.sp,
                  ),
                ),
                subtitle: Text(
                  'v$fwVer',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _jumpToLocalOTA(chipMap);
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
          ],
        );
      },
    );
  }
}
