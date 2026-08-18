import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:inv_app/core/data/local_cache_database.dart';
import 'package:inv_app/core/services/ble/ble_binding_service.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/ble/ble_direct_service.dart';
import 'package:inv_app/core/services/ble/ble_polling_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/settings_widgets.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 离网直连设置页
///
/// 聚焦 BLE 直连链路：BLE 直连总开关、自动连接开关、
/// 发现的设备列表（PIN 绑定）、轮询周期与本地缓存管理。
class OfflineModeSettingsPage extends StatefulWidget {
  const OfflineModeSettingsPage({super.key});

  @override
  State<OfflineModeSettingsPage> createState() =>
      _OfflineModeSettingsPageState();
}

class _OfflineModeSettingsPageState extends State<OfflineModeSettingsPage> {
  final _storage = getIt<StorageService>();

  bool _isBleDirectEnabled = false;
  bool _autoConnect = true;
  int _blePollInterval = 180;
  bool _loading = true;

  /// 发现设备列表（来自 BleDirectService.scanResultsStream）
  StreamSubscription<List<BleDiscoveredDevice>>? _scanSub;
  List<BleDiscoveredDevice> _foundDevices = const [];

  /// 发现设备的绑定状态（key: macAddress）：本地 keyStore 存有 device_key 即为已绑定
  Map<String, bool> _boundByMac = const {};

  /// BLE 广播名前缀（形如 CS_INV_SN / CS-INV-SN），去掉后即为 SN
  static final RegExp _snPrefixPattern =
      RegExp(r'^CS[-_]INV[-_]', caseSensitive: false);

  /// 解析发现设备的展示名：BLE 广播名形如 CS_INV_1234567890123456，
  /// 去掉前缀直接显示 SN；去前缀后为空则回退原名称，名称为空回退 MAC
  static String displaySnOf(BleDiscoveredDevice device) {
    if (device.name.isEmpty) return device.macAddress;
    final sn = device.name.replaceFirst(_snPrefixPattern, '');
    return sn.isEmpty ? device.name : sn;
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final bleDirect = await _storage.getIsBleDirectEnabled();
    final autoConnect = await _storage.getIsBleAutoConnect();
    final pollInterval = await _storage.getBlePollInterval();

    if (mounted) {
      setState(() {
        _isBleDirectEnabled = bleDirect;
        _autoConnect = autoConnect;
        _blePollInterval = pollInterval;
        _loading = false;
      });
      // 开关已打开（上次会话恢复）：展示已缓存的发现设备
      if (bleDirect) {
        final service = getIt<BleDirectService>();
        _foundDevices = service.scanResults;
        _subscribeScanResults();
        _refreshBoundStatuses(_foundDevices);
      }
    }
  }

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  Future<void> _toggleBleDirect(bool value) async {
    try {
      // 打开/关闭聚合服务（校验蓝牙权限 → 按自动连接开关连接 → 轮询；
      // 关闭 → 断开全部）
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
      _foundDevices = getIt<BleDirectService>().scanResults;
      _subscribeScanResults();
    } else {
      await _scanSub?.cancel();
      _scanSub = null;
      setState(() {
        _foundDevices = const [];
        _boundByMac = const {};
      });
    }
    if (!mounted) return;
    AppToast.show(
      context,
      value ? l10n.bleDirectOn : l10n.bleDirectOff,
      type: ToastType.success,
    );
  }

  Future<void> _toggleAutoConnect(bool value) async {
    await _storage.saveIsBleAutoConnect(value);
    await getIt<BleDirectService>().setAutoConnect(value);
    if (!mounted) return;
    setState(() => _autoConnect = value);
  }

  /// 订阅发现设备列表流
  void _subscribeScanResults() {
    _scanSub?.cancel();
    _scanSub = getIt<BleDirectService>().scanResultsStream.listen((devices) {
      if (!mounted) return;
      setState(() => _foundDevices = devices);
      // 设备列表变化后异步刷新各设备的绑定状态
      _refreshBoundStatuses(devices);
    });
  }

  /// 异步批量查询发现设备的绑定状态（本地 keyStore 按 SN 存有 device_key 即已绑定），
  /// 结果以 macAddress 为 key 缓存供同步行渲染
  Future<void> _refreshBoundStatuses(List<BleDiscoveredDevice> devices) async {
    final keyStore = getIt<BleDeviceKeyStore>();
    final result = <String, bool>{};
    for (final device in devices) {
      // 广播名去掉 CS[-_]INV[-_] 前缀即为 SN；解析不出 SN 则视为未绑定
      final sn = device.name.replaceFirst(_snPrefixPattern, '');
      if (device.name.isEmpty || sn.isEmpty) {
        result[device.macAddress] = false;
        continue;
      }
      try {
        result[device.macAddress] = await keyStore.read(sn) != null;
      } catch (_) {
        // 安全存储读取异常：保守视为未绑定
        result[device.macAddress] = false;
      }
    }
    if (!mounted) return;
    setState(() => _boundByMac = result);
  }

