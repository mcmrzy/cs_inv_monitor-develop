import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/firmware_download_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/features/ota/presentation/bloc/ota_bloc.dart';
import 'package:inv_app/features/ota/presentation/pages/firmware_list_page.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class OTAPage extends StatefulWidget {
  final String deviceSN;

  const OTAPage({super.key, required this.deviceSN});

  @override
  State<OTAPage> createState() => _OTAPageState();
}

class _OTAPageState extends State<OTAPage> {
  // 应用级单例：并发守卫与进度流跨页面共享，页面退出不再 dispose
  final FirmwareDownloadService _downloadService =
      getIt<FirmwareDownloadService>();

  final Map<int, bool> _downloadedCache = {};
  final Map<int, double> _downloadingProgress = {};
  final Set<int> _downloadingIds = {};

  /// 下载进度订阅（页面生命周期内单一订阅，dispose 时 cancel）
  StreamSubscription<DownloadProgressEvent>? _progressSub;

  OtaState? _cachedState;
  bool _triggering = false;
  final Set<int> _checkedDownloadIds = {};

  @override
  void initState() {
    super.initState();
    context.read<OtaBloc>().add(OTACheckRequested(sn: widget.deviceSN));
    // 单一进度订阅：按 firmwareId 过滤，避免每次点下载新增订阅导致泄漏
    _progressSub = _downloadService.progressStream.listen((event) {
      if (!mounted || !_downloadingIds.contains(event.firmwareId)) return;
      setState(() {
        _downloadingProgress[event.firmwareId] = event.progress;
      });
    });
  }

  Future<void> _restoreDownloadState(int firmwareId) async {
    if (_checkedDownloadIds.contains(firmwareId)) return;
    _checkedDownloadIds.add(firmwareId);
    final downloaded = await _downloadService.isFirmwareDownloaded(firmwareId);
    if (downloaded && mounted) {
      setState(() => _downloadedCache[firmwareId] = true);
    }
  }

  /// 恢复升级包模式的下载状态（遍历包内所有芯片固件，全部已下载才标记已下载）。
  /// 与单固件模式共用 [_checkedDownloadIds] 防重复检查。
  Future<void> _restorePackageDownloadState(Map<String, dynamic> info) async {
    final firmwareId = info['firmware_id'] as int? ?? 0;
    if (firmwareId <= 0) return;
    if (_checkedDownloadIds.contains(firmwareId)) return;
    _checkedDownloadIds.add(firmwareId);

    // 兼容后端字段：chips_to_upgrade（check-update 返回）/ chips / items
    final chips = (info['chips_to_upgrade'] is List)
        ? (info['chips_to_upgrade'] as List)
        : (info['chips'] is List)
            ? (info['chips'] as List)
            : (info['items'] is List)
                ? (info['items'] as List)
                : <dynamic>[];

    if (chips.isEmpty) return;

    bool allDownloaded = true;
    for (final chip in chips) {
      if (chip is Map) {
        final chipFirmwareId = chip['firmware_id'] as int? ?? 0;
        if (chipFirmwareId > 0) {
          final downloaded =
              await _downloadService.isFirmwareDownloaded(chipFirmwareId);
          if (!downloaded) {
            allDownloaded = false;
            break;
          }
        }
      }
    }

    if (allDownloaded && mounted) {
      setState(() {
        _downloadedCache[firmwareId] = true;
      });
    }
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    // 下载服务是应用级单例，不随页面 dispose
    super.dispose();
  }

