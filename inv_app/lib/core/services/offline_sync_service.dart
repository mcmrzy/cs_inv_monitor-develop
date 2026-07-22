import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:inv_app/core/entities/offline_action.dart';
import 'package:inv_app/core/services/offline_cache_service.dart';
import 'package:inv_app/core/services/api_service.dart';

class OfflineSyncService {
  final OfflineCacheService _cacheService;
  final ApiService _apiService;
  final Connectivity _connectivity;
  StreamSubscription<ConnectivityResult>? _connectivitySub;

  OfflineSyncService({
    required OfflineCacheService cacheService,
    required ApiService apiService,
    required Connectivity connectivity,
  })  : _cacheService = cacheService,
        _apiService = apiService,
        _connectivity = connectivity;

  void init() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        syncAll();
      }
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  Future<void> syncAll() async {
    final actions = await _cacheService.getUnsyncedActions();
    for (final action in actions) {
      try {
        await _syncAction(action);
        await _cacheService.markAsSynced(action.id);
      } catch (_) {}
    }
    await _cacheService.clearSynced();
  }

  Future<void> _syncAction(OfflineAction action) async {
    switch (action.type) {
      case 'param_update':
        await _apiService.put(
          '/devices/${action.sn}/params',
          data: {'params': action.data},
          fromJson: (json) => json,
        );
        break;
      case 'control':
        await _apiService.post(
          '/devices/${action.sn}/control',
          data: {
            'command': action.data['cmd_type'],
            'params': action.data['params'],
          },
          fromJson: (json) => json,
        );
        break;
      case 'wifi_config':
        await _apiService.post(
          '/devices/${action.sn}/wifi/config',
          data: action.data,
          fromJson: (json) => json,
        );
        break;
    }
  }
}
