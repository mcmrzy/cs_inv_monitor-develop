import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
// StationBloc 与 DeviceBloc 存在同名事件/状态（DeviceUnbindRequested 等），加前缀消歧
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart'
    as station_bloc;
import 'package:inv_app/l10n/app_localizations.dart';

/// 设备编辑页：别名/备注可编辑；型号/额定功率/固件/硬件版本由设备自动解析，只读展示。
/// 电站上下文（stationId 非空）时提供排序/换绑/解绑/删除操作。
class DeviceEditPage extends StatefulWidget {
  final String sn;
  // 打开页面时的设备快照（只读信息展示与表单初值）
  final Map<String, dynamic> device;
  // 电站上下文：非空时显示操作区（排序/换绑/解绑/删除）
  final int? stationId;
  // 点击“设备排序”：pop 编辑页后回调，由外层列表进入拖动排序模式
  final VoidCallback? onEnterSortMode;

  const DeviceEditPage({
    super.key,
    required this.sn,
    required this.device,
    this.stationId,
    this.onEnterSortMode,
  });

  @override
  State<DeviceEditPage> createState() => _DeviceEditPageState();
}

class _DeviceEditPageState extends State<DeviceEditPage> {
  late final TextEditingController _aliasController;
  late final TextEditingController _remarkController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _aliasController = TextEditingController(
      text: (widget.device['alias'] ?? '').toString(),
    );
    _remarkController = TextEditingController(
      text: (widget.device['remark'] ?? '').toString(),
    );
  }

  @override
  void dispose() {
    _aliasController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  String _extractString(List<String> keys) {
    for (final key in keys) {
      final val = widget.device[key];
      if (val != null && val.toString().isNotEmpty) {
        return val.toString();
      }
    }
    return '--';
  }

  String _getDeviceTypeLabel(AppLocalizations l10n) {
    final model = (widget.device['model'] ?? '').toString().toLowerCase();
    if (model.contains('battery') ||
        model.contains('bms') ||
        model.contains('储能')) {
      return l10n.deviceTypeStorage;
    }
    if (model.contains('collect') || model.contains('采集')) {
      return l10n.collector;
    }
    return l10n.inverter;
  }

  void _submit() {
    setState(() => _isSubmitting = true);
    context.read<DeviceBloc>().add(
          DeviceUpdateRequested(
            sn: widget.sn,
            alias: _aliasController.text.trim(),
            remark: _remarkController.text.trim(),
          ),
        );
  }

  // 解绑确认后走 StationBloc（操作结果由电站详情页监听并刷新）
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
            child: Text(l10n.unbind,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context
          .read<station_bloc.StationBloc>()
          .add(station_bloc.DeviceUnbindRequested(sn: widget.sn));
      context.pop();
    }
  }

  // 删除确认后走 StationBloc（操作结果由电站详情页监听并刷新）
  Future<void> _confirmDelete(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteDevice),
        content: const Text('确认删除该设备吗？删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context
          .read<station_bloc.StationBloc>()
          .add(station_bloc.DeviceDeleteRequested(sn: widget.sn));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(title: Text(l10n.editDevice)),
      body: BlocListener<DeviceBloc, DeviceState>(
        listener: (context, state) {
          if (state is DeviceUpdateSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.deviceUpdated)),
            );
            context.pop();
          } else if (state is DeviceError) {
            setState(() => _isSubmitting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.translateError(state.message))),
            );
          }
        },
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildInfoCard(l10n),
              SizedBox(height: 16.h),
              _buildFormCard(l10n),
              if (widget.stationId != null) ...[
                SizedBox(height: 16.h),
                _buildActionsCard(l10n),
              ],
              SizedBox(height: 32.h),
              _buildSaveButton(l10n),
              SizedBox(height: 16.h),
              TextButton(
                onPressed: () => context.pop(),
                child: Text(
                  l10n.cancel,
                  style: TextStyle(fontSize: 14.sp, color: AppColor.textHint(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 只读信息卡：SN/类型/型号/额定功率/固件/硬件版本
  Widget _buildInfoCard(AppLocalizations l10n) {
    final ratedPower = widget.device['rated_power'];
    final ratedPowerW = ratedPower is num ? ratedPower.toDouble() : 0.0;
    final firmware = _extractString(['firmware_arm', 'fw_version']);
    final hardware = _extractString(['hardware_version', 'hw_version']);
    final model = _extractString(['model', 'model_name']);

    return _buildSection(
      icon: Icons.memory_rounded,
      title: l10n.deviceBaseInfo,
      subtitle: l10n.autoParsedReadonly,
      child: Column(
        children: [
          _buildInfoRow('SN', widget.sn),
          _buildInfoRow(l10n.deviceTypeLabelKey, _getDeviceTypeLabel(l10n)),
          if (model != '--') _buildInfoRow(l10n.str('device_model'), model),
          if (ratedPowerW > 0)
            _buildInfoRow(
              l10n.ratedPowerLabel,
              '${ratedPowerW.toStringAsFixed(0)} W',
            ),
          if (firmware != '--')
            _buildInfoRow(l10n.str('firmware_version'), firmware),
          if (hardware != '--')
            _buildInfoRow(l10n.str('control_hardware_version'), hardware),
        ],
      ),
    );
  }

  // 信息行：标签左、值右（与设备卡片信息行同款）
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.h),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13.sp, color: AppColor.textHint(context)),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColor.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 表单卡：别名（单行，max 50）+ 备注（多行，max 200）
  Widget _buildFormCard(AppLocalizations l10n) {
    return _buildSection(
      icon: Icons.edit_outlined,
      title: l10n.editDevice,
      subtitle: l10n.str('edit_device_hint'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel(l10n.deviceAlias),
          SizedBox(height: 8.h),
          _buildTextField(
            controller: _aliasController,
            hint: l10n.deviceAliasHint,
            maxLength: 50,
          ),
          SizedBox(height: 16.h),
          _buildFieldLabel(l10n.deviceRemark),
          SizedBox(height: 8.h),
          _buildTextField(
            controller: _remarkController,
            hint: l10n.deviceRemarkHint,
            maxLength: 200,
            maxLines: 4,
          ),
        ],
      ),
    );
  }

  // 操作区（仅电站上下文）：排序/换绑/解绑/删除
  Widget _buildActionsCard(AppLocalizations l10n) {
    return _buildSection(
      icon: Icons.tune_rounded,
      title: l10n.deviceActions,
      subtitle: '',
      child: Column(
        children: [
          // 操作日志入口（路由在后续 Task 注册，运行时解析）
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(l10n.opLogs),
            subtitle: Text(l10n.opLogsSubtitle),
            onTap: () => context.push('/device/op-logs/${widget.sn}'),
          ),
          Divider(height: 1, color: AppColor.border(context)),
          _buildActionTile(
            icon: Icons.swap_vert_rounded,
            color: AppColors.primary,
            label: l10n.sortDevices,
            onTap: () {
              // 关闭编辑页并通知外层进入拖动排序模式
              context.pop();
              widget.onEnterSortMode?.call();
            },
          ),
          _buildActionTile(
            icon: Icons.swap_horiz_rounded,
            color: AppColors.primary,
            label: l10n.rebindDevice,
            onTap: () {
              // TODO: 实现换绑逻辑，需要选择新电站（与列表原行为一致）
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('换绑功能开发中')),
              );
            },
          ),
          _buildActionTile(
            icon: Icons.link_off_rounded,
            color: AppColors.error,
            label: l10n.unbind,
            isDanger: true,
            onTap: () => _confirmUnbind(l10n),
          ),
          _buildActionTile(
            icon: Icons.delete_outline_rounded,
            color: AppColors.error,
            label: l10n.deleteDevice,
            isDanger: true,
            showDivider: false,
            onTap: () => _confirmDelete(l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
    bool isDanger = false,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10.r),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 12.h),
            child: Row(
              children: [
                Icon(icon, size: 20.sp, color: color),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color: isDanger ? color : AppColor.textPrimary(context),
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20.sp,
                  color: AppColor.textHint(context),
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, color: AppColor.border(context)),
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13.sp,
        fontWeight: FontWeight.w500,
        color: AppColor.textPrimary(context),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required int maxLength,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      cursorColor: AppColors.primary,
      style: TextStyle(fontSize: 14.sp, color: AppColor.textPrimary(context)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 14.sp, color: AppColor.textHint(context)),
        counterStyle: TextStyle(fontSize: 11.sp, color: AppColor.textHint(context)),
        filled: true,
        fillColor: AppColor.surfaceHover(context),
        contentPadding:
            EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: AppColor.border(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: AppColor.border(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }

  // 保存按钮：与电站编辑页同款渐变按钮
  Widget _buildSaveButton(AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      height: 52.h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              AppColors.primaryLight,
              AppColors.primary,
              AppColors.primaryDark,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16.r),
            onTap: _isSubmitting ? null : _submit,
            child: Center(
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.save_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          l10n.saveChanges,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// 分区卡片：图标圆底 + 标题 + 副标题 + 内容（与电站编辑页风格一致）
  Widget _buildSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36.w,
                height: 36.w,
                decoration: BoxDecoration(
                  color: AppColor.primarySoft(context),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(icon, size: 18.sp, color: AppColors.primary),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColor.textPrimary(context),
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      SizedBox(height: 1.h),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),
          child,
        ],
      ),
    );
  }
}
