import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class NotifySettingsPage extends StatefulWidget {
  const NotifySettingsPage({super.key});

  @override
  State<NotifySettingsPage> createState() => _NotifySettingsPageState();
}

class _NotifySettingsPageState extends State<NotifySettingsPage> {
  final _storage = getIt<StorageService>();

  bool _pushEnabled = true;
  bool _alertEnabled = true;
  bool _offlineEnabled = true;
  bool _systemEnabled = true;
  String _dndStart = '22:00';
  String _dndEnd = '07:00';
  bool _dndEnabled = false;
  bool _loading = true;

  static const String _keyPush = 'notify_push';
  static const String _keyAlert = 'notify_alert';
  static const String _keyOffline = 'notify_offline';
  static const String _keySystem = 'notify_system';
  static const String _keyDndStart = 'notify_dnd_start';
  static const String _keyDndEnd = 'notify_dnd_end';
  static const String _keyDndEnabled = 'notify_dnd_enabled';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await _getSharedPrefs();
    if (mounted) {
      setState(() {
        _pushEnabled = prefs['$_keyPush'] ?? true;
        _alertEnabled = prefs['$_keyAlert'] ?? true;
        _offlineEnabled = prefs['$_keyOffline'] ?? true;
        _systemEnabled = prefs['$_keySystem'] ?? true;
        _dndStart = prefs['$_keyDndStart'] ?? '22:00';
        _dndEnd = prefs['$_keyDndEnd'] ?? '07:00';
        _dndEnabled = prefs['$_keyDndEnabled'] ?? false;
        _loading = false;
      });
    }
  }

  Future<Map<String, dynamic>> _getSharedPrefs() async {
    return {
      '$_keyPush': await _storage.getNotifyPush(),
      '$_keyAlert': await _storage.getNotifyAlert(),
      '$_keyOffline': await _storage.getNotifyOffline(),
      '$_keySystem': await _storage.getNotifySystem(),
      '$_keyDndStart': await _storage.getNotifyDndStart(),
      '$_keyDndEnd': await _storage.getNotifyDndEnd(),
      '$_keyDndEnabled': await _storage.getNotifyDndEnabled(),
    };
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    switch (key) {
      case _keyPush:
        await _storage.saveNotifyPush(value as bool);
        break;
      case _keyAlert:
        await _storage.saveNotifyAlert(value as bool);
        break;
      case _keyOffline:
        await _storage.saveNotifyOffline(value as bool);
        break;
      case _keySystem:
        await _storage.saveNotifySystem(value as bool);
        break;
      case _keyDndStart:
        await _storage.saveNotifyDndStart(value as String);
        break;
      case _keyDndEnd:
        await _storage.saveNotifyDndEnd(value as String);
        break;
      case _keyDndEnabled:
        await _storage.saveNotifyDndEnabled(value as bool);
        break;
    }
  }

  Future<void> _showTimePickerDialog(String type) async {
    final initialTime = type == 'start' ? _dndStart : _dndEnd;
    final parts = initialTime.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;

    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (selected != null && mounted) {
      final timeStr = '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
      if (type == 'start') {
        setState(() => _dndStart = timeStr);
        await _saveSetting(_keyDndStart, timeStr);
      } else {
        setState(() => _dndEnd = timeStr);
        await _saveSetting(_keyDndEnd, timeStr);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.messageNotifySettings)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.messageNotifySettings)),
      body: ListView(
        children: [
          _buildSectionTitle(l10n.notificationType),
          SwitchListTile(
            title: Text(l10n.pushNotification),
            subtitle: Text(l10n.pushNotificationDesc),
            value: _pushEnabled,
            onChanged: (value) async {
              setState(() => _pushEnabled = value);
              await _saveSetting(_keyPush, value);
            },
            activeColor: AppColors.primary,
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: Text(l10n.alarmPush),
            subtitle: Text(l10n.alarmPushDesc),
            value: _alertEnabled,
            onChanged: (value) async {
              setState(() => _alertEnabled = value);
              await _saveSetting(_keyAlert, value);
            },
            activeColor: AppColors.primary,
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: Text(l10n.offlinePush),
            subtitle: Text(l10n.offlinePushDesc),
            value: _offlineEnabled,
            onChanged: (value) async {
              setState(() => _offlineEnabled = value);
              await _saveSetting(_keyOffline, value);
            },
            activeColor: AppColors.primary,
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: Text(l10n.systemMessage),
            subtitle: Text(l10n.systemMessageDesc),
            value: _systemEnabled,
            onChanged: (value) async {
              setState(() => _systemEnabled = value);
              await _saveSetting(_keySystem, value);
            },
            activeColor: AppColors.primary,
          ),
          _buildSectionTitle(l10n.dndSection),
          SwitchListTile(
            title: Text(l10n.dndMode),
            subtitle: Text('$_dndStart - $_dndEnd'),
            value: _dndEnabled,
            onChanged: (value) async {
              setState(() => _dndEnabled = value);
              await _saveSetting(_keyDndEnabled, value);
            },
            activeColor: AppColors.primary,
          ),
          if (_dndEnabled) ...[
            const Divider(height: 1),
            ListTile(
              title: Text(l10n.startTime),
              subtitle: Text(_dndStart),
              trailing: const Icon(Icons.access_time),
              onTap: () => _showTimePickerDialog('start'),
            ),
            const Divider(height: 1),
            ListTile(
              title: Text(l10n.endTime),
              subtitle: Text(_dndEnd),
              trailing: const Icon(Icons.access_time),
              onTap: () => _showTimePickerDialog('end'),
            ),
          ],
          _buildResetButton(l10n),
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

  Widget _buildResetButton(AppLocalizations l10n) {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: OutlinedButton(
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(l10n.resetNotifySettings),
              content: Text(l10n.resetNotifyConfirm),
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
            await _storage.saveNotifyPush(true);
            await _storage.saveNotifyAlert(true);
            await _storage.saveNotifyOffline(true);
            await _storage.saveNotifySystem(true);
            await _storage.saveNotifyDndEnabled(false);
            await _storage.saveNotifyDndStart('22:00');
            await _storage.saveNotifyDndEnd('07:00');
            if (mounted) {
              setState(() {
                _pushEnabled = true;
                _alertEnabled = true;
                _offlineEnabled = true;
                _systemEnabled = true;
                _dndEnabled = false;
                _dndStart = '22:00';
                _dndEnd = '07:00';
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.notifySettingsReset), duration: const Duration(seconds: 1)),
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
        child: Text(l10n.resetAllNotify),
      ),
    );
  }
}
