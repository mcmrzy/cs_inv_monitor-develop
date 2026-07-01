import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/entities/device_model_field.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class DeviceControlPage extends StatefulWidget {
  final String deviceSN;

  const DeviceControlPage({super.key, required this.deviceSN});

  @override
  State<DeviceControlPage> createState() => _DeviceControlPageState();
}

class _DeviceControlPageState extends State<DeviceControlPage> {
  List<DeviceModelField> _controlFields = [];
  bool _loading = true;
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _fetchControlFields();
  }

  Future<void> _fetchControlFields() async {
    final dio = getIt<Dio>();

    // 独立 try-catch，一个失败不影响另一个
    List<DeviceModelField> controlFields = [];
    bool isOnline = false;

    try {
      final fieldsRes = await dio.get('/devices/${widget.deviceSN}/control-fields');
      final fieldsData = fieldsRes.data['data'] as List<dynamic>? ?? [];
      controlFields = fieldsData
          .map((e) => DeviceModelField.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}

    try {
      final deviceRes = await dio.get('/devices/${widget.deviceSN}');
      final deviceData = deviceRes.data['data'] as Map<String, dynamic>? ?? {};
      isOnline = deviceData['online_status']?['online'] == true ||
          deviceData['device']?['status'] == 1;
    } catch (_) {}

    if (mounted) {
      setState(() {
        _controlFields = controlFields;
        _isOnline = isOnline;
        _loading = false;
      });
    }
  }

  Future<void> _sendCommand(DeviceModelField field, {Map<String, dynamic>? params}) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final dio = getIt<Dio>();
      final response = await dio.post('/devices/${widget.deviceSN}/control', data: {
        'command': field.fieldKey,
        'params': params ?? {},
      });

      if (mounted) {
        final code = response.data['code'];
        final msg = response.data['message'] ?? l10n.commandSent;
        final success = code == 0;

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success ? '✅ $msg' : '❌ $msg'),
          backgroundColor: success ? AppColors.success : AppColors.error,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.str('command_send_failed', {'error': '$e'})),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50.h),
        child: AppBar(
          title: Text(l10n.deviceControl, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17.sp)),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _controlFields.isEmpty
              ? _buildEmpty()
              : _buildContent(),
    );
  }

  Widget _buildEmpty() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune_rounded, size: 44.sp, color: AppColors.textHint),
          SizedBox(height: 12.h),
          Text(l10n.noControlCommand, style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
          SizedBox(height: 8.h),
          Text(l10n.configureControlFieldsHint, style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: EdgeInsets.all(16.w),
      children: [
        // 离线提示
        if (!_isOnline)
          Container(
            margin: EdgeInsets.only(bottom: 16.h),
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.wifi_off_rounded, size: 18.w, color: AppColors.warning),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(l10n.deviceOfflineWarning,
                    style: TextStyle(fontSize: 12.sp, color: AppColors.warning)),
                ),
              ],
            ),
          ),

        // 控制命令列表
        ..._controlFields.map((field) => _buildControlCard(field)),
      ],
    );
  }

  Widget _buildControlCard(DeviceModelField field) {
    final l10n = AppLocalizations.of(context)!;
    final params = field.controlParams ?? {};
    final label = params['label'] as String? ?? field.fieldName;
    final confirm = params['confirm'] == true;
    final confirmMsg = params['confirm_message'] as String? ?? l10n.str('confirm_execute', {'label': label});
    final inputType = params['input_type'] as String?;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: AppColor.card(context),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        leading: Container(
          width: 40.w,
          height: 40.w,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(_getCommandIcon(field.fieldKey), size: 20.sp, color: AppColors.primary),
        ),
        title: Text(label, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
        subtitle: Text(
          '${l10n.commandPrefix}: ${field.fieldKey}',
          style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
        ),
        trailing: _isOnline
            ? Icon(Icons.chevron_right_rounded, color: AppColors.textHint)
            : Icon(Icons.lock_outline, color: AppColors.textHint, size: 18.sp),
        onTap: !_isOnline
            ? null
            : () {
                if (inputType == 'number') {
                  _showNumberInput(field, params);
                } else if (confirm) {
                  _showConfirm(field, label, confirmMsg);
                } else {
                  _sendCommand(field);
                }
              },
      ),
      ),
    );
  }

  void _showConfirm(DeviceModelField field, String title, String message) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _sendCommand(field);
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  void _showNumberInput(DeviceModelField field, Map<String, dynamic> params) {
    final l10n = AppLocalizations.of(context)!;
    final min = (params['min'] as num?)?.toDouble() ?? 0;
    final max = (params['max'] as num?)?.toDouble() ?? 10000;
    final step = (params['step'] as num?)?.toDouble() ?? 1;
    final unit = params['unit'] as String? ?? '';
    final label = params['label'] as String? ?? field.fieldName;

    double value = min;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(label),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${value.toStringAsFixed(0)} $unit',
                style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w700, color: AppColors.primary)),
              SizedBox(height: 16.h),
              Slider(
                value: value,
                min: min,
                max: max,
                divisions: max > min ? ((max - min) / step).round().clamp(1, 10000) : null,
                onChanged: (v) => setDialogState(() => value = v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${min.toStringAsFixed(0)}$unit', style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
                  Text('${max.toStringAsFixed(0)}$unit', style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
                ],
              ),
            ],
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _sendCommand(field, params: {'value': value});
              },
              child: Text(l10n.send),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCommandIcon(String fieldKey) {
    switch (fieldKey) {
      case 'ac_on':
        return Icons.power_settings_new;
      case 'ac_off':
        return Icons.power_off;
      case 'set_power_limit':
        return Icons.tune;
      case 'eco_mode':
        return Icons.eco;
      case 'restart':
        return Icons.restart_alt;
      case 'query':
        return Icons.search;
      default:
        return Icons.send_rounded;
    }
  }
}
