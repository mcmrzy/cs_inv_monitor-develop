// 设备详情页 ——「能源流监控中心」
//
// 结构：AppBar + 横幅区（MQTT 降级 / 数据滞后）+ TabBar（5 Tab）+ TabBarView
//   Tab1 能源流    Tab2 实时数据    Tab3 能量统计    Tab4 状态中心    Tab5 设备健康
//
// 取数机制保持不变：
//   - _fetchDeviceDetail：GET /devices/by-sn/:sn（realtime_data 展平为 derived 来源）
//   - RealtimeDataService：订阅/轮询获取 InverterRealtime 结构化遥测
//   - DeviceBloc 本地直连：DeviceStartLocalPoll / DeviceStopLocalPoll / DeviceLocalDisconnected

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/realtime_data_service.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/device/presentation/widgets/energy_dashboard_tabs.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/utils/api_response.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class DeviceRealtimePage extends StatefulWidget {
  final String sn;
  final String type;

  const DeviceRealtimePage({super.key, required this.sn, required this.type});

  @override
  State<DeviceRealtimePage> createState() => _DeviceRealtimePageState();
}

class _DeviceRealtimePageState extends State<DeviceRealtimePage> {
  /// 扁平 realtime map（_fetchDeviceDetail 的 realtime_data 展平结果，
  /// 供 derived_health_score / diag_work_time_total 等 derived 字段使用）
  final Map<String, dynamic> _realtimeData = {};

  /// 最新结构化遥测（RealtimeDataService / API realtime_data 解析结果）
  InverterRealtime? _latest;

  bool _online = false;
  bool _loading = true;
  String? _error;
  StreamSubscription? _statusSub;
  StreamSubscription? _realtimeSub;
  bool _hasMqttData = false;
  bool _apiUnavailable = false;
  bool _isLocalMode = false;

  /// 遥测数据时间戳（用于滞后提示；null 表示未知）
  DateTime? _dataUpdatedAt;

  /// 周期性刷新滞后状态：设备离线后数据不再更新，
  /// 需要定时器驱动 UI 进入"数据滞后"态
  Timer? _staleRefreshTimer;

