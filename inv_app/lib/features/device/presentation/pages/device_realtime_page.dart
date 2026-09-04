// 设备详情页 —— 实时监控与远程设置
//
// 结构：AppBar + 横幅区（MQTT 降级 / 数据滞后）+ TabBarView + 底部 Tab 栏（4 Tab）
//   Tab1 实时数据    Tab2 能量统计    Tab3 远程设置    Tab4 设备健康
//
// 取数机制保持不变：
//   - _fetchDeviceDetail：GET /devices/by-sn/:sn（realtime_data 展平为 derived 来源）
//   - RealtimeDataService：订阅/轮询获取 InverterRealtime 结构化遥测
//   - DeviceBloc 本地直连：DeviceStartLocalPoll / DeviceStopLocalPoll / DeviceLocalDisconnected

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
import 'package:inv_app/features/device/presentation/pages/device_settings_page.dart';
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

class _DeviceRealtimePageState extends State<DeviceRealtimePage>
    with SingleTickerProviderStateMixin {
  /// 底部 Tab 栏控制器（4 Tab：实时数据 / 能量统计 / 远程设置 / 设备健康）
  late final TabController _tabController;

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
    _tabController = TabController(length: 4, vsync: this);
    _subscribeMqttData();
    _listenOnlineStatus();
    // 初始化本地模式（异步），完成后再决定是否调用云端 API
    _initLocalMode().then((_) {
      if (!mounted) return;
      if (!_isLocalMode) {
        _fetchDeviceDetail();
      } else {
        // 本地模式：等 DeviceBloc 推送数据，先显示加载态
        setState(() => _loading = true);
      }
    });
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
    _tabController.dispose();
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
      if (kDebugMode) {
        debugPrint('[DeviceRealtimePage] Fetching device detail for ${widget.sn}');
      }
      // API 路径: /devices/by-sn/:sn
      final res = await dio
          .get('/devices/by-sn/${widget.sn}')
          .timeout(const Duration(seconds: 10));
      if (kDebugMode) {
        debugPrint('[DeviceRealtimePage] API response status: ${res.statusCode}');
      }
      if (res.statusCode == 200 && mounted) {
        final data = unwrapApiResponse<Map<String, dynamic>>(
          res.data,
          validate: (value) {
            if (kDebugMode) {
              debugPrint('[DeviceRealtimePage] Validating data type: ${value.runtimeType}, isMap: ${value is Map<String, dynamic>}');
            }
            return value is Map<String, dynamic>;
          },
          expected: 'an object',
        );
        if (kDebugMode) {
          debugPrint('[DeviceRealtimePage] API data keys: ${data.keys.toList()}');
          debugPrint('[DeviceRealtimePage] has realtime_data: ${data.containsKey('realtime_data')}, value: ${data['realtime_data'] != null}');
          debugPrint('[DeviceRealtimePage] has online_status: ${data.containsKey('online_status')}, value: ${data['online_status']}');
        }

        // 解析 realtime_data
        final realtimeRaw =
            data['realtime_data'] as Map<String, dynamic>? ?? {};
        if (kDebugMode) {
          debugPrint('[DeviceRealtimePage] realtimeRaw keys: ${realtimeRaw.keys.toList()}');
        }
        Map<String, dynamic> flatData = {};

        // realtime_data 可能是嵌套结构（ac/pv/energy 对象），展平它
        realtimeRaw.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            if (value.containsKey('data') &&
                value['data'] is Map<String, dynamic>) {
              final innerData = value['data'] as Map<String, dynamic>;
              innerData.forEach((subKey, subValue) {
                final flatKey = '${key}_$subKey';
                flatData[flatKey] = subValue;
              });
            } else {
              value.forEach((subKey, subValue) {
                final flatKey = '${key}_$subKey';
                flatData[flatKey] = subValue;
              });
            }
          } else {
            flatData[key] = value;
          }
        });

        // 尝试将 realtime_data 解析为结构化遥测
        final structured = InverterRealtime.fromJson(realtimeRaw);
        final hasSection = structured.ac != null ||
            structured.pv != null ||
            structured.battery != null ||
            structured.sysStatus != null ||
            structured.energy != null;

        if (kDebugMode) {
          debugPrint('[DeviceRealtimePage] structured: ac=${structured.ac != null}, pv=${structured.pv != null}, batt=${structured.battery != null}, sys=${structured.sysStatus != null}, energy=${structured.energy != null}');
          if (structured.ac != null) {
            debugPrint('[DeviceRealtimePage] ac: voltage=${structured.ac!.voltage}, power=${structured.ac!.power}, current=${structured.ac!.current}');
          }
          if (structured.pv != null) {
            debugPrint('[DeviceRealtimePage] pv: power=${structured.pv!.pvPower}, pv1V=${structured.pv!.pvVoltage}');
          }
          if (structured.battery != null) {
            debugPrint('[DeviceRealtimePage] batt: soc=${structured.battery!.soc}, voltage=${structured.battery!.voltage}, power=${structured.battery!.power}');
          }
          if (structured.energy != null) {
            debugPrint('[DeviceRealtimePage] energy: dailyPv=${structured.energy!.dailyPV}, dailyCharge=${structured.energy!.dailyCharge}, dailyLoad=${structured.energy!.dailyLoad}');
          }
          debugPrint('[DeviceRealtimePage] hasSection=$hasSection, flatData keys: ${flatData.keys.toList()}');
        }

        setState(() {
          _realtimeData.addAll(flatData);
          if (_latest == null && hasSection) {
            _latest = structured;
          }
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
          if (kDebugMode) {
            debugPrint('[DeviceRealtimePage] setState complete: _loading=$_loading, _error=$_error, _online=$_online');
          }
        });
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[DeviceRealtimePage] _fetchDeviceDetail failed: $e');
        debugPrint('[DeviceRealtimePage] Stack trace: $stackTrace');
      }
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

  /// 将 InverterRealtime 转为与云端 API 一致的扁平 Map（V2.1 键，
  /// 与服务端 normalizeRealtimeData 展平后的顶层键一致），
  /// 保持 derived 字段合并机制与原实现一致
  Map<String, dynamic> _inverterToFlatMap(InverterRealtime rt) {
    final map = <String, dynamic>{};
    // AC
    if (rt.ac != null) {
      map['ac_output_voltage'] = rt.ac!.voltage;
      map['output_current'] = rt.ac!.current;
      map['output_power'] = rt.ac!.power;
      map['ac_output_frequency'] = rt.ac!.frequency;
      map['output_apparent_power'] = rt.ac!.apparentPower;
    }
    // Battery
    if (rt.battery != null) {
      map['battery_soc'] = rt.battery!.soc;
      map['battery_soh'] = rt.battery!.soh;
      map['battery_voltage'] = rt.battery!.voltage;
      map['battery_current'] = rt.battery!.current;
      map['battery_power'] = rt.battery!.power;
      map['battery_charge_power'] = rt.battery!.chargePower;
      map['battery_discharge_power'] = rt.battery!.dischargePower;
    }
    // PV
    if (rt.pv != null) {
      map['pv1_voltage'] = rt.pv!.pvVoltage;
      map['pv1_current'] = rt.pv!.pvCurrent;
      map['pv_total_power'] = rt.pv!.pvPower;
      map['mppt_state'] = rt.pv!.mpptState;
    }
    // System Status
    if (rt.sysStatus != null) {
      map['work_state'] = rt.sysStatus!.state;
      map['fault_code'] = rt.sysStatus!.faultCode;
      map['alarm_code'] = rt.sysStatus!.alarmCode;
      map['inverter_temperature'] = rt.sysStatus!.tempInv;
      map['boost_temperature'] = rt.sysStatus!.boostTemp;
      map['transformer_temperature'] = rt.sysStatus!.transformerTemp;
      map['pv_temperature'] = rt.sysStatus!.pvTemp;
      map['dc_bus_voltage'] = rt.sysStatus!.dcBusVoltage;
      map['load_percent'] = rt.sysStatus!.loadPercent;
    }
    // Fan（V2.1 双风扇）
    if (rt.fan != null) {
      map['mppt_fan_speed'] = rt.fan!.mpptSpeed;
      map['inv_fan_speed'] = rt.fan!.invSpeed;
    }
    // Diag（V2.1 诊断量）
    map['work_time_total'] = rt.workTimeTotalSec;
    // Energy
    if (rt.energy != null) {
      map['daily_pv_energy'] = rt.energy!.dailyPV;
      map['total_pv_energy'] = rt.energy!.totalPV;
      map['daily_charge_energy'] = rt.energy!.dailyCharge;
      map['total_charge_energy'] = rt.energy!.totalCharge;
      map['daily_discharge_energy'] = rt.energy!.dailyDischarge;
      map['total_discharge_energy'] = rt.energy!.totalDischarge;
      map['daily_load_energy'] = rt.energy!.dailyLoad;
      map['output_energy_daily'] = rt.energy!.dailyLoad;
      map['total_load_energy'] = rt.energy!.totalLoad;
      map['output_energy_total'] = rt.energy!.totalLoad;
      // V2 能量分项
      map['gen_energy_daily'] = rt.energy!.dailyGenEnergy;
      map['gen_energy_total'] = rt.energy!.totalGenEnergy;
      map['ac_charge_energy_daily'] = rt.energy!.dailyAcChargeEnergy;
      map['ac_charge_energy_total'] = rt.energy!.totalAcChargeEnergy;
      map['ac_bypass_energy_daily'] = rt.energy!.dailyAcBypassEnergy;
      map['ac_bypass_energy_total'] = rt.energy!.totalAcBypassEnergy;
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
        // 本地直连模式：接收 DeviceBloc 的本地实时数据
        if (state is DeviceDetailLoaded && state.realtimeData != null) {
          final rt = state.realtimeData!;
          setState(() {
            _latest = rt;
            final newMqttData = _inverterToFlatMap(rt);
            _realtimeData.addAll(newMqttData);
            _hasMqttData = true;
            _apiUnavailable = false;
            _error = null;
            _loading = false;
            if (rt.updatedAt != null) {
              _dataUpdatedAt = rt.updatedAt;
            }
            if (rt.onlineStatus != null) {
              _online = rt.onlineStatus!.online;
            }
          });
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

  /// 内容区：横幅区（顶部）+ TabBarView（4 Tab）+ 底部品牌 Tab 栏
  Widget _buildContent() {
    return Column(
      children: [
        // ── 横幅区（位于 TabBarView 上方）──
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
        // ── TabBarView ──
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              RealtimeDataTab(
                data: _latest,
                footer: _buildProtocolEntry(),
              ),
              EnergyStatsTab(data: _latest),
              RemoteSettingsTab(sn: widget.sn),
              DeviceHealthTab(
                data: _latest,
                flat: _realtimeData,
                online: _online,
              ),
            ],
          ),
        ),
        // ── 底部 Tab 栏（品牌浮起容器）──
        _buildBottomTabBar(),
      ],
    );
  }

  /// 底部 Tab 栏：品牌浮起圆角容器，图标 + 文字组合；
  /// 选中项品牌色渐变药丸高亮，未选中灰色；SafeArea 适配底部安全区
  Widget _buildBottomTabBar() {
    final l10n = AppLocalizations.of(context)!;
    final tabs = [
      (Icons.assessment_outlined, l10n.str('realtime_data')),
      (Icons.insights_outlined, l10n.str('energy_stats')),
      (Icons.tune_rounded, l10n.str('remote_settings')),
      (Icons.health_and_safety_outlined, l10n.str('health_title')),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Container(
        margin: EdgeInsets.fromLTRB(12.w, 0, 12.w, 8.h),
        padding: EdgeInsets.all(5.w),
        decoration: BoxDecoration(
          color: AppColor.surfaceContainer(context),
          borderRadius: BorderRadius.circular(22.r),
          border: Border.all(color: AppColor.border(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withValues(alpha: isDark ? 0.3 : 0.08),
              blurRadius: 18,
              offset: Offset(0, 4.h),
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) {
            final current =
                _tabController.animation?.value.round() ?? _tabController.index;
            return Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: _buildBottomTabItem(
                      i,
                      current,
                      tabs[i].$1,
                      tabs[i].$2,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 单个底部 Tab 项：选中品牌蓝渐变药丸（图标+文字白色），未选中灰
  Widget _buildBottomTabItem(
    int index,
    int current,
    IconData icon,
    String label,
  ) {
    final selected = index == current;
    return InkWell(
      onTap: () => _tabController.animateTo(index),
      borderRadius: BorderRadius.circular(16.r),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(vertical: 8.h),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withValues(alpha: 0.75),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : null,
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17.sp,
              color:
                  selected ? Colors.white : AppColor.textSecondary(context),
            ),
            SizedBox(width: 5.w),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color:
                    selected ? Colors.white : AppColor.textSecondary(context),
              ),
            ),
          ],
        ),
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
