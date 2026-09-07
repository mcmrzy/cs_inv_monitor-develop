import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/utils/api_response.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/features/device/domain/entities/config_schema.dart';
import 'package:inv_app/features/device/presentation/widgets/config_param_controls.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 高级参数设置页（工程师模式）
///
/// 功能：
/// - 进入页面自动发送 query_config 读取设备当前配置
/// - 顶部提供手动「读取设备」按钮
/// - 全量 schema 按 group_code 分组渲染
/// - 修改后底部显示「应用」按钮
class DeviceSettingsAdvancedPage extends StatefulWidget {
  final String sn;

  const DeviceSettingsAdvancedPage({super.key, required this.sn});

  @override
  State<DeviceSettingsAdvancedPage> createState() =>
      _DeviceSettingsAdvancedPageState();
}

class _DeviceSettingsAdvancedPageState
    extends State<DeviceSettingsAdvancedPage> {
  /// 全量 schema（param_key → schema）
  Map<String, ConfigParamSchema> _schemaMap = {};

  /// 原始值（最近一次服务端状态）
  Map<String, dynamic> _original = {};

  /// 工作值（含未应用修改）
  Map<String, dynamic> _pending = {};

  bool _loading = true;
  bool _failed = false;
  bool _applying = false;
  bool _reading = false;
  DateTime? _lastReadAt;

  /// 设备尚未实际回报配置（reported 空且 sync_status 为 unknown）
  bool _configUnreported = false;

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  // ==================== 数据加载 ====================

  /// 拉取 schema + control-state，然后自动发送 query_config
  Future<void> _fetchAll() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final dio = getIt<Dio>();
    try {
      final results = await Future.wait([
        dio.get('/devices/by-sn/${widget.sn}/config-schema'),
        dio.get('/devices/by-sn/${widget.sn}/control-state'),
      ]);
      final schemaList = unwrapApiResponse<List<dynamic>>(
        results[0].data,
        validate: (v) => v is List,
        expected: 'an array of config schema',
      );
      final state = unwrapApiResponse<Map<String, dynamic>>(
        results[1].data,
        validate: (v) => v is Map<String, dynamic>,
        expected: 'an object',
      );
      final schemas = <String, ConfigParamSchema>{};
      for (final item in schemaList) {
        if (item is Map<String, dynamic>) {
          final s = ConfigParamSchema.fromJson(item);
          if (s.paramKey.isNotEmpty) schemas[s.paramKey] = s;
        }
      }
      // 基线用 reported 优先：设备真实值优先，未被设备回报的键回退 desired
      final values = mergeControlStateReportedFirst(state);
      if (!mounted) return;
      setState(() {
        _schemaMap = schemas;
        _original = Map.from(values);
        _pending = Map.from(values);
        _configUnreported = !controlStateHasReported(state);
        _loading = false;
      });
      // 自动发送 query_config 读取设备实际配置
      _readDeviceConfig();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// 仅刷新 control-state。返回最新 control-state，失败返回 null。
  Future<Map<String, dynamic>?> _refreshState() async {
    try {
      final dio = getIt<Dio>();
      final res = await dio.get('/devices/by-sn/${widget.sn}/control-state');
      final state = unwrapApiResponse<Map<String, dynamic>>(
        res.data,
        validate: (v) => v is Map<String, dynamic>,
        expected: 'an object',
      );
      final values = mergeControlStateReportedFirst(state);
      if (!mounted) return state;
      setState(() {
        _original = Map.from(values);
        _pending = Map.from(values);
        _configUnreported = !controlStateHasReported(state);
      });
      return state;
    } catch (_) {
      // 刷新失败静默
    }
    return null;
  }

  /// 发送 query_config 命令读取设备当前配置
  Future<void> _readDeviceConfig() async {
    if (_reading) return;
    setState(() => _reading = true);
    final l10n = AppLocalizations.of(context)!;

    try {
      final dio = getIt<Dio>();
      // 发送 query_config 命令
      final response = await dio.post(
        '/devices/by-sn/${widget.sn}/control',
        data: {'command': 'query_config', 'params': {}},
      );
      unwrapApiResponse<Map<String, dynamic>>(
        response.data,
        validate: (value) =>
            value is Map<String, dynamic> && value['task_id'] is String,
        expected: 'an object containing task_id',
      );

      // 等待设备响应后刷新状态（给设备 2 秒处理时间）
      await Future.delayed(const Duration(seconds: 2));
      final refreshed = await _refreshState();

      if (!mounted) return;
      final reported = refreshed != null && controlStateHasReported(refreshed);
      setState(() {
        _reading = false;
        _lastReadAt = DateTime.now();
        _configUnreported = !reported;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reported
                ? l10n.str('settings_read_success')
                : l10n.str('settings_read_no_report'),
          ),
          backgroundColor: reported ? AppColors.success : AppColors.warning,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _reading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.str('settings_read_failed')),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  // ==================== 修改与应用 ====================

  int get _modifiedCount {
    return _pending.entries.where((e) => e.value != _original[e.key]).length;
  }

  bool _isModified(String key) =>
      _pending.containsKey(key) && _pending[key] != _original[key];

  void _requestChange(ConfigParamSchema schema, dynamic newValue) {
    if (schema.needsModalConfirm) {
      _showModalConfirm(schema, newValue);
      return;
    }
    setState(() => _pending[schema.paramKey] = newValue);
  }

  void _showModalConfirm(ConfigParamSchema schema, dynamic newValue) {
    final l10n = AppLocalizations.of(context)!;
    final name = configParamName(l10n, schema);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 24.sp),
            SizedBox(width: 8.w),
            Expanded(child: Text(l10n.str('config_confirm_title'))),
          ],
        ),
        content: Text(l10n.str('config_confirm_body', {'param': name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _pending[schema.paramKey] = newValue);
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  /// 应用修改：POST set_params 仅写改动项
  Future<void> _applyChanges() async {
    final l10n = AppLocalizations.of(context)!;
    final paramsToWrite = <String, dynamic>{};
    for (final entry in _pending.entries) {
      if (entry.value != _original[entry.key]) {
        paramsToWrite[entry.key] = entry.value;
      }
    }
    if (paramsToWrite.isEmpty) return;

    setState(() => _applying = true);
    try {
      final dio = getIt<Dio>();
      final response = await dio.post(
        '/devices/by-sn/${widget.sn}/control',
        data: {'command': 'set_params', 'params': paramsToWrite},
      );
      unwrapApiResponse<Map<String, dynamic>>(
        response.data,
        validate: (value) =>
            value is Map<String, dynamic> && value['task_id'] is String,
        expected: 'an object containing task_id',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(l10n.settingSetSuccess),
            backgroundColor: AppColors.success),
      );
      setState(() {
        _original = Map.from(_pending);
        _applying = false;
      });
      _refreshState();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(l10n.settingSetFailed),
            backgroundColor: AppColors.error),
      );
      setState(() => _applying = false);
    }
  }

  /// 发送单命令（restart 等）
  Future<void> _sendSingleCommand(String command) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final dio = getIt<Dio>();
      final response = await dio.post(
        '/devices/by-sn/${widget.sn}/control',
        data: {'command': command, 'params': {}},
      );
      unwrapApiResponse<Map<String, dynamic>>(
        response.data,
        validate: (value) =>
            value is Map<String, dynamic> && value['task_id'] is String,
        expected: 'an object containing task_id',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l10n.commandSent),
              backgroundColor: AppColors.success),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l10n.settingSetFailed),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showDangerousConfirm(String confirmKey, String command) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.error, size: 24.sp),
            SizedBox(width: 8.w),
            Expanded(child: Text(l10n.settingForceConfirmTitle)),
          ],
        ),
        content: Text(l10n.str(confirmKey)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              _sendSingleCommand(command);
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  void _showDangerousConfirmWithCallback(
    String confirmKey,
    bool newValue,
    ValueChanged<bool> onConfirm,
  ) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.error, size: 24.sp),
            SizedBox(width: 8.w),
            Expanded(child: Text(l10n.settingForceConfirmTitle)),
          ],
        ),
        content: Text(l10n.str(confirmKey)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm(newValue);
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  // ==================== 渲染 ====================

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.str('settings_cat_advanced'),
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17.sp),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        actions: [
          // 读取设备按钮
          IconButton(
            icon: _reading
                ? SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : Icon(Icons.download_rounded, size: 22),
            tooltip: l10n.str('settings_read_device'),
            onPressed: _reading ? null : _readDeviceConfig,
          ),
        ],
      ),
      body: _buildBody(l10n),
      bottomNavigationBar:
          _modifiedCount > 0 ? _buildApplyBar(l10n) : _buildHintBar(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) return const PageSkeleton();
    if (_failed) {
      return XiaoshuoStatePanel(
        asset: CsergyAssets.xiaoshuoOffline,
        title: l10n.str('settings_load_failed'),
        size: 168,
        action: OutlinedButton(
          onPressed: _fetchAll,
          child: Text(l10n.retry),
        ),
      );
    }

    // 全量 schema 按 group_code 分组
    final grouped = <String, List<ConfigParamSchema>>{};
    for (final schema in _schemaMap.values) {
      if (!configParamVisible(schema, _pending)) continue;
      grouped.putIfAbsent(schema.groupCode, () => []).add(schema);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }

    return Column(
      children: [
        // 读取状态提示条
        if (_reading) _buildReadingBanner(l10n),
        // 设备未上报配置提示条：值不可信，不要谎称“读取成功”
        if (_configUnreported && !_reading) _buildNotReportedBanner(l10n),
        // 主内容
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 96.h),
            children: [
              // 顶部提示条
              _buildInfoBanner(l10n),
              SizedBox(height: 8.h),
              // 按 group_code 分组渲染
              for (final groupCode in configGroupOrder)
                if ((grouped[groupCode] ?? const []).isNotEmpty) ...[
                  _buildGroupHeader(l10n, groupCode),
                  _buildGroupCard(grouped[groupCode]!),
                  SizedBox(height: 12.h),
                ],
              // 危险操作区块
              _buildDangerousZone(l10n),
            ],
          ),
        ),
      ],
    );
  }

  /// 设备未上报配置提示条：值不可信
  Widget _buildNotReportedBanner(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      color: AppColors.warning.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 16.sp, color: AppColors.warning),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              l10n.str('settings_not_reported_hint'),
              style: TextStyle(
                  fontSize: 12.sp,
                  color: AppColors.warning,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  /// 读取中提示条
  Widget _buildReadingBanner(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      color: AppColors.primary.withValues(alpha: 0.08),
      child: Row(
        children: [
          SizedBox(
            width: 16.w,
            height: 16.w,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
          SizedBox(width: 10.w),
          Text(
            l10n.str('settings_reading_device'),
            style: TextStyle(
                fontSize: 13.sp,
                color: AppColors.primary,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  /// 顶部信息提示条
  Widget _buildInfoBanner(AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 18.w, color: AppColors.primary),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.str('settings_write_hint'),
                  style: TextStyle(fontSize: 12.sp, color: AppColors.primary),
                ),
                if (_lastReadAt != null) ...[
                  SizedBox(height: 4.h),
                  Text(
                    '${l10n.str("settings_last_read")}: ${_formatTime(_lastReadAt!)}',
                    style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColor.textSecondary(context)),
                  ),
                ],
              ],
            ),
          ),
          // 手动读取按钮
          TextButton.icon(
            onPressed: _reading ? null : _readDeviceConfig,
            icon: Icon(Icons.refresh_rounded, size: 16.sp),
            label: Text(l10n.str('settings_read_device'),
                style: TextStyle(fontSize: 12.sp)),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  /// 分组标题
  Widget _buildGroupHeader(AppLocalizations l10n, String groupCode) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Row(
        children: [
          Container(
            width: 3.w,
            height: 14.h,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            configGroupTitle(l10n, groupCode),
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: AppColor.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 分组卡片：将同组参数包裹在圆角卡片内
  Widget _buildGroupCard(List<ConfigParamSchema> schemas) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8.r,
            offset: Offset(0, 2.h),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.r),
        child: Column(
          children: [
            for (int i = 0; i < schemas.length; i++) ...[
              if (i > 0) Divider(height: 1.h, indent: 16.w, endIndent: 16.w),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                child: ConfigParamControl(
                  schema: schemas[i],
                  value: _pending[schemas[i].paramKey],
                  modified: _isModified(schemas[i].paramKey),
                  onRequestChange: (v) => _requestChange(schemas[i], v),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 底部应用栏
  Widget _buildApplyBar(AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8.r,
            offset: Offset(0, -2.h),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                '$_modifiedCount ${l10n.str("settings_no_changes").split("暂无")[0]}',
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.warning,
                ),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: FilledButton(
                onPressed: _applying ? null : _applyChanges,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                ),
                child: _applying
                    ? SizedBox(
                        width: 20.w,
                        height: 20.w,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(l10n.applyChanges,
                        style: TextStyle(
                            fontSize: 15.sp, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 无修改时的底部提示栏
  Widget _buildHintBar(AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
      child: SafeArea(
        child: Text(
          l10n.str('settings_write_hint'),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12.sp, color: AppColor.textSecondary(context)),
        ),
      ),
    );
  }

  /// 危险操作区块
  Widget _buildDangerousZone(AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8.r,
            offset: Offset(0, 2.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: AppColors.error, size: 18.sp),
              SizedBox(width: 6.w),
              Text(
                l10n.str('settings_dangerous_zone'),
                style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.error),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          Text(
            l10n.settingAdvancedHint,
            style: TextStyle(
                fontSize: 12.sp, color: AppColor.textSecondary(context)),
          ),
          SizedBox(height: 12.h),
          _buildDangerousSwitch(
            l10n,
            label: l10n.str('setting_force_charge'),
            confirmKey: 'setting_force_charge_confirm',
            value: configBoolIsOn(_pending['force_charge']),
            onConfirm: (v) => setState(() => _pending['force_charge'] = v),
          ),
          Divider(height: 16.h),
          _buildDangerousSwitch(
            l10n,
            label: l10n.str('setting_force_discharge'),
            confirmKey: 'setting_force_discharge_confirm',
            value: configBoolIsOn(_pending['force_discharge']),
            onConfirm: (v) => setState(() => _pending['force_discharge'] = v),
          ),
          SizedBox(height: 12.h),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: Icon(Icons.restart_alt_rounded, size: 18.sp),
              label: Text(l10n.settingRestartBtn),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                padding: EdgeInsets.symmetric(vertical: 12.h),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r)),
              ),
              onPressed: () =>
                  _showDangerousConfirm('setting_restart_confirm', 'restart'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerousSwitch(
    AppLocalizations l10n, {
    required String label,
    required String confirmKey,
    required bool value,
    required ValueChanged<bool> onConfirm,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.error),
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: AppColors.error,
          onChanged: (v) =>
              _showDangerousConfirmWithCallback(confirmKey, v, onConfirm),
        ),
      ],
    );
  }
}
