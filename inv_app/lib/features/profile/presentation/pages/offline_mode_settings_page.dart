import 'package:inv_app/core/services/connection_mode_service.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:inv_app/core/data/local_cache_database.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/ble/ble_direct_service.dart';
import 'package:inv_app/core/services/ble/ble_polling_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/settings_widgets.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/features/device/presentation/pages/modbus_panel_page.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 离网直连设置页
///
/// 聚焦 BLE 直连链路：BLE 直连总开关、自动连接开关、
/// 发现的设备列表（本地连接）、轮询周期与本地缓存管理。
class OfflineModeSettingsPage extends StatefulWidget {
  const OfflineModeSettingsPage({super.key, this.expectedSn});

  final String? expectedSn;

  @override
  State<OfflineModeSettingsPage> createState() =>
      _OfflineModeSettingsPageState();
}

class _OfflineModeSettingsPageState extends State<OfflineModeSettingsPage> {
  final _storage = getIt<StorageService>();

  bool _isBleDirectEnabled = false;
  bool _autoConnect = true;
  int _blePollInterval = 180;
  bool _isOfflineMode = false;
  Set<String> _directConnectedDevices = {};
  bool _loading = true;

  String? _openingPanelMac;
  bool _enabling = false;

  /// 发现设备列表（来自 BleDirectService.scanResultsStream）
  StreamSubscription<List<BleDiscoveredDevice>>? _scanSub;
  List<BleDiscoveredDevice> _foundDevices = const [];

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

