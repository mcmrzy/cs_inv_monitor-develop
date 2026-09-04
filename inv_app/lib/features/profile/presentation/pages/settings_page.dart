import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/ble/ble_direct_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/services/locale_service.dart';
import 'package:inv_app/core/services/theme_service.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
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

  String _themeMode = 'system';
  String _unitType = 'kW';
  String? _savedLocale;
  String _currentLocale = 'zh';
  String _currentTimezone = TimezoneUtils.defaultTimezone;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final themeMode = await _storage.getThemeMode();
    final locale = await _storage.getLocale();
    final timezone = await _storage.getTimezone();

    if (mounted) {
      setState(() {
        _themeMode = themeMode ?? 'system';
        _savedLocale = locale;
        _currentLocale = locale ??
            _localeService.currentLocale.languageCode; // 未保存时跟随系统
        _currentTimezone = timezone ?? TimezoneUtils.defaultTimezone;
        _loading = false;
      });
    }
  }

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  /// 主题三态弹窗：系统 / 浅色 / 深色
  Future<void> _showThemeDialog() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.str('theme_mode')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'system'),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Row(
                children: [
                  Text(
                    l10n.str('theme_system'),
                    style: TextStyle(fontSize: 16.sp),
                  ),
                  if (_themeMode == 'system') ...[
                    const Spacer(),
                    const Icon(Icons.check, color: AppColors.primary),
                  ],
                ],
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'light'),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Row(
                children: [
                  Text(
                    l10n.str('theme_light'),
                    style: TextStyle(fontSize: 16.sp),
                  ),
                  if (_themeMode == 'light') ...[
                    const Spacer(),
                    const Icon(Icons.check, color: AppColors.primary),
                  ],
                ],
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'dark'),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Row(
                children: [
                  Text(
                    l10n.str('theme_dark'),
                    style: TextStyle(fontSize: 16.sp),
                  ),
                  if (_themeMode == 'dark') ...[
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
    if (selected == null) return;
    await getIt<ThemeService>().switchThemeMode(selected);
    if (mounted) {
      setState(() => _themeMode = selected);
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
              AppToast.show(
                context,
                l10n.str('unit_changed', {'unit': 'kW'}),
                type: ToastType.success,
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
              AppToast.show(
                context,
                l10n.str('unit_changed', {'unit': 'W'}),
                type: ToastType.success,
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
              AppToast.show(
                context, // ignore: use_build_context_synchronously
                l10n.str('timezone_changed', {'timezone': label}),
                type: ToastType.success,
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
              _localeService.switchToSystem();
              setState(() => _savedLocale = null);
              Navigator.pop(context);
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Row(
                children: [
                  Text(
                    l10n.str('language_system'),
                    style: TextStyle(fontSize: 16.sp),
                  ),
                  if (_savedLocale == null) ...[
                    const Spacer(),
                    const Icon(Icons.check, color: AppColors.primary),
                  ],
                ],
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              _localeService.switchLocale(const Locale('zh', 'CN'));
              setState(() {
                _savedLocale = 'zh';
                _currentLocale = 'zh';
              });
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
                  if (_savedLocale == 'zh') ...[
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
              setState(() {
                _savedLocale = 'en';
                _currentLocale = 'en';
              });
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
                  if (_savedLocale == 'en') ...[
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
            SettingsValueRow(
              icon: Icons.cloud_off_rounded,
              accent: AppColors.blue,
              title: l10n.offlineModeSettings,
              subtitle: l10n.offlineModeSettingsHint,
              onTap: () => context.push('/offline-mode-settings'),
            ),
          ]),
          SettingsSectionTitle(
            icon: Icons.palette_outlined,
            title: l10n.displaySettings,
            accent: AppColors.purple,
          ),
          SettingsCard([
            SettingsValueRow(
              icon: Icons.dark_mode,
              accent: AppColors.purple,
              title: l10n.str('theme_mode'),
              subtitle: _themeMode == 'dark'
                  ? l10n.str('theme_dark')
                  : _themeMode == 'light'
                      ? l10n.str('theme_light')
                      : l10n.str('theme_system'),
              onTap: _showThemeDialog,
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
              subtitle: _savedLocale == null
                  ? l10n.str('language_system')
                  : _currentLocale == 'zh'
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
            // 离网相关设置同步重置（UI 已迁移至离网模式设置页）
            await _storage.saveIsLocalMode(false);
            await _storage.saveIsBleDirectEnabled(false);
            await _storage.saveBlePollInterval(180);
            await getIt<BleDirectService>().setEnabled(false);
            await getIt<ThemeService>().switchThemeMode('system');
            await _storage.saveServerUrl(AppConfig.apiBaseUrl);
            await _storage.saveTimezone(TimezoneUtils.defaultTimezone);
            if (mounted) {
              setState(() {
                _themeMode = 'system';
                _currentTimezone = TimezoneUtils.defaultTimezone;
              });
              AppToast.show(
                context,
                l10n.settingsReset,
                type: ToastType.success,
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
