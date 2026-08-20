import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/entities/device_model_field.dart';
import 'package:inv_app/core/utils/api_response.dart';
import 'package:inv_app/core/utils/energy_schedule.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';

import 'package:inv_app/l10n/app_localizations.dart';
import 'package:inv_app/features/ota/presentation/pages/local_ota_channel_select_page.dart';

part 'device_control_sections.dart';

/// 从嵌套或扁平的 realtime 数据中提取值
/// V2 数据嵌套在分组下（ac.output_power, bat.battery_soc 等），
/// V1 数据是扁平的（ac_power, battery_soc 等）
dynamic _rtPick(Map<String, dynamic> rt, String flatKey, String group, String nestedKey) {
  // 先尝试嵌套路径：rt[group][nestedKey]
  final groupData = rt[group];
  if (groupData is Map<String, dynamic>) {
    final v = groupData[nestedKey];
    if (v != null) return v;
  }
  // 回退扁平路径：rt[flatKey]
  return rt[flatKey];
}

double _rtPickNum(Map<String, dynamic> rt, String flatKey, String group, String nestedKey, [double fallback = 0]) {
  return (_rtPick(rt, flatKey, group, nestedKey) as num?)?.toDouble() ?? fallback;
}

class DeviceControlPage extends StatefulWidget {
  final String deviceSN;

  const DeviceControlPage({super.key, required this.deviceSN});

  @override
  State<DeviceControlPage> createState() => _DeviceControlPageState();
}

