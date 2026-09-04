import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:inv_app/core/services/firmware_download_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 固件库（OTA 升级中心四入口之一）
///
/// 按设备型号浏览已发布的全部升级包版本，支持整包预下载到本地；
/// 已下载的包显示标记，可直接进入本地升级。
/// 数据源：GET /ota/app/packages?model=（items 含完整下载元数据）。
class FirmwareLibraryPage extends StatefulWidget {
  /// 预选型号（可空，为空时取设备列表聚合出的第一个型号）
  final String? initialModel;

  const FirmwareLibraryPage({super.key, this.initialModel});

  @override
  State<FirmwareLibraryPage> createState() => _FirmwareLibraryPageState();
}

class _FirmwareLibraryPageState extends State<FirmwareLibraryPage> {
  // 应用级单例：并发守卫与进度流跨页面共享，页面退出不再 dispose
  final FirmwareDownloadService _downloadService =
      getIt<FirmwareDownloadService>();

  List<String> _models = const [];
  String? _selectedModel;
  List<Map<String, dynamic>> _packages = const [];
  bool _loadingModels = true;
  bool _loadingPackages = false;
  String? _error;

  /// 下载状态：包 ID → 是否全部已下载 / 下载中进度
  final Map<int, bool> _downloadedCache = {};
  final Map<int, double> _downloadingProgress = {};
  final Set<int> _downloadingIds = {};
  final Set<int> _checkedDownloadIds = {};

  StreamSubscription<DownloadProgressEvent>? _progressSub;

