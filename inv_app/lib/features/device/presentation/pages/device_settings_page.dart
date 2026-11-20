import 'package:inv_app/features/device/presentation/widgets/device_settings_group_card.dart';
import 'package:inv_app/features/device/presentation/widgets/device_setting_change.dart';
import 'package:inv_app/features/device/presentation/widgets/device_settings_navigation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/utils/api_response.dart';
import 'package:inv_app/core/utils/device_command_state.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/core/widgets/settings_widgets.dart';
import 'package:inv_app/core/widgets/device_list_view.dart'
    show DeviceSearchBar;
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/features/device/domain/entities/config_schema.dart';
import 'package:inv_app/features/device/domain/services/config_param_apply.dart';
import 'package:inv_app/features/device/presentation/pages/device_settings_advanced_page.dart';
import 'package:inv_app/features/device/presentation/widgets/config_param_controls.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 远程设置页签。切换分类与设备页签时保留待应用的修改。
class RemoteSettingsTab extends StatefulWidget {
  final String sn;
  final bool? cloudOnline;
  final bool modelBindingMismatch;

  const RemoteSettingsTab({
    super.key,
    required this.sn,
    this.cloudOnline,
    this.modelBindingMismatch = false,
  });

  @override
  State<RemoteSettingsTab> createState() => _RemoteSettingsTabState();
}

