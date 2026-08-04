import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/profile/data/notify_prefs_service.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 消息通知设置页：偏好存储于服务端（user_notify_prefs），
/// 推送链路（JPush/邮件）发送前按此过滤。保存即调 API（乐观更新 + 失败回滚）。
class NotifySettingsPage extends StatefulWidget {
  const NotifySettingsPage({super.key});

  @override
  State<NotifySettingsPage> createState() => _NotifySettingsPageState();
}

class _NotifySettingsPageState extends State<NotifySettingsPage> {
  final _service = getIt<NotifyPrefsService>();

  NotifyPrefs _prefs = NotifyPrefs.defaults;
  bool _loading = true;

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await _service.fetchPrefs();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _loading = false;
    });
  }

  /// 乐观更新：先切换 UI，保存失败时回滚并提示。
  Future<void> _update(NotifyPrefs updated) async {
    final previous = _prefs;
    setState(() => _prefs = updated);
    try {
      await _service.savePrefs(updated);
    } catch (_) {
      if (!mounted) return;
      setState(() => _prefs = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l10n.notifySettingsSaveFailed),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _showTimePickerDialog({
    required String current,
    required ValueChanged<String> onPicked,
  }) async {
    final parts = current.split(':');
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
      final timeStr =
          '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
      onPicked(timeStr);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(_l10n.messageNotifySettings)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_l10n.messageNotifySettings)),
      body: ListView(
        children: [
          _buildSectionTitle(_l10n.notificationType),
          // 设备上下线（合并开关）
          SwitchListTile(
            title: Text(_l10n.deviceStatusNotify),
            subtitle: Text(_l10n.deviceStatusNotifyDesc),
            value: _prefs.notifyOnline || _prefs.notifyOffline,
            onChanged: (value) => _update(
              _prefs.copyWith(notifyOnline: value, notifyOffline: value),
            ),
            activeThumbColor: AppColors.primary,
          ),
          const Divider(height: 1),
          // 告警通知（总开关 + 级别子开关）
          SwitchListTile(
            title: Text(_l10n.alarmNotify),
            subtitle: Text(_l10n.alarmNotifyDesc),
            value: _prefs.notifyAlarm,
            onChanged: (value) => _update(_prefs.copyWith(notifyAlarm: value)),
            activeThumbColor: AppColors.primary,
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.symmetric(horizontal: 16.w),
            childrenPadding: EdgeInsets.only(bottom: 4.h),
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              _l10n.alarmLevel,
              style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
            ),
            children: [
              _buildLevelSwitch(
                title: _l10n.alarmFatal,
                value: _prefs.notifyAlarmFatal,
                onChanged: (v) =>
                    _update(_prefs.copyWith(notifyAlarmFatal: v)),
              ),
              _buildLevelSwitch(
                title: _l10n.alarmWarning,
                value: _prefs.notifyAlarmWarning,
                onChanged: (v) =>
                    _update(_prefs.copyWith(notifyAlarmWarning: v)),
              ),
              _buildLevelSwitch(
                title: _l10n.alarmLevelInfo,
                value: _prefs.notifyAlarmInfo,
                onChanged: (v) => _update(_prefs.copyWith(notifyAlarmInfo: v)),
              ),
            ],
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: Text(_l10n.alarmCleared),
            value: _prefs.notifyAlarmCleared,
            onChanged: (value) =>
                _update(_prefs.copyWith(notifyAlarmCleared: value)),
            activeThumbColor: AppColors.primary,
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: Text(_l10n.otaNotify),
            value: _prefs.notifyOta,
            onChanged: (value) => _update(_prefs.copyWith(notifyOta: value)),
            activeThumbColor: AppColors.primary,
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: Text(_l10n.systemMessage),
            subtitle: Text(_l10n.systemMessageDesc),
            value: _prefs.notifySystem,
            onChanged: (value) => _update(_prefs.copyWith(notifySystem: value)),
            activeThumbColor: AppColors.primary,
          ),
          _buildSectionTitle(_l10n.dailyReportSection),
          SwitchListTile(
            title: Text(_l10n.dailyReport),
            subtitle: Text(_l10n.dailyReportDesc),
            value: _prefs.notifyDaily,
            onChanged: (value) => _update(_prefs.copyWith(notifyDaily: value)),
            activeThumbColor: AppColors.primary,
          ),
          if (_prefs.notifyDaily) ...[
            const Divider(height: 1),
            ListTile(
              title: Text(_l10n.dailyReportTime),
              subtitle: Text(_prefs.dailyReportTime),
              trailing: const Icon(Icons.access_time),
              onTap: () => _showTimePickerDialog(
                current: _prefs.dailyReportTime,
                onPicked: (time) =>
                    _update(_prefs.copyWith(dailyReportTime: time)),
              ),
            ),
          ],
          _buildSectionTitle(_l10n.notifyChannelSection),
          SwitchListTile(
            title: Text(_l10n.appPush),
            subtitle: Text(_l10n.pushNotificationDesc),
            value: _prefs.pushEnabled,
            onChanged: (value) => _update(_prefs.copyWith(pushEnabled: value)),
            activeThumbColor: AppColors.primary,
          ),
          const Divider(height: 1),
          ListTile(
            title: Text(_l10n.emailNotify),
            subtitle: Text(_buildEmailSubtitle()),
            trailing: Switch(
              value: _prefs.emailEnabled,
              activeThumbColor: AppColors.primary,
              onChanged: (value) =>
                  _update(_prefs.copyWith(emailEnabled: value)),
            ),
            onTap: () => context.push('/edit-profile'),
          ),
          _buildSectionTitle(_l10n.dndSection),
          SwitchListTile(
            title: Text(_l10n.dndMode),
            subtitle: Text('${_prefs.dndStart} - ${_prefs.dndEnd}'),
            value: _prefs.dndEnabled,
            onChanged: (value) => _update(_prefs.copyWith(dndEnabled: value)),
            activeThumbColor: AppColors.primary,
          ),
          if (_prefs.dndEnabled) ...[
            const Divider(height: 1),
            ListTile(
              title: Text(_l10n.startTime),
              subtitle: Text(_prefs.dndStart),
              trailing: const Icon(Icons.access_time),
              onTap: () => _showTimePickerDialog(
                current: _prefs.dndStart,
                onPicked: (time) => _update(_prefs.copyWith(dndStart: time)),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              title: Text(_l10n.endTime),
              subtitle: Text(_prefs.dndEnd),
              trailing: const Icon(Icons.access_time),
              onTap: () => _showTimePickerDialog(
                current: _prefs.dndEnd,
                onPicked: (time) => _update(_prefs.copyWith(dndEnd: time)),
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: Text(_l10n.alarmBreakDnd),
              subtitle: Text(_l10n.alarmBreakDndDesc),
              value: _prefs.alarmBreakDnd,
              onChanged: (value) =>
                  _update(_prefs.copyWith(alarmBreakDnd: value)),
              activeThumbColor: AppColors.primary,
            ),
          ],
          _buildResetButton(),
        ],
      ),
    );
  }

  /// 告警级别子开关（ExpansionTile 内）
  Widget _buildLevelSwitch({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 32.w),
      title: Text(title, style: TextStyle(fontSize: 14.sp)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.primary,
    );
  }

  String _buildEmailSubtitle() {
    if (_prefs.email.isNotEmpty) {
      return _prefs.email;
    }
    return '${_l10n.emailNotBind} · ${_l10n.emailBindHint}';
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13.sp,
          fontWeight: FontWeight.w600,
          color: AppColors.textHint,
        ),
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
              title: Text(_l10n.resetNotifySettings),
              content: Text(_l10n.resetNotifyConfirm),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(_l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style:
                      FilledButton.styleFrom(backgroundColor: AppColors.error),
                  child: Text(_l10n.reset),
                ),
              ],
            ),
          );

          if (confirmed == true) {
            await _update(NotifyPrefs.defaults);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_l10n.notifySettingsReset),
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
        child: Text(_l10n.resetAllNotify),
      ),
    );
  }
}