class _DeviceControlPageState extends State<DeviceControlPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Shared state
  bool _loading = true;
  int _failedSectionCount = 0;
  bool _isOnline = false;
  Timer? _pollTimer;
  int _pollGeneration = 0;
  Map<String, int> _riskLevels = {};

  // Tab1 — 运行
  Map<String, dynamic> _realtimeData = {};
  bool _acOutputOn = false;
  bool _muteEnabled = false;

  // Tab2 — 电池保护
  double _reserveSoc = 20; // low_x10 / 10
  double _chargeTargetSoc = 100; // high_x10 / 10
  int _chargeSpeedPreset = 1; // 0=温和 1=标准 2=快速
  Map<String, dynamic> _bmsLimits = {};

  // Tab3 — 能源计划
  List<Map<String, dynamic>> _energySchedule = [];
  int _energyScheduleRevision = 0;
  String _energyScheduleTimezone = 'Asia/Shanghai';
  bool _energyScheduleEnabled = true;
  List<dynamic> _controlOverrides = [];

  // Tab4 — 设备信息
  Map<String, dynamic> _deviceInfo = {};
  Map<String, dynamic> _controlState = {};
  List<dynamic> _commandHistory = [];

  bool _isListOrPage(dynamic value) =>
      value is List || (value is Map && value['items'] is List);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchAllData();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Data fetching
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _fetchAllData() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    final results = await Future.wait([
      _fetchControlFields(),
      _fetchRealtimeData(),
      _fetchEnergySchedule(),
      _fetchControlState(),
      _fetchCommandHistory(),
    ]);
    if (mounted) {
      setState(() {
        _failedSectionCount = results.where((success) => !success).length;
        _loading = false;
      });
    }
  }

  Future<bool> _fetchControlFields() async {
    final dio = getIt<Dio>();
    bool isOnline = false;
    Map<String, int> riskLevels = {};
    var success = true;

    try {
      final fieldsRes =
          await dio.get('/devices/by-sn/${widget.deviceSN}/control-fields');
      final fieldsData = unwrapApiResponse<List<dynamic>>(
        fieldsRes.data,
        validate: (data) => data is List,
        expected: 'a list',
      );
      // Control fields are fetched for risk metadata; UI tabs use dedicated endpoints
      fieldsData
          .map((e) => DeviceModelField.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      success = false;
    }

    try {
      final capsRes = await dio
          .get('/devices/by-sn/${widget.deviceSN}/control-capabilities');
      final capsData = unwrapApiResponse<List<dynamic>>(
        capsRes.data,
        validate: (data) => data is List,
        expected: 'a list',
      );
      for (final cap in capsData) {
        if (cap is Map<String, dynamic>) {
          final code = cap['command_code'] as String?;
          final risk = cap['risk_level'] as int?;
          if (code != null && risk != null) {
            riskLevels[code] = risk;
          }
        }
      }
    } catch (_) {
      success = false;
    }

    try {
      final deviceRes = await dio.get('/devices/by-sn/${widget.deviceSN}');
      final deviceData = unwrapApiResponse<Map<String, dynamic>>(
        deviceRes.data,
        validate: (data) => data is Map<String, dynamic>,
        expected: 'an object',
      );
      isOnline = deviceData['online_status']?['online'] == true ||
          deviceData['device']?['status'] == 1;
      _deviceInfo = deviceData;
    } catch (_) {
      success = false;
    }

    if (mounted) {
      setState(() {
        _isOnline = isOnline;
        _riskLevels = riskLevels;
      });
    }
    return success;
  }

  Future<bool> _fetchRealtimeData() async {
    final dio = getIt<Dio>();
    try {
      final res = await dio.get('/devices/by-sn/${widget.deviceSN}/realtime');
      final data = unwrapApiResponse<Map<String, dynamic>>(
        res.data,
        validate: (value) => value is Map<String, dynamic>,
        expected: 'an object',
      );
      if (mounted) {
        setState(() {
          _realtimeData = data;
          // Infer AC output state from realtime data (V2: ac.output_power, V1: output_power)
          final outputPower = _rtPickNum(data, 'output_power', 'ac', 'output_power');
          _acOutputOn = data['ac_output_on'] == true ||
              data['ac_on'] == true ||
              outputPower > 0;
        });
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _fetchEnergySchedule() async {
    final dio = getIt<Dio>();
    var success = true;
    try {
      final res =
          await dio.get('/devices/by-sn/${widget.deviceSN}/energy-schedule');
      final data = unwrapApiResponse<Map<String, dynamic>>(
        res.data,
        validate: isEnergySchedulePayload,
        expected: 'a schedule object containing periods',
      );
      if (mounted) {
        setState(() {
          _energySchedule = normalizeSchedulePeriods(data['periods']);
          _energyScheduleRevision = (data['revision'] as num?)?.toInt() ?? 0;
          _energyScheduleTimezone =
              data['timezone'] as String? ?? 'Asia/Shanghai';
          _energyScheduleEnabled = data['enabled'] as bool? ?? true;
        });
      }
    } catch (_) {
      success = false;
    }

    try {
      final res =
          await dio.get('/devices/by-sn/${widget.deviceSN}/control-overrides');
      final data = unwrapApiResponse<dynamic>(
        res.data,
        validate: _isListOrPage,
        expected: 'a list or page object',
      );
      if (mounted) {
        setState(() {
          _controlOverrides = data is List
              ? data
              : (data is Map ? (data['items'] as List? ?? []) : []);
        });
      }
    } catch (_) {
      success = false;
    }
    return success;
  }

  Future<bool> _fetchControlState() async {
    final dio = getIt<Dio>();
    try {
      final res =
          await dio.get('/devices/by-sn/${widget.deviceSN}/control-state');
      final data = unwrapApiResponse<Map<String, dynamic>>(
        res.data,
        validate: (value) => value is Map<String, dynamic>,
        expected: 'an object',
      );
      if (mounted) {
        setState(() {
          _controlState = data;
          // Parse BMS limits if present
          _bmsLimits = (data['bms_limits'] as Map<String, dynamic>?) ??
              (data['reported']?['bms_limits'] as Map<String, dynamic>?) ??
              {};
          // Parse SOC window from desired/reported
          final desired = data['desired'] as Map<String, dynamic>?;
          final reported = data['reported'] as Map<String, dynamic>?;
          final lowSrc = desired?['soc_low'] ?? reported?['soc_low'];
          final highSrc = desired?['soc_high'] ?? reported?['soc_high'];
          if (lowSrc != null) {
            _reserveSoc = (lowSrc as num).toDouble();
          }
          if (highSrc != null) {
            _chargeTargetSoc = (highSrc as num).toDouble();
          }
        });
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _fetchCommandHistory() async {
    final dio = getIt<Dio>();
    try {
      final res = await dio.get(
        '/devices/by-sn/${widget.deviceSN}/commands',
        queryParameters: {'page_size': 20},
      );
      final data = unwrapApiResponse<dynamic>(
        res.data,
        validate: _isListOrPage,
        expected: 'a list or page object',
      );
      List? items;
      if (data is Map) {
        items = data['items'] as List?;
      } else if (data is List) {
        items = data;
      }
      if (mounted) {
        setState(() => _commandHistory = items ?? []);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Command sending (preserved from original)
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _sendCommand(
    String commandCode, {
    Map<String, dynamic>? params,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final dio = getIt<Dio>();
      final response = await dio.post(
        '/devices/by-sn/${widget.deviceSN}/control',
        data: {
          'command': commandCode,
          'params': params ?? {},
        },
      );

      if (!mounted) return;
      final code = response.data['code'];
      final msg = response.data['message'] ?? l10n.commandSent;
      final success = code == 0;

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ $msg'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      final respData = response.data['data'];
      String? taskID;
      if (respData is Map<String, dynamic>) {
        taskID = respData['task_id'] as String?;
      }

      if (taskID == null || taskID.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $msg'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.str('control_waiting_execution')),
          backgroundColor: AppColors.info,
          duration: const Duration(seconds: 3),
        ),
      );

      _pollCommandStatus(taskID);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.str('command_send_failed', {'error': '$e'})),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Poll command status every 3 seconds, timeout after 60 seconds.
  void _pollCommandStatus(String taskID) {
    final l10n = AppLocalizations.of(context)!;
    _pollTimer?.cancel();
    final generation = ++_pollGeneration;
    const pollInterval = Duration(seconds: 3);
    const timeout = Duration(seconds: 60);
    final startTime = DateTime.now();
    String? lastDisplayedStatus;

    void poll() async {
      if (!mounted || generation != _pollGeneration) return;

      if (DateTime.now().difference(startTime) >= timeout) {
        if (mounted && generation == _pollGeneration) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.str('control_execution_timeout')),
              backgroundColor: AppColors.warning,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      try {
        final dio = getIt<Dio>();
        final response = await dio.get(
          '/devices/by-sn/${widget.deviceSN}/commands',
          queryParameters: {'task_id': taskID, 'page_size': 50},
        );

        if (!mounted || generation != _pollGeneration) return;

        final data = response.data['data'];
        List? items;
        if (data is Map) {
          items = data['items'] as List?;
        }

        String? status;
        if (items != null) {
          for (final item in items) {
            if (item is Map<String, dynamic> && item['task_id'] == taskID) {
              status = item['status'] as String?;
              break;
            }
          }
        }

        if (status != null && status != lastDisplayedStatus) {
          lastDisplayedStatus = status;
          _showCommandStatusSnack(status);
        }

        if (status != null && _isTerminalStatus(status)) {
          // Refresh data after terminal status
          _fetchAllData();
          return;
        }
      } catch (_) {}

      if (mounted && generation == _pollGeneration) {
        _pollTimer = Timer(pollInterval, poll);
      }
    }

    poll();
  }

  void _showCommandStatusSnack(String status) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;

    String message;
    Color color;

    switch (status) {
      case 'acknowledged':
      case 'executing':
        message = l10n.str('control_executing');
        color = AppColors.info;
        break;
      case 'success':
      case 'completed':
        message = l10n.str('control_applied');
        color = AppColors.success;
        break;
      case 'timeout':
      case 'failed':
      case 'cancelled':
        message = l10n.str('control_execution_failed');
        color = AppColors.error;
        break;
      default:
        message = l10n.str('control_waiting_execution');
        color = AppColors.info;
        break;
    }

    final isTerminal = _isTerminalStatus(status);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: isTerminal
            ? const Duration(seconds: 3)
            : const Duration(seconds: 2),
      ),
    );
  }

  bool _isTerminalStatus(String status) {
    return status == 'success' ||
        status == 'completed' ||
        status == 'failed' ||
        status == 'timeout' ||
        status == 'cancelled';
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColor.surfaceHover(context),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(100.h),
        child: AppBar(
          title: Text(
            l10n.deviceControl,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 17.sp,
            ),
          ),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: AppColor.surfaceContainer(context),
          foregroundColor: AppColor.textPrimary(context),
          bottom: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColor.textSecondary(context),
            indicatorColor: AppColors.primary,
            labelStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
            unselectedLabelStyle: TextStyle(fontSize: 13.sp),
            tabAlignment: TabAlignment.fill,
            tabs: [
              Tab(text: l10n.str('control_tab_running')),
              Tab(text: l10n.str('control_tab_battery')),
              Tab(text: l10n.str('control_tab_energy_plan')),
              Tab(text: l10n.deviceInfo),
            ],
          ),
        ),
      ),
      body: _loading
          ? const SkeletonDeviceControl()
          : _failedSectionCount == 5
              // 小烁警示动作插画：控制页全部数据加载失败（美术路由 C5/failure）
              ? XiaoshuoStatePanel(
                  asset: CsergyAssets.xiaoshuoWarning,
                  title: l10n.str('control_load_failed'),
                  message: l10n.loadFailed,
                  size: 184,
                  action: OutlinedButton(
                    onPressed: _fetchAllData,
                    child: Text(l10n.retry),
                  ),
                )
              : Column(
                  children: [
                    if (_failedSectionCount > 0)
                      Material(
                        color: _failedSectionCount == 5
                            ? AppColors.error.withValues(alpha: 0.1)
                            : AppColors.warning.withValues(alpha: 0.12),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16.w, vertical: 8.h),
                          child: Row(
                            children: [
                              Icon(
                                _failedSectionCount == 5
                                    ? Icons.error_outline
                                    : Icons.warning_amber_rounded,
                                color: _failedSectionCount == 5
                                    ? AppColors.error
                                    : AppColors.warning,
                              ),
                              SizedBox(width: 8.w),
                              Expanded(
                                child: Text(
                                  _failedSectionCount == 5
                                      ? l10n.str('control_load_failed')
                                      : l10n.str('control_partial_failed', {
                                          'count': '$_failedSectionCount',
                                        }),
                                  style: TextStyle(fontSize: 13.sp),
                                ),
                              ),
                              TextButton(
                                onPressed: _fetchAllData,
                                child: Text(l10n.retry),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildRunningTab(),
                          _buildBatteryProtectionTab(),
                          _buildEnergyScheduleTab(),
                          _buildDeviceInfoTab(),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Offline warning banner
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildOfflineWarning() {
    final l10n = AppLocalizations.of(context)!;
    if (_isOnline) return const SizedBox.shrink();
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
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
            child: Text(
              l10n.deviceOfflineWarning,
              style: TextStyle(fontSize: 12.sp, color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Tab 1 — 运行
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildRunningTab() {
    return ListView(
      padding: EdgeInsets.all(16.w),
      children: [
        _buildOfflineWarning(),

        // AC 输出开关
        _buildAcOutputCard(),

        SizedBox(height: 12.h),

        // 当前运行模式
        _buildRunModeCard(),

        SizedBox(height: 12.h),

        // 能源流简化展示
        _buildEnergyFlowCard(),

        SizedBox(height: 12.h),

        // 临时静音按钮
        _buildMuteCard(),
      ],
    );
  }

  Widget _buildAcOutputCard() {
    final l10n = AppLocalizations.of(context)!;
    final riskLevel = _riskLevels['ac_on'] ?? _riskLevels['ac_off'] ?? 2;
    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  color: (_acOutputOn ? AppColors.success : AppColors.error)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(
                  _acOutputOn ? Icons.power_settings_new : Icons.power_off,
                  size: 20.sp,
                  color: _acOutputOn ? AppColors.success : AppColors.error,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.str('control_ac_output'),
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      _acOutputOn
                          ? l10n.str('control_enabled')
                          : l10n.str('control_disabled'),
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColor.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (riskLevel >= 2)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 6.w,
                    vertical: 2.h,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                  child: Text(
                    'R$riskLevel',
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isOnline ? () => _toggleAcOutput(true) : null,
                  icon: Icon(Icons.power_settings_new, size: 18.sp),
                  label: Text(l10n.str('open')),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.success.withValues(alpha: 0.3),
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isOnline ? () => _toggleAcOutput(false) : null,
                  icon: Icon(Icons.power_off, size: 18.sp),
                  label: Text(l10n.str('close')),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _toggleAcOutput(bool turnOn) {
    final l10n = AppLocalizations.of(context)!;
    final command = turnOn ? 'ac_on' : 'ac_off';
    final riskLevel = _riskLevels[command] ?? 0;
    if (riskLevel >= 2) {
      _showConfirmDialog(
        turnOn
            ? l10n.str('control_enable_ac_title')
            : l10n.str('control_disable_ac_title'),
        turnOn
            ? l10n.str('control_enable_ac_confirm')
            : l10n.str('control_disable_ac_confirm'),
        () {
          _sendCommand(command);
          setState(() => _acOutputOn = turnOn);
        },
      );
    } else {
      _sendCommand(command);
      setState(() => _acOutputOn = turnOn);
    }
  }

  Widget _buildRunModeCard() {
    final l10n = AppLocalizations.of(context)!;
    // V2: sys.work_state, V1: run_mode/running_mode/mode
    final runMode = _rtPick(_realtimeData, 'run_mode', 'sys', 'work_state') ??
        _realtimeData['running_mode'] ??
        _realtimeData['mode'];
    final modeStr = runMode?.toString() ?? '—';
    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.settings_suggest_outlined,
                size: 20.sp,
                color: AppColors.primary,
              ),
              SizedBox(width: 8.w),
              Text(
                l10n.str('control_current_mode'),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: 12.w,
              vertical: 10.h,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Text(
              modeStr,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnergyFlowCard() {
    final l10n = AppLocalizations.of(context)!;
    // V2: pv.pv_total_power, V1: pv_power
    final pvPower = _rtPickNum(_realtimeData, 'pv_power', 'pv', 'pv_total_power');
    // V2: bat.battery_charge_power - bat.battery_discharge_power, V1: battery_power
    final chgW = (_rtPick(_realtimeData, 'battery_charge_power', 'bat', 'battery_charge_power') as num?)?.toDouble();
    final disW = (_rtPick(_realtimeData, 'battery_discharge_power', 'bat', 'battery_discharge_power') as num?)?.toDouble();
    final battPower = (chgW != null || disW != null)
        ? (chgW ?? 0) - (disW ?? 0)
        : _rtPickNum(_realtimeData, 'battery_power', 'bat', 'power');
    // V2: ac.output_power, V1: load_power
    final loadPower = _rtPickNum(_realtimeData, 'load_power', 'ac', 'output_power');

    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bolt_rounded,
                size: 20.sp,
                color: AppColors.orange,
              ),
              SizedBox(width: 8.w),
              Text(
                l10n.str('control_energy_flow'),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: _buildEnergyFlowItem(
                  icon: Icons.wb_sunny_outlined,
                  label: l10n.pv,
                  value: pvPower,
                  unit: 'W',
                  color: AppColors.orange,
                ),
              ),
              Container(
                width: 1,
                height: 40.h,
                color: AppColor.divider(context),
              ),
              Expanded(
                child: _buildEnergyFlowItem(
                  icon: Icons.battery_charging_full,
                  label: l10n.battery,
                  value: battPower,
                  unit: 'W',
                  color: AppColors.teal,
                ),
              ),
              Container(
                width: 1,
                height: 40.h,
                color: AppColor.divider(context),
              ),
              Expanded(
                child: _buildEnergyFlowItem(
                  icon: Icons.home_outlined,
                  label: l10n.str('load'),
                  value: loadPower,
                  unit: 'W',
                  color: AppColors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEnergyFlowItem({
    required IconData icon,
    required String label,
    required dynamic value,
    required String unit,
    required Color color,
  }) {
    final valStr = value != null
        ? (value is num ? value.toStringAsFixed(0) : value.toString())
        : '—';
    return Column(
      children: [
        Icon(icon, size: 22.sp, color: color),
        SizedBox(height: 4.h),
        Text(
          label,
          style: TextStyle(fontSize: 11.sp, color: AppColor.textSecondary(context)),
        ),
        SizedBox(height: 2.h),
        Text(
          '$valStr $unit',
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: AppColor.textPrimary(context),
          ),
        ),
      ],
    );
  }

  Widget _buildMuteCard() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: (_muteEnabled ? AppColors.warning : AppColor.textHint(context))
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(
              _muteEnabled ? Icons.volume_off : Icons.volume_up,
              size: 18.sp,
              color: _muteEnabled ? AppColors.warning : AppColor.textHint(context),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.str('control_temporary_mute'),
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  _muteEnabled
                      ? l10n.str('control_alarm_muted')
                      : l10n.str('control_mute_hint'),
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: AppColor.textHint(context),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _muteEnabled,
            onChanged: _isOnline
                ? (v) {
                    setState(() => _muteEnabled = v);
                    _sendCommand('set_mute', params: {'enabled': v});
                  }
                : null,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Tab 2 — 电池保护
  // ─────────────────────────────────────────────────────────────────────

}
