import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:inv_app/core/services/firmware_download_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_overview.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:inv_app/features/ota/presentation/models/firmware_module_presentation.dart';

/// 固件库（OTA 升级中心四入口之一）
///
/// 先选择设备，再按模块浏览该设备已发布的固件；支持预下载到本地。
/// 数据源：GET /ota/devices/{sn}/firmware-resources
class FirmwareLibraryPage extends StatefulWidget {
  /// 预选设备 SN（可空）
  final String? initialSn;

  const FirmwareLibraryPage({super.key, this.initialSn});

  @override
  State<FirmwareLibraryPage> createState() => _FirmwareLibraryPageState();
}

class _FirmwareLibraryPageState extends State<FirmwareLibraryPage> {
  final FirmwareDownloadService _downloadService =
      getIt<FirmwareDownloadService>();
  final DeviceRepository _deviceRepo = getIt<DeviceRepository>();
  final OtaRepository _otaRepo = getIt<OtaRepository>();

  List<Map<String, dynamic>> _devices = const [];
  String? _selectedSn;
  String? _selectedModel;
  List<FirmwareResource> _resources = const [];
  bool _loadingDevices = true;
  bool _loadingResources = false;
  String? _deviceError;
  String? _resourceError;

  final Map<int, bool> _downloadedCache = {};
  final Map<int, double> _downloadingProgress = {};
  final Set<int> _downloadingIds = {};

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  String _str(dynamic map, List<String> keys) {
    for (final k in keys) {
      final v = map is Map ? map[k] : null;
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return '';
  }

  Future<void> _loadDevices() async {
    setState(() {
      _loadingDevices = true;
      _deviceError = null;
    });
    final result = await _deviceRepo.getList(page: 1, pageSize: 200);
    if (!mounted) return;
    result.match(
      (failure) => setState(() {
        _loadingDevices = false;
        _deviceError = failure.message;
      }),
      (data) {
        final items = (data['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        setState(() {
          _devices = items;
          _loadingDevices = false;
          if (_selectedSn == null && items.isNotEmpty) {
            final preferred = widget.initialSn;
            final match = preferred == null
                ? null
                : items.where((d) => _str(d, ['sn', 'device_sn']) == preferred);
            if (match != null && match.isNotEmpty) {
              _selectDevice(match.first, loadResources: false);
            } else {
              _selectDevice(items.first, loadResources: false);
            }
          }
        });
        if (_selectedSn != null) {
          _loadResources();
        }
      },
    );
  }

  void _selectDevice(
    Map<String, dynamic> device, {
    bool loadResources = true,
  }) {
    final sn = _str(device, ['sn', 'device_sn']);
    final model = _str(device, ['model', 'device_model']);
    setState(() {
      _selectedSn = sn;
      _selectedModel = model;
      _resources = const [];
      _downloadedCache.clear();
      _downloadingIds.clear();
      _downloadingProgress.clear();
    });
    if (loadResources && sn.isNotEmpty) {
      _loadResources();
    }
  }

  Future<void> _loadResources() async {
    final sn = _selectedSn;
    if (sn == null || sn.isEmpty) return;
    setState(() {
      _loadingResources = true;
      _resourceError = null;
    });
    final result = await _otaRepo.getFirmwareResources(sn);
    if (!mounted) return;
    result.match(
      (failure) => setState(() {
        _loadingResources = false;
        _resourceError = failure.message;
      }),
      (resources) {
        setState(() {
          _resources = resources;
          _loadingResources = false;
        });
        for (final r in resources) {
          _restoreDownloadState(r);
        }
      },
    );
  }

  Future<void> _restoreDownloadState(FirmwareResource r) async {
    if (_downloadedCache.containsKey(r.id)) return;
    final downloaded = await _downloadService.isFirmwareDownloaded(r.id);
    if (mounted && downloaded) {
      setState(() => _downloadedCache[r.id] = true);
    }
  }

  Future<void> _download(FirmwareResource r) async {
    final l10n = AppLocalizations.of(context)!;
    if (r.fileUrl.isEmpty) {
      AppToast.show(context, l10n.str('ota_firmware_library_download_failed'),
          type: ToastType.info);
      return;
    }
    setState(() {
      _downloadingIds.add(r.id);
      _downloadingProgress[r.id] = 0.0;
    });
    try {
      if (!await _downloadService.isFirmwareDownloaded(r.id)) {
        await _downloadService.downloadFirmware(
          url: r.fileUrl,
          fileName: r.fileName.isEmpty
              ? '${r.targetChip}_${r.version}.bin'
              : r.fileName,
          firmwareId: r.id,
          expectedSize: r.fileSize,
          deviceModel: _selectedModel,
          expectedSha256: r.fileSha256.isEmpty ? null : r.fileSha256,
          targetChip: r.targetChip,
          version: r.version,
          signature: r.releaseSignature,
          securityVersion: r.securityVersion,
        );
      }
      if (!mounted) return;
      setState(() {
        _downloadedCache[r.id] = true;
        _downloadingProgress.remove(r.id);
      });
      AppToast.show(context, l10n.str('ota_firmware_library_download_done'),
          type: ToastType.success);
    } catch (e) {
      debugPrint('[FirmwareLibrary] download failed: $e');
      if (!mounted) return;
      AppToast.show(context, l10n.str('ota_firmware_library_download_failed'),
          type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _downloadingIds.remove(r.id);
          _downloadingProgress.remove(r.id);
        });
      }
    }
  }

  void _goLocalUpgrade(FirmwareResource r) {
    final model = _selectedModel ?? '';
    final sn = _selectedSn ?? '';
    context.push(
      '/local-upgrade?model=${Uri.encodeComponent(model)}'
      '&sn=${Uri.encodeComponent(sn)}'
      '&firmware_id=${r.id}',
    );
  }

  /// 按模块分组
  Map<String, List<FirmwareResource>> get _grouped {
    final map = <String, List<FirmwareResource>>{};
    for (final r in _resources) {
      map.putIfAbsent(r.targetChip, () => []).add(r);
    }
    // ESP 模块排最后
    final keys = map.keys.toList()
      ..sort((a, b) {
        if (a == 'esp') return 1;
        if (b == 'esp') return -1;
        return a.compareTo(b);
      });
    return {for (final k in keys) k: map[k]!};
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(
        title: Text(
          l10n.str('ota_firmware_library'),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColor.surfaceContainer(context),
        foregroundColor: AppColor.textPrimary(context),
      ),
      body: _loadingDevices
          ? const Center(child: CircularProgressIndicator())
          : _deviceError != null
              ? XiaoshuoStatePanel(
                  asset: CsergyAssets.xiaoshuoOffline,
                  title: l10n.loadFailed,
                  message: _deviceError!,
                  size: 160,
                  action: OutlinedButton(
                    onPressed: _loadDevices,
                    child: Text(l10n.retry),
                  ),
                )
              : _devices.isEmpty
                  ? XiaoshuoStatePanel(
                      asset: CsergyAssets.emptyDevice,
                      title: l10n.str('ota_firmware_library_no_device'),
                      message:
                          l10n.str('ota_firmware_library_select_device_hint'),
                      size: 160,
                    )
                  : Column(
                      children: [
                        SizedBox(
                          height: 44.h,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.symmetric(horizontal: 16.w),
                            itemCount: _devices.length,
                            separatorBuilder: (_, __) => SizedBox(width: 8.w),
                            itemBuilder: (_, i) {
                              final device = _devices[i];
                              final sn = _str(device, ['sn', 'device_sn']);
                              final name = _str(device, [
                                'alias',
                                'name',
                                'device_name',
                              ]);
                              final selected = sn == _selectedSn;
                              return ChoiceChip(
                                label: Text(name.isEmpty ? sn : name),
                                selected: selected,
                                onSelected: (_) {
                                  if (selected) return;
                                  _selectDevice(device);
                                },
                              );
                            },
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Expanded(child: _buildBody(l10n)),
                      ],
                    ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loadingResources) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_resourceError != null) {
      return XiaoshuoStatePanel(
        asset: CsergyAssets.xiaoshuoOffline,
        title: l10n.loadFailed,
        message: _resourceError,
        size: 160,
        action: OutlinedButton(
          onPressed: _loadResources,
          child: Text(l10n.retry),
        ),
      );
    }
    if (_resources.isEmpty) {
      return XiaoshuoStatePanel(
        asset: CsergyAssets.emptyDevice,
        title: l10n.str('ota_firmware_library_empty'),
        message: l10n.str('ota_firmware_library_empty_hint'),
        size: 160,
      );
    }
    final grouped = _grouped;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 32.h),
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 8.h, left: 4.w),
          child: Text(
            l10n.str('ota_firmware_library_module_group'),
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: AppColor.textSecondary(context),
            ),
          ),
        ),
        for (final entry in grouped.entries) ...[
          _moduleHeader(entry.key, entry.value.length, l10n),
          for (final r in entry.value) _buildResourceCard(r, l10n),
        ],
      ],
    );
  }

  Widget _moduleHeader(String target, int count, AppLocalizations l10n) {
    final module = FirmwareModulePresentation.fromTarget(target);
    return Padding(
      padding: EdgeInsets.fromLTRB(4.w, 12.h, 4.w, 8.h),
      child: Row(
        children: [
          Icon(module.icon, size: 16.sp, color: AppColors.primary),
          SizedBox(width: 6.w),
          Text(
            '${module.displayLabel(l10n)} ($count)',
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: AppColor.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResourceCard(FirmwareResource r, AppLocalizations l10n) {
    final downloaded = _downloadedCache[r.id] == true;
    final downloading = _downloadingIds.contains(r.id);
    final progress = _downloadingProgress[r.id] ?? 0.0;
    final published = r.publishedAt?.toLocal();
    final dateStr = published == null
        ? ''
        : '${published.year.toString().padLeft(4, '0')}-'
            '${published.month.toString().padLeft(2, '0')}-'
            '${published.day.toString().padLeft(2, '0')}';

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: downloaded
              ? AppColors.success.withValues(alpha: 0.4)
              : AppColor.divider(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                r.version,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColor.textPrimary(context),
                ),
              ),
              if (downloaded) ...[
                SizedBox(width: 8.w),
                _badge(l10n.str('ota_firmware_library_downloaded'),
                    AppColors.success),
              ],
              const Spacer(),
              if (dateStr.isNotEmpty)
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: AppColor.textHint(context),
                  ),
                ),
            ],
          ),
          if (r.changelog.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Text(
              r.changelog,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.sp,
                height: 1.4,
                color: AppColor.textSecondary(context),
              ),
            ),
          ],
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(
                child: downloading
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4.r),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6.h,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (downloading) SizedBox(width: 10.w),
              if (downloaded)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    minimumSize: Size(0, 36.h),
                  ),
                  onPressed: () => _goLocalUpgrade(r),
                  icon: Icon(Icons.wifi_rounded, size: 16.sp),
                  label: Text(
                    l10n.str('ota_local_upgrade'),
                    style: TextStyle(fontSize: 13.sp),
                  ),
                )
              else
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: Size(0, 36.h),
                  ),
                  onPressed: downloading ? null : () => _download(r),
                  icon: Icon(
                    downloading
                        ? Icons.downloading_rounded
                        : Icons.download_rounded,
                    size: 16.sp,
                  ),
                  label: Text(
                    downloading
                        ? '${(progress * 100).toInt()}%'
                        : l10n.str('ota_firmware_library_download'),
                    style: TextStyle(fontSize: 13.sp),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.sp,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
