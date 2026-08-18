import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';

/// 设置类页面共享组件（设计系统）。
///
/// 系统设置 / 消息通知设置等页面统一使用本组件，保证：
/// - 分组卡片（圆角 16 + 细边框 + 表面色）
/// - 36×36 圆角图标容器（语义色 10% 底 + 语义色图标）
/// - 精致开关（打开态淡色轨道 + 语义色圆点）
/// - 分区标题（语义色小图标 + 灰色文字）
/// 视觉语言一致，语义色由调用方按分组传入（见 AppColors accent 色板）。

/// 分区标题：语义色小图标 + 灰色加粗文字（iOS 分组标题风格）
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle({
    super.key,
    required this.icon,
    required this.title,
    required this.accent,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Color accent;

  /// 行尾可选操作区（如「重新扫描」按钮）
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 8.h),
      child: Row(
        children: [
          Icon(icon, size: 16.sp, color: accent),
          SizedBox(width: 6.w),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColor.textSecondary(context),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 分组卡片：圆角 16 白卡 + 细边框，行间细分隔线（缩进避开图标容器）
class SettingsCard extends StatelessWidget {
  const SettingsCard(this.children, {super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 56.w,
                color: AppColor.outline(context).withValues(alpha: 0.5),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 圆角图标容器：语义色 10% 浅底 + 语义色图标（列表项视觉锚点）
class SettingsIconContainer extends StatelessWidget {
  const SettingsIconContainer({
    super.key,
    required this.icon,
    required this.accent,
  });

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36.w,
      height: 36.w,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Icon(icon, size: 20.sp, color: accent),
    );
  }
}

/// 精致开关：打开态淡色轨道 + 语义色圆点（轻盈不厚重），
/// 关闭态浅灰轨道 + 白圆点 + 细描边；整体缩放 0.9 更纤细耐看
class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.9,
      child: Switch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: AppColor.primary(context).withValues(alpha: 0.15),
        activeThumbColor: AppColor.primary(context),
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
}

/// 开关行：图标容器 + 标题 + 可选副标题 + 开关；
/// 默认点击行切换开关，可传 onTap 覆盖（如跳转绑定页）；
/// onChanged 为 null 时开关置灰（如未绑定邮箱）
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onTap;
  /// 置灰开关（父级关闭时子项禁用）：开关禁用 + 图标/文字灰化
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w),
      leading: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: SettingsIconContainer(icon: icon, accent: accent),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15.sp,
          color: enabled ? null : AppColor.textHint(context),
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12.sp,
                color: enabled
                    ? AppColor.textSecondary(context)
                    : AppColor.textHint(context),
              ),
            ),
      onTap: enabled
          ? (onTap ?? (onChanged == null ? null : () => onChanged!(!value)))
          : null,
      trailing: SettingsSwitch(
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

/// 级别子开关：彩色圆点标识级别，缩进于主开关行之下
class SettingsLevelRow extends StatelessWidget {
  const SettingsLevelRow({
    super.key,
    required this.title,
    required this.value,
    required this.dotColor,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final bool value;
  final Color dotColor;
  final ValueChanged<bool> onChanged;
  /// 置灰开关（父级关闭时子项禁用）：开关禁用 + 文字/圆点灰化
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: 56.w, right: 16.w),
      leading: Container(
        width: 8.w,
        height: 8.w,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? dotColor : AppColor.textHint(context),
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14.sp,
          color: enabled ? null : AppColor.textHint(context),
        ),
      ),
      onTap: enabled ? () => onChanged(!value) : null,
      trailing: SettingsSwitch(
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

/// 时间选择行：图标容器 + 标题 + 语义色时间 + 右箭头
class SettingsTimeRow extends StatelessWidget {
  const SettingsTimeRow({
    super.key,
    required this.title,
    required this.time,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String time;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w),
      leading: SettingsIconContainer(icon: Icons.schedule, accent: accent),
      title: Text(title, style: TextStyle(fontSize: 15.sp)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            time,
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w500,
              color: accent,
            ),
          ),
          SizedBox(width: 2.w),
          Icon(Icons.chevron_right, size: 20, color: AppColor.textHint(context)),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// 值行：图标容器 + 标题 + 可选副标题 + 自定义尾部（默认右箭头）
class SettingsValueRow extends StatelessWidget {
  const SettingsValueRow({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w),
      leading: SettingsIconContainer(icon: icon, accent: accent),
      title: Text(title, style: TextStyle(fontSize: 15.sp)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: 12.sp, color: AppColor.textSecondary(context)),
            ),
      trailing: trailing ?? Icon(Icons.chevron_right, size: 20, color: AppColor.textHint(context)),
      onTap: onTap,
    );
  }
}
