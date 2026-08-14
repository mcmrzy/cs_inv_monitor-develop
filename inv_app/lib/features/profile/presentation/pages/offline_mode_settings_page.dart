import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:go_router/go_router.dart';

import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/data/local_cache_database.dart';
import 'package:inv_app/core/services/ble/ble_binding_service.dart';
import 'package:inv_app/core/services/ble/ble_direct_service.dart';
import 'package:inv_app/core/services/ble/ble_polling_service.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/settings_widgets.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 离网模式设置页（需求 17）
///
/// 从系统设置页迁移而来的"连接设置"分组：本地模式、BLE 直连、
/// BLE 轮询间隔、自定义服务器、OTA 入口、本地模式入口与本地缓存管理。
/// 存储键保持不变，仅迁移 UI。
class OfflineModeSettingsPage extends StatefulWidget {
  const OfflineModeSettingsPage({super.key});

  @override
  State<OfflineModeSettingsPage> createState() =>
      _OfflineModeSettingsPageState();
}

class _OfflineModeSettingsPageState extends State<OfflineModeSettingsPage> {
  final _storage = getIt<StorageService>();

  bool _isLocalMode = false;
  bool _isBleDirectEnabled = false;
  int _blePollInterval = 180;
  String _serverUrl = '';
  bool _loading = true;

  /// 场景 B：未绑定设备发现流订阅（打开 BLE 开关时监听）
  StreamSubscription<BleDiscoveredDevice>? _unboundSub;
  bool _unboundDialogShowing = false;
  final Set<String> _dismissedMacs = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _unboundSub?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final localMode = await _storage.getIsLocalMode();
    final serverUrl = await _storage.getServerUrl();
    final bleDirect = await _storage.getIsBleDirectEnabled();
    final pollInterval = await _storage.getBlePollInterval();

