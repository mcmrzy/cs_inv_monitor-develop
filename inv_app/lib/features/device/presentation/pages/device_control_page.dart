import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../core/entities/inverter_data.dart';
import '../../../../core/entities/command_result.dart';
import '../../../../core/theme/app_theme.dart';

class DeviceControlPage extends StatefulWidget {
  final InverterRealtime? data;
  final bool isOnline;
  final Future<CommandResult?> Function(String command, Map<String, dynamic>? params) onSendCommand;

  const DeviceControlPage({
    super.key,
    this.data,
    this.isOnline = false,
    required this.onSendCommand,
  });

  @override
  State<DeviceControlPage> createState() => _DeviceControlPageState();
}

class _DeviceControlPageState extends State<DeviceControlPage> {
  bool _powerLimitEnabled = false;
  double _powerLimitPercent = 100;
  bool _ecoModeEnabled = false;
  bool _isLoading = false;
  String? _lastMessage;
  bool _lastSuccess = false;

  @override
  void initState() {
    super.initState();
    _powerLimitPercent = 100;
  }

  Future<void> _execute(String command, {Map<String, dynamic>? params}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final result = await widget.onSendCommand(command, params);
      if (mounted) {
        setState(() {
          _lastMessage = result?.message ?? '命令已发送';
          _lastSuccess = result?.isSuccess ?? false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_lastMessage!),
            backgroundColor: _lastSuccess ? AppColors.success : AppColors.error,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('命令发送失败: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmAction(String title, String message, VoidCallback onConfirm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认')),
        ],
      ),
    );
    if (confirmed == true) onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = widget.isOnline;

    return ListView(
      padding: EdgeInsets.all(16.w),
      children: [
        _buildSectionHeader('基本控制'),
        SizedBox(height: 10.h),
        Row(
          children: [
            Expanded(
              child: _buildControlButton(
                icon: Icons.power_settings_new,
                label: '开机',
                color: AppColors.success,
                enabled: isOnline,
                onTap: () => _confirmAction('确认开机', '确定要启动逆变器吗？', () => _execute('ac_on')),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: _buildControlButton(
                icon: Icons.power_off,
                label: '关机',
                color: AppColors.error,
                enabled: isOnline,
                onTap: () => _confirmAction('确认关机', '确定要停止逆变器吗？', () => _execute('ac_off')),
              ),
            ),
          ],
        ),
        SizedBox(height: 24.h),
        _buildSectionHeader('功率控制'),
        SizedBox(height: 10.h),
        _buildToggleCard(
          icon: Icons.tune,
          title: '限功率设置',
          subtitle: '限制逆变器输出功率百分比',
          enabled: _powerLimitEnabled,
          onToggle: (v) => setState(() => _powerLimitEnabled = v),
        ),
        if (_powerLimitEnabled) ...[
          SizedBox(height: 8.h),
          _buildSliderCard(
            value: _powerLimitPercent,
            min: 0,
            max: 100,
            label: '限功率: ${_powerLimitPercent.toStringAsFixed(0)}%',
            onChanged: (v) => setState(() => _powerLimitPercent = v),
          ),
          SizedBox(height: 8.h),
          _buildApplyButton(
            label: '应用限功率 ${_powerLimitPercent.toStringAsFixed(0)}%',
            onTap: () => _execute('set_power_limit', params: {
              'value': _powerLimitPercent.toInt(),
            }),
          ),
        ],
        SizedBox(height: 16.h),
        _buildToggleCard(
          icon: Icons.eco,
          title: '节能模式',
          subtitle: '启用/关闭节能模式',
          enabled: _ecoModeEnabled,
          onToggle: (v) => setState(() => _ecoModeEnabled = v),
        ),
        if (_ecoModeEnabled) ...[
          SizedBox(height: 8.h),
          _buildApplyButton(
            label: '切换节能模式',
            onTap: () => _execute('eco_mode', params: {
              'value': _ecoModeEnabled ? 1 : 0,
            }),
          ),
        ],
        SizedBox(height: 24.h),
        _buildSectionHeader('系统操作'),
        SizedBox(height: 10.h),
        _buildControlButton(
          icon: Icons.restart_alt,
          label: '软重启',
          color: Colors.orange,
          enabled: isOnline,
          onTap: () => _confirmAction('确认重启', '确定要重启逆变器吗？', () => _execute('restart')),
        ),
        SizedBox(height: 10.h),
        _buildControlButton(
          icon: Icons.search,
          label: '立即查询全量数据',
          color: Colors.blue,
          enabled: isOnline,
          onTap: () => _execute('query'),
        ),
        SizedBox(height: 16.h),
        if (!isOnline)
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: AppColors.warning),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text('设备当前离线，控制命令无法发送', style: TextStyle(fontSize: 13.sp, color: AppColors.warning)),
                ),
              ],
            ),
          ),
        SizedBox(height: 32.h),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface));
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 80.h,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16.r),
          onTap: enabled ? onTap : null,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 28.sp, color: enabled ? color : AppColors.offline),
                SizedBox(height: 4.h),
                Text(label, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: enabled ? color : AppColors.offline)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required ValueChanged<bool> onToggle,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4)],
      ),
      child: Row(
        children: [
          Icon(icon, size: 22.sp, color: AppColors.primary),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                Text(subtitle, style: TextStyle(fontSize: 11.sp, color: Theme.of(context).colorScheme.outline)),
              ],
            ),
          ),
          Switch(value: enabled, onChanged: onToggle),
        ],
      ),
    );
  }

  Widget _buildSliderCard({
    required double value,
    required double min,
    required double max,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500)),
          Slider(value: value, min: min, max: max, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildApplyButton({required String label, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _isLoading ? null : onTap,
        icon: _isLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: EdgeInsets.symmetric(vertical: 14.h),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        ),
      ),
    );
  }
}