class _RemoteSettingsTabState extends State<RemoteSettingsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  /// 全量 schema（param_key → schema），用于摘要文案与参数渲染
  Map<String, ConfigParamSchema> _schemaMap = {};

  /// 设备最近一次回报的值。旧版入口兼容仅有 desired 的状态。
  Map<String, dynamic> _original = {};

  /// 工作值（含未应用修改）
  Map<String, dynamic> _pending = {};

  final _scrollController = ScrollController();
  String? _selectedCategoryId;

  bool _loading = true;
  bool _failed = false;
  bool _applying = false;
  bool _reading = false;
  String _search = '';
  Set<String> _commands = {};
  // 命令能力可为旧版数值 schema 补充该机型的离散电流档位。
  Map<String, Set<num>> _currentCommandValues = {};
  bool get _guarded => widget.cloudOnline != null;
  bool get _canWrite =>
      !widget.modelBindingMismatch && (!_guarded || widget.cloudOnline == true);
  bool get _canRead =>
      _canWrite && (!_guarded || _commands.contains('query_config'));
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(RemoteSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cloudOnline == true && oldWidget.cloudOnline == false) {
      _fetchData();
    }
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
        dio.get(
          '/devices/by-sn/${Uri.encodeComponent(widget.sn)}/config-schema',
        ),
        dio.get(
          '/devices/by-sn/${Uri.encodeComponent(widget.sn)}/control-state',
        ),
        if (_guarded)
          dio.get(
            '/devices/by-sn/${Uri.encodeComponent(widget.sn)}/control-capabilities',
          ),
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
      final capabilities = _guarded
          ? unwrapApiResponse<List<dynamic>>(
              results[2].data,
              validate: (value) => value is List,
              expected: 'device command capabilities',
            )
          : <dynamic>[];
      if (!mounted) return;
      setState(() {
        _commands = enabledDeviceCommands(capabilities);
        _currentCommandValues = _readCurrentCommandValues(capabilities, schemas);
        _schemaMap = schemas;
        _showControlState(state);
        _readable = true;
        _loading = false;
      });
      // 自动发送 query_config 读取设备实际配置
      if (_canRead && (!_guarded || _schemaMap.isNotEmpty)) {
        _readDeviceConfig();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _readable = false;
        _loading = false;
        _failed = true;
      });
    }
  }

  Map<String, Set<num>> _readCurrentCommandValues(
    List<dynamic> capabilities,
    Map<String, ConfigParamSchema> schemas,
  ) {
    final values = <String, Set<num>>{};
    for (final capability in capabilities) {
      if (capability is! Map || capability['is_enabled'] != true) continue;
      final key = capability['command_code'];
      if (key is! String || schemas[key]?.isCurrent != true) continue;
      final spec = capability['parameter_schema'];
      final args = spec is Map ? spec['args'] : null;
      if (args is! List) continue;
      for (final argument in args) {
        if (argument is! Map || argument['key'] != 'value') continue;
        final options = argument['enum'];
        if (options is! List) continue;
        values[key] = options.whereType<num>().where((n) => n.isFinite).toSet();
      }
    }
    return values;
  }

  Future<Map<String, dynamic>?> _fetchControlState() async {
    try {
      final dio = getIt<Dio>();
      final res = await dio.get(
        '/devices/by-sn/${Uri.encodeComponent(widget.sn)}/control-state',
      );
      return unwrapApiResponse<Map<String, dynamic>>(
        res.data,
        validate: (v) => v is Map<String, dynamic>,
        expected: 'an object',
      );
    } catch (_) {
      return null;
    }
  }

  void _showControlState(Map<String, dynamic> state) {
    final values = _guarded
        ? (state['reported'] is Map
            ? Map<String, dynamic>.from(state['reported'] as Map)
            : <String, dynamic>{})
        : mergeControlStateReportedFirst(state);
    _original = Map.from(values);
    _pending = Map.from(values);
    _configUnreported = !controlStateHasReported(state);
  }

  Future<void> _refreshState() async {
    final state = await _fetchControlState();
    if (mounted && state != null) {
      setState(() => _showControlState(state));
    }
  }

  /// 发送 query_config 命令读取设备当前配置
  Future<void> _readDeviceConfig() async {
    if (_reading || _applying || !_canRead) return;
    setState(() => _reading = true);

    try {
      final dio = getIt<Dio>();
      DateTime? baselineTime;
      if (_guarded) {
        final baselineResponse = await dio.get(
          '/devices/by-sn/${Uri.encodeComponent(widget.sn)}/control-state',
        );
        final baseline = unwrapApiResponse<Map<String, dynamic>>(
          baselineResponse.data,
          validate: (value) => value is Map<String, dynamic>,
          expected: 'device configuration',
        );
        baselineTime =
            DateTime.tryParse(baseline['reported_at']?.toString() ?? '');
        if (!mounted || !_canRead) return;
      }
      final response = await dio.post(
        '/devices/by-sn/${Uri.encodeComponent(widget.sn)}/control',
        data: {'command': 'query_config', 'params': {}},
      );
      unwrapApiResponse<Map<String, dynamic>>(
        response.data,
        validate: (value) =>
            value is Map<String, dynamic> && value['task_id'] is String,
        expected: 'an object containing task_id',
      );

      // 等待设备响应后刷新状态
      await Future<void>.delayed(const Duration(seconds: 2));
      var refreshed = await _fetchControlState();
      if (!mounted) return;
      var reported = refreshed != null && controlStateHasReported(refreshed);
      if (_guarded) {
        final timer = Stopwatch()..start();
        while (mounted && _canRead) {
          final reportTime =
              DateTime.tryParse(refreshed?['reported_at']?.toString() ?? '');
          reported = refreshed != null &&
              refreshed['reported'] is Map &&
              (refreshed['reported'] as Map).isNotEmpty &&
              reportTime != null &&
              (baselineTime == null || reportTime.isAfter(baselineTime));
          if (reported || timer.elapsed >= const Duration(seconds: 28)) break;
          await Future<void>.delayed(const Duration(seconds: 1));
          if (!mounted) return;
          refreshed = await _fetchControlState();
        }
        if (!_canRead) reported = false;
      }

      if (!mounted) return;
      final currentReport = refreshed;
      setState(() {
        if (reported && currentReport != null) {
          _showControlState(currentReport);
          _lastReadAt = DateTime.now();
        }
        _configUnreported = !reported;
      });
    } catch (_) {
      if (mounted) setState(() => _configUnreported = true);
    } finally {
      if (mounted) setState(() => _reading = false);
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
            ) ??
            configNumberSummaryText(
              _schemaMap,
              _original,
              'set_max_charge_current',
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
    if (parts.isNotEmpty) return parts.join(' / ');
    if (!_guarded) return empty;
    final count = _matchingParams(l10n, category).length;
    return Localizations.localeOf(context).languageCode == 'zh'
        ? '$count 项参数'
        : '$count settings';
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

  List<ConfigParamSchema> _matchingParams(
    AppLocalizations l10n,
    SettingsCategory category,
  ) {
    final params = _visibleParams(category);
    if (_search.isEmpty ||
        l10n.str(category.titleKey).toLowerCase().contains(_search)) {
      return params;
    }
    return params.where((schema) {
      final text = '${configParamName(l10n, schema)} ${schema.paramKey}';
      return text.toLowerCase().contains(_search);
    }).toList();
  }

  /// 全局待提交项数量（跨分类汇总）
  int get _modifiedCount =>
      _pending.keys.where((k) => _pending[k] != _original[k]).length;

  bool _isModified(String key) =>
      _pending.containsKey(key) && _pending[key] != _original[key];

  // ==================== 修改与应用 ====================

  /// 请求修改：confirmation_mode=='modal' 的参数先弹确认框再纳入
  void _requestChange(ConfigParamSchema schema, dynamic newValue) {
    if (!_canWrite ||
        _reading ||
        _applying ||
        (_guarded && !_commands.contains(schema.paramKey))) {
      return;
    }
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

  /// 应用修改：按 param_key 逐条下发独立命令（与 Web 远程设置一致）
  String _displayValue(AppLocalizations l10n, String key, Object? value) {
    if (value == null) return '—';
    final schema = _schemaMap[key]!;
    return switch (schema.controlType) {
      'boolean' => configBoolIsOn(value) ? l10n.paramOn : l10n.paramOff,
      'enum' => configEnumSummaryText(l10n, _schemaMap, {key: value}, key) ??
          value.toString(),
      'number' when value is num => formatConfigNumber(value, schema),
      _ => value.toString(),
    };
  }

  Future<void> _applyChanges() async {
    if (_applying || _reading || !_canWrite) return;
    final l10n = AppLocalizations.of(context)!;
    final paramsToWrite = <String, dynamic>{
      for (final key in _pending.keys)
        if (_pending[key] != _original[key]) key: _pending[key],
    };
    if (paramsToWrite.isEmpty) return;
    if (_guarded) {
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(zh ? '确认远程设置' : 'Confirm remote settings'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.sn),
                const SizedBox(height: 12),
                for (final change in paramsToWrite.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DeviceSettingChange(
                      label: configParamName(l10n, _schemaMap[change.key]!),
                      current: _displayValue(
                          l10n, change.key, _original[change.key]),
                      target: _displayValue(l10n, change.key, change.value),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.confirm),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true || !_canWrite) return;
    }

    setState(() => _applying = true);
    try {
      await applyConfigParamWrites(
        dio: getIt<Dio>(),
        sn: widget.sn,
        changes: paramsToWrite,
        verifyReadback: _guarded,
        isActive: () => mounted,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _guarded
                ? (Localizations.localeOf(context).languageCode == 'zh'
                    ? '已回读确认'
                    : 'Verified by device readback')
                : l10n.settingSetSuccess,
          ),
          backgroundColor: AppColors.success,
        ),
      );
      setState(() {
        if (!_guarded) _original = Map.from(_pending);
        _applying = false;
      });
      // 成功后刷新 control-state，同步服务端 desired
      _refreshState();
    } catch (e) {
      if (!mounted) return;
      final detail = e is ApiBusinessException
          ? e.message
          : (e is FormatException ? e.message : null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            detail == null || detail.isEmpty
                ? l10n.settingSetFailed
                : '${l10n.settingSetFailed}: $detail',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _applying = false);
      if (_guarded) await _refreshState();
    }
  }

  // ==================== 渲染 ====================

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        Expanded(child: _buildBody(l10n)),
        if (_modifiedCount > 0 && _canWrite && !_reading)
          ConfigApplyBar(
            modifiedCount: _modifiedCount,
            applying: _applying,
            onApply: _applyChanges,
          ),
      ],
    );
  }

  Widget _buildSettingsHeader(AppLocalizations l10n) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final ready =
        !widget.modelBindingMismatch && (widget.cloudOnline ?? _readable);
    final status = switch ((widget.modelBindingMismatch, widget.cloudOnline)) {
      (true, _) => zh ? '型号待核对' : 'Check model',
      (false, true) => zh ? '云端在线' : 'Cloud online',
      (false, false) => l10n.str('offline'),
      _ => _readable
          ? zh
              ? '配置已加载'
              : 'Configuration loaded'
          : zh
              ? '连接待确认'
              : 'Connection unknown',
    };
    final readAt = _lastReadAt;
    return DeviceSettingsHeader(
      title: l10n.str('remote_settings'),
      icon: Icons.cloud_outlined,
      device: widget.sn,
      status: status,
      ready: ready,
      detail: _reading
          ? l10n.str('settings_reading_device')
          : readAt == null
              ? null
              : '${l10n.str("settings_last_read")} · ${_formatTime(readAt)}',
      readLabel: l10n.str('settings_read_device'),
      reading: _reading,
      onRead: _applying || !_canRead ? null : _readDeviceConfig,
      refreshLabel: l10n.refreshLabel,
      onRefresh: _reading || _applying ? null : _fetchData,
    );
  }

  void _selectCategory(String? id) {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    setState(() => _selectedCategoryId = id);
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

    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final searching = _search.isNotEmpty;
    final categories = [
      for (final category in settingsCategories)
        if ((!_guarded && !searching) ||
            _matchingParams(l10n, category).isNotEmpty)
          category,
    ];
    final selectedId = _selectedCategoryId;
    final selected = searching || selectedId == null
        ? null
        : findSettingsCategory(selectedId);

    return ListView(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
      children: [
        _buildSettingsHeader(l10n),
        if (widget.modelBindingMismatch) ...[
          const SizedBox(height: 10),
          DeviceSettingsNotice(
            warning: true,
            text: zh
                ? '设备上报机型与系统绑定型号不一致，请先核对设备型号绑定。'
                : 'The reported inverter model differs from the assigned model. Check the device model binding first.',
          ),
        ],
        if (widget.cloudOnline == false) ...[
          const SizedBox(height: 10),
          DeviceSettingsNotice(
            warning: true,
            text: zh
                ? '云端离线。设备恢复云端连接后可继续远程设置。'
                : 'Cloud offline. Remote settings resume when the device reconnects.',
          ),
        ],
        if (_configUnreported) ...[
          const SizedBox(height: 10),
          DeviceSettingsNotice(
            warning: true,
            text: l10n.str('settings_not_reported_hint'),
          ),
        ],
        if (_schemaMap.isNotEmpty) ...[
          const SizedBox(height: 14),
          DeviceSearchBar(
            padding: EdgeInsets.zero,
            hintText: zh ? '搜索参数' : 'Search settings',
            fillColor: AppColor.surfaceContainer(context),
            onSearchChanged: (value) =>
                setState(() => _search = value.trim().toLowerCase()),
          ),
        ],
        const SizedBox(height: 16),
        if (_guarded && _schemaMap.isEmpty)
          DeviceSettingsNotice(
            text: zh
                ? '当前设备尚未登记可用的远程设置，请核对系统型号绑定。'
                : 'No remote settings are registered. Check the device model binding.',
          )
        else if (searching && categories.isEmpty)
          DeviceSettingsNotice(
            text: zh ? '未找到匹配的参数' : 'No matching settings',
          )
        else if (searching)
          _buildCategoryContent(l10n, categories)
        else if (selected != null && categories.contains(selected)) ...[
          DeviceSettingsCategoryBack(onPressed: () => _selectCategory(null)),
          _buildCategoryContent(l10n, [selected]),
        ] else if (categories.isNotEmpty) ...[
          DeviceSettingsDirectory(
            entries: [
              for (final category in categories)
                (
                  title: l10n.str(category.titleKey),
                  summary: _categorySummary(category),
                  icon: category.icon,
                  accent: AppColor.accent(context, category.color),
                  onTap: () => _selectCategory(category.id),
                ),
            ],
          ),
          if (!_guarded) ...[
            const SizedBox(height: 12),
            _buildAdvancedEntry(l10n),
          ],
        ],
      ],
    );
  }

  Widget _buildCategoryContent(
    AppLocalizations l10n,
    List<SettingsCategory> categories,
  ) {
    final cards = [
      for (final category in categories) _buildCategoryCard(l10n, category),
    ];
    return _guarded
        ? SettingsCard(cards, margin: EdgeInsets.zero)
        : Column(children: cards);
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  Widget _buildCategoryCard(AppLocalizations l10n, SettingsCategory category) {
    final modified = category.paramKeys.where(_isModified).length;
    return DeviceSettingsGroupCard(
      compact: _guarded,
      title: l10n.str(category.titleKey),
      summary: _categorySummary(category),
      icon: category.icon,
      accent: AppColor.accent(context, category.color),
      expanded: true,
      onToggle: null,
      content: _buildExpandedParams(l10n, category),
      badge: modified == 0
          ? null
          : Text(
              l10n.paramModifiedCount('$modified'),
              style: TextStyle(color: AppColors.primary, fontSize: 11.sp),
            ),
    );
  }

  /// 展开区内容：分类描述 + 参数控件列表
  Widget _buildExpandedParams(
    AppLocalizations l10n,
    SettingsCategory category,
  ) {
    final params = _matchingParams(l10n, category);
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
            for (final schema in params) ...[
              if (schema != params.first)
                Divider(height: 1, color: AppColor.divider(context)),
              ConfigParamControl(
                compact: _guarded,
                embedded: true,
                currentCommandValues: _currentCommandValues[schema.paramKey],
                schema: schema,
                value: _pending[schema.paramKey],
                modified: _isModified(schema.paramKey),
                disabled: _applying ||
                    _reading ||
                    !_canWrite ||
                    (_guarded && !_commands.contains(schema.paramKey)),
                onRequestChange: (v) => _requestChange(schema, v),
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildAdvancedEntry(AppLocalizations l10n) {
    return SettingsCard(
      [
        SettingsValueRow(
          icon: Icons.construction_outlined,
          accent: AppColor.textSecondary(context),
          title: l10n.str('settings_cat_advanced'),
          subtitle: l10n.str('settings_cat_advanced_desc'),
          onTap: _openAdvanced,
        ),
      ],
      margin: EdgeInsets.zero,
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