    if (mounted) {
      setState(() {
        _isLocalMode = localMode;
        _isBleDirectEnabled = bleDirect;
        _blePollInterval = pollInterval;
        _serverUrl = serverUrl ?? AppConfig.apiBaseUrl;
        _loading = false;
      });
      // 开关已打开（上次会话恢复）：继续监听未绑定设备发现
      if (bleDirect) _subscribeUnboundDevices();
    }
  }

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  Future<void> _toggleLocalMode(bool value) async {
    // 与 ConnectionModeService 共享状态（需求 6：页面数据源切换标记）
    await getIt<ConnectionModeService>().setLocalMode(value);
    if (mounted) {
      setState(() => _isLocalMode = value);
      AppToast.show(
        context,
        value ? l10n.localModeOn : l10n.localModeOff,
        type: ToastType.success,
      );
    }
  }

  Future<void> _toggleBleDirect(bool value) async {
    try {
      // 打开/关闭聚合服务（校验蓝牙权限 → 自动连接 → 轮询；关闭 → 断开全部）
      await getIt<BleDirectService>().setEnabled(value);
    } catch (_) {
      // 蓝牙未开启等异常：不持久化、开关保持原状
      if (!mounted) return;
      AppToast.show(
        context,
        l10n.str('ble_bluetooth_off'),
        type: ToastType.error,
      );
      return;
    }
    await _storage.saveIsBleDirectEnabled(value);
    if (!mounted) return;
    setState(() => _isBleDirectEnabled = value);
    if (value) {
      _subscribeUnboundDevices();
    } else {
      await _unboundSub?.cancel();
      _unboundSub = null;
    }
    if (!mounted) return;
    AppToast.show(
      context,
      value ? l10n.bleDirectOn : l10n.bleDirectOff,
      type: ToastType.success,
    );
  }

  /// 订阅场景 B 发现流：扫描到未绑定设备时弹确认框（含 PIN 输入，防抢绑）
  void _subscribeUnboundDevices() {
    _unboundSub?.cancel();
    _unboundSub = getIt<BleDirectService>().unboundDevices.listen(
      (device) {
        if (!mounted || _unboundDialogShowing) return;
        if (_dismissedMacs.contains(device.macAddress)) return;
        _unboundDialogShowing = true;
        _showUnboundBindDialog(device);
      },
    );
  }

  /// 场景 B 确认对话框：设备名 + PIN 输入 → BLE 绑定（设备端校验 PIN）
  Future<void> _showUnboundBindDialog(BleDiscoveredDevice device) async {
    final pinController = TextEditingController();
    var enteredPin = '';
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.str('ble_bind_confirm_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.str('ble_bind_confirm_desc')),
            SizedBox(height: 8.h),
            Text(
              device.name.isEmpty ? device.macAddress : device.name,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 16.h),
            TextField(
              controller: pinController,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: l10n.pinInputTitle,
                hintText: l10n.pinInputHint,
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              enteredPin = pinController.text.trim();
              if (enteredPin.isEmpty) {
                AppToast.show(
                  dialogContext,
                  l10n.pinRequired,
                  type: ToastType.info,
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: Text(l10n.pinInputConfirm),
          ),
        ],
      ),
    );
    pinController.dispose();
    _unboundDialogShowing = false;
    // 无论结果如何，本会话内不再提示该设备（防重复弹窗）
    _dismissedMacs.add(device.macAddress);
    if (proceed != true || !mounted) return;

    // 绑定中
    final outcome = await getIt<BleBindingService>().bindAfterProvision(
      macAddress: device.macAddress,
      pin: enteredPin,
    );
    if (!mounted) return;
    final (icon, text) = switch (outcome) {
      BindOutcome.bound =>
        (Icons.check_circle, l10n.str('ble_binding_success')),
      BindOutcome.alreadyBound =>
        (Icons.info, l10n.str('ble_binding_already_bound')),
      BindOutcome.invalidPin => (Icons.lock, l10n.pinInvalid),
      BindOutcome.locked => (Icons.lock, l10n.pinLocked),
      BindOutcome.needLoginForSync =>
        (Icons.cloud_sync, l10n.str('ble_binding_need_login')),
      _ => (Icons.error_outline, l10n.str('ble_binding_failed')),
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            SizedBox(width: 8.w),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }

  Future<void> _showPollIntervalDialog() async {
    final options = [60, 180, 300];
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.blePollInterval),
        children: options.map((seconds) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, seconds),
            child: Text(
              seconds == 60
                  ? l10n.str('poll_interval_60s')
                  : seconds == 180
                      ? l10n.str('poll_interval_180s')
                      : l10n.str('poll_interval_300s'),
            ),
          );
        }).toList(),
      ),
    );
    if (selected == null) return;
    await _storage.saveBlePollInterval(selected);
    getIt<BlePollingService>().setInterval(Duration(seconds: selected));
    if (!mounted) return;
    setState(() => _blePollInterval = selected);
    AppToast.show(
      context,
      l10n.pollIntervalSaved,
      type: ToastType.success,
    );
  }

  void _showServerUrlDialog() {
    final controller = TextEditingController(text: _serverUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.serverAddress),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: l10n.serverHint,
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                await _storage.saveServerUrl(url);
                await Future.microtask(() {});
                if (!mounted) return;
                setState(() => _serverUrl = url); // ignore: use_build_context_synchronously
                Navigator.pop(context); // ignore: use_build_context_synchronously
                AppToast.show(
                  context, // ignore: use_build_context_synchronously
                  l10n.serverSaved,
                  type: ToastType.success,
                );
              }
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  /// 缓存管理对话框：查看缓存统计 + 清空缓存
  Future<void> _showCacheManageDialog(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final cache = LocalCacheDatabase();
    final stats = await cache.getStats();
    if (!mounted) return;

    showDialog<void>(
      context: context, // ignore: use_build_context_synchronously
      builder: (ctx) => AlertDialog(
        title: Text(l10n.str('local_cache_manage')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.str('local_cache_stats')
                  .replaceAll('{stations}', '${stats['stations']}')
                  .replaceAll('{devices}', '${stats['devices']}'),
              style: TextStyle(fontSize: 14.sp),
            ),
            SizedBox(height: 16.h),
            Text(
              l10n.str('local_cache_clear_confirm'),
              style: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              await cache.clearAll();
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
                  SnackBar(content: Text(l10n.str('local_cache_cleared'))),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(l10n.str('local_cache_clear')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.offlineModeSettings)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.offlineModeSettings)),
      body: ListView(
        padding: EdgeInsets.only(bottom: 24.h),
        children: [
          SettingsSectionTitle(
            icon: Icons.wifi_tethering,
            title: l10n.connectionSettings,
            accent: AppColors.blue,
          ),
          SettingsCard([
            SettingsSwitchRow(
              icon: Icons.cloud_off,
              accent: AppColors.blue,
              title: l10n.localMode,
              subtitle: l10n.localModeDesc,
              value: _isLocalMode,
              onChanged: _toggleLocalMode,
            ),
            SettingsSwitchRow(
              icon: Icons.bluetooth,
              accent: AppColors.blue,
              title: l10n.bleDirectEnabled,
              subtitle: l10n.bleDirectEnabledDesc,
              value: _isBleDirectEnabled,
              onChanged: _toggleBleDirect,
            ),
            SettingsValueRow(
              icon: Icons.speed,
              accent: AppColors.blue,
              title: l10n.blePollInterval,
              subtitle: l10n.blePollIntervalDesc,
              trailing: Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Text(
                  '$_blePollInterval s',
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.blue,
                  ),
                ),
              ),
              onTap: _showPollIntervalDialog,
            ),
            SettingsValueRow(
              icon: Icons.dns,
              accent: AppColors.blue,
              title: l10n.customServer,
              subtitle: _serverUrl,
              onTap: _showServerUrlDialog,
            ),
            SettingsValueRow(
              icon: Icons.system_update_alt_rounded,
              accent: AppColors.blue,
              title: l10n.otaTitle,
              subtitle: l10n.str('ota_settings_hint'),
              onTap: () => context.push('/ota'),
            ),
            SettingsValueRow(
              icon: Icons.wifi_tethering_rounded,
              accent: AppColors.blue,
              title: l10n.str('local_mode_entry_title'),
              subtitle: l10n.str('local_mode_settings_hint'),
              onTap: () => context.push('/local-mode'),
            ),
            SettingsValueRow(
              icon: Icons.storage_rounded,
              accent: AppColors.teal,
              title: l10n.str('local_cache_manage'),
              subtitle: l10n.str('local_cache_manage_hint'),
              onTap: () => _showCacheManageDialog(context, l10n),
            ),
          ]),
        ],
      ),
    );
  }
}
