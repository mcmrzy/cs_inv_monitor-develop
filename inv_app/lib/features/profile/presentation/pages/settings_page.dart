import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:dio/dio.dart';
import 'package:inv_app/core/services/ble/ble_binding_service.dart';
import 'package:inv_app/core/services/ble/ble_direct_service.dart';
import 'package:inv_app/core/services/ble/ble_polling_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/services/locale_service.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/utils/timezone_utils.dart';
import 'package:inv_app/core/widgets/settings_widgets.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _storage = getIt<StorageService>();
  final _localeService = getIt<LocaleService>();

  bool _isLocalMode = false;
  bool _isBleDirectEnabled = false;
  int _blePollInterval = 180;
  bool _isDarkMode = false;
  String _unitType = 'kW';
  String _serverUrl = '';
  String _currentLocale = 'zh';
  String _currentTimezone = TimezoneUtils.defaultTimezone;
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
    final darkMode = await _storage.getIsDarkMode();
    final serverUrl = await _storage.getServerUrl();
    final locale = await _storage.getLocale();
    final timezone = await _storage.getTimezone();
    final bleDirect = await _storage.getIsBleDirectEnabled();
    final pollInterval = await _storage.getBlePollInterval();

    if (mounted) {
      setState(() {
        _isLocalMode = localMode;
        _isBleDirectEnabled = bleDirect;
        _blePollInterval = pollInterval;
        _isDarkMode = darkMode;
        _serverUrl = serverUrl ?? AppConfig.apiBaseUrl;
        _currentLocale = locale ??
            _localeService.currentLocale.languageCode; // 未保存时跟随系统
        _currentTimezone = timezone ?? TimezoneUtils.defaultTimezone;
        _loading = false;
      });
      // 开关已打开（上次会话恢复）：继续监听未绑定设备发现
      if (bleDirect) _subscribeUnboundDevices();
    }
  }

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  Future<void> _toggleLocalMode(bool value) async {
    await _storage.saveIsLocalMode(value);
    if (mounted) {
      setState(() => _isLocalMode = value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? l10n.localModeOn : l10n.localModeOff),
          duration: const Duration(seconds: 1),
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.str('ble_bluetooth_off')),
          duration: const Duration(seconds: 1),
        ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value ? l10n.bleDirectOn : l10n.bleDirectOff),
        duration: const Duration(seconds: 1),
      ),
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
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text(l10n.pinRequired)),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.pollIntervalSaved),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _toggleDarkMode(bool value) async {
    await _storage.saveIsDarkMode(value);
    if (mounted) {
      setState(() => _isDarkMode = value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? l10n.darkModeOn : l10n.darkModeOff),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _showUnitDialog() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.selectPowerUnit),
        children: [
          SimpleDialogOption(
            onPressed: () {
              setState(() => _unitType = 'kW');
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.str('unit_changed', {'unit': 'kW'})),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Row(
                children: [
                  Text('kW', style: TextStyle(fontSize: 16.sp)),
                  if (_unitType == 'kW') ...[
                    const Spacer(),
                    const Icon(Icons.check, color: AppColors.primary),
                  ],
                ],
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              setState(() => _unitType = 'W');
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.str('unit_changed', {'unit': 'W'})),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Row(
                children: [
                  Text('W', style: TextStyle(fontSize: 16.sp)),
                  if (_unitType == 'W') ...[
                    const Spacer(),
                    const Icon(Icons.check, color: AppColors.primary),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
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
                ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
                  SnackBar(
                    content: Text(l10n.serverSaved),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _showTimezoneDialog() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.selectTimezone),
        children: TimezoneUtils.commonTimezones.map((tz) {
          final id = tz['id']!;
          final label = TimezoneUtils.getLabel(id, langCode: _currentLocale);
          return SimpleDialogOption(
            onPressed: () async {
              await _storage.saveTimezone(id);
              // 同步时区到服务器
              try {
                final dio = getIt<Dio>();
                await dio.put('/auth/profile', data: {'timezone': id});
              } catch (_) {}
              await Future.microtask(() {});
              if (!mounted) return;
              setState(() => _currentTimezone = id); // ignore: use_build_context_synchronously
              Navigator.pop(context); // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
                SnackBar(
                  content: Text(
                    l10n.str('timezone_changed', {'timezone': label}),
                  ),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Row(
                children: [
                  Text(label, style: TextStyle(fontSize: 16.sp)),
                  if (_currentTimezone == id) ...[
                    const Spacer(),
                    const Icon(Icons.check, color: AppColors.primary),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.languageSwitch),
        children: [
          SimpleDialogOption(
            onPressed: () {
              _localeService.switchLocale(const Locale('zh', 'CN'));
              setState(() => _currentLocale = 'zh');
              Navigator.pop(context);
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Row(
                children: [
                  Text(
                    l10n.str('language_chinese'),
                    style: TextStyle(fontSize: 16.sp),
                  ),
                  if (_currentLocale == 'zh') ...[
                    const Spacer(),
                    const Icon(Icons.check, color: AppColors.primary),
                  ],
                ],
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              _localeService.switchLocale(const Locale('en', 'US'));
              setState(() => _currentLocale = 'en');
              Navigator.pop(context);
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Row(
                children: [
                  Text(
                    l10n.str('language_english'),
                    style: TextStyle(fontSize: 16.sp),
                  ),
                  if (_currentLocale == 'en') ...[
                    const Spacer(),
                    const Icon(Icons.check, color: AppColors.primary),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.systemSettings)),
        body: const SkeletonSettingsPage(),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.systemSettings)),
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
          ]),
          SettingsSectionTitle(
            icon: Icons.palette_outlined,
            title: l10n.displaySettings,
            accent: AppColors.purple,
          ),
          SettingsCard([
            SettingsSwitchRow(
              icon: Icons.dark_mode,
              accent: AppColors.purple,
              title: l10n.darkMode,
              value: _isDarkMode,
              onChanged: _toggleDarkMode,
            ),
            SettingsValueRow(
              icon: Icons.electric_bolt,
              accent: AppColors.purple,
              title: l10n.unitSwitch,
              subtitle: _unitType,
              onTap: _showUnitDialog,
            ),
            SettingsValueRow(
              icon: Icons.public,
              accent: AppColors.purple,
              title: l10n.timezone,
              subtitle: TimezoneUtils.getLabel(
                _currentTimezone,
                langCode: _currentLocale,
              ),
              onTap: _showTimezoneDialog,
            ),
          ]),
          SettingsSectionTitle(
            icon: Icons.language,
            title: l10n.generalSettings,
            accent: AppColors.teal,
          ),
          SettingsCard([
            SettingsValueRow(
              icon: Icons.translate,
              accent: AppColors.teal,
              title: l10n.languageSwitch,
              subtitle: _currentLocale == 'zh'
                  ? l10n.str('language_chinese')
                  : l10n.str('language_english'),
              onTap: _showLanguageDialog,
            ),
          ]),
          _buildResetButton(),
        ],
      ),
    );
  }

  Widget _buildResetButton() {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: OutlinedButton(
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(l10n.resetSettings),
              content: Text(l10n.resetConfirm),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style:
                      FilledButton.styleFrom(backgroundColor: AppColors.error),
                  child: Text(l10n.reset),
                ),
              ],
            ),
          );

          if (confirmed == true) {
            await _unboundSub?.cancel();
            _unboundSub = null;
            _dismissedMacs.clear();
            await _storage.saveIsLocalMode(false);
            await _storage.saveIsBleDirectEnabled(false);
            await _storage.saveBlePollInterval(180);
            await getIt<BleDirectService>().setEnabled(false);
            await _storage.saveIsDarkMode(false);
            await _storage.saveServerUrl(AppConfig.apiBaseUrl);
            await _storage.saveTimezone(TimezoneUtils.defaultTimezone);
            if (mounted) {
              setState(() {
                _isLocalMode = false;
                _isBleDirectEnabled = false;
                _blePollInterval = 180;
                _isDarkMode = false;
                _serverUrl = AppConfig.apiBaseUrl;
                _currentTimezone = TimezoneUtils.defaultTimezone;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.settingsReset),
                  duration: const Duration(seconds: 1),
                ),
              );
            }
          }
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: BorderSide(color: AppColors.error.withAlpha(40)),
          padding: EdgeInsets.symmetric(vertical: 14.h),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
        ),
        child: Text(l10n.resetAll),
      ),
    );
  }
}
