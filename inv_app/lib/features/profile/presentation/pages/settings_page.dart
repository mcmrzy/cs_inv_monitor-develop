import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/services/locale_service.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/theme/app_theme.dart';
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

    if (mounted) {
      setState(() {
        _isLocalMode = localMode;
        _isDarkMode = darkMode;
        _serverUrl = serverUrl ?? AppConfig.apiBaseUrl;
        _currentLocale = locale ?? 'zh';
        _loading = false;
      });
    }
  }

  Future<void> _toggleLocalMode(bool value) async {
    await _storage.saveIsLocalMode(value);
    if (mounted) {
      setState(() => _isLocalMode = value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? '已切换到本地模式' : '已切换到远程模式'),
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
          content: Text(value ? '已开启深色模式' : '已切换到浅色模式'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _showUnitDialog() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择功率单位'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              setState(() => _unitType = 'kW');
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('单位已切换为 kW'), duration: Duration(seconds: 1)),
              );
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Row(
                children: [
                  Text('kW', style: TextStyle(fontSize: 16.sp)),
                  if (_unitType == 'kW') ...[
                    const Spacer(),
                    Icon(Icons.check, color: AppColors.primary),
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
                const SnackBar(content: Text('单位已切换为 W'), duration: Duration(seconds: 1)),
              );
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Row(
                children: [
                  Text('W', style: TextStyle(fontSize: 16.sp)),
                  if (_unitType == 'W') ...[
                    const Spacer(),
                    Icon(Icons.check, color: AppColors.primary),
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
        title: const Text('自定义服务器地址'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: '例如: http://192.168.1.100:8080/api/v1',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
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
                    const SnackBar(
                      content: Text('服务器地址已保存，请重启应用生效'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppLocalizations.of(context)?.languageSwitch ?? '选择语言'),
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
                    Icon(Icons.check, color: AppColors.primary),
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
                    Icon(Icons.check, color: AppColors.primary),
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
        appBar: AppBar(title: Text(AppLocalizations.of(context)?.systemSettings ?? '系统设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)?.systemSettings ?? '系统设置')),
      body: ListView(
        children: [
          _buildSectionTitle('连接设置'),
          SwitchListTile(
            title: Text(AppLocalizations.of(context)?.localMode ?? '本地模式'),
            subtitle: Text(AppLocalizations.of(context)?.localModeDesc ?? '通过局域网直连设备，无需云端'),
            value: _isLocalMode,
            onChanged: _toggleLocalMode,
            activeColor: AppColors.primary,
          ),
          const Divider(height: 1),
          ListTile(
            title: Text(AppLocalizations.of(context)?.customServer ?? '自定义服务器'),
            subtitle: Text(
              _serverUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showServerUrlDialog,
          ),
          _buildSectionTitle('显示设置'),
          SwitchListTile(
            title: Text(AppLocalizations.of(context)?.darkMode ?? '深色模式'),
            value: _isDarkMode,
            onChanged: _toggleDarkMode,
            activeColor: AppColors.primary,
          ),
          const Divider(height: 1),
          ListTile(
            title: Text(AppLocalizations.of(context)?.unitSwitch ?? '功率单位'),
            subtitle: Text(_unitType),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showUnitDialog,
          ),
          _buildSectionTitle('通用设置'),
          ListTile(
            title: Text(AppLocalizations.of(context)?.languageSwitch ?? '语言'),
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
              title: const Text('重置设置'),
              content: const Text('确定要重置所有设置为默认值吗？'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                  child: const Text('重置'),
                ),
              ],
            ),
          );

          if (confirmed == true) {
            await _storage.saveIsLocalMode(false);
            await _storage.saveIsDarkMode(false);
            await _storage.saveServerUrl(AppConfig.apiBaseUrl);
            if (mounted) {
              setState(() {
                _isLocalMode = false;
                _isDarkMode = false;
                _serverUrl = AppConfig.apiBaseUrl;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('设置已重置'), duration: Duration(seconds: 1)),
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
        child: const Text('重置所有设置'),
      ),
    );
  }
}
