import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/settings_widgets.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
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

  /// 保存序号：连续快速切换时仅最后一次失败才回滚，避免旧请求覆盖新状态
  int _saveSeq = 0;

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await _service.fetchPrefs();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _loading = false;
      });
    } catch (_) {
      // 网络异常时回退默认值，避免页面卡死在加载态
      if (!mounted) return;
      setState(() {
        _prefs = NotifyPrefs.defaults;
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l10n.notifySettingsLoadFailed),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// 乐观更新：先切换 UI，保存失败时回滚并提示；返回是否保存成功。
  Future<bool> _update(NotifyPrefs updated) async {
    final seq = ++_saveSeq;
    final previous = _prefs;
    setState(() => _prefs = updated);
    try {
      await _service.savePrefs(updated);
      return true;
    } catch (_) {
      // 期间已有更新的变更，跳过回滚（由最新一次请求负责状态一致性）
      if (!mounted || seq != _saveSeq) return false;
      setState(() => _prefs = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l10n.notifySettingsSaveFailed),
          duration: const Duration(seconds: 2),
        ),
      );
      return false;
    }
  }

  Future<void> _showTimePickerDialog({
    required String current,
    required ValueChanged<String> onPicked,
  }) async {
    final parts = current.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

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
    return Scaffold(
      appBar: AppBar(title: Text(_l10n.messageNotifySettings)),
      body: _loading ? _buildSkeleton() : _buildContent(),
    );
  }

  /// 加载骨架屏（分区标题 + 卡片占位）
  Widget _buildSkeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
      children: [
        _skeletonSectionTitle(),
        const SkeletonListItem(),
        const SkeletonListItem(),
        const SkeletonListItem(),
        _skeletonSectionTitle(),
        const SkeletonListItem(),
        const SkeletonListItem(),
        _skeletonSectionTitle(),
        const SkeletonListItem(),
      ],
    );
  }

  Widget _skeletonSectionTitle() {
    return Padding(
      padding: EdgeInsets.fromLTRB(4.w, 20.h, 4.w, 10.h),
      child: SkeletonBox(width: 120.w, height: 14.h, borderRadius: 4),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: EdgeInsets.only(bottom: 24.h),
      children: [
        // ===== 通知类型（橙） =====
        SettingsSectionTitle(
          icon: Icons.notifications_outlined,
          title: _l10n.notificationType,
          accent: AppColors.orange,
        ),
        SettingsCard([
          SettingsSwitchRow(
            icon: Icons.sensors_outlined,
            accent: AppColors.orange,
            title: _l10n.deviceStatusNotify,
            subtitle: _l10n.deviceStatusNotifyDesc,
            value: _prefs.notifyOnline || _prefs.notifyOffline,
            onChanged: (value) => _update(
              _prefs.copyWith(notifyOnline: value, notifyOffline: value),
            ),
          ),
          SettingsSwitchRow(
            icon: Icons.notification_important_outlined,
            accent: AppColors.orange,
            title: _l10n.alarmNotify,
            subtitle: _l10n.alarmNotifyDesc,
            value: _prefs.notifyAlarm,
            onChanged: (value) => _update(_prefs.copyWith(notifyAlarm: value)),
          ),
          // 告警级别子开关（红/橙/蓝圆点区分级别）；父级关闭时置灰保留上下文
          SettingsLevelRow(
            title: _l10n.alarmFatal,
            value: _prefs.notifyAlarmFatal,
            dotColor: AppColors.error,
            enabled: _prefs.notifyAlarm,
            onChanged: (v) => _update(_prefs.copyWith(notifyAlarmFatal: v)),
          ),
          SettingsLevelRow(
            title: _l10n.alarmWarning,
            value: _prefs.notifyAlarmWarning,
            dotColor: AppColors.warning,
            enabled: _prefs.notifyAlarm,
            onChanged: (v) => _update(_prefs.copyWith(notifyAlarmWarning: v)),
          ),
          SettingsLevelRow(
            title: _l10n.alarmLevelInfo,
            value: _prefs.notifyAlarmInfo,
            dotColor: AppColors.primary,
            enabled: _prefs.notifyAlarm,
            onChanged: (v) => _update(_prefs.copyWith(notifyAlarmInfo: v)),
          ),
          SettingsSwitchRow(
            icon: Icons.done_all_outlined,
            accent: AppColors.orange,
            title: _l10n.alarmCleared,
            value: _prefs.notifyAlarmCleared,
            onChanged: (value) =>
                _update(_prefs.copyWith(notifyAlarmCleared: value)),
          ),
          SettingsSwitchRow(
            icon: Icons.system_update_alt_outlined,
            accent: AppColors.orange,
            title: _l10n.otaNotify,
            value: _prefs.notifyOta,
            onChanged: (value) => _update(_prefs.copyWith(notifyOta: value)),
          ),
          SettingsSwitchRow(
            icon: Icons.campaign_outlined,
            accent: AppColors.orange,
            title: _l10n.systemMessage,
            subtitle: _l10n.systemMessageDesc,
            value: _prefs.notifySystem,
            onChanged: (value) => _update(_prefs.copyWith(notifySystem: value)),
          ),
        ]),
        // ===== 日报（绿） =====
        SettingsSectionTitle(
          icon: Icons.bar_chart_outlined,
          title: _l10n.dailyReportSection,
          accent: AppColors.successLight,
        ),
        SettingsCard([
          SettingsSwitchRow(
            icon: Icons.bar_chart_outlined,
            accent: AppColors.successLight,
            title: _l10n.dailyReport,
            subtitle: _l10n.dailyReportDesc,
            value: _prefs.notifyDaily,
            onChanged: (value) => _update(_prefs.copyWith(notifyDaily: value)),
          ),
          if (_prefs.notifyDaily)
            SettingsTimeRow(
              title: _l10n.dailyReportTime,
              time: _prefs.dailyReportTime,
              accent: AppColors.successLight,
              onTap: () => _showTimePickerDialog(
                current: _prefs.dailyReportTime,
                onPicked: (time) =>
                    _update(_prefs.copyWith(dailyReportTime: time)),
              ),
            ),
        ]),
        // ===== 通知渠道（青绿） =====
        SettingsSectionTitle(
          icon: Icons.notifications_active_outlined,
          title: _l10n.notifyChannelSection,
          accent: AppColors.teal,
        ),
        SettingsCard([
          SettingsSwitchRow(
            icon: Icons.notifications_active_outlined,
            accent: AppColors.teal,
            title: _l10n.appPush,
            subtitle: _l10n.pushNotificationDesc,
            value: _prefs.pushEnabled,
            onChanged: (value) =>
                _update(_prefs.copyWith(pushEnabled: value)),
          ),
          _buildEmailRow(),
        ]),
        // ===== 勿扰模式（靛蓝） =====
        SettingsSectionTitle(
          icon: Icons.bedtime_outlined,
          title: _l10n.dndSection,
          accent: AppColors.indigo,
        ),
        SettingsCard([
          SettingsSwitchRow(
            icon: Icons.bedtime_outlined,
            accent: AppColors.indigo,
            title: _l10n.dndMode,
            subtitle: '${_prefs.dndStart} - ${_prefs.dndEnd}',
            value: _prefs.dndEnabled,
            onChanged: (value) => _update(_prefs.copyWith(dndEnabled: value)),
          ),
          if (_prefs.dndEnabled) ...[
            SettingsTimeRow(
              title: _l10n.startTime,
              time: _prefs.dndStart,
              accent: AppColors.indigo,
              onTap: () => _showTimePickerDialog(
                current: _prefs.dndStart,
                onPicked: (time) => _update(_prefs.copyWith(dndStart: time)),
              ),
            ),
            SettingsTimeRow(
              title: _l10n.endTime,
              time: _prefs.dndEnd,
              accent: AppColors.indigo,
              onTap: () => _showTimePickerDialog(
                current: _prefs.dndEnd,
                onPicked: (time) => _update(_prefs.copyWith(dndEnd: time)),
              ),
            ),
            SettingsSwitchRow(
              icon: Icons.notifications_active_outlined,
              accent: AppColors.indigo,
              title: _l10n.alarmBreakDnd,
              subtitle: _l10n.alarmBreakDndDesc,
              value: _prefs.alarmBreakDnd,
              onChanged: (value) =>
                  _update(_prefs.copyWith(alarmBreakDnd: value)),
            ),
          ],
        ]),
        _buildResetButton(),
      ],
    );
  }

  /// 邮件通知行：未绑定邮箱时禁用开关，点击引导去绑定
  Widget _buildEmailRow() {
    final bound = _prefs.email.isNotEmpty;
    return SettingsSwitchRow(
      icon: Icons.mail_outline,
      accent: AppColors.teal,
      title: _l10n.emailNotify,
      subtitle: _buildEmailSubtitle(),
      value: bound ? _prefs.emailEnabled : false,
      onChanged: bound
          ? (value) => _update(_prefs.copyWith(emailEnabled: value))
          : null,
      // 点击整行引导去绑定邮箱（未绑定或已绑定均可修改）
      onTap: () => context.push('/edit-profile'),
    );
  }

  String _buildEmailSubtitle() {
    if (_prefs.email.isNotEmpty) {
      return _prefs.email;
    }
    return '${_l10n.emailNotBind} · ${_l10n.emailBindHint}';
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
            final ok = await _update(NotifyPrefs.defaults);
            // 仅重置成功才提示，失败时 _update 已提示保存失败
            if (mounted && ok) {
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