  @override
  void initState() {
    super.initState();
    _progressSub = _downloadService.progressStream.listen((event) {
      if (!mounted) return;
      // 仅用于保持下载中卡片的活跃渲染
      if (_downloadingIds.isEmpty) return;
      setState(() {});
    });
    context.read<DeviceBloc>().add(const DeviceListRequested(pageSize: 200));
    // BlocListener 只对后续新状态触发；若进入页面时 bloc 已是
    // 加载完成/失败的缓存态，首帧后在此兼容处理（不能在 build 中 setState）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_loadingModels) return;
      final state = context.read<DeviceBloc>().state;
      if (state is DeviceListLoaded) {
        _collectModels(state);
      } else if (state is DeviceError) {
        setState(() => _loadingModels = false);
      }
    });
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    // 下载服务是应用级单例，不随页面 dispose
    super.dispose();
  }

  String _str(dynamic map, List<String> keys) {
    for (final k in keys) {
      final v = map is Map ? map[k] : null;
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return '';
  }

  /// 从设备列表聚合型号（去重保序）
  void _collectModels(DeviceListLoaded state) {
    final models = <String>[];
    for (final d in state.devices) {
      final model = _str(d, ['model', 'device_model']);
      if (model.isNotEmpty && !models.contains(model)) {
        models.add(model);
      }
    }
    if (!mounted) return;
    setState(() {
      _models = models;
      _loadingModels = false;
      _selectedModel ??= widget.initialModel != null &&
              models.contains(widget.initialModel)
          ? widget.initialModel
          : models.firstOrNull;
    });
    if (_selectedModel != null && _packages.isEmpty && _error == null) {
      _loadPackages(_selectedModel!);
    }
  }

  Future<void> _loadPackages(String model) async {
    setState(() {
      _loadingPackages = true;
      _error = null;
    });
    final result = await getIt<OtaRepository>().listUpgradePackages(model: model);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _loadingPackages = false;
        _error = failure.message;
      }),
      (list) {
        final packages = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
          ..sort((a, b) {
            // 版本倒序：新版本在前（字符串逐段数字比较）
            return _compareVersions(
              _str(b, ['user_version', 'main_version']),
              _str(a, ['user_version', 'main_version']),
            );
          });
        setState(() {
          _packages = packages;
          _loadingPackages = false;
        });
        for (final pkg in packages) {
          _restorePackageDownloadState(pkg);
        }
      },
    );
  }

  /// 版本比较：逐段数字比较，非数字段按字符串比较
  int _compareVersions(String a, String b) {
    final pa = a.replaceAll(RegExp(r'^[Vv]'), '').split('.');
    final pb = b.replaceAll(RegExp(r'^[Vv]'), '').split('.');
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final sa = i < pa.length ? pa[i] : '0';
      final sb = i < pb.length ? pb[i] : '0';
      final na = int.tryParse(sa);
      final nb = int.tryParse(sb);
      if (na != null && nb != null) {
        if (na != nb) return na.compareTo(nb);
      } else {
        final c = sa.compareTo(sb);
        if (c != 0) return c;
      }
    }
    return 0;
  }

  List<Map<String, dynamic>> _chipsOf(Map<String, dynamic> pkg) {
    final chips = pkg['items'];
    if (chips is List) {
      return chips.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  /// 恢复包的下载状态（逐芯片校验本地文件）
  Future<void> _restorePackageDownloadState(Map<String, dynamic> pkg) async {
    final packageId = (pkg['id'] as num?)?.toInt() ?? 0;
    if (packageId == 0 || _checkedDownloadIds.contains(packageId)) return;
    _checkedDownloadIds.add(packageId);

    final chips = _chipsOf(pkg);
    if (chips.isEmpty) return;

    for (final chip in chips) {
      final firmwareId = (chip['firmware_id'] as num?)?.toInt() ?? 0;
      if (firmwareId == 0) continue;
      if (!await _downloadService.isFirmwareDownloaded(firmwareId)) {
        return; // 存在未下载芯片
      }
    }
    if (mounted) {
      setState(() => _downloadedCache[packageId] = true);
    }
  }

  /// 整包预下载：逐芯片顺序下载（下载服务自带并发守卫）
  Future<void> _downloadPackage(Map<String, dynamic> pkg) async {
    final l10n = AppLocalizations.of(context)!;
    final packageId = (pkg['id'] as num?)?.toInt() ?? 0;
    final chips = _chipsOf(pkg);
    if (chips.isEmpty) {
      AppToast.show(
        context,
        l10n.str('ota_firmware_library_no_items'),
        type: ToastType.info,
      );
      return;
    }

    setState(() {
      _downloadingIds.add(packageId);
      _downloadingProgress[packageId] = 0.0;
    });

    try {
      var done = 0;
      for (final chip in chips) {
        final firmwareId = (chip['firmware_id'] as num?)?.toInt() ?? 0;
        final url = (chip['download_url'] ?? '').toString();
        if (firmwareId == 0 || url.isEmpty) continue;

        if (!await _downloadService.isFirmwareDownloaded(firmwareId)) {
          await _downloadService.downloadFirmware(
            url: url,
            fileName:
                (chip['file_name'] ?? '').toString().isEmpty
                    ? '${chip['target_chip']}_${chip['firmware_version']}.bin'
                    : (chip['file_name'] ?? '').toString(),
            firmwareId: firmwareId,
            expectedSize: (chip['file_size'] as num?)?.toInt(),
            expectedSha256: (chip['file_sha256'] ?? '').toString().isEmpty
                ? null
                : (chip['file_sha256'] ?? '').toString(),
            targetChip: (chip['target_chip'] ?? '').toString(),
            version: (chip['firmware_version'] ?? '').toString(),
            signature: (chip['release_signature'] ?? '').toString(),
            securityVersion: (chip['security_version'] as num?)?.toInt(),
          );
        }
        done++;
        if (!mounted) return;
        setState(() {
          _downloadingProgress[packageId] = done / chips.length;
        });
      }
      if (!mounted) return;
      setState(() => _downloadedCache[packageId] = true);
      AppToast.show(
        context,
        l10n.str('ota_firmware_library_download_done'),
        type: ToastType.success,
      );
    } on StateError {
      if (!mounted) return;
      AppToast.show(
        context,
        l10n.str('ota_firmware_library_download_busy'),
        type: ToastType.info,
      );
    } catch (e) {
      debugPrint('[FirmwareLibrary] download failed: $e');
      if (!mounted) return;
      AppToast.show(
        context,
        l10n.str('ota_firmware_library_download_failed'),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloadingIds.remove(packageId);
          _downloadingProgress.remove(packageId);
        });
      }
    }
  }

  /// 已下载 → 本地升级：优先选择同型号的绑定设备
  void _goLocalUpgrade(Map<String, dynamic> pkg) {
    final l10n = AppLocalizations.of(context)!;
    final state = context.read<DeviceBloc>().state;
    final devices = state is DeviceListLoaded ? state.devices : const [];
    final model = _selectedModel ?? '';
    dynamic matched;
    for (final d in devices) {
      if (_str(d, ['model', 'device_model']) == model) {
        matched = d;
        break;
      }
    }
    if (matched == null) {
      AppToast.show(
        context,
        l10n.str('ota_firmware_library_no_device'),
        type: ToastType.info,
      );
      return;
    }
    final sn = _str(matched, ['sn', 'device_sn']);
    context.push(
      '/local-upgrade?sn=${Uri.encodeComponent(sn)}'
      '&model=${Uri.encodeComponent(model)}',
    );
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
      body: BlocConsumer<DeviceBloc, DeviceState>(
        listenWhen: (previous, current) =>
            current is DeviceListLoaded || current is DeviceError,
        listener: (context, state) {
          if (state is DeviceListLoaded) {
            _collectModels(state);
          } else if (state is DeviceError && _loadingModels) {
            // 加载失败：停止等待，UI 展示重试入口
            setState(() => _loadingModels = false);
          }
        },
        builder: (context, state) {
          if (_loadingModels) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is DeviceError && _models.isEmpty) {
            return XiaoshuoStatePanel(
              asset: CsergyAssets.xiaoshuoOffline,
              title: l10n.loadFailed,
              message: state.message,
              size: 160,
              action: OutlinedButton(
                onPressed: () {
                  setState(() => _loadingModels = true);
                  context
                      .read<DeviceBloc>()
                      .add(const DeviceListRequested(pageSize: 200));
                },
                child: Text(l10n.retry),
              ),
            );
          }
          if (_models.isEmpty) {
            return XiaoshuoStatePanel(
              asset: CsergyAssets.emptyDevice,
              title: l10n.str('ota_firmware_library_no_model'),
              message: l10n.str('ota_firmware_library_no_model_hint'),
              size: 160,
            );
          }
          return Column(
            children: [
              // 型号选择器
              SizedBox(
                height: 44.h,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  itemCount: _models.length,
                  separatorBuilder: (_, __) => SizedBox(width: 8.w),
                  itemBuilder: (_, i) {
                    final model = _models[i];
                    final selected = model == _selectedModel;
                    return ChoiceChip(
                      label: Text(model),
                      selected: selected,
                      onSelected: (_) {
                        if (selected) return;
                        setState(() {
                          _selectedModel = model;
                          _packages = const [];
                          _checkedDownloadIds.clear();
                        });
                        _loadPackages(model);
                      },
                    );
                  },
                ),
              ),
              SizedBox(height: 8.h),
              Expanded(child: _buildPackageList(l10n)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPackageList(AppLocalizations l10n) {
    if (_loadingPackages) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return XiaoshuoStatePanel(
        asset: CsergyAssets.xiaoshuoOffline,
        title: l10n.loadFailed,
        message: _error,
        size: 160,
        action: OutlinedButton(
          onPressed: () => _loadPackages(_selectedModel ?? ''),
          child: Text(l10n.retry),
        ),
      );
    }
    if (_packages.isEmpty) {
      return XiaoshuoStatePanel(
        asset: CsergyAssets.emptyDevice,
        title: l10n.str('ota_firmware_library_empty'),
        message: l10n.str('ota_firmware_library_empty_hint'),
        size: 160,
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 32.h),
      itemCount: _packages.length,
      itemBuilder: (_, i) => _buildPackageCard(_packages[i], l10n),
    );
  }

  Widget _buildPackageCard(Map<String, dynamic> pkg, AppLocalizations l10n) {
    final packageId = (pkg['id'] as num?)?.toInt() ?? 0;
    final version = _str(pkg, ['user_version', 'main_version']);
    final changelog = _str(pkg, ['user_changelog', 'changelog']);
    final isForce = pkg['is_force'] == true;
    final chips = _chipsOf(pkg);
    final downloaded = _downloadedCache[packageId] == true;
    final downloading = _downloadingIds.contains(packageId);
    final progress = _downloadingProgress[packageId] ?? 0.0;

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
                version,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColor.textPrimary(context),
                ),
              ),
              SizedBox(width: 8.w),
              if (isForce)
                _badge(l10n.str('ota_firmware_library_force'), AppColors.error),
              if (downloaded)
                _badge(
                  l10n.str('ota_firmware_library_downloaded'),
                  AppColors.success,
                ),
              const Spacer(),
              if (!downloaded)
                Text(
                  ((pkg['created_at'] ?? '').toString()).length >= 10
                      ? (pkg['created_at'] ?? '').toString().substring(0, 10)
                      : (pkg['created_at'] ?? '').toString(),
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: AppColor.textHint(context),
                  ),
                ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Wrap(
              spacing: 6.w,
              runSpacing: 4.h,
              children: [
                for (final chip in chips)
                  _badge(
                    '${chip['target_chip'] ?? ''} '
                    '${chip['firmware_version'] ?? ''}',
                    AppColors.blue,
                  ),
              ],
            ),
          ],
          if (changelog.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Text(
              changelog,
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
                  onPressed: () => _goLocalUpgrade(pkg),
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
                  onPressed: downloading
                      ? null
                      : () => _downloadPackage(pkg),
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