  Future<void> _startPreDownload(
    int firmwareId,
    String url,
    String fileName, {
    int? expectedSize,
    String? expectedSha256,
    String? targetChip,
    String? firmwareVersion,
    String? releaseSignature,
    int? securityVersion,
  }) async {
    setState(() {
      _downloadingIds.add(firmwareId);
      _downloadingProgress[firmwareId] = 0.0;
    });

    try {
      await _downloadService.downloadFirmware(
        url: url,
        fileName: fileName,
        firmwareId: firmwareId,
        expectedSize: expectedSize,
        expectedSha256: expectedSha256,
        // 持久化离线升级元数据，支持无网时从已下载列表直接本地升级
        targetChip: targetChip,
        version: firmwareVersion,
        signature: releaseSignature,
        securityVersion: securityVersion,
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
        AppToast.show(context, l10n.str('pre_download_failed', {'error': '$e'}), type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(
        title: Text(
          l10n.otaTitle,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColor.surfaceContainer(context),
        foregroundColor: AppColor.textPrimary(context),
      ),
      body: BlocListener<OtaBloc, OtaState>(
        // 状态副作用（缓存/标志位/Toast）统一放 Listener，
        // 避免在 build 期间写可变状态导致 UI 竞态
        listener: (context, state) {
          if (state is OTAUpdateAvailable || state is OTAUpToDate) {
            _cachedState = state;
          }
          if (state is OTATriggered ||
              state is OTAProgress ||
              state is OTAComplete) {
            _triggering = false;
          }
          if (state is OTAError && _cachedState != null) {
            _triggering = false;
            AppToast.show(
              context,
              AppLocalizations.of(context)!.translateError(state.message),
              type: ToastType.error,
            );
          }
        },
        child: BlocBuilder<OtaBloc, OtaState>(
          builder: (context, state) {
            // 升级进行中或已完成
            if (state is OTAProgress) {
              return _buildProgress(state);
            }
            if (state is OTAComplete) {
              return _buildComplete();
            }
            if (state is OTATriggering || state is OTATriggered) {
              return _buildTriggering();
            }

            if (_cachedState is OTAUpdateAvailable) {
              return _buildUpdateAvailable(_cachedState as OTAUpdateAvailable);
            }
            if (_cachedState is OTAUpToDate) {
              return _buildUpToDate(_cachedState as OTAUpToDate);
            }
            if (state is OTAError) {
              // 小烁警告动作插画：升级查询失败/离线态（美术路由 C6/ota-failure）
              return XiaoshuoStatePanel(
                asset: CsergyAssets.xiaoshuoWarning,
                title:
                    AppLocalizations.of(context)!.translateError(state.message),
                message: l10n.loadFailed,
                size: 176,
                action: ElevatedButton(
                  onPressed: () {
                    context
                        .read<OtaBloc>()
                        .add(OTACheckRequested(sn: widget.deviceSN));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(l10n.retry),
                ),
              );
            }

            return _buildSkeletonBody();
          },
        ),
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _restoreDownloadState(firmwareId));
    final latestVersion = info['version'] as String? ?? l10n.unknown;
    final currentVersion = info['current_version'] as String? ?? '';
    final targetChip = (info['target_chip'] as String? ?? '').toUpperCase();
    final downloadUrl = info['download_url'] as String? ?? '';
    final fileName = info['file_name'] as String? ?? 'firmware_$firmwareId.bin';
    final fileSize = (info['file_size'] as num?)?.toInt();
    final fileSha256 = info['file_sha256'] as String?;
    final securityVersion = (info['security_version'] as num?)?.toInt();
    final releaseSignature = info['release_signature'] as String?;

    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
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
                        l10n.currentDevice,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColor.textPrimary(context),
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        widget.deviceSN,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
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
              color: AppColor.primarySoft(context),
              borderRadius: BorderRadius.circular(14.r),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.system_update_rounded,
                      size: 20.sp,
                      color: AppColors.primary,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      l10n.newVersionFound,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8.h),
                Text(
                  '${l10n.str('latest_version_label', {
                        'version': latestVersion,
                      })}${targetChip.isNotEmpty ? ' ($targetChip)' : ''}',
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColor.textSecondary(context),
                  ),
                ),
                if (currentVersion.isNotEmpty)
                  Text(
                    '${l10n.str('current_version_label', {
                          'version': currentVersion,
                        })}${targetChip.isNotEmpty ? ' ($targetChip)' : ''}',
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColor.textHint(context),
                    ),
                  ),
              ],
            ),
          ),
          // 芯片固件版本明细
          if ((info['firmware_esp'] as String? ?? '').isNotEmpty ||
              (info['firmware_dsp'] as String? ?? '').isNotEmpty ||
              (info['firmware_bms'] as String? ?? '').isNotEmpty) ...[
            SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: AppColor.surfaceContainer(context),
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: AppColor.border(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 4.h),
                    child: Text(
                      l10n.chipFirmwareVersion,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColor.textHint(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  _buildChipVersionRow(
                    'ESP',
                    info['firmware_esp'] as String? ?? '',
                  ),
                  if ((info['firmware_dsp'] as String? ?? '').isNotEmpty)
                    _buildChipVersionRow(
                      'DSP',
                      info['firmware_dsp'] as String? ?? '',
                    ),
                  if ((info['firmware_bms'] as String? ?? '').isNotEmpty)
                    _buildChipVersionRow(
                      'BMS',
                      info['firmware_bms'] as String? ?? '',
                    ),
                ],
              ),
            ),
          ],
          SizedBox(height: 24.h),
          SizedBox(
            width: double.infinity,
            height: 48.h,
            child: ElevatedButton(
              onPressed: _triggering
                  ? null
                  : () {
                      setState(() => _triggering = true);
                      // 使用 package_id 触发升级（后端已改为 package_id）
                      context.read<OtaBloc>().add(
                            OTATriggerRequested(
                              sn: widget.deviceSN,
                              packageId: firmwareId,
                            ),
                          );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _triggering ? AppColor.textHint(context) : AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                elevation: 0,
              ),
              child: _triggering
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      l10n.startUpgrade,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          SizedBox(height: 12.h),
          _buildPreDownloadButton(
            firmwareId,
            downloadUrl,
            fileName,
            fileSize,
            fileSha256,
            targetChip,
            latestVersion,
            securityVersion,
            releaseSignature,
          ),
          // 查看可用升级包入口
          Padding(
            padding: EdgeInsets.only(top: 12.h),
            child: Center(
              child: TextButton.icon(
                onPressed: () {
                  final deviceModel = info['device_model'] as String? ?? '';
                  final mainVer = info['current_main_version'] as String? ??
                      info['current_version'] as String? ??
                      '';
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
                label: Text(
                  l10n.viewAvailableUpgrades,
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColor.textSecondary(context),
                ),
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _restorePackageDownloadState(info));
    final chipsToUpgrade = (info['chips_to_upgrade'] as List?) ?? [];
    final changelog = info['changelog'] as String? ?? '';

    // 从chips_to_upgrade中提取下载信息用于预下载
    String downloadUrl = '';
    String fileName = 'firmware_$firmwareId.bin';
    int? fileSize;
    String? fileSha256;
    String targetChip = '';
    String firmwareVersion = '';
    int? securityVersion;
    String? releaseSignature;

    if (chipsToUpgrade.isNotEmpty) {
      final firstChip = chipsToUpgrade[0] as Map<String, dynamic>;
      downloadUrl = firstChip['download_url'] as String? ?? '';
      final chipName = firstChip['chip'] ?? 'firmware';
      final target = firstChip['target'] ?? '';
      fileName = '${chipName}_$target.bin';
      fileSize = (firstChip['file_size'] as num?)?.toInt();
      fileSha256 = firstChip['file_sha256'] as String?;
      targetChip =
          (firstChip['target_chip'] ?? firstChip['chip'] ?? '') as String;
      firmwareVersion = (firstChip['firmware_version'] ??
          firstChip['target'] ??
          '') as String;
      securityVersion = (firstChip['security_version'] as num?)?.toInt();
      releaseSignature = firstChip['release_signature'] as String?;
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
                        l10n.currentDevice,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColor.textPrimary(context),
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        widget.deviceSN,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
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
              color: AppColor.primarySoft(context),
              borderRadius: BorderRadius.circular(14.r),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.system_update_rounded,
                      size: 20.sp,
                      color: AppColors.primary,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      l10n.newVersionFound,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8.h),
                Text(
                  l10n.str('latest_version_label', {'version': mainVersion}),
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColor.textSecondary(context),
                  ),
                ),
                if (currentMainVersion.isNotEmpty)
                  Text(
                    l10n.str(
                      'current_version_label',
                      {'version': currentMainVersion},
                    ),
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColor.textHint(context),
                    ),
                  ),
              ],
            ),
          ),
          // Chips to upgrade
          if (chipsToUpgrade.isNotEmpty) ...[
            SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: AppColor.surfaceContainer(context),
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: AppColor.border(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.str('chips_to_upgrade_label'),
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColor.textPrimary(context),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  ...chipsToUpgrade.map((chip) {
                    final chipName =
                        (chip['chip'] as String? ?? '').toUpperCase();
                    final current = chip['current'] as String? ?? '-';
                    final target = chip['target'] as String? ?? '-';
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 2.h),
                      child: Row(
                        children: [
                          _buildChipTag(
                            label: chipName,
                            color: AppColors.primary,
                          ),
                          SizedBox(width: 8.w),
                          Text(
                            '$current → $target',
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: AppColor.textSecondary(context),
                            ),
                          ),
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
              (info['firmware_bms'] as String? ?? '').isNotEmpty) ...[
            SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: AppColor.surfaceContainer(context),
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: AppColor.border(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 4.h),
                    child: Text(
                      l10n.currentFirmwareVersion,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColor.textHint(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  _buildChipVersionRow(
                    'ESP',
                    info['firmware_esp'] as String? ?? '',
                  ),
                  if ((info['firmware_dsp'] as String? ?? '').isNotEmpty)
                    _buildChipVersionRow(
                      'DSP',
                      info['firmware_dsp'] as String? ?? '',
                    ),
                  if ((info['firmware_bms'] as String? ?? '').isNotEmpty)
                    _buildChipVersionRow(
                      'BMS',
                      info['firmware_bms'] as String? ?? '',
                    ),
                ],
              ),
            ),
          ],
          // Changelog
          if (changelog.isNotEmpty) ...[
            SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.all(12.w),
              width: double.infinity, // 确保占满宽度
              decoration: BoxDecoration(
                color: AppColor.surfaceContainer(context),
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: AppColor.border(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.str('changelog'),
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColor.textPrimary(context),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    changelog,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColor.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 24.h),
          SizedBox(
            width: double.infinity,
            height: 48.h,
            child: ElevatedButton(
              onPressed: _triggering
                  ? null
                  : () {
                      setState(() => _triggering = true);
                      context
                          .read<OtaBloc>()
                          .add(OTAPackageTriggerRequested(sn: widget.deviceSN));
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _triggering ? AppColor.textHint(context) : AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                elevation: 0,
              ),
              child: _triggering
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      l10n.startUpgrade,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          SizedBox(height: 12.h),
          _buildPreDownloadButton(
            firmwareId,
            downloadUrl,
            fileName,
            fileSize,
            fileSha256,
            targetChip,
            firmwareVersion,
            securityVersion,
            releaseSignature,
          ),
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
                label: Text(
                  l10n.viewAvailableUpgrades,
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColor.textSecondary(context),
                ),
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
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.sp,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildPreDownloadButton(
    int firmwareId,
    String downloadUrl,
    String fileName,
    int? expectedSize,
    String? expectedSha256,
    String targetChip,
    String firmwareVersion,
    int? securityVersion,
    String? releaseSignature,
  ) {
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
              color: AppColors.badgeNormalBg,
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(
                color: AppColors.successLight.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 16.sp,
                  color: AppColors.successLight,
                ),
                SizedBox(width: 6.w),
                Text(
                  l10n.downloaded,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.successLight,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    // 路由仅携带 firmware_id，升级元数据由页面按 ID 拉取，
                    // 避免在 URL query 中传递签名等复杂参数
                    final route = Uri(
                      path: '/ota/${widget.deviceSN}/local',
                      queryParameters: {
                        'ip': '192.168.4.1',
                        'firmware_id': '$firmwareId',
                      },
                    ).toString();
                    context.push(route);
                  },
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
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
              backgroundColor: AppColor.border(context),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            progress > 0
                ? l10n.str(
                    'pre_downloading_percent',
                    {'percent': (progress * 100).toStringAsFixed(0)},
                  )
                : '${l10n.preDownloading}...',
            style: TextStyle(fontSize: 12.sp, color: AppColors.primary),
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 44.h,
      child: OutlinedButton(
        onPressed: downloadUrl.isNotEmpty
            ? () => _startPreDownload(
                  firmwareId,
                  downloadUrl,
                  fileName,
                  expectedSize: expectedSize,
                  expectedSha256: expectedSha256,
                  targetChip: targetChip,
                  firmwareVersion: firmwareVersion,
                  releaseSignature: releaseSignature,
                  securityVersion: securityVersion,
                )
            : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        ),
        child: Text(
          l10n.preDownloadFirmware,
          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
        ),
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
            child: Text(
              chipName,
              style: TextStyle(
                fontSize: 11.sp,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            version,
            style: TextStyle(fontSize: 12.sp, color: AppColor.textSecondary(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildUpToDate(OTAUpToDate state) {
    final l10n = AppLocalizations.of(context)!;
    // Prefer current_main_version (from CheckUpdate no-update response);
    // fall back to current_version for backward compatibility.
    final currentVersion = (state.info['current_main_version'] as String? ??
        state.info['current_version'] as String? ??
        '');
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
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
                        l10n.currentDevice,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColor.textPrimary(context),
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        widget.deviceSN,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (currentVersion.isNotEmpty) ...[
            SizedBox(height: 16.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: AppColor.surfaceContainer(context),
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: AppColor.border(context)),
              ),
              child: Text(
                l10n.str('current_version_label', {'version': currentVersion}),
                style:
                    TextStyle(fontSize: 13.sp, color: AppColor.textSecondary(context)),
              ),
            ),
          ],
          // 芯片固件版本明细
          if ((state.info['firmware_esp'] as String? ?? '').isNotEmpty ||
              (state.info['firmware_dsp'] as String? ?? '').isNotEmpty ||
              (state.info['firmware_bms'] as String? ?? '').isNotEmpty) ...[
            SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: AppColor.surfaceContainer(context),
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: AppColor.border(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 4.h),
                    child: Text(
                      l10n.chipFirmwareVersion,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColor.textHint(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  _buildChipVersionRow(
                    'ESP',
                    state.info['firmware_esp'] as String? ?? '',
                  ),
                  if ((state.info['firmware_dsp'] as String? ?? '').isNotEmpty)
                    _buildChipVersionRow(
                      'DSP',
                      state.info['firmware_dsp'] as String? ?? '',
                    ),
                  if ((state.info['firmware_bms'] as String? ?? '').isNotEmpty)
                    _buildChipVersionRow(
                      'BMS',
                      state.info['firmware_bms'] as String? ?? '',
                    ),
                ],
              ),
            ),
          ],
          SizedBox(height: 16.h),
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: AppColors.badgeNormalBg,
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(
                color: AppColors.successLight.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 20.sp,
                  color: AppColors.successLight,
                ),
                SizedBox(width: 8.w),
                Text(
                  l10n.alreadyLatest,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.successLight,
                  ),
                ),
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
                  final deviceModel =
                      state.info['device_model'] as String? ?? '';
                  final mainVer =
                      state.info['current_main_version'] as String? ??
                          state.info['current_version'] as String? ??
                          '';
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
                label: Text(
                  l10n.viewAvailableUpgrades,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
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
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.primary,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            l10n.sendingUpgradeCommand,
            style: TextStyle(fontSize: 14.sp, color: AppColor.textSecondary(context)),
          ),
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
          Icon(
            Icons.system_update_rounded,
            size: 64.sp,
            color: AppColors.primary,
          ),
          SizedBox(height: 24.h),
          Text(
            l10n.deviceUpgrading,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
              color: AppColor.textPrimary(context),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '${l10n.str('status_prefix')}: ${_localizedStatus(state.status, l10n)}',
            style: TextStyle(fontSize: 13.sp, color: AppColor.textHint(context)),
          ),
          SizedBox(height: 24.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(8.r),
            child: LinearProgressIndicator(
              value: state.progress > 0
                  ? state.progress.clamp(0.0, 100.0) / 100.0
                  : null,
              minHeight: 8.h,
              backgroundColor: AppColor.border(context),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '$percent%',
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          SizedBox(height: 40.h),
        ],
      ),
    );
  }

  Widget _buildComplete() {
    final l10n = AppLocalizations.of(context)!;
    // 小烁成功动作插画：升级完成态（美术路由 C5/ota-success）
    return XiaoshuoStatePanel(
      asset: CsergyAssets.xiaoshuoSuccess,
      title: l10n.upgradeComplete,
      size: 184,
      action: ElevatedButton(
        onPressed: () {
          context
              .read<OtaBloc>()
              .add(OTACheckRequested(sn: widget.deviceSN));
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
        child: Text(l10n.back),
      ),
    );
  }
}
