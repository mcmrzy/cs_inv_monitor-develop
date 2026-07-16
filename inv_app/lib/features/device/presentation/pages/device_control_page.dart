import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/entities/device_model_field.dart';
import 'package:inv_app/core/utils/api_response.dart';
import 'package:inv_app/core/utils/energy_schedule.dart';

import 'package:inv_app/l10n/app_localizations.dart';

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
          await dio.get('/devices/${widget.deviceSN}/control-fields');
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
      final capsRes =
          await dio.get('/devices/${widget.deviceSN}/control-capabilities');
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
      final deviceRes = await dio.get('/devices/${widget.deviceSN}');
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
      final res = await dio.get('/devices/${widget.deviceSN}/realtime');
      final data = unwrapApiResponse<Map<String, dynamic>>(
        res.data,
        validate: (value) => value is Map<String, dynamic>,
        expected: 'an object',
      );
      if (mounted) {
        setState(() {
          _realtimeData = data;
          // Infer AC output state from realtime data
          _acOutputOn = data['ac_output_on'] == true ||
              data['ac_on'] == true ||
              (data['output_power'] != null &&
                  (data['output_power'] as num) > 0);
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
      final res = await dio.get('/devices/${widget.deviceSN}/energy-schedule');
      final data = unwrapApiResponse<Map<String, dynamic>>(
        res.data,
        validate: isEnergySchedulePayload,
        expected: 'a schedule object containing periods',
      );
      if (mounted) {
        setState(() {
          _energySchedule = normalizeSchedulePeriods(data['periods']);
          _energyScheduleRevision =
              (data['revision'] as num?)?.toInt() ?? 0;
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
          await dio.get('/devices/${widget.deviceSN}/control-overrides');
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
      final res = await dio.get('/devices/${widget.deviceSN}/control-state');
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
        '/devices/${widget.deviceSN}/commands',
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
        '/devices/${widget.deviceSN}/control',
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
          '/devices/${widget.deviceSN}/commands',
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
      backgroundColor: AppColors.background,
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
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          bottom: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
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
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_failedSectionCount > 0)
                  Material(
                    color: _failedSectionCount == 5
                        ? AppColors.error.withValues(alpha: 0.1)
                        : AppColors.warning.withValues(alpha: 0.12),
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
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
                        color: AppColors.textSecondary,
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
    final runMode = _realtimeData['run_mode'] ??
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
    final pvPower = _realtimeData['pv_power'] ?? _realtimeData['pv_power_w'];
    final battPower =
        _realtimeData['battery_power'] ?? _realtimeData['batt_power'];
    final loadPower =
        _realtimeData['load_power'] ?? _realtimeData['output_power'];

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
                color: AppColors.divider,
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
                color: AppColors.divider,
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
          style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
        ),
        SizedBox(height: 2.h),
        Text(
          '$valStr $unit',
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
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
              color: (_muteEnabled ? AppColors.warning : AppColors.textHint)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(
              _muteEnabled ? Icons.volume_off : Icons.volume_up,
              size: 18.sp,
              color: _muteEnabled ? AppColors.warning : AppColors.textHint,
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
                    color: AppColors.textHint,
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

  Widget _buildBatteryProtectionTab() {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: EdgeInsets.all(16.w),
      children: [
        _buildOfflineWarning(),

        // 备电保留 SOC
        _buildSliderCard(
          title: l10n.str('control_reserve_soc'),
          subtitle: l10n.str('control_reserve_soc_hint'),
          value: _reserveSoc,
          min: 0,
          max: 80,
          unit: '%',
          icon: Icons.battery_saver,
          color: AppColors.warning,
          onChanged: (v) => setState(() => _reserveSoc = v),
          onCommit: () => _sendSocWindow(),
        ),

        SizedBox(height: 12.h),

        // 充电目标 SOC
        _buildSliderCard(
          title: l10n.str('control_target_soc'),
          subtitle: l10n.str('control_target_soc_hint'),
          value: _chargeTargetSoc,
          min: 20,
          max: 100,
          unit: '%',
          icon: Icons.battery_charging_full,
          color: AppColors.success,
          onChanged: (v) => setState(() => _chargeTargetSoc = v),
          onCommit: () => _sendSocWindow(),
        ),

        SizedBox(height: 12.h),

        // 充电速度预设
        _buildChargeSpeedCard(),

        SizedBox(height: 12.h),

        // BMS 实时限制
        _buildBmsLimitsCard(),
      ],
    );
  }

  Widget _buildSliderCard({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required String unit,
    required IconData icon,
    required Color color,
    required ValueChanged<double> onChanged,
    required VoidCallback onCommit,
  }) {
    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36.w,
                height: 36.w,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(icon, size: 18.sp, color: color),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${value.toStringAsFixed(0)}$unit',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) ~/ 5),
            activeColor: color,
            onChanged: _isOnline ? onChanged : null,
            onChangeEnd: (_) => _isOnline ? onCommit() : null,
          ),
        ],
      ),
    );
  }

  void _sendSocWindow() {
    final lowX10 = (_reserveSoc * 10).round();
    final highX10 = (_chargeTargetSoc * 10).round();
    _sendCommand(
      'set_soc_window',
      params: {
        'low_x10': lowX10,
        'high_x10': highX10,
      },
    );
  }

  Widget _buildChargeSpeedCard() {
    final l10n = AppLocalizations.of(context)!;
    final presets = [
      {
        'label': l10n.str('control_charge_gentle'),
        'icon': Icons.eco_outlined,
        'color': AppColors.teal,
        'limit': 30,
      },
      {
        'label': l10n.str('control_charge_standard'),
        'icon': Icons.speed_outlined,
        'color': AppColors.primary,
        'limit': 60,
      },
      {
        'label': l10n.str('control_charge_fast'),
        'icon': Icons.flash_on,
        'color': AppColors.orange,
        'limit': 100,
      },
    ];

    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.speed_rounded,
                size: 20.sp,
                color: AppColors.primary,
              ),
              SizedBox(width: 8.w),
              Text(
                l10n.str('control_charge_speed'),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: presets.asMap().entries.map((entry) {
              final idx = entry.key;
              final p = entry.value;
              final isSelected = _chargeSpeedPreset == idx;
              final color = p['color'] as Color;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: idx == 1 ? 8.w : 0,
                  ),
                  child: GestureDetector(
                    onTap: _isOnline
                        ? () {
                            setState(() => _chargeSpeedPreset = idx);
                            _sendCommand(
                              'set_charge_limit',
                              params: {
                                'max_current_pct': p['limit'],
                              },
                            );
                          }
                        : null,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        vertical: 12.h,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color.withValues(alpha: 0.1)
                            : AppColors.surfaceHover.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(
                          color: isSelected ? color : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            p['icon'] as IconData,
                            size: 22.sp,
                            color: isSelected ? color : AppColors.textHint,
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            p['label'] as String,
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color:
                                  isSelected ? color : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBmsLimitsCard() {
    final l10n = AppLocalizations.of(context)!;
    final entries = _bmsLimits.entries.toList();
    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.security_outlined,
                size: 20.sp,
                color: AppColors.info,
              ),
              SizedBox(width: 8.w),
              Text(
                l10n.str('control_bms_limits'),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          if (entries.isEmpty)
            Text(
              l10n.noData,
              style: TextStyle(
                fontSize: 12.sp,
                color: AppColors.textHint,
              ),
            )
          else
            ...entries.map(
              (e) => Padding(
                padding: EdgeInsets.symmetric(vertical: 4.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      e.key,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '${e.value}',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Tab 3 — 能源计划
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildEnergyScheduleTab() {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: EdgeInsets.all(16.w),
      children: [
        _buildOfflineWarning(),

        // 时间段列表
        Container(
          decoration: AppColor.card(context),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          child: Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 20.sp,
                color: AppColors.primary,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  l10n.str('control_schedule_list'),
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed:
                    _isOnline ? () => _showEnergyScheduleEditor(null) : null,
                icon: Icon(
                  Icons.add_circle_outline,
                  size: 22.sp,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 8.h),

        if (_energySchedule.isEmpty)
          Container(
            decoration: AppColor.card(context),
            padding: EdgeInsets.all(24.w),
            child: Column(
              children: [
                Icon(
                  Icons.event_available,
                  size: 36.sp,
                  color: AppColors.textHint,
                ),
                SizedBox(height: 8.h),
                Text(
                  l10n.noData,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          )
        else
          ..._energySchedule.map(_buildEnergyScheduleItem),

        SizedBox(height: 12.h),

        // 临时覆盖显示
        Container(
          decoration: AppColor.card(context),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.edit_calendar,
                    size: 20.sp,
                    color: AppColors.warning,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    l10n.str('control_temporary_override'),
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              if (_controlOverrides.isEmpty)
                Text(
                  l10n.str('control_no_override'),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textHint,
                  ),
                )
              else
                ..._controlOverrides.map((o) {
                  final m = o as Map<String, dynamic>;
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 4.h),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${m['command'] ?? '—'}',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          '${m['params'] ?? ''}',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEnergyScheduleItem(Map<String, dynamic> slot) {
    final l10n = AppLocalizations.of(context)!;
    final start = slot['start_time'] ?? slot['start'] ?? '—';
    final end = slot['end_time'] ?? slot['end'] ?? '—';
    final mode = slot['mode'] ?? slot['action'] ?? '—';
    final enabled = slot['enabled'] ?? true;

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: AppColor.card(context),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
        leading: Container(
          width: 40.w,
          height: 40.w,
          decoration: BoxDecoration(
            color: (enabled ? AppColors.primary : AppColors.textHint)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(
            Icons.timer_outlined,
            size: 20.sp,
            color: enabled ? AppColors.primary : AppColors.textHint,
          ),
        ),
        title: Text(
          '$start — $end',
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          l10n.str('control_mode_value', {'mode': '$mode'}),
          style: TextStyle(
            fontSize: 11.sp,
            color: AppColors.textHint,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.edit_outlined,
                size: 18.sp,
                color: AppColors.primary,
              ),
              onPressed:
                  _isOnline ? () => _showEnergyScheduleEditor(slot) : null,
            ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 18.sp,
                color: AppColors.error,
              ),
              onPressed: _isOnline ? () => _deleteEnergySchedule(slot) : null,
            ),
          ],
        ),
      ),
    );
  }

  void _showEnergyScheduleEditor(Map<String, dynamic>? existing) {
    final l10n = AppLocalizations.of(context)!;
    final isEdit = existing != null;
    final startCtrl =
        TextEditingController(text: existing?['start_time'] ?? '');
    final endCtrl = TextEditingController(text: existing?['end_time'] ?? '');
    final modeCtrl = TextEditingController(text: existing?['mode'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isEdit
              ? l10n.str('control_edit_schedule')
              : l10n.str('control_add_schedule'),
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: startCtrl,
                decoration: InputDecoration(
                  labelText: l10n.str('control_start_time'),
                  hintText: l10n.str('control_start_time_hint'),
                ),
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: endCtrl,
                decoration: InputDecoration(
                  labelText: l10n.str('control_end_time'),
                  hintText: l10n.str('control_end_time_hint'),
                ),
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: modeCtrl,
                decoration: InputDecoration(
                  labelText: l10n.str('control_mode'),
                  hintText: l10n.str('control_mode_hint'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _saveEnergySchedule(
                existing,
                startCtrl.text,
                endCtrl.text,
                modeCtrl.text,
                isEdit,
              );
            },
            child: Text(AppLocalizations.of(context)!.save),
          ),
        ],
      ),
    );
  }

  void _saveEnergySchedule(
    Map<String, dynamic>? existing,
    String start,
    String end,
    String mode,
    bool isEdit,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final dio = getIt<Dio>();
    try {
      var periods = _energySchedule.map(Map<String, dynamic>.from).toList();
      final updatedPeriod = <String, dynamic>{
        if (existing != null) ...existing,
        'start_time': start,
        'end_time': end,
        'mode': mode,
        'enabled': existing?['enabled'] ?? true,
      };
      if (isEdit && existing != null) {
        periods = replaceSchedulePeriod(periods, existing, updatedPeriod);
      } else {
        periods.add(updatedPeriod);
      }
      final response = await dio.put(
        '/devices/${widget.deviceSN}/energy-schedule',
        data: {
          'timezone': _energyScheduleTimezone,
          'enabled': _energyScheduleEnabled,
          'periods': periods,
        },
        options: Options(
          headers: {'If-Match': '$_energyScheduleRevision'},
        ),
      );
      final schedule = unwrapApiResponse<Map<String, dynamic>>(
        response.data,
        validate: isEnergySchedulePayload,
        expected: 'an updated schedule object',
      );
      if (mounted) {
        setState(() {
          _energySchedule = normalizeSchedulePeriods(schedule['periods']);
          _energyScheduleRevision =
              (schedule['revision'] as num?)?.toInt() ??
                  _energyScheduleRevision;
          _energyScheduleTimezone =
              schedule['timezone'] as String? ?? _energyScheduleTimezone;
          _energyScheduleEnabled =
              schedule['enabled'] as bool? ?? _energyScheduleEnabled;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit
                ? l10n.str('control_schedule_updated')
                : l10n.str('control_schedule_added')),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.str('control_schedule_save_failed')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _deleteEnergySchedule(Map<String, dynamic> slot) async {
    final l10n = AppLocalizations.of(context)!;
    final dio = getIt<Dio>();
    try {
      final periods = removeSchedulePeriod(_energySchedule, slot);
      final response = await dio.put(
        '/devices/${widget.deviceSN}/energy-schedule',
        data: {
          'timezone': _energyScheduleTimezone,
          'enabled': _energyScheduleEnabled,
          'periods': periods,
        },
        options: Options(
          headers: {'If-Match': '$_energyScheduleRevision'},
        ),
      );
      final schedule = unwrapApiResponse<Map<String, dynamic>>(
        response.data,
        validate: isEnergySchedulePayload,
        expected: 'an updated schedule object',
      );
      if (mounted) {
        setState(() {
          _energySchedule = normalizeSchedulePeriods(schedule['periods']);
          _energyScheduleRevision =
              (schedule['revision'] as num?)?.toInt() ??
                  _energyScheduleRevision;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.str('control_schedule_deleted')),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.str('control_schedule_delete_failed')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Tab 4 — 设备信息
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildDeviceInfoTab() {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: EdgeInsets.all(16.w),
      children: [
        // 安装配置只读展示
        _buildInfoSection(
          l10n.str('control_installation'),
          Icons.build_outlined,
          _extractDeviceInfoFields(),
        ),

        SizedBox(height: 12.h),

        // 固件版本
        _buildFirmwareCard(),

        SizedBox(height: 12.h),

        // desired/reported 配置差异
        _buildConfigDiffCard(),

        SizedBox(height: 12.h),

        // 命令记录
        _buildCommandHistoryCard(),
      ],
    );
  }

  Map<String, dynamic> _extractDeviceInfoFields() {
    final l10n = AppLocalizations.of(context)!;
    final device =
        _deviceInfo['device'] as Map<String, dynamic>? ?? _deviceInfo;
    return {
      l10n.str('control_device_sn'): widget.deviceSN,
      l10n.str('control_device_model'):
          device['model'] ?? device['model_name'] ?? '—',
      l10n.str('control_device_name'):
          device['name'] ?? device['device_name'] ?? '—',
      l10n.str('control_install_location'):
          device['location'] ?? device['install_location'] ?? '—',
      l10n.str('control_install_date'):
          device['install_date'] ?? device['created_at'] ?? '—',
      l10n.str('control_station'):
          device['station_name'] ?? device['station'] ?? '—',
    };
  }

  Widget _buildInfoSection(
    String title,
    IconData icon,
    Map<String, dynamic> fields,
  ) {
    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20.sp, color: AppColors.primary),
              SizedBox(width: 8.w),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          ...fields.entries.map(
            (e) => Padding(
              padding: EdgeInsets.symmetric(vertical: 3.h),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    e.key,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      '${e.value}',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFirmwareCard() {
    final l10n = AppLocalizations.of(context)!;
    final device =
        _deviceInfo['device'] as Map<String, dynamic>? ?? _deviceInfo;
    final fwVersion = device['firmware_version'] ??
        device['fw_version'] ??
        _controlState['reported']?['firmware_version'] ??
        '—';
    final hwVersion = device['hardware_version'] ??
        device['hw_version'] ??
        _controlState['reported']?['hardware_version'] ??
        '—';
    final mcuVersion =
        device['mcu_version'] ?? _controlState['reported']?['mcu_version'];

    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.memory,
                size: 20.sp,
                color: AppColors.indigo,
              ),
              SizedBox(width: 8.w),
              Text(
                l10n.str('control_firmware_versions'),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          _buildInfoRow(l10n.str('control_firmware_version'), '$fwVersion'),
          _buildInfoRow(l10n.str('control_hardware_version'), '$hwVersion'),
          if (mcuVersion != null)
            _buildInfoRow(l10n.str('control_mcu_version'), '$mcuVersion'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13.sp,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigDiffCard() {
    final l10n = AppLocalizations.of(context)!;
    final desired = _controlState['desired'] as Map<String, dynamic>? ?? {};
    final reported = _controlState['reported'] as Map<String, dynamic>? ?? {};
    final allKeys = {...desired.keys, ...reported.keys}.toList()..sort();

    final diffKeys = allKeys.where((k) {
      final d = desired[k];
      final r = reported[k];
      return '$d' != '$r';
    }).toList();

    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.compare_arrows,
                size: 20.sp,
                color: AppColors.purple,
              ),
              SizedBox(width: 8.w),
              Text(
                l10n.str('control_config_diff'),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          if (diffKeys.isEmpty)
            Text(
              l10n.str('control_config_in_sync'),
              style: TextStyle(
                fontSize: 12.sp,
                color: AppColors.success,
              ),
            )
          else
            ...diffKeys.map((k) {
              final d = desired[k] ?? '—';
              final r = reported[k] ?? '—';
              return Container(
                margin: EdgeInsets.only(bottom: 6.h),
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      k,
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      l10n.str('control_desired_value', {'value': '$d'}),
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      l10n.str('control_reported_value', {'value': '$r'}),
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildCommandHistoryCard() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.history,
                size: 20.sp,
                color: AppColors.teal,
              ),
              SizedBox(width: 8.w),
              Text(
                l10n.str('control_command_history'),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _fetchCommandHistory,
                icon: Icon(
                  Icons.refresh,
                  size: 18.sp,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          if (_commandHistory.isEmpty)
            Text(
              l10n.str('control_no_command_history'),
              style: TextStyle(
                fontSize: 12.sp,
                color: AppColors.textHint,
              ),
            )
          else
            ..._commandHistory.take(10).map((cmd) {
              final m = cmd as Map<String, dynamic>;
              final status = m['status'] as String? ?? '—';
              final command = m['command'] as String? ?? '—';
              final time = m['created_at'] ?? m['timestamp'] ?? '';
              return _buildCommandHistoryItem(command, status, '$time');
            }),
        ],
      ),
    );
  }

  Widget _buildCommandHistoryItem(
    String command,
    String status,
    String time,
  ) {
    Color statusColor;
    switch (status) {
      case 'success':
      case 'completed':
        statusColor = AppColors.success;
        break;
      case 'failed':
      case 'timeout':
      case 'cancelled':
        statusColor = AppColors.error;
        break;
      case 'acknowledged':
      case 'executing':
        statusColor = AppColors.info;
        break;
      default:
        statusColor = AppColors.textHint;
    }

    return Container(
      margin: EdgeInsets.only(bottom: 6.h),
      padding: EdgeInsets.symmetric(
        horizontal: 10.w,
        vertical: 8.h,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceHover.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Row(
        children: [
          Container(
            width: 8.w,
            height: 8.w,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  command,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (time.isNotEmpty)
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: AppColors.textHint,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            status,
            style: TextStyle(
              fontSize: 11.sp,
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Dialogs
  // ─────────────────────────────────────────────────────────────────────

  void _showConfirmDialog(
    String title,
    String message,
    VoidCallback onConfirm,
  ) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }
}