  bool _matchesTarget(BleDiscoveredDevice device) {
    final expected = widget.expectedSn?.trim();
    if (expected == null || expected.isEmpty) return true;
    final session = getIt<BleDeviceManager>().sessionOf(device.macAddress);
    return (session?.sn ?? displaySnOf(device)) == expected;
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void deactivate() {
    _scanSub?.cancel();
    _scanSub = null;
    super.deactivate();
  }

  @override
  void dispose() {
    unawaited(_scanSub?.cancel());
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final bleDirect = await _storage.getIsBleDirectEnabled();
    final autoConnect = await _storage.getIsBleAutoConnect();
    final pollInterval = await _storage.getBlePollInterval();
    final offlineMode = await _storage.getIsOfflineMode();
    final directDevices = await _storage.getDirectConnectedDevices();

    if (mounted) {
      setState(() {
        _isBleDirectEnabled = bleDirect;
        _autoConnect = autoConnect;
        _blePollInterval = pollInterval;
        _isOfflineMode = offlineMode;
        _directConnectedDevices = directDevices;
        _loading = false;
      });
      // 开关已打开（上次会话恢复）：展示已缓存的发现设备
      if (bleDirect) {
        final service = getIt<BleDirectService>();
        _foundDevices = service.scanResults;
        _subscribeScanResults();
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
      if (!mounted) return;
      setState(() {
        _foundDevices = const [];
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

  Future<void> _toggleOfflineMode(bool value) async {
    if (value && !_isBleDirectEnabled) {
      await _toggleBleDirect(true);
      if (!_isBleDirectEnabled) return;
    }
    await getIt<ConnectionModeService>().setOfflineMode(value);
    if (!mounted) return;
    setState(() => _isOfflineMode = value);
    AppToast.show(
      context,
      Localizations.localeOf(context).languageCode == 'zh'
          ? (value ? '已切换至本地蓝牙与缓存' : '已切换至云端模式')
          : (value
              ? 'Local Bluetooth and cache are active'
              : 'Cloud mode is active'),
      type: ToastType.success,
    );
  }

  Future<void> _toggleDeviceDirectConnection(
    String macAddress,
    bool value,
  ) async {
    try {
      final updated = Set<String>.from(_directConnectedDevices);
      final manager = getIt<BleDeviceManager>();
      if (value) {
        final session = await manager.connectDevice(macAddress);
        if (session.state != BleDeviceState.ready) {
          throw const BleCommandException('NOT_READY', 'Device not ready');
        }
        updated.add(macAddress);
      } else {
        await manager.disconnectDevice(macAddress);
        updated.remove(macAddress);
      }
      await _storage.saveDirectConnectedDevices(updated);
      if (!mounted) return;
      setState(() => _directConnectedDevices = updated);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(
        context,
        Localizations.localeOf(context).languageCode == 'zh'
            ? '蓝牙连接未完成，请靠近设备后重试。'
            : 'Bluetooth connection failed. Move closer and retry.',
        type: ToastType.error,
      );
    }
  }

  /// 订阅发现设备列表流
  void _subscribeScanResults() {
    _scanSub?.cancel();
    _scanSub = getIt<BleDirectService>().scanResultsStream.listen((devices) {
      if (!mounted) return;
      setState(() => _foundDevices = devices);
    });
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
    if (!context.mounted) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.str('local_cache_manage')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n
                  .str('local_cache_stats')
                  .replaceAll('{stations}', '${stats['stations']}')
                  .replaceAll('{devices}', '${stats['devices']}'),
              style: TextStyle(fontSize: 14.sp),
            ),
            SizedBox(height: 16.h),
            Text(
              l10n.str('local_cache_clear_confirm'),
              style:
                  TextStyle(fontSize: 13.sp, color: AppColor.textHint(context)),
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
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
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
    final target = widget.expectedSn?.trim();
    final targeted = target != null && target.isNotEmpty;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final background = AppColor.background(context);
    final accent = AppColor.primary(context);
    final appBar = AppBar(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      title: Text(
        targeted
            ? (zh ? '连接设备蓝牙' : 'Connect device over Bluetooth')
            : (zh ? '蓝牙连接' : 'Bluetooth connections'),
      ),
    );
    if (_loading) {
      return Scaffold(
        backgroundColor: background,
        appBar: appBar,
        body: const PageSkeleton(),
      );
    }

    final connectedCount = getIt<BleDeviceManager>()
        .sessions
        .values
        .where((session) => session.state == BleDeviceState.ready)
        .length;
    final devices = _foundDevices.where(_matchesTarget).toList();
    final readyPanel =
        targeted ? getIt<BleDeviceManager>().readyPanelFor(target) : null;
    if (readyPanel != null &&
        devices.every((device) => device.macAddress != readyPanel.macAddress)) {
      devices.insert(
        0,
        BleDiscoveredDevice(
          macAddress: readyPanel.macAddress,
          name: target!,
        ),
      );
    }
    final status = !_isBleDirectEnabled
        ? (zh ? '蓝牙直连已关闭' : 'Bluetooth direct is off')
        : targeted
            ? (devices.isEmpty ? target : null)
            : (zh ? '已连接 $connectedCount 台' : '$connectedCount connected');

    return Scaffold(
      backgroundColor: background,
      appBar: appBar,
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              children: [
                _buildDiscoverySummary(
                  targeted: targeted,
                  status: status,
                  zh: zh,
                ),
                if (_isBleDirectEnabled) ...[
                  SettingsSectionTitle(
                    icon: Icons.sensors_rounded,
                    title: targeted
                        ? (zh ? '目标设备' : 'Target device')
                        : l10n.str('ble_found_devices'),
                    accent: accent,
                  ),
                  if (devices.isEmpty)
                    SettingsCard([
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          targeted
                              ? (zh
                                  ? '暂未发现目标设备，可以靠近面板后重新扫描。'
                                  : 'Device not found. Move closer to the panel and scan again.')
                              : l10n.str('ble_found_empty'),
                          style:
                              TextStyle(color: AppColor.textSecondary(context)),
                        ),
                      ),
                    ])
                  else
                    SettingsCard([
                      for (final device in devices)
                        _buildFoundDeviceRow(device, targeted: targeted),
                    ]),
                ],
                if (!targeted) ...[
                  SettingsSectionTitle(
                    icon: Icons.bluetooth_connected_rounded,
                    title: l10n.connectionSettings,
                    accent: accent,
                  ),
                  SettingsCard([
                    SettingsSwitchRow(
                      icon: Icons.bluetooth,
                      accent: accent,
                      title: l10n.bleDirectEnabled,
                      subtitle: l10n.bleDirectEnabledDesc,
                      value: _isBleDirectEnabled,
                      onChanged: _toggleBleDirect,
                    ),
                    SettingsSwitchRow(
                      icon: Icons.wifi_off_rounded,
                      accent: accent,
                      title: l10n.bleOfflineMode,
                      subtitle: l10n.bleOfflineModeDesc,
                      value: _isOfflineMode,
                      onChanged: _toggleOfflineMode,
                    ),
                    SettingsSwitchRow(
                      icon: Icons.link_rounded,
                      accent: accent,
                      title: l10n.str('ble_auto_connect'),
                      subtitle: l10n.str('ble_auto_connect_desc'),
                      value: _autoConnect,
                      onChanged: _toggleAutoConnect,
                    ),
                  ]),
                  SettingsSectionTitle(
                    icon: Icons.storage_rounded,
                    title: zh ? '本地数据' : 'Local data',
                    accent: accent,
                  ),
                  SettingsCard([
                    SettingsValueRow(
                      icon: Icons.speed,
                      accent: accent,
                      title: l10n.blePollInterval,
                      subtitle: l10n.blePollIntervalDesc,
                      trailing: Text(
                        '$_blePollInterval s',
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColor.textSecondary(context),
                        ),
                      ),
                      onTap: _showPollIntervalDialog,
                    ),
                    SettingsValueRow(
                      icon: Icons.storage_rounded,
                      accent: accent,
                      title: l10n.str('local_cache_manage'),
                      subtitle: l10n.str('local_cache_manage_hint'),
                      onTap: () => _showCacheManageDialog(context, l10n),
                    ),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiscoverySummary({
    required bool targeted,
    required String? status,
    required bool zh,
  }) {
    final text = Theme.of(context).textTheme;
    final accent = AppColor.primary(context);
    final muted = AppColor.textSecondary(context);
    final description = targeted
        ? (zh
            ? '在面板打开「手机连接」，核对序列号后连接。'
            : 'Open Phone connection on the panel, then connect to the matching serial number.')
        : _isOfflineMode
            ? (zh
                ? '离网模式 · 通过蓝牙和本地缓存访问设备'
                : 'Offline mode · Uses Bluetooth and cached data')
            : (zh
                ? '云端模式 · 可同时连接附近的蓝牙设备'
                : 'Cloud mode · Nearby devices can also connect over Bluetooth');

    return SettingsCard([
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SettingsIconContainer(
                  icon: Icons.bluetooth_rounded,
                  accent: accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        zh ? '蓝牙直连' : 'Bluetooth direct',
                        style: text.titleMedium?.copyWith(
                          color: AppColor.textPrimary(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (status != null)
                        Text(
                          status,
                          style: text.bodySmall?.copyWith(color: muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: text.bodyMedium?.copyWith(color: muted, height: 1.45),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              key: const ValueKey('bluetooth-discovery-action'),
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                minimumSize: const Size(0, 48),
                side: BorderSide(color: AppColor.border(context)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _openingPanelMac != null || _enabling
                  ? null
                  : _isBleDirectEnabled
                      ? getIt<BleDirectService>().rescan
                      : _enableBluetoothDiscovery,
              icon: Icon(
                _isBleDirectEnabled
                    ? Icons.refresh_rounded
                    : Icons.bluetooth_rounded,
                size: 18,
              ),
              label: Text(
                _enabling
                    ? (zh ? '正在开启' : 'Enabling')
                    : _isBleDirectEnabled
                        ? l10n.str('ble_rescan')
                        : (zh ? '开启蓝牙直连' : 'Enable Bluetooth direct'),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Future<void> _enableBluetoothDiscovery() async {
    setState(() => _enabling = true);
    try {
      await _toggleBleDirect(true);
    } finally {
      if (mounted) setState(() => _enabling = false);
    }
  }

  Widget _buildFoundDeviceRow(
    BleDiscoveredDevice device, {
    required bool targeted,
  }) {
    final session = getIt<BleDeviceManager>().sessionOf(device.macAddress);
    final connected = session?.state == BleDeviceState.ready;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final opening = _openingPanelMac == device.macAddress;
    final autoReconnect = _directConnectedDevices.contains(device.macAddress);
    final accent = AppColor.primary(context);
    final muted = AppColor.textSecondary(context);
    final open =
        _openingPanelMac == null ? () => _openPanel(device.macAddress) : null;
    final status = opening
        ? (zh ? '正在连接' : 'Connecting')
        : connected
            ? (zh ? '蓝牙已连接' : 'Bluetooth connected')
            : (zh ? '等待连接' : 'Ready to connect');
    final actionLabel = connected
        ? (zh ? '进入设置' : 'Open settings')
        : (zh ? '连接设备' : 'Connect device');
    const spinner = SizedBox.square(
      dimension: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    return Column(
      key: ValueKey(device.macAddress),
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: SettingsIconContainer(
            icon: Icons.memory_rounded,
            accent: connected ? accent : muted,
          ),
          title: Text(
            session?.sn ?? displaySnOf(device),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColor.textPrimary(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
          subtitle: Text(
            status,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: connected || opening ? accent : muted,
                ),
          ),
          trailing: targeted
              ? null
              : SizedBox.square(
                  dimension: 24,
                  child: Center(
                    child: opening
                        ? spinner
                        : Tooltip(
                            message: actionLabel,
                            child: Icon(
                              connected
                                  ? Icons.chevron_right_rounded
                                  : Icons.link_rounded,
                              size: 20,
                              color: open == null ? muted : accent,
                            ),
                          ),
                  ),
                ),
          onTap: open,
        ),
        if (targeted)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColor.primarySoft(context),
                  foregroundColor: accent,
                  disabledBackgroundColor: AppColor.surfaceHover(context),
                  disabledForegroundColor: muted,
                  minimumSize: const Size(0, 48),
                ),
                onPressed: open,
                icon: opening
                    ? spinner
                    : Icon(connected ? Icons.tune_rounded : Icons.link_rounded),
                label: Text(opening ? status : actionLabel),
              ),
            ),
          ),
        Divider(
          color: AppColor.divider(context),
          height: 1,
          indent: 16,
          endIndent: 16,
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(
            zh ? '自动重连此设备' : 'Reconnect to this device',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColor.textSecondary(context),
                ),
          ),
          value: autoReconnect,
          onChanged: _openingPanelMac == null
              ? (value) =>
                  _toggleDeviceDirectConnection(device.macAddress, value)
              : null,
        ),
      ],
    );
  }

  Future<void> _openPanel(String mac) async {
    if (_openingPanelMac != null) return;
    setState(() => _openingPanelMac = mac);
    try {
      final session = await getIt<BleDeviceManager>().connectDevice(
        mac,
        autoReconnect: _directConnectedDevices.contains(mac),
      );
      if (session.state == BleDeviceState.connecting ||
          session.state == BleDeviceState.authenticating) {
        await session.stateStream
            .firstWhere(
              (state) =>
                  state == BleDeviceState.ready ||
                  state == BleDeviceState.disconnected,
            )
            .timeout(const Duration(seconds: 15));
      }
      if (!mounted) return;
      if (session.state != BleDeviceState.ready) {
        throw const BleCommandException('NOT_READY', 'Panel not connected');
      }
      final expected = widget.expectedSn?.trim();
      if (expected != null && expected.isNotEmpty && session.sn != expected) {
        AppToast.show(
          context,
          Localizations.localeOf(context).languageCode == 'zh'
              ? '蓝牙设备的序列号与所选设备不一致。'
              : 'The Bluetooth device serial number does not match.',
          type: ToastType.error,
        );
        return;
      }
      if (!session.supportsPanelApi) {
        AppToast.show(
          context,
          Localizations.localeOf(context).languageCode == 'zh'
              ? '该设备固件暂未开放蓝牙面板功能。'
              : 'Bluetooth panel controls are unavailable on this firmware.',
          type: ToastType.info,
        );
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ModbusPanelPage(
            session: session,
            startInSettings: expected?.isNotEmpty == true,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.show(
        context,
        Localizations.localeOf(context).languageCode == 'zh'
            ? '无法连接设备，请确认面板已打开「手机连接」并靠近后重试。'
            : 'Could not connect. Open Phone connection on the panel, move closer and retry.',
        type: ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _openingPanelMac = null);
    }
  }
}
