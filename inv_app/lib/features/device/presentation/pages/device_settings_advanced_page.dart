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

/// 第 3 层：高级参数页（工程师模式）
///
/// 内容 = 全部 schema 键按 group_code 分组渲染，外加「危险操作」区块
/// （force_charge / force_discharge 开关与 restart 按钮，沿用旧设置页逻辑）。
/// 顶部黄色警示条提示谨慎修改，不做密码门（产品决定）。
class DeviceSettingsAdvancedPage extends StatefulWidget {
  final String sn;

  const DeviceSettingsAdvancedPage({super.key, required this.sn});

  @override
  State<DeviceSettingsAdvancedPage> createState() =>
      _DeviceSettingsAdvancedPageState();
}

class _DeviceSettingsAdvancedPageState extends State<DeviceSettingsAdvancedPage> {
  /// 全量 schema（param_key → schema）
  Map<String, ConfigParamSchema> _schemaMap = {};

  /// 原始值（最近一次服务端状态）
  Map<String, dynamic> _original = {};

  /// 工作值（含未应用修改，含 force_charge/force_discharge）
  Map<String, dynamic> _pending = {};

  bool _loading = true;
  bool _failed = false;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  // ==================== 数据加载 ====================

  /// 拉取 schema + control-state（进入页面重新请求，简单可靠）
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
      final values = mergeControlState(state);
      if (!mounted) return;
      setState(() {
        _schemaMap = schemas;
        _original = Map.from(values);
        _pending = Map.from(values);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// 仅刷新 control-state（应用成功后调用）
  Future<void> _refreshState() async {
    try {
      final dio = getIt<Dio>();
      final res = await dio.get('/devices/by-sn/${widget.sn}/control-state');
      final state = unwrapApiResponse<Map<String, dynamic>>(
        res.data,
        validate: (v) => v is Map<String, dynamic>,
        expected: 'an object',
      );
      final values = mergeControlState(state);
      if (!mounted) return;
      setState(() {
        _original = Map.from(values);
        _pending = Map.from(values);
      });
    } catch (_) {
      // 刷新失败静默：保留本地已应用状态
    }
  }

  // ==================== 修改与应用 ====================

  int get _modifiedCount {
    return _pending.entries
        .where((e) => e.value != _original[e.key])
        .length;
  }

  bool _isModified(String key) =>
      _pending.containsKey(key) && _pending[key] != _original[key];

  /// 请求修改：confirmation_mode=='modal' 的参数先弹确认框再纳入
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
            Icon(
              Icons.warning_amber_rounded,
              color: AppColors.warning,
              size: 24.sp,
            ),
            SizedBox(width: 8.w),
            Expanded(child: Text(l10n.str('config_confirm_title'))),
          ],
        ),
        content: Text(
          l10n.str('config_confirm_body', {'param': name}),
        ),
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

