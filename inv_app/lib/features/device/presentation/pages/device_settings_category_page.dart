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

/// 第 2 层：设置分类页
///
/// 按分类固定映射渲染参数控件，支持 visibility 联动、confirmation_mode
/// 二次确认与批量应用（POST set_params，仅写改动项）。
class DeviceSettingsCategoryPage extends StatefulWidget {
  final String sn;
  final String categoryId;

  const DeviceSettingsCategoryPage({
    super.key,
    required this.sn,
    required this.categoryId,
  });

  @override
  State<DeviceSettingsCategoryPage> createState() =>
      _DeviceSettingsCategoryPageState();
}

class _DeviceSettingsCategoryPageState
    extends State<DeviceSettingsCategoryPage> {
  /// 分类定义（含 param_key 固定映射）
  late final SettingsCategory _category = findSettingsCategory(widget.categoryId)!;

  /// 全量 schema（param_key → schema）
  Map<String, ConfigParamSchema> _schemaMap = {};

  /// 原始值（最近一次服务端状态）
  Map<String, dynamic> _original = {};

  /// 工作值（含未应用修改）
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

  // ==================== 参数集合 ====================

  /// 分类内参数：按映射顺序取 schema（缺失跳过），并按 visibility 过滤
  List<ConfigParamSchema> get _visibleParams {
    final result = <ConfigParamSchema>[];
    for (final key in _category.paramKeys) {
      final schema = _schemaMap[key];
      if (schema == null) continue;
      if (!configParamVisible(schema, _pending)) continue;
      result.add(schema);
    }
    return result;
  }

  int get _modifiedCount {
    return _category.paramKeys
        .where(
          (k) => _pending.containsKey(k) && _pending[k] != _original[k],
        )
        .length;
  }

  bool _isModified(String key) =>
      _pending.containsKey(key) && _pending[key] != _original[key];

  // ==================== 修改与应用 ====================

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

  /// 应用修改：POST set_params 仅写改动项
  Future<void> _applyChanges() async {
    final l10n = AppLocalizations.of(context)!;
    final paramsToWrite = <String, dynamic>{};
    for (final key in _category.paramKeys) {
      if (_pending.containsKey(key) && _pending[key] != _original[key]) {
        paramsToWrite[key] = _pending[key];
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
      // 成功后刷新 control-state，同步服务端 desired
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

  // ==================== 渲染 ====================

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.str(_category.titleKey),
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

    final params = _visibleParams;
    if (params.isEmpty) {
      return Center(
        child: Text(
          l10n.str('no_params'),
          style: TextStyle(
            fontSize: 13.sp,
            color: AppColor.textSecondary(context),
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 96.h),
      children: [
        // 分类描述
        Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: Text(
            l10n.str(_category.descKey),
            style: TextStyle(
              fontSize: 12.sp,
              color: AppColor.textSecondary(context),
            ),
          ),
        ),
        for (final schema in params)
          ConfigParamControl(
            schema: schema,
            value: _pending[schema.paramKey],
            modified: _isModified(schema.paramKey),
            onRequestChange: (v) => _requestChange(schema, v),
          ),
      ],
    );
  }
}
