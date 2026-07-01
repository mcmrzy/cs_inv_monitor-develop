import 'dart:async';
import 'dart:developer' as dev;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/core/services/data_cache_service.dart';
import 'package:inv_app/features/dashboard/data/datasources/dashboard_sse_data_source.dart';
import 'package:inv_app/features/dashboard/domain/entities/dashboard_data.dart';
import 'package:inv_app/features/dashboard/domain/entities/trend_data_point.dart';
import 'package:inv_app/features/dashboard/domain/entities/station_rank_item.dart';
import 'package:inv_app/features/dashboard/domain/repositories/dashboard_repository.dart';

part 'dashboard_event.dart';
part 'dashboard_state.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final DashboardRepository repository;
  final DataCacheService dataCacheService;
  final DashboardSSEDataSource sseDataSource;

  static const String _cacheKey = 'dashboard_data';

  StreamSubscription<Map<String, dynamic>>? _sseSubscription;

  DashboardBloc({
    required this.repository,
    required this.dataCacheService,
    required this.sseDataSource,
  }) : super(const DashboardInitial()) {
    on<DashboardLoadRequested>(_onLoadRequested);
    on<DashboardSSEConnectRequested>(_onSSEConnectRequested);
    on<DashboardSSEDisconnectRequested>(_onSSEDisconnectRequested);
    on<DashboardSSEDataReceived>(_onSSEDataReceived);
    on<DashboardSSEConnectionChanged>(_onSSEConnectionChanged);
    on<DashboardTimeRangeChanged>(_onTimeRangeChanged);
  }

  @override
  Future<void> close() {
    _sseSubscription?.cancel();
    sseDataSource.disconnect();
    return super.close();
  }

  /// 快速检查是否有网络连接
  Future<bool> _hasNetwork() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (_) {
      return true;
    }
  }

  Future<void> _onLoadRequested(
    DashboardLoadRequested event,
    Emitter<DashboardState> emit,
  ) async {
    // 如果已有数据，不显示 loading（避免刷新时闪烁）
    if (state is! DashboardLoaded) {
      emit(const DashboardLoading());
    }

    // 断网时直接加载缓存，不等待 30s×4 超时
    if (!await _hasNetwork()) {
      final cached = _loadCachedData();
      if (cached != null) {
        emit(DashboardLoaded(data: cached));
      } else if (state is DashboardLoaded) {
        // 保留旧数据
      } else {
        emit(const DashboardError(message: 'Failed to load, please check network'));
      }
      return;
    }

    // 每个 API 独立 try-catch，一个失败不影响其他
    Map<String, dynamic> stats = {};
    List<TrendDataPoint> trendData = [];
    Map<String, dynamic> dist = {};
    List<StationRankItem> ranking = [];
    int successCount = 0;

    // 1. 统计数据（Hero 卡片 + 告警）
    try {
      final result = await repository.getStatistics();
      result.fold(
        (failure) => dev.log('Dashboard: getStatistics failed: ${failure.message}'),
        (data) {
          stats = data;
          successCount++;
        },
      );
    } catch (e) {
      dev.log('Dashboard: getStatistics exception: $e');
    }

    // 2. 趋势数据
    try {
      final result = await repository.getTrendData();
      result.fold(
        (failure) => dev.log('Dashboard: getTrendData failed: ${failure.message}'),
        (data) {
          trendData = data;
          successCount++;
        },
      );
    } catch (e) {
      dev.log('Dashboard: getTrendData exception: $e');
    }

    // 3. 设备分布
    try {
      final result = await repository.getDeviceDistribution();
      result.fold(
        (failure) => dev.log('Dashboard: getDeviceDistribution failed: ${failure.message}'),
        (data) {
          dist = data;
          successCount++;
        },
      );
    } catch (e) {
      dev.log('Dashboard: getDeviceDistribution exception: $e');
    }

    // 4. 电站排行
    try {
      final result = await repository.getStationRanking();
      result.fold(
        (failure) => dev.log('Dashboard: getStationRanking failed: ${failure.message}'),
        (data) {
          ranking = data;
          successCount++;
        },
      );
    } catch (e) {
      dev.log('Dashboard: getStationRanking exception: $e');
    }

    // 全部失败时尝试缓存
    if (successCount == 0) {
      final cached = _loadCachedData();
      if (cached != null) {
        emit(DashboardLoaded(data: cached));
      } else if (state is DashboardLoaded) {
        // 保留旧数据
      } else {
        emit(const DashboardError(message: 'Failed to load, please check network'));
      }
      return;
    }

    final deviceStats = stats['deviceStats'] as Map<String, dynamic>? ?? {};
    final recentAlarms =
        (stats['recentAlarms'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    final dashboardData = DashboardData(
      todayEnergy: (stats['todayEnergy'] as num?)?.toDouble() ?? 0,
      totalEnergy: (stats['totalEnergy'] as num?)?.toDouble() ?? 0,
      deviceTotal: (deviceStats['total'] as num?)?.toInt() ?? 0,
      onlineCount: (deviceStats['online'] as num?)?.toInt() ??
          (dist['online'] as num?)?.toInt() ??
          0,
      offlineCount: (deviceStats['offline'] as num?)?.toInt() ??
          (dist['offline'] as num?)?.toInt() ??
          0,
      faultCount: (deviceStats['fault'] as num?)?.toInt() ??
          (dist['fault'] as num?)?.toInt() ??
          0,
      trendData: trendData,
      stationRanking: ranking,
      recentAlarms: recentAlarms,
    );

    // 缓存数据
    await _cacheDashboardData(dashboardData);

    final currentState = state;
    if (currentState is DashboardLoaded) {
      emit(currentState.copyWith(data: dashboardData));
    } else {
      emit(DashboardLoaded(data: dashboardData));
    }
  }

  Future<void> _onSSEConnectRequested(
    DashboardSSEConnectRequested event,
    Emitter<DashboardState> emit,
  ) async {
    if (state is DashboardLoaded) {
      emit((state as DashboardLoaded).copyWith(isSSEConnected: false));
    }

    _sseSubscription?.cancel();
    _sseSubscription = sseDataSource.connectToSSE().listen(
      (data) {
        add(DashboardSSEDataReceived(data: data));
      },
      onError: (error) {
        dev.log('Dashboard SSE error: $error');
        add(const DashboardSSEConnectionChanged(isConnected: false));
      },
      onDone: () {
        add(const DashboardSSEConnectionChanged(isConnected: false));
      },
    );

    add(const DashboardSSEConnectionChanged(isConnected: true));
  }

  Future<void> _onSSEDisconnectRequested(
    DashboardSSEDisconnectRequested event,
    Emitter<DashboardState> emit,
  ) async {
    _sseSubscription?.cancel();
    _sseSubscription = null;
    sseDataSource.disconnect();

    if (state is DashboardLoaded) {
      emit((state as DashboardLoaded).copyWith(isSSEConnected: false));
    }
  }

  Future<void> _onSSEDataReceived(
    DashboardSSEDataReceived event,
    Emitter<DashboardState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DashboardLoaded) return;

    try {
      final data = event.data;
      final type = data['type'] as String? ?? '';

      if (type == 'dashboard_update') {
        final currentData = currentState.data;

        // 解析设备统计（后端格式：deviceStats 对象）
        final deviceStats = data['deviceStats'] as Map<String, dynamic>?;
        final onlineCount = (deviceStats?['online'] as num?)?.toInt() ?? currentData.onlineCount;
        final offlineCount = (deviceStats?['offline'] as num?)?.toInt() ?? currentData.offlineCount;
        final faultCount = (deviceStats?['fault'] as num?)?.toInt() ?? currentData.faultCount;
        final deviceTotal = (deviceStats?['total'] as num?)?.toInt() ?? currentData.deviceTotal;

        // 解析最近告警（后端格式：recentAlarms 数组）
        final recentAlarmsRaw = data['recentAlarms'] as List<dynamic>?;
        final recentAlarms = recentAlarmsRaw?.map((e) {
          if (e is Map<String, dynamic>) return e;
          return <String, dynamic>{};
        }).toList() ?? currentData.recentAlarms;

        final updatedData = DashboardData(
          todayEnergy: currentData.todayEnergy,
          totalEnergy: currentData.totalEnergy,
          deviceTotal: deviceTotal,
          onlineCount: onlineCount,
          offlineCount: offlineCount,
          faultCount: faultCount,
          trendData: currentData.trendData,
          stationRanking: currentData.stationRanking,
          recentAlarms: recentAlarms.cast<Map<String, dynamic>>(),
          isFromCache: false,
        );

        emit(currentState.copyWith(data: updatedData));
      }
    } catch (e) {
      dev.log('Dashboard: SSE data processing error: $e');
    }
  }

  Future<void> _onSSEConnectionChanged(
    DashboardSSEConnectionChanged event,
    Emitter<DashboardState> emit,
  ) async {
    if (state is DashboardLoaded) {
      emit((state as DashboardLoaded).copyWith(isSSEConnected: event.isConnected));
    }
  }

  Future<void> _onTimeRangeChanged(
    DashboardTimeRangeChanged event,
    Emitter<DashboardState> emit,
  ) async {
    if (state is DashboardLoaded) {
      emit((state as DashboardLoaded).copyWith(selectedTimeRange: event.range));
    }

    // 根据时间范围重新加载趋势数据
    try {
      final result = await repository.getTrendData();
      result.fold(
        (failure) => dev.log('Dashboard: getTrendData failed: ${failure.message}'),
        (data) {
          if (state is DashboardLoaded) {
            final currentState = state as DashboardLoaded;
            final updatedData = DashboardData(
              todayEnergy: currentState.data.todayEnergy,
              totalEnergy: currentState.data.totalEnergy,
              deviceTotal: currentState.data.deviceTotal,
              onlineCount: currentState.data.onlineCount,
              offlineCount: currentState.data.offlineCount,
              faultCount: currentState.data.faultCount,
              trendData: data,
              stationRanking: currentState.data.stationRanking,
              recentAlarms: currentState.data.recentAlarms,
              isFromCache: currentState.data.isFromCache,
            );
            emit(currentState.copyWith(data: updatedData));
          }
        },
      );
    } catch (e) {
      dev.log('Dashboard: getTrendData exception: $e');
    }
  }

  Future<void> _cacheDashboardData(DashboardData data) async {
    try {
      await dataCacheService.save(_cacheKey, {
        'todayEnergy': data.todayEnergy,
        'totalEnergy': data.totalEnergy,
        'deviceTotal': data.deviceTotal,
        'onlineCount': data.onlineCount,
        'offlineCount': data.offlineCount,
        'faultCount': data.faultCount,
        'trendData': data.trendData
            .map((e) => {'date': e.date, 'energy': e.energy, 'load': e.load, 'cumulative': e.cumulative})
            .toList(),
        'stationRanking': data.stationRanking
            .map((e) => {
                  'stationId': e.stationId,
                  'stationName': e.stationName,
                  'energy': e.energy,
                  'deviceCount': e.deviceCount,
                })
            .toList(),
        'recentAlarms': data.recentAlarms,
      });
    } catch (_) {
      // 缓存失败不影响主流程
    }
  }

  DashboardData? _loadCachedData() {
    try {
      final cached = dataCacheService.load(_cacheKey);
      if (cached is! Map<String, dynamic>) return null;

      return DashboardData(
        todayEnergy: (cached['todayEnergy'] as num?)?.toDouble() ?? 0,
        totalEnergy: (cached['totalEnergy'] as num?)?.toDouble() ?? 0,
        deviceTotal: (cached['deviceTotal'] as num?)?.toInt() ?? 0,
        onlineCount: (cached['onlineCount'] as num?)?.toInt() ?? 0,
        offlineCount: (cached['offlineCount'] as num?)?.toInt() ?? 0,
        faultCount: (cached['faultCount'] as num?)?.toInt() ?? 0,
        trendData: ((cached['trendData'] as List<dynamic>?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map((e) => TrendDataPoint.fromJson(e))
            .toList(),
        stationRanking: ((cached['stationRanking'] as List<dynamic>?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map((e) => StationRankItem.fromJson(e))
            .toList(),
        recentAlarms:
            ((cached['recentAlarms'] as List<dynamic>?) ?? []).cast<Map<String, dynamic>>(),
        isFromCache: true,
      );
    } catch (_) {
      return null;
    }
  }
}