  /// 应用修改：POST set_params 仅写改动项（含 force_charge/force_discharge）
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
          backgroundColor: AppColors.success,
        ),
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
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _applying = false);
    }
  }

  /// 发送单命令（restart 等，沿用旧设置页逻辑）
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
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.settingSetFailed),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// 危险操作确认弹窗（沿用旧设置页样式），确认后直接发送单命令（restart）
  void _showDangerousConfirm(String confirmKey, String command) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: AppColors.error,
              size: 24.sp,
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(l10n.settingForceConfirmTitle),
            ),
          ],
        ),
        content: Text(l10n.str(confirmKey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
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
      ),
      body: _buildBody(l10n),
      bottomNavigationBar: _modifiedCount > 0
          ? ConfigApplyBar(
              modifiedCount: _modifiedCount,
              applying: _applying,
              onApply: _applyChanges,
            )
          : null,
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

    // 全部 schema 按 group_code 分组（组内按 sort_order），并按 visibility 过滤
    final grouped = <String, List<ConfigParamSchema>>{};
    for (final schema in _schemaMap.values) {
      if (!configParamVisible(schema, _pending)) continue;
      grouped.putIfAbsent(schema.groupCode, () => []).add(schema);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 96.h),
      children: [
        // 顶部黄色警示条
        _buildWarningBanner(l10n),
        // 按 group_code 分组渲染全部参数
        for (final groupCode in configGroupOrder)
          if ((grouped[groupCode] ?? const []).isNotEmpty) ...[
            _buildGroupHeader(l10n, groupCode),
            for (final schema in grouped[groupCode]!)
              ConfigParamControl(
                schema: schema,
                value: _pending[schema.paramKey],
                modified: _isModified(schema.paramKey),
                onRequestChange: (v) => _requestChange(schema, v),
              ),
          ],
        // 危险操作区块
        _buildDangerousZone(l10n),
      ],
    );
  }

  /// 黄色警示条：高级参数供安装调试使用
  Widget _buildWarningBanner(AppLocalizations l10n) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18.w, color: AppColors.warning),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              l10n.str('settings_advanced_warning'),
              style: TextStyle(
                fontSize: 12.sp,
                color: AppColors.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 分组标题
  Widget _buildGroupHeader(AppLocalizations l10n, String groupCode) {
    return Padding(
      padding: EdgeInsets.fromLTRB(2.w, 8.h, 2.w, 8.h),
      child: Text(
        configGroupTitle(l10n, groupCode),
        style: TextStyle(
          fontSize: 13.sp,
          fontWeight: FontWeight.w600,
          color: AppColor.textSecondary(context),
        ),
      ),
    );
  }

  /// 危险操作区块：强制充电/放电开关 + 故障复位按钮（沿用旧设置页逻辑）
  Widget _buildDangerousZone(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Container(
      margin: EdgeInsets.only(top: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4.r,
            offset: Offset(0, 1.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: AppColors.error,
                size: 18.sp,
              ),
              SizedBox(width: 6.w),
              Text(
                l10n.str('settings_dangerous_zone'),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          Text(
            l10n.settingAdvancedHint,
            style: TextStyle(
              fontSize: 12.sp,
              color: AppColor.textSecondary(context),
            ),
          ),
          SizedBox(height: 8.h),
          // 强制充电开关（确认后纳入待提交）
          _buildDangerousSwitch(
            l10n,
            label: l10n.str('setting_force_charge'),
            confirmKey: 'setting_force_charge_confirm',
            value: configBoolIsOn(_pending['force_charge']),
            onConfirm: (v) =>
                setState(() => _pending['force_charge'] = v),
          ),
          // 强制放电开关（确认后纳入待提交）
          _buildDangerousSwitch(
            l10n,
            label: l10n.str('setting_force_discharge'),
            confirmKey: 'setting_force_discharge_confirm',
            value: configBoolIsOn(_pending['force_discharge']),
            onConfirm: (v) =>
                setState(() => _pending['force_discharge'] = v),
          ),
          SizedBox(height: 8.h),
          // 故障复位按钮（确认后立即发送单命令）
          OutlinedButton.icon(
            icon: Icon(Icons.restart_alt_rounded, size: 18.sp),
            label: Text(l10n.settingRestartBtn),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
            ),
            onPressed: () => _showDangerousConfirm(
              'setting_restart_confirm',
              'restart',
            ),
          ),
        ],
      ),
    );
  }

  /// 危险开关行：点击先弹危险确认框，确认后回调纳入修改
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
              color: AppColors.error,
            ),
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

  /// 危险确认弹窗（Switch 版）：确认后执行回调纳入待提交
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
            Icon(
              Icons.warning_amber_rounded,
              color: AppColors.error,
              size: 24.sp,
            ),
            SizedBox(width: 8.w),
            Expanded(child: Text(l10n.settingForceConfirmTitle)),
          ],
        ),
        content: Text(l10n.str(confirmKey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
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
}
