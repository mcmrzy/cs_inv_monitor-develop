import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
// StationBloc 与 DeviceBloc 存在同名事件/状态（DeviceUnbindRequested 等），加前缀消歧
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart'
    as station_bloc;
import 'package:inv_app/core/widgets/station_selector_sheet.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 长按设备卡片弹出的操作菜单（交互与长按电站一致）：
/// 设备信息头 + 操作项（逐项入场动画）。
/// 操作项：编辑/排序/绑定或换绑/解绑/删除；
/// 全局设备页（无电站上下文）同样显示解绑/删除，并可绑定电站。
/// 绑定/换绑复用共享的 StationSelectorSheet 选择目标电站（事件只依赖 sn）。
class DeviceActionSheet extends StatefulWidget {
  final Map<String, dynamic> device;
  // 电站上下文：非空时显示解绑/删除
  final int? stationId;
  // 点击“设备排序”：关闭菜单后由外层列表进入拖动排序模式
  final VoidCallback? onEnterSortMode;
  // 编辑页返回后回调（外层刷新设备列表）
  final VoidCallback? onEditClosed;

  const DeviceActionSheet({
    super.key,
    required this.device,
    this.stationId,
    this.onEnterSortMode,
    this.onEditClosed,
  });

  @override
  State<DeviceActionSheet> createState() => _DeviceActionSheetState();
}

