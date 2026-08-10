import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
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
        // ===== 通知类型 =====
        _buildSectionTitle(_l10n.notificationType),
        _buildCard([
          _buildSwitchRow(
            icon: Icons.sensors_outlined,
            title: _l10n.deviceStatusNotify,
            subtitle: _l10n.deviceStatusNotifyDesc,
            value: _prefs.notifyOnline || _prefs.notifyOffline,
            onChanged: (value) => _update(
              _prefs.copyWith(notifyOnline: value, notifyOffline: value),
            ),
          ),
          _buildSwitchRow(
            icon: Icons.notification_important_outlined,
            title: _l10n.alarmNotify,
            subtitle: _l10n.alarmNotifyDesc,
            value: _prefs.notifyAlarm,
            onChanged: (value) => _update(_prefs.copyWith(notifyAlarm: value)),
          ),
          // 告警级别子开关（红/橙/蓝圆点区分级别）
          _buildLevelSwitch(
            title: _l10n.alarmFatal,
            value: _prefs.notifyAlarmFatal,
            dotColor: AppColors.error,
            onChanged: (v) => _update(_prefs.copyWith(notifyAlarmFatal: v)),
          ),
          _buildLevelSwitch(
            title: _l10n.alarmWarning,
            value: _prefs.notifyAlarmWarning,
            dotColor: const Color(0xFFF57C00),
            onChanged: (v) => _update(_prefs.copyWith(notifyAlarmWarning: v)),
          ),
          _buildLevelSwitch(
            title: _l10n.alarmLevelInfo,
            value: _prefs.notifyAlarmInfo,
            dotColor: AppColors.primary,
            onChanged: (v) => _update(_prefs.copyWith(notifyAlarmInfo: v)),
          ),
          _buildSwitchRow(
            icon: Icons.done_all_outlined,
            title: _l10n.alarmCleared,
            value: _prefs.notifyAlarmCleared,
            onChanged: (value) =>
                _update(_prefs.copyWith(notifyAlarmCleared: value)),
          ),
          _buildSwitchRow(
            icon: Icons.system_update_alt_outlined,
            title: _l10n.otaNotify,
            value: _prefs.notifyOta,
            onChanged: (value) => _update(_prefs.copyWith(notifyOta: value)),
          ),
          _buildSwitchRow(
            icon: Icons.campaign_outlined,
            title: _l10n.systemMessage,
            subtitle: _l10n.systemMessageDesc,
            value: _prefs.notifySystem,
            onChanged: (value) => _update(_prefs.copyWith(notifySystem: value)),
          ),
        ]),
        // ===== 日报 =====
        _buildSectionTitle(_l10n.dailyReportSection),
        _buildCard([
          _buildSwitchRow(
            icon: Icons.bar_chart_outlined,
            title: _l10n.dailyReport,
            subtitle: _l10n.dailyReportDesc,
            value: _prefs.notifyDaily,
            onChanged: (value) => _update(_prefs.copyWith(notifyDaily: value)),
          ),
          if (_prefs.notifyDaily)
            _buildTimeRow(
              title: _l10n.dailyReportTime,
              time: _prefs.dailyReportTime,
              onTap: () => _showTimePickerDialog(
                current: _prefs.dailyReportTime,
                onPicked: (time) =>
                    _update(_prefs.copyWith(dailyReportTime: time)),
              ),
            ),
        ]),
        // ===== 通知渠道 =====
        _buildSectionTitle(_l10n.notifyChannelSection),
        _buildCard([
          _buildSwitchRow(
            icon: Icons.notifications_active_outlined,
            title: _l10n.appPush,
            subtitle: _l10n.pushNotificationDesc,
            value: _prefs.pushEnabled,
            onChanged: (value) =>
                _update(_prefs.copyWith(pushEnabled: value)),
          ),
          _buildEmailRow(),
        ]),
        // ===== 勿扰模式 =====
        _buildSectionTitle(_l10n.dndSection),
        _buildCard([
          _buildSwitchRow(
            icon: Icons.bedtime_outlined,
            title: _l10n.dndMode,
            subtitle: '${_prefs.dndStart} - ${_prefs.dndEnd}',
            value: _prefs.dndEnabled,
            onChanged: (value) => _update(_prefs.copyWith(dndEnabled: value)),
          ),
          if (_prefs.dndEnabled) ...[
            _buildTimeRow(
              title: _l10n.startTime,
              time: _prefs.dndStart,
              onTap: () => _showTimePickerDialog(
                current: _prefs.dndStart,
                onPicked: (time) => _update(_prefs.copyWith(dndStart: time)),
              ),
            ),
            _buildTimeRow(
              title: _l10n.endTime,
              time: _prefs.dndEnd,
              onTap: () => _showTimePickerDialog(
                current: _prefs.dndEnd,
                onPicked: (time) => _update(_prefs.copyWith(dndEnd: time)),
              ),
            ),
            _buildSwitchRow(
              icon: Icons.notifications_active_outlined,
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

  /// 分组卡片：圆角白卡 + 细边框，行间细分隔线（缩进避开图标）
  Widget _buildCard(List<Widget> rows) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: AppColor.outline(context).withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 56.w,
                color: AppColor.outline(context).withValues(alpha: 0.5),
              ),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 8.h),
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

  /// 精致开关：打开态淡蓝轨道 + 品牌深蓝圆点（轻盈不厚重），
  /// 关闭态浅灰轨道 + 白圆点 + 细描边；整体缩放 0.9 更纤细耐看
  Widget _buildSwitch({
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Transform.scale(
      scale: 0.9,
      child: Switch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: AppColors.primary.withValues(alpha: 0.15),
        activeThumbColor: AppColors.primary,
        inactiveTrackColor: AppColor.outline(context).withValues(alpha: 0.25),
        inactiveThumbColor: Colors.white,
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : AppColor.outline(context).withValues(alpha: 0.2),
        ),
      ),
    );
  }

  /// 开关行：品牌蓝图标 + 标题 + 可选副标题
  Widget _buildSwitchRow({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w),
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title, style: TextStyle(fontSize: 15.sp)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
            ),
      onTap: () => onChanged(!value),
      trailing: _buildSwitch(value: value, onChanged: onChanged),
    );
  }

  /// 告警级别子开关：彩色圆点标识级别，缩进于告警通知行之下
  Widget _buildLevelSwitch({
    required String title,
    required bool value,
    required Color dotColor,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: 56.w, right: 16.w),
      leading: Container(
        width: 8.w,
        height: 8.w,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dotColor,
        ),
      ),
      title: Text(title, style: TextStyle(fontSize: 14.sp)),
      onTap: () => onChanged(!value),
      trailing: _buildSwitch(value: value, onChanged: onChanged),
    );
  }

  /// 时间选择行：当前时间主色展示 + 右箭头
  Widget _buildTimeRow({
    required String title,
    required String time,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w),
      leading: const Icon(Icons.schedule, color: AppColors.primary),
      title: Text(title, style: TextStyle(fontSize: 15.sp)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            time,
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.primary,
            ),
          ),
          SizedBox(width: 2.w),
          const Icon(Icons.chevron_right, size: 20, color: AppColors.textHint),
        ],
      ),
      onTap: onTap,
    );
  }

  /// 邮件通知行：未绑定邮箱时禁用开关，点击引导去绑定
  Widget _buildEmailRow() {
    final bound = _prefs.email.isNotEmpty;
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w),
      leading: const Icon(Icons.mail_outline, color: AppColors.primary),
      title: Text(_l10n.emailNotify, style: TextStyle(fontSize: 15.sp)),
      subtitle: Text(
        _buildEmailSubtitle(),
        style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
      ),
      trailing: _buildSwitch(
        value: bound ? _prefs.emailEnabled : false,
        onChanged: bound
            ? (value) => _update(_prefs.copyWith(emailEnabled: value))
            : null,
      ),
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
