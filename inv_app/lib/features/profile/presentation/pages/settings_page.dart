import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:dio/dio.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/services/locale_service.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/utils/timezone_utils.dart';
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
  bool _isDarkMode = false;
  String _unitType = 'kW';
  String _serverUrl = '';
  String _currentLocale = 'zh';
  String _currentTimezone = TimezoneUtils.defaultTimezone;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final localMode = await _storage.getIsLocalMode();
    final darkMode = await _storage.getIsDarkMode();
    final serverUrl = await _storage.getServerUrl();
    final locale = await _storage.getLocale();
    final timezone = await _storage.getTimezone();

    if (mounted) {
      setState(() {
        _isLocalMode = localMode;
        _isDarkMode = darkMode;
        _serverUrl = serverUrl ?? AppConfig.apiBaseUrl;
        _currentLocale = locale ?? 'zh';
        _currentTimezone = timezone ?? TimezoneUtils.defaultTimezone;
        _loading = false;
      });
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
                SnackBar(content: Text(l10n.str('unit_changed', {'unit': 'kW'})), duration: const Duration(seconds: 1)),
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
                SnackBar(content: Text(l10n.str('unit_changed', {'unit': 'W'})), duration: const Duration(seconds: 1)),
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
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
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
                if (mounted) {
                  setState(() => _serverUrl = url);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.serverSaved),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
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
              if (mounted) {
                setState(() => _currentTimezone = id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.str('timezone_changed', {'timezone': label})), duration: const Duration(seconds: 1)),
                );
              }
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
                  Text('中文', style: TextStyle(fontSize: 16.sp)),
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
                  Text('English', style: TextStyle(fontSize: 16.sp)),
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
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.systemSettings)),
      body: ListView(
        children: [
          _buildSectionTitle(l10n.connectionSettings),
          SwitchListTile(
            title: Text(l10n.localMode),
            subtitle: Text(l10n.localModeDesc),
            value: _isLocalMode,
            onChanged: _toggleLocalMode,
            activeColor: AppColors.primary,
          ),
          const Divider(height: 1),
          ListTile(
            title: Text(l10n.customServer),
            subtitle: Text(
              _serverUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showServerUrlDialog,
          ),
          _buildSectionTitle(l10n.displaySettings),
          SwitchListTile(
            title: Text(l10n.darkMode),
            value: _isDarkMode,
            onChanged: _toggleDarkMode,
            activeColor: AppColors.primary,
          ),
          const Divider(height: 1),
          ListTile(
            title: Text(l10n.unitSwitch),
            subtitle: Text(_unitType),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showUnitDialog,
          ),
          const Divider(height: 1),
          ListTile(
            title: Text(l10n.timezone),
            subtitle: Text(TimezoneUtils.getLabel(_currentTimezone, langCode: _currentLocale)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showTimezoneDialog,
          ),
          _buildSectionTitle(l10n.generalSettings),
          ListTile(
            title: Text(l10n.languageSwitch),
            subtitle: Text(_currentLocale == 'zh' ? '中文' : 'English'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showLanguageDialog,
          ),
          _buildResetButton(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
      child: Text(
        title,
        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textHint),
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
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                  child: Text(l10n.reset),
                ),
              ],
            ),
          );

          if (confirmed == true) {
            await _storage.saveIsLocalMode(false);
            await _storage.saveIsDarkMode(false);
            await _storage.saveServerUrl(AppConfig.apiBaseUrl);
            await _storage.saveTimezone(TimezoneUtils.defaultTimezone);
            if (mounted) {
              setState(() {
                _isLocalMode = false;
                _isDarkMode = false;
                _serverUrl = AppConfig.apiBaseUrl;
                _currentTimezone = TimezoneUtils.defaultTimezone;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.settingsReset), duration: const Duration(seconds: 1)),
              );
            }
          }
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: BorderSide(color: AppColors.error.withAlpha(40)),
          padding: EdgeInsets.symmetric(vertical: 14.h),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
        ),
        child: Text(l10n.resetAll),
      ),
    );
  }
}
