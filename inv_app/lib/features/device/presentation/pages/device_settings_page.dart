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
import 'package:inv_app/features/device/presentation/pages/device_settings_advanced_page.dart';
import 'package:inv_app/features/device/presentation/widgets/config_param_controls.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 远程设置 Tab（设备详情页内嵌，手风琴式）
///
/// 单页展示 8 大功能分类：点击分类卡片原地展开参数控件，
/// 再点收起；修改项全局汇总，底部应用条一次性提交（set_params 仅写改动项）。
/// 高级参数仍为独立页（工程师模式，参数多且按 group_code 分组）。
/// 作为 TabBarView 子页内嵌于设备详情页（无 Scaffold/AppBar），
/// AutomaticKeepAliveClientMixin 保持切 Tab 不重建（避免重复 query_config）。
class RemoteSettingsTab extends StatefulWidget {
  final String sn;

  const RemoteSettingsTab({super.key, required this.sn});

  @override
  State<RemoteSettingsTab> createState() => _RemoteSettingsTabState();
}

class _RemoteSettingsTabState extends State<RemoteSettingsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  /// 全量 schema（param_key → schema），用于摘要文案与参数渲染
  Map<String, ConfigParamSchema> _schemaMap = {};

  /// 原始值（设备真实值：reported 优先、desired 兜底）——
  /// 读取设备配置后输入框与摘要均反映设备最新回报
  Map<String, dynamic> _original = {};

  /// 工作值（含未应用修改）
  Map<String, dynamic> _pending = {};

  /// 当前展开的分类 id（手风琴：同时只展开一个，null 表示全部收起）
  String? _expandedId;

  bool _loading = true;
  bool _failed = false;
  bool _applying = false;
  bool _reading = false;
  DateTime? _lastReadAt;

  /// control-state 拉取成功即视为设备可读（在线徽标）
  bool _readable = false;

  /// 设备是否尚未实际回报配置（reported 空且 sync_status 为 unknown）：
  /// 为 true 时 value 不可信，应给出“未上报”提示而非“读取成功/在线”
  bool _configUnreported = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  // ==================== 数据加载 ====================

  /// 并行拉取参数 schema 与当前值，然后自动读取设备配置
  Future<void> _fetchData() async {
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
        _readable = true;
        _configUnreported = !controlStateHasReported(state);
        _loading = false;
      });
      // 自动发送 query_config 读取设备实际配置
      _readDeviceConfig();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _readable = false;
        _loading = false;
        _failed = true;
      });
    }
  }

  /// 仅刷新 control-state（应用成功后调用）。返回最新 control-state，
  /// 供调用方判断设备是否已实际回报配置；失败返回 null。
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
      // 刷新失败静默：保留本地已应用状态
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

      // 等待设备响应后刷新状态
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
    }
  }

  // ==================== 摘要 / 参数集合 ====================

  /// 分类卡片摘要文案（无值显示 '—'）
  String _categorySummary(SettingsCategory category) {
    final l10n = AppLocalizations.of(context)!;
    final empty = l10n.str('settings_summary_empty');
    final parts = <String>[];
    switch (category.id) {
      case 'work_mode':
        final t = configEnumSummaryText(
          l10n,
          _schemaMap,
          _original,
          'set_output_priority',
        );
        if (t != null) parts.add(t);
      case 'battery':
        final t = configEnumSummaryText(
          l10n,
          _schemaMap,
          _original,
          'set_battery_type',
        );
        if (t != null) parts.add(t);
        final c = configNumberSummaryText(
          _schemaMap,
          _original,
          'set_battery_capacity',
        );
        if (c != null) parts.add(c);
      case 'charge':
        final t = configNumberSummaryText(
          _schemaMap,
          _original,
          'set_max_chg_curr',
        );
        if (t != null) parts.add(t);
      case 'discharge':
        final t = configNumberSummaryText(
          _schemaMap,
          _original,
          'set_max_discharge_current',
        );
        if (t != null) parts.add(t);
      case 'output':
        final v = configNumberSummaryText(
          _schemaMap,
          _original,
          'set_output_voltage',
        );
        if (v != null) parts.add(v);
        final f = configNumberSummaryText(
          _schemaMap,
          _original,
          'set_output_frequency',
        );
        if (f != null) parts.add(f);
      case 'solar':
        final t = configBoolSummaryText(
          l10n,
          _original,
          'set_solar_power_balance',
        );
        if (t != null) parts.add(t);
      case 'generator':
        final t = configNumberSummaryText(
          _schemaMap,
          _original,
          'set_gen_start_voltage',
        );
        if (t != null) parts.add(t);
      case 'alarm':
        final t = configBoolSummaryText(l10n, _original, 'set_buzzer');
        if (t != null) parts.add(t);
    }
    return parts.isEmpty ? empty : parts.join(' / ');
  }

  /// 分类内可见参数：按映射顺序取 schema（缺失跳过），按 visibility 过滤
  List<ConfigParamSchema> _visibleParams(SettingsCategory category) {
    final result = <ConfigParamSchema>[];
    for (final key in category.paramKeys) {
      final schema = _schemaMap[key];
      if (schema == null) continue;
      if (!configParamVisible(schema, _pending)) continue;
      result.add(schema);
    }
    return result;
  }

  /// 全局待提交项数量（跨分类汇总）
  int get _modifiedCount =>
      _pending.keys.where((k) => _pending[k] != _original[k]).length;

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

  /// 应用修改：POST set_params 仅写改动项（跨分类汇总）
  Future<void> _applyChanges() async {
    final l10n = AppLocalizations.of(context)!;
    final paramsToWrite = <String, dynamic>{
      for (final key in _pending.keys)
        if (_pending[key] != _original[key]) key: _pending[key],
    };
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
    super.build(context);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        // Tab 顶部操作条（原 AppBar actions 下沉）
        _buildActionBar(l10n),
        // 主内容
        Expanded(child: _buildBody(l10n)),
        // 底部应用条（有修改项时）
        if (_modifiedCount > 0)
          ConfigApplyBar(
            modifiedCount: _modifiedCount,
            applying: _applying,
            onApply: _applyChanges,
          ),
      ],
    );
  }

  /// Tab 顶部操作条：在线徽标 + 读取设备 + 刷新
  Widget _buildActionBar(AppLocalizations l10n) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 8.w, 4.h),
      child: Row(
        children: [
          if (!_loading) _buildReadableBadge(l10n),
          const Spacer(),
          // 读取设备（含 loading 态）
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: Size(0, 34.h),
              padding: EdgeInsets.symmetric(horizontal: 12.w),
              textStyle:
                  TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
              foregroundColor: AppColors.primary,
              side:
                  BorderSide(color: AppColors.primary.withValues(alpha: 0.45)),
            ),
            onPressed: _reading ? null : _readDeviceConfig,
            icon: _reading
                ? SizedBox(
                    width: 14.w,
                    height: 14.w,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppColors.primary,
                    ),
                  )
                : Icon(Icons.download_rounded, size: 16.sp),
            label: Text(l10n.str('settings_read_device')),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 20.sp,
            color: AppColor.textSecondary(context),
            tooltip: l10n.str('settings_read_device'),
            onPressed: _loading ? null : _fetchData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }

  /// 在线/离线小徽标
  Widget _buildReadableBadge(AppLocalizations l10n) {
    final online = _readable;
    final color = online ? AppColors.online : AppColors.offline;
    return Container(
      margin: EdgeInsets.only(right: 4.w),
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6.w,
            height: 6.w,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: 4.w),
          Text(
            online ? l10n.str('online') : l10n.str('offline'),
            style: TextStyle(
              fontSize: 11.sp,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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
          onPressed: _fetchData,
          child: Text(l10n.retry),
        ),
      );
    }

    return Column(
      children: [
        // 读取中提示条
        if (_reading)
          Container(
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
          ),
        // 设备未上报配置提示条：值不可信，不要谎称“读取成功/在线”
        if (_configUnreported && !_reading)
          Container(
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
          ),
        // 主内容
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
            children: [
              // 读取时间提示
              if (_lastReadAt != null)
                Padding(
                  padding: EdgeInsets.only(bottom: 8.h),
                  child: Text(
                    '${l10n.str("settings_last_read")}: ${_formatTime(_lastReadAt!)}',
                    style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColor.textSecondary(context)),
                  ),
                ),
              // 8 大功能分类：点击原地展开参数控件（手风琴）
              for (final category in settingsCategories)
                _buildCategoryCard(l10n, category),
              SizedBox(height: 6.h),
              // 高级参数入口（独立页：工程师模式）
              _buildAdvancedEntry(l10n),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  /// 分类卡片：彩色图标圆底 + 标题 + 摘要/已修改数 + 展开箭头
  ///
  /// 点击切换展开：展开后内嵌该分类的参数控件（visibility 联动）。
  Widget _buildCategoryCard(AppLocalizations l10n, SettingsCategory category) {
    final theme = Theme.of(context);
    final expanded = _expandedId == category.id;
    final modifiedInCategory =
        category.paramKeys.where((k) => _isModified(k)).length;

    return Card(
      elevation: 0,
      margin: EdgeInsets.only(bottom: 10.h),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.r),
        side: BorderSide(
          color: expanded
              ? category.color.withValues(alpha: 0.45)
              : AppColor.border(context),
          width: expanded ? 1 : 0.6,
        ),
      ),
      color: AppColor.surfaceContainer(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 仅标题行可点击切换展开，避免展开区内误触收起
          InkWell(
            onTap: () {
              setState(() => _expandedId = expanded ? null : category.id);
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
              child: Row(
                children: [
                  // 彩色图标圆底
                  Container(
                    width: 40.w,
                    height: 40.w,
                    decoration: BoxDecoration(
                      color: category.color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      category.icon,
                      size: 22.sp,
                      color: category.color,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.str(category.titleKey),
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        SizedBox(height: 3.h),
                        Text(
                          _categorySummary(category),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColor.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (modifiedInCategory > 0) ...[
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6.w,
                        vertical: 2.h,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                      child: Text(
                        l10n.paramModifiedCount('$modifiedInCategory'),
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(width: 6.w),
                  ],
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 22.sp,
                      color: AppColor.textHint(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 展开区：分类描述 + 参数控件（AnimatedSize 平滑伸缩）
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? _buildExpandedParams(l10n, category)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  /// 展开区内容：分类描述 + 参数控件列表
  Widget _buildExpandedParams(
    AppLocalizations l10n,
    SettingsCategory category,
  ) {
    final params = _visibleParams(category);
    return Padding(
      padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: AppColor.border(context)),
          SizedBox(height: 10.h),
          Text(
            l10n.str(category.descKey),
            style: TextStyle(
              fontSize: 12.sp,
              color: AppColor.textSecondary(context),
            ),
          ),
          SizedBox(height: 10.h),
          if (params.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Text(
                l10n.str('no_params'),
                style: TextStyle(
                  fontSize: 13.sp,
                  color: AppColor.textSecondary(context),
                ),
              ),
            )
          else
            for (final schema in params)
              ConfigParamControl(
                schema: schema,
                value: _pending[schema.paramKey],
                modified: _isModified(schema.paramKey),
                onRequestChange: (v) => _requestChange(schema, v),
              ),
        ],
      ),
    );
  }

  /// 高级参数入口：描边样式（工程师模式，独立页）
  Widget _buildAdvancedEntry(AppLocalizations l10n) {
    final theme = Theme.of(context);
    // 主题自适应的深色调：亮色用石墨灰、暗色用浅灰，避免硬编码色在暗色模式下失配
    final accent = theme.brightness == Brightness.dark
        ? theme.colorScheme.onSurfaceVariant
        : const Color(0xFF374151);
    return Card(
      elevation: 0,
      margin: EdgeInsets.only(bottom: 10.h),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.r),
        side: BorderSide(
          color: AppColor.outline(context).withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      color: AppColor.surfaceContainer(context).withValues(alpha: 0.6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: _openAdvanced,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
          child: Row(
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.construction_rounded,
                  size: 22.sp,
                  color: accent,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.str('settings_cat_advanced'),
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                    SizedBox(height: 3.h),
                    Text(
                      l10n.str('settings_cat_advanced_desc'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColor.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 22.sp,
                color: AppColor.textHint(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 导航 ====================

  /// 进入高级参数页（第 2 层，参数多且按 group_code 分组，保持独立页）
  void _openAdvanced() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeviceSettingsAdvancedPage(sn: widget.sn),
      ),
    );
  }
}
