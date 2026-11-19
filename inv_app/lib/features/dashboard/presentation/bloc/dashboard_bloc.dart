import 'dart:async';
import 'dart:developer' as dev;
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/services/data_cache_service.dart';
import 'package:inv_app/core/services/network_status_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
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
  static const _emptyOverview = DashboardData(
    todayEnergy: 0,
    totalEnergy: 0,
    deviceTotal: 0,
    onlineCount: 0,
    offlineCount: 0,
    faultCount: 0,
    trendData: [],
    stationRanking: [],
    recentAlarms: [],
  );

  Future<void>? _activeLoad;

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

  /// 快速检查是否有网络连接（带连续确认，启动瞬间不误判离线）
  Future<bool> _hasNetwork() async {
    try {
      return await getIt<NetworkStatusService>().checkConnectivity();
    } catch (_) {
      return true;
    }
  }

  Future<void> _onLoadRequested(
    DashboardLoadRequested event,
    Emitter<DashboardState> emit,
  ) async {
    final operation = _activeLoad ??= _loadOverview(emit);
    try {
      await operation;
    } finally {
      if (identical(_activeLoad, operation)) _activeLoad = null;
      event.completion?.complete();
    }
  }

  void _showCachedOverview(
    Emitter<DashboardState> emit, {
    required DashboardErrorKind errorKind,
  }) {
    final current = state;
    final cached = _loadCachedData();
    if (cached != null) {
      emit(DashboardLoaded(data: cached));
    } else if (current is DashboardLoaded) {
      emit(current.copyWith(data: current.data.copyWith(isFromCache: true)));
    } else {
      emit(
        DashboardError(
          message: 'Failed to load, please check network',
          kind: errorKind,
        ),
      );
    }
  }

  Future<void> _loadOverview(Emitter<DashboardState> emit) async {
    final initialLoad = state is! DashboardLoaded;
    if (initialLoad) emit(const DashboardLoading());

    final hasNetwork = await _hasNetwork();
    if (emit.isDone) return;
    if (!hasNetwork) {
      _showCachedOverview(emit, errorKind: DashboardErrorKind.networkUnavailable);
      return;
    }

    final pending = <DashboardSection>{
      DashboardSection.statistics,
      DashboardSection.distribution,
      DashboardSection.trend,
      DashboardSection.ranking,
    };
    final failed = <DashboardSection>{};
    var hasData = false;
    Map<String, dynamic>? statistics;
    Map<String, dynamic>? distribution;
    List<TrendDataPoint>? trend;
    List<StationRankItem>? ranking;

    DashboardLoaded buildOverview() {
      final current = state;
      final base = current is DashboardLoaded ? current.data : _emptyOverview;
      final deviceStats = statistics?['deviceStats'] as Map<String, dynamic>?;
      final online = (deviceStats?['online'] as num?)?.toInt() ??
          (distribution?['online'] as num?)?.toInt();
      final offline = (deviceStats?['offline'] as num?)?.toInt() ??
          (distribution?['offline'] as num?)?.toInt();
      final fault = (deviceStats?['fault'] as num?)?.toInt() ??
          (distribution?['fault'] as num?)?.toInt();

      final visiblePending = {...pending};
      final visibleFailures = {...failed};
      final hasCounts = online != null && offline != null && fault != null;
      if (hasCounts) {
        visiblePending.remove(DashboardSection.distribution);
        visibleFailures.remove(DashboardSection.distribution);
      } else if (pending.contains(DashboardSection.statistics) ||
          pending.contains(DashboardSection.distribution)) {
        visiblePending.add(DashboardSection.distribution);
        visibleFailures.remove(DashboardSection.distribution);
      } else {
        visibleFailures.add(DashboardSection.distribution);
      }
      if (pending.contains(DashboardSection.statistics)) {
        visiblePending.add(DashboardSection.alarms);
      } else if (failed.contains(DashboardSection.statistics)) {
        visibleFailures.add(DashboardSection.alarms);
      }

      final data = base.copyWith(
        todayEnergy: (statistics?['todayEnergy'] as num?)?.toDouble(),
        totalEnergy: (statistics?['totalEnergy'] as num?)?.toDouble(),
        deviceTotal: (deviceStats?['total'] as num?)?.toInt() ??
            (hasCounts ? online + offline + fault : null),
        onlineCount: online,
        offlineCount: offline,
        faultCount: fault,
        trendData: trend,
        stationRanking: ranking,
        recentAlarms: (statistics?['recentAlarms'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList(),
        isFromCache: false,
      );

      return (current is DashboardLoaded ? current : DashboardLoaded(data: data))
          .copyWith(
        data: data,
        pendingSections: visiblePending,
        failedSections: visibleFailures,
      );
    }

    Future<void> loadSection<T>(
      DashboardSection section,
      Future<Either<Failure, T>> Function() fetch,
      void Function(T) accept,
    ) async {
      try {
        final result = await fetch();
        result.fold(
          (failure) {
            failed.add(section);
            dev.log('Dashboard: ${section.name} failed: ${failure.message}');
          },
          (data) {
            accept(data);
            hasData = true;
          },
        );
      } catch (error) {
        failed.add(section);
        dev.log('Dashboard: ${section.name} failed: $error');
      }

      pending.remove(section);
      if (initialLoad && hasData && pending.isNotEmpty && !emit.isDone) {
        emit(buildOverview());
      }
    }

    final timeRange = state is DashboardLoaded
        ? (state as DashboardLoaded).selectedTimeRange
        : 'day';
    await Future.wait([
      loadSection(DashboardSection.statistics, repository.getStatistics, (data) {
        statistics = data;
      }),
      loadSection(
        DashboardSection.distribution,
        repository.getDeviceDistribution,
        (data) => distribution = data,
      ),
      loadSection(
        DashboardSection.trend,
        () => repository.getTrendData(type: timeRange),
        (data) => trend = data,
      ),
      loadSection(DashboardSection.ranking, repository.getStationRanking, (data) {
        ranking = data;
      }),
    ]);

    if (emit.isDone) return;
    if (!hasData) {
      _showCachedOverview(emit, errorKind: DashboardErrorKind.requestFailed);
      return;
    }

    final overview = buildOverview();
    emit(overview);
    if (overview.failedSections.isEmpty) {
      await _cacheDashboardData(overview.data);
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
        final onlineCount = (deviceStats?['online'] as num?)?.toInt() ??
            currentData.onlineCount;
        final offlineCount = (deviceStats?['offline'] as num?)?.toInt() ??
            currentData.offlineCount;
        final faultCount =
            (deviceStats?['fault'] as num?)?.toInt() ?? currentData.faultCount;
        final deviceTotal =
            (deviceStats?['total'] as num?)?.toInt() ?? currentData.deviceTotal;

        // 解析最近告警（后端格式：recentAlarms 数组）
        final recentAlarmsRaw = data['recentAlarms'] as List<dynamic>?;
        final recentAlarms = recentAlarmsRaw?.map((e) {
              if (e is Map<String, dynamic>) return e;
              return <String, dynamic>{};
            }).toList() ??
            currentData.recentAlarms;

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
          isFromCache: currentData.isFromCache,
        );

        final failures = {...currentState.failedSections};
        if (recentAlarmsRaw != null) failures.remove(DashboardSection.alarms);
        if (deviceStats?['total'] is num &&
            deviceStats?['online'] is num &&
            deviceStats?['offline'] is num &&
            deviceStats?['fault'] is num) {
          failures.remove(DashboardSection.distribution);
        }
        emit(currentState.copyWith(data: updatedData, failedSections: failures));
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
      emit(
        (state as DashboardLoaded).copyWith(isSSEConnected: event.isConnected),
      );
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
      final result = await repository.getTrendData(type: event.range);
      result.fold(
        (failure) =>
            dev.log('Dashboard: getTrendData failed: ${failure.message}'),
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
            .map(
              (e) => {
                'date': e.date,
                'energy': e.energy,
                'load': e.load,
                'cumulative': e.cumulative,
              },
            )
            .toList(),
        'stationRanking': data.stationRanking
            .map(
              (e) => {
                'stationId': e.stationId,
                'stationName': e.stationName,
                'energy': e.energy,
                'deviceCount': e.deviceCount,
              },
            )
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
        recentAlarms: ((cached['recentAlarms'] as List<dynamic>?) ?? [])
            .cast<Map<String, dynamic>>(),
        isFromCache: true,
      );
    } catch (_) {
      return null;
    }
  }
}
