import 'dart:async';
import 'package:inv_app/core/services/storage_service.dart';

enum ConnectionMode { remote, local }

class ConnectionModeService {
  final StorageService _storageService;
  final StreamController<ConnectionMode> _modeController =
      StreamController<ConnectionMode>.broadcast();

  ConnectionMode _currentMode = ConnectionMode.remote;
  ConnectionMode get currentMode => _currentMode;
  bool get isLocal => _currentMode == ConnectionMode.local;
  bool get isRemote => _currentMode == ConnectionMode.remote;

  Stream<ConnectionMode> get modeStream => _modeController.stream;

  ConnectionModeService(this._storageService);

  Future<bool> isLocalMode() async {
    return _storageService.getIsLocalMode();
  }

  Future<void> setLocalMode(bool isLocal) async {
    await _storageService.saveIsLocalMode(isLocal);
    _currentMode = isLocal ? ConnectionMode.local : ConnectionMode.remote;
    _modeController.add(_currentMode);
  }

  Future<void> switchToRemote() async {
    _currentMode = ConnectionMode.remote;
    _modeController.add(_currentMode);
    await _storageService.saveIsLocalMode(false);
    // 使用 API 轮询，无需重连 MQTT
  }

  Future<void> switchToLocal() async {
    _currentMode = ConnectionMode.local;
    _modeController.add(_currentMode);
    await _storageService.saveIsLocalMode(true);
  }

  Future<void> init() async {
    final isLocal = await _storageService.getIsLocalMode();
    _currentMode = isLocal ? ConnectionMode.local : ConnectionMode.remote;
    _modeController.add(_currentMode);
  }

  void dispose() {
    _modeController.close();
  }
}