class _DeviceActionSheetState extends State<DeviceActionSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  String get _sn => (widget.device['sn'] ?? '').toString();

  // 逐项入场动画（淡入 + 上移），间隔 0.15
  Widget _animatedItem(int i, Widget child) {
    final start = i * 0.15;
    final end = (start + 0.7).clamp(0.0, 1.0);
    final animation = CurvedAnimation(
      parent: _ctl,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.2),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
          child: Row(
            children: [
              Container(
                width: 44.w,
                height: 44.w,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.r),
                  color: color.withValues(alpha: 0.1),
                ),
                child: Icon(icon, color: color, size: 22.sp),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14.sp,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 编辑：关闭菜单后进入设备编辑页（沿用现有 extra 契约）
  void _edit() {
    Navigator.pop(context);
    context.push(
      '/device/$_sn/edit',
      extra: {
        'device': widget.device,
        'stationId': widget.stationId,
      },
    ).then((_) => widget.onEditClosed?.call());
  }

  // 排序：关闭菜单后由外层进入拖动排序模式
  void _sort() {
    Navigator.pop(context);
    widget.onEnterSortMode?.call();
  }

  // 解绑确认后走 StationBloc（操作结果由电站详情页/全局设备页监听并刷新）
  Future<void> _confirmUnbind(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.unbind),
        content: const Text('确认解绑该设备吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.unbind,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context
          .read<station_bloc.StationBloc>()
          .add(station_bloc.DeviceUnbindRequested(sn: _sn));
      Navigator.pop(context);
    }
  }

  // 删除确认后走 StationBloc（操作结果由电站详情页监听并刷新）
  Future<void> _confirmDelete(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.str('remove_device')),
        content: Text(l10n.str('confirm_remove_device')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.delete,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context
          .read<station_bloc.StationBloc>()
          .add(station_bloc.DeviceDeleteRequested(sn: _sn));
      Navigator.pop(context);
    }
  }

  // 绑定/换绑：打开电站选择器，选中后走 StationBloc（结果由外层监听刷新）
  Future<void> _bindOrRebind(AppLocalizations l10n) async {
    final hasStation = widget.stationId != null;
    final selected = await _showStationSelector();
    if (selected == null || !mounted) return;
    final (stationId, _) = selected;
    if (hasStation) {
      // 换绑确认：提示原电站将不再显示该设备
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.rebindDevice),
          content: Text(l10n.str('rebind_station_hint')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.confirm),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      context
          .read<station_bloc.StationBloc>()
          .add(
            station_bloc.DeviceRebindRequested(
              sn: _sn,
              newStationId: stationId,
            ),
          );
    } else {
      context
          .read<station_bloc.StationBloc>()
          .add(
            station_bloc.DeviceBindRequested(
              sn: _sn,
              stationId: stationId,
            ),
          );
    }
    Navigator.pop(context);
  }

  // 操作结果 Toast 提示（成功绿色、失败红色）
  void _showResultSnackBar(String message, {required bool success}) {
    if (!mounted) return;
    AppToast.show(context, message, type: success ? ToastType.success : ToastType.error);
  }

  // 电站选择器（复用 add_device_page 提取的共享组件 StationSelectorSheet）
  Future<(int, String)?> _showStationSelector() async {
    final completer = Completer<(int, String)?>();
    if (!mounted) {
      completer.complete(null);
      return completer.future;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) => StationSelectorSheet(
        onSelected: (id, name) {
          Navigator.pop(ctx);
          completer.complete((id, name));
        },
        onCancel: () {
          Navigator.pop(ctx);
          completer.complete(null);
        },
      ),
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final alias = (widget.device['alias'] ?? '').toString();
    final model = (widget.device['model'] ?? '').toString();
    final hasStation = widget.stationId != null;

    // 绑定/换绑/解绑/移除结果反馈：成功绿色、失败红色（sheet pop 前 emit 也能捕获，sn 匹配避免误报）
    return BlocListener<station_bloc.StationBloc, station_bloc.StationState>(
      listener: (context, state) {
        if (state is station_bloc.DeviceBindSuccess && state.sn == _sn) {
          _showResultSnackBar(l10n.str('device_bound'), success: true);
        } else if (state is station_bloc.DeviceRebindSuccess &&
            state.sn == _sn) {
          _showResultSnackBar(l10n.str('device_rebound'), success: true);
        } else if (state is station_bloc.DeviceUnbindSuccess &&
            state.sn == _sn) {
          _showResultSnackBar(l10n.str('device_unbound'), success: true);
        } else if (state is station_bloc.DeviceDeleteSuccess &&
            state.sn == _sn) {
          _showResultSnackBar(l10n.str('device_deleted'), success: true);
        } else if (state is station_bloc.StationError) {
          _showResultSnackBar(
            l10n.str('device_action_failed', {'message': state.message}),
            success: false,
          );
        }
      },
      child: Container(
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: SafeArea(
        // 小屏/大字体下可滚动，避免取消按钮溢出（内容不超限时视觉不变）
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              // 设备信息头
              Row(
                children: [
                  Container(
                    width: 48.w,
                    height: 48.w,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14.r),
                      color: AppColors.primary.withValues(alpha: 0.1),
                    ),
                    child: Icon(
                      Icons.memory_rounded,
                      size: 24.sp,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alias.isNotEmpty ? alias : _sn,
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          model.isNotEmpty ? '$model · $_sn' : _sn,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColors.textHint,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),
              const Divider(height: 1, color: AppColors.divider),
              SizedBox(height: 6.h),
              _animatedItem(
                0,
                _buildActionItem(
                  icon: Icons.edit_outlined,
                  color: AppColors.primary,
                  title: l10n.editDevice,
                  subtitle: l10n.editStationHint,
                  onTap: _edit,
                ),
              ),
              _animatedItem(
                1,
                _buildActionItem(
                  icon: Icons.swap_vert_rounded,
                  color: AppColors.primary,
                  title: l10n.sortDevices,
                  subtitle: l10n.sortModeHint,
                  onTap: _sort,
                ),
              ),
              _animatedItem(
                2,
                _buildActionItem(
                  icon: hasStation
                      ? Icons.swap_horiz_rounded
                      : Icons.link_rounded,
                  color: AppColors.primary,
                  title: hasStation
                      ? l10n.rebindDevice
                      : l10n.str('bind_to_station'),
                  subtitle: hasStation
                      ? l10n.str('device_action_rebind_hint')
                      : l10n.str('device_action_bind_hint'),
                  onTap: () => _bindOrRebind(l10n),
                ),
              ),
              if (hasStation)
                _animatedItem(
                  3,
                  _buildActionItem(
                    icon: Icons.link_off_rounded,
                    color: AppColors.error,
                    title: l10n.unbind,
                    subtitle: l10n.str('device_action_unbind_hint'),
                    onTap: () => _confirmUnbind(l10n),
                  ),
                ),
              _animatedItem(
                hasStation ? 4 : 3,
                _buildActionItem(
                  icon: Icons.delete_outline_rounded,
                  color: AppColors.error,
                  title: l10n.str('remove_device'),
                  subtitle: l10n.str('device_action_delete_hint'),
                  onTap: () => _confirmDelete(l10n),
                ),
              ),
              SizedBox(height: 14.h),
              _animatedItem(
                hasStation ? 5 : 4,
                Material(
                  color: AppColor.surfaceHover(context),
                  borderRadius: BorderRadius.circular(14.r),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14.r),
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 48.h,
                      alignment: Alignment.center,
                      child: Text(
                        l10n.cancel,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
        ),
      ),
    ),
  );
  }
}