  /// 绑定对话框：设备名 + 铭牌 PIN 输入 → BLE 绑定（设备端校验 PIN）
  Future<void> _showBindDialog(BleDiscoveredDevice device) async {
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
              displaySnOf(device),
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: AppColor.textPrimary(context),
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
    if (proceed != true || !mounted) return;

    final outcome = await getIt<BleBindingService>().bindAfterProvision(
      macAddress: device.macAddress,
      pin: enteredPin,
    );
    if (!mounted) return;
    final (text, type) = switch (outcome) {
      BindOutcome.bound => (
          l10n.str('ble_binding_success'),
          ToastType.success,
        ),
      BindOutcome.alreadyBound => (
          l10n.str('ble_binding_already_bound'),
          ToastType.info,
        ),
      BindOutcome.invalidPin => (l10n.pinInvalid, ToastType.error),
      BindOutcome.locked => (l10n.pinLocked, ToastType.error),
      BindOutcome.needLoginForSync => (
          l10n.str('ble_binding_need_login'),
          ToastType.info,
        ),
      _ => (
          l10n.str('ble_binding_failed'),
          ToastType.error,
        ),
    };
    AppToast.show(context, text, type: type);
    // 绑定成功（或设备端判定已绑定）：立即更新该行的绑定状态
    if (outcome == BindOutcome.bound || outcome == BindOutcome.alreadyBound) {
      _boundByMac = {..._boundByMac, device.macAddress: true};
    }
    // 刷新列表（会话状态可能变化）
    setState(() => _foundDevices = getIt<BleDirectService>().scanResults);
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
              style: TextStyle(fontSize: 13.sp, color: AppColor.textHint(context)),
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
        body: const PageSkeleton(),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.offlineModeSettings)),
      body: ListView(
        padding: EdgeInsets.only(bottom: 24.h),
        children: [
          SettingsSectionTitle(
            icon: Icons.bluetooth_connected_rounded,
            title: l10n.connectionSettings,
            accent: AppColors.blue,
          ),
          SettingsCard([
            SettingsSwitchRow(
              icon: Icons.bluetooth,
              accent: AppColors.blue,
              title: l10n.bleDirectEnabled,
              subtitle: l10n.bleDirectEnabledDesc,
              value: _isBleDirectEnabled,
              onChanged: _toggleBleDirect,
            ),
            SettingsSwitchRow(
              icon: Icons.link_rounded,
              accent: AppColors.blue,
              title: l10n.str('ble_auto_connect'),
              subtitle: l10n.str('ble_auto_connect_desc'),
              value: _autoConnect,
              onChanged: _toggleAutoConnect,
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
              icon: Icons.storage_rounded,
              accent: AppColors.teal,
              title: l10n.str('local_cache_manage'),
              subtitle: l10n.str('local_cache_manage_hint'),
              onTap: () => _showCacheManageDialog(context, l10n),
            ),
          ]),
          // 发现的设备列表：仅 BLE 直连开启时展示
          if (_isBleDirectEnabled) ...[
            SettingsSectionTitle(
              icon: Icons.radar_rounded,
              title: l10n.str('ble_found_devices'),
              accent: AppColors.teal,
              trailing: TextButton.icon(
                onPressed: () => getIt<BleDirectService>().rescan(),
                icon: Icon(Icons.refresh_rounded, size: 16.sp),
                label: Text(
                  l10n.str('ble_rescan'),
                  style: TextStyle(fontSize: 12.sp),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 8.h),
              child: Text(
                l10n.str('ble_found_devices_hint'),
                style: TextStyle(
                  fontSize: 12.sp,
                  color: AppColor.textHint(context),
                ),
              ),
            ),
            if (_foundDevices.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 24.h),
                  decoration: BoxDecoration(
                    color: AppColor.surfaceContainer(context),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.bluetooth_searching_rounded,
                        size: 32.sp,
                        color: AppColor.textHint(context),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        l10n.str('ble_found_empty'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SettingsCard([
                for (final device in _foundDevices)
                  _buildFoundDeviceRow(device),
              ]),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
              child: Text(
                l10n.str('ble_scanning_hint'),
                style: TextStyle(
                  fontSize: 11.sp,
                  color: AppColor.textHint(context),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 发现设备行：SN + 已连接徽标 > 已绑定徽标 > 绑定按钮
  Widget _buildFoundDeviceRow(BleDiscoveredDevice device) {
    final connected =
        getIt<BleDeviceManager>().sessionOf(device.macAddress) != null;
    final bound = _boundByMac[device.macAddress] ?? false;
    final displaySn = displaySnOf(device);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.router_rounded,
              size: 18.sp,
              color: AppColors.blue,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displaySn,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                    color: AppColor.textPrimary(context),
                  ),
                ),
                SizedBox(height: 2.h),
                // 副标题显示 SN（不再展示 MAC）
                Text(
                  displaySn,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: AppColor.textHint(context),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          // 状态渲染优先级：已连接 > 已绑定 > 未绑定（绑定按钮）
          if (connected)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 12.sp,
                    color: AppColors.success,
                  ),
                  SizedBox(width: 4.w),
                  Text(
                    l10n.str('ble_device_connected'),
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            )
          else if (bound)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.link_rounded,
                    size: 12.sp,
                    color: AppColors.blue,
                  ),
                  SizedBox(width: 4.w),
                  Text(
                    l10n.str('ble_device_bound'),
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.blue,
                    ),
                  ),
                ],
              ),
            )
          else
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                minimumSize: Size(0, 34.h),
              ),
              onPressed: () => _showBindDialog(device),
              child: Text(
                l10n.str('ble_bind_device'),
                style: TextStyle(fontSize: 13.sp),
              ),
            ),
        ],
      ),
    );
  }
}