  /// 超过该时长未更新的遥测数据视为滞后
  static const Duration _staleThreshold = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _initLocalMode();
    _subscribeMqttData();
    _listenOnlineStatus();
    _fetchDeviceDetail();
    // 每 30 秒刷新一次，保证数据停更后滞后提示能及时出现
    _staleRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _dataUpdatedAt != null) {
        setState(() {});
      }
    });
  }

  /// 检测本地模式并启动 bloc 本地轮询（含逆变器连接监控）
  Future<void> _initLocalMode() async {
    try {
      final modeService = getIt<ConnectionModeService>();
      await modeService.init();
      if (modeService.isLocal && mounted) {
        setState(() => _isLocalMode = true);
        // 启动 bloc 本地轮询：每 3 秒拉取逆变器实时数据并喂给连接监控
        context.read<DeviceBloc>().add(
              const DeviceStartLocalPoll(deviceIP: '192.168.4.1'),
            );
      }
    } catch (_) {
      // ConnectionModeService 不可用时忽略
    }
  }

  void _listenOnlineStatus() {
    try {
      final realtimeService = getIt<RealtimeDataService>();
      _statusSub = realtimeService.statusStream
          .where((status) => true) // 接收所有状态更新
          .listen((status) {
        if (mounted) {
          setState(() {
            _online = status.online;
          });
        }
      });
    } catch (_) {
      // MQTT 服务未初始化时忽略
    }
  }

  @override
  void dispose() {
    // 本地模式下停止 bloc 本地轮询和连接监控
    if (_isLocalMode) {
      try {
        // 使用全局 bloc 访问，避免 context 已失效
        final bloc =
            getIt.isRegistered<DeviceBloc>() ? getIt<DeviceBloc>() : null;
        bloc?.add(const DeviceStopLocalPoll());
      } catch (_) {}
    }
    _statusSub?.cancel();
    _realtimeSub?.cancel();
    _staleRefreshTimer?.cancel();
    try {
      getIt<RealtimeDataService>().stopPolling(widget.sn);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _fetchDeviceDetail() async {
    try {
      final dio = getIt<Dio>();
      // API 路径: /devices/by-sn/:sn
      final res = await dio
          .get('/devices/by-sn/${widget.sn}')
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200 && mounted) {
        final data = unwrapApiResponse<Map<String, dynamic>>(
          res.data,
          validate: (value) => value is Map<String, dynamic>,
          expected: 'an object',
        );

        // 解析 realtime_data
        final realtimeRaw =
            data['realtime_data'] as Map<String, dynamic>? ?? {};
        Map<String, dynamic> flatData = {};

        // realtime_data 可能是嵌套结构（ac/pv/energy 对象），展平它
        // 数据结构可能是 {"ac": {"power": 2319}} 或 {"ac": {"data": {...}, "timestamp": ...}}
        realtimeRaw.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            // 检查是否有 data 子字段（新格式）
            if (value.containsKey('data') &&
                value['data'] is Map<String, dynamic>) {
              final innerData = value['data'] as Map<String, dynamic>;
              innerData.forEach((subKey, subValue) {
                final flatKey = '${key}_$subKey';
                flatData[flatKey] = subValue;
              });
            } else {
              // 旧格式：直接嵌套
              value.forEach((subKey, subValue) {
                final flatKey = '${key}_$subKey';
                flatData[flatKey] = subValue;
              });
            }
          } else {
            flatData[key] = value;
          }
        });

        // 尝试将 realtime_data 解析为结构化遥测（MQTT 数据缺失时的兜底）
        final structured = InverterRealtime.fromJson(realtimeRaw);
        final hasSection = structured.ac != null ||
            structured.pv != null ||
            structured.battery != null ||
            structured.sysStatus != null ||
            structured.energy != null;

        setState(() {
          // 合并 API 数据到现有数据（MQTT 实时数据优先）
          _realtimeData.addAll(flatData);
          // 结构化数据：MQTT/轮询未提供时才使用 API 解析结果
          if (_latest == null && hasSection) {
            _latest = structured;
          }
          // 提取遥测时间戳（后端字段兼容 updated_at / data_time）
          final updatedAtStr = (data['updated_at'] ??
                  data['data_time'] ??
                  realtimeRaw['updated_at'])
              as String?;
          final parsed =
              updatedAtStr == null ? null : DateTime.tryParse(updatedAtStr);
          if (parsed != null) {
            _dataUpdatedAt = parsed;
          }
          _online = data['online_status']?['online'] == true ||
              data['device']?['status'] == 1;
          _loading = false;
          _error = null;
          _apiUnavailable = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _apiUnavailable = true;
          _loading = false;
          _error = _hasMqttData
              ? null
              : AppLocalizations.of(context)!.str('realtime_load_failed');
        });
      }
    }
  }

  /// 订阅实时数据流，通过 API 轮询获取实时数据
  void _subscribeMqttData() {
    try {
      final realtimeService = getIt<RealtimeDataService>();
      // 页面打开时先读取已缓存的实时数据（避免数据未变化导致流不触发）
      final cached = realtimeService.getLatestData(widget.sn);
      if (cached != null && mounted) {
        setState(() {
          _latest = cached;
          final newMqttData = _inverterToFlatMap(cached);
          _realtimeData.addAll(newMqttData);
          _hasMqttData = true;
          if (cached.updatedAt != null) {
            _dataUpdatedAt = cached.updatedAt;
          }
          if (cached.onlineStatus != null) {
            _online = cached.onlineStatus!.online;
          }
          if (_loading) {
            _loading = false;
            _error = null;
          }
        });
      }
      realtimeService.startPolling(widget.sn);
      _realtimeSub = realtimeService.realtimeDataStream
          .where((rt) => rt.deviceSN == widget.sn)
          .listen((rt) {
        if (mounted) {
          setState(() {
            _latest = rt;
            // 合并 MQTT 新数据到现有数据，而非完全替换
            // 这样 API 返回的字段不会因 MQTT 数据缺失而丢失
            final newMqttData = _inverterToFlatMap(rt);
            _realtimeData.addAll(newMqttData);
            _hasMqttData = true;
            if (rt.updatedAt != null) {
              _dataUpdatedAt = rt.updatedAt;
            }
            if (_apiUnavailable) {
              _error = null;
            }
            if (rt.onlineStatus != null) {
              _online = rt.onlineStatus!.online;
            }
            // 首次收到 MQTT 数据时取消 loading 状态
            if (_loading) {
              _loading = false;
              _error = null;
            }
          });
        }
      });
    } catch (_) {
      // MQTT 服务不可用时忽略
    }
  }

  /// 将 InverterRealtime 转为与云端 API 一致的扁平 Map，
  /// 保持 derived 字段合并机制与原实现一致
  Map<String, dynamic> _inverterToFlatMap(InverterRealtime rt) {
    final map = <String, dynamic>{};
    // AC
    if (rt.ac != null) {
      map['ac_voltage'] = rt.ac!.voltage;
      map['ac_current'] = rt.ac!.current;
      map['ac_power'] = rt.ac!.power;
      map['ac_frequency'] = rt.ac!.frequency;
      map['ac_load_percent'] = rt.ac!.loadPercent;
      map['ac_pf'] = rt.ac!.pf;
    }
    // Battery
    if (rt.battery != null) {
      map['batt_soc'] = rt.battery!.soc;
      map['batt_soh'] = rt.battery!.soh;
      map['batt_voltage'] = rt.battery!.voltage;
      map['batt_current'] = rt.battery!.current;
      map['batt_charge_state'] = rt.battery!.chargeState;
    }
    // PV
    if (rt.pv != null) {
      map['pv_voltage'] = rt.pv!.pvVoltage;
      map['pv_current'] = rt.pv!.pvCurrent;
      map['pv_power'] = rt.pv!.pvPower;
      map['mppt_state'] = rt.pv!.mpptState;
    }
    // System Status
    if (rt.sysStatus != null) {
      map['state'] = rt.sysStatus!.state;
      map['fault_code'] = rt.sysStatus!.faultCode;
      map['alarm_code'] = rt.sysStatus!.alarmCode;
      map['temp_inv'] = rt.sysStatus!.tempInv;
      map['temp_mos'] = rt.sysStatus!.tempMos;
      map['efficiency'] = rt.sysStatus!.efficiency;
    }
    // Energy
    if (rt.energy != null) {
      map['daily_pv'] = rt.energy!.dailyPV;
      map['total_pv'] = rt.energy!.totalPV;
      map['runtime_hours'] = rt.energy!.runtimeHours;
      map['daily_feed_energy'] = rt.energy!.dailyFeedEnergy;
      map['total_feed_energy'] = rt.energy!.totalFeedEnergy;
      map['daily_grid_import'] = rt.energy!.dailyGridImport;
      map['total_grid_import'] = rt.energy!.totalGridImport;
    }
    // Cells
    if (rt.cells != null && rt.cells!.voltages.isNotEmpty) {
      map['cell_count'] = rt.cells!.cellCount;
    }
    // Device Info
    if (rt.deviceInfo != null) {
      map['model'] = rt.deviceInfo!.model;
    }
    if (rt.loadPower != 0) {
      map['load_power'] = rt.loadPower;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocListener<DeviceBloc, DeviceState>(
      listener: (context, state) {
        if (state is DeviceLocalDisconnected) {
          // 逆变器无响应，已自动断开设备热点并切回家用 WiFi
          final l10n = AppLocalizations.of(context)!;
          AppToast.show(context, l10n.inverterNoResponse, type: ToastType.error);
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColor.surfaceHover(context),
        appBar: AppBar(
          title: Text(
            l10n.deviceDetail,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17.sp),
          ),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: AppColor.surfaceContainer(context),
          foregroundColor: AppColor.textPrimary(context),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                setState(() => _loading = true);
                _fetchDeviceDetail();
              },
            ),
          ],
        ),
        body: _loading
            ? const PageSkeleton(cardCount: 4)
            : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  Widget _buildError() {
    final l10n = AppLocalizations.of(context)!;
    // 小烁离线动作插画：设备详情加载失败/断网态（美术路由 C4/offline）
    return XiaoshuoStatePanel(
      asset: CsergyAssets.xiaoshuoOffline,
      title: _error!,
      message: l10n.loadFailed,
      size: 176,
      action: OutlinedButton(
        onPressed: () {
          setState(() {
            _loading = true;
            _error = null;
          });
          _fetchDeviceDetail();
        },
        child: Text(l10n.retry),
      ),
    );
  }

  /// 内容区：横幅区（TabBar 上方）+ TabBar（5 Tab）+ TabBarView
  Widget _buildContent() {
    final l10n = AppLocalizations.of(context)!;

    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          // ── 横幅区（位于 TabBar 上方）──
          if (_apiUnavailable && _hasMqttData)
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
              child: _buildMqttFallbackBanner(),
            ),
          // 数据滞后提示：设备离线时陈旧数据不再被误当实时值
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
            child: _buildStaleDataBanner(),
          ),
          // ── TabBar ──
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
            unselectedLabelStyle:
                TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w400),
            tabs: [
              Tab(text: l10n.str('energy_flow')),
              Tab(text: l10n.str('realtime_data')),
              Tab(text: l10n.str('energy_stats')),
              Tab(text: l10n.str('status_center_title')),
              Tab(text: l10n.str('health_title')),
            ],
          ),
          // ── TabBarView ──
          Expanded(
            child: TabBarView(
              children: [
                EnergyFlowTab(data: _latest),
                RealtimeDataTab(
                  data: _latest,
                  footer: Column(
                    children: [
                      _buildSettingsEntry(),
                      SizedBox(height: 12.h),
                      _buildProtocolEntry(),
                    ],
                  ),
                ),
                EnergyStatsTab(data: _latest),
                StatusCenterTab(sn: widget.sn, data: _latest),
                DeviceHealthTab(
                  data: _latest,
                  flat: _realtimeData,
                  online: _online,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 数据滞后提示：遥测时间戳超过阈值时展示，
  /// 避免设备离线时用户把陈旧功率/SOC 等数值当实时值
  Widget _buildStaleDataBanner() {
    final updatedAt = _dataUpdatedAt;
    if (updatedAt == null) return const SizedBox.shrink();
    final stale = DateTime.now().difference(updatedAt.toLocal()) >
        _staleThreshold;
    if (!stale) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final timeStr = DateFormat('HH:mm:ss').format(updatedAt.toLocal());
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
          Icon(
            Icons.hourglass_bottom_rounded,
            size: 18.sp,
            color: AppColors.warning,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              l10n.str('realtime_data_stale', {'time': timeStr}),
              style: TextStyle(fontSize: 12.sp, color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMqttFallbackBanner() {
    final l10n = AppLocalizations.of(context)!;
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
          Icon(Icons.cloud_off_outlined, size: 18.w, color: AppColors.warning),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              l10n.str('realtime_mqtt_fallback'),
              style: TextStyle(fontSize: 12.sp, color: AppColors.warning),
            ),
          ),
          TextButton(
            onPressed: _fetchDeviceDetail,
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
  }

  /// 参数设置入口（push /device/:sn/settings）
  Widget _buildSettingsEntry() {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () => context.push('/device/${widget.sn}/settings'),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        decoration: AppColor.card(context),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(
                Icons.tune_rounded,
                size: 20.sp,
                color: AppColors.primary,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.paramSettings,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColor.textPrimary(context),
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    l10n.settingsEntryDesc,
                    style:
                        TextStyle(fontSize: 12.sp, color: AppColor.textHint(context)),
                  ),
                ],
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
    );
  }

  /// 协议遥测入口（push /device/:sn/protocol）
  Widget _buildProtocolEntry() {
    return GestureDetector(
      onTap: () => context.push('/device/${widget.sn}/protocol'),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        decoration: AppColor.card(context),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(
                Icons.monitor_heart_outlined,
                size: 20.sp,
                color: AppColors.blue,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.protocolTelemetryTitle,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColor.textPrimary(context),
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    AppLocalizations.of(context)!.protocolTelemetryDesc,
                    style:
                        TextStyle(fontSize: 12.sp, color: AppColor.textHint(context)),
                  ),
                ],
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
    );
  }
}
