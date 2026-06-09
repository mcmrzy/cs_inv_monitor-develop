import 'dart:async';
import 'package:esp_smartconfig/esp_smartconfig.dart';
import 'package:wifi_iot/wifi_iot.dart';

enum SmartConfigStatus { idle, scanning, configuring, success, timeout, error }

class SmartConfigService {
  Provisioner? _provisioner;
  StreamController<SmartConfigStatus>? _statusController;
  bool _running = false;

  Stream<SmartConfigStatus> get statusStream =>
      (_statusController ??= StreamController<SmartConfigStatus>.broadcast()).stream;

  SmartConfigStatus _currentStatus = SmartConfigStatus.idle;
  SmartConfigStatus get currentStatus => _currentStatus;

  void _emit(SmartConfigStatus status) {
    _currentStatus = status;
    _statusController?.add(status);
  }

  Future<bool> startSmartConfig({
    required String ssid,
    required String password,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (_running) return false;
    _running = true;

    _statusController ??= StreamController<SmartConfigStatus>.broadcast();

    try {
      _emit(SmartConfigStatus.scanning);

      final bssid = await WiFiForIoTPlugin.getBSSID();

      _emit(SmartConfigStatus.configuring);

      _provisioner = Provisioner.espTouch();

      final completer = Completer<bool>();

      _provisioner!.listen((response) {
        if (!completer.isCompleted) {
          _emit(SmartConfigStatus.success);
          completer.complete(true);
        }
      });

      await _provisioner!.start(ProvisioningRequest.fromStrings(
        ssid: ssid,
        bssid: bssid ?? '',
        password: password,
      ));

      // 超时保护
      Timer(timeout, () {
        if (!completer.isCompleted) {
          stopSmartConfig();
          _emit(SmartConfigStatus.timeout);
          completer.complete(false);
        }
      });

      return await completer.future;
    } catch (e) {
      stopSmartConfig();
      _emit(SmartConfigStatus.error);
      return false;
    }
  }

  void stopSmartConfig() {
    _running = false;
    _provisioner?.stop();
    _provisioner = null;
    if (_currentStatus != SmartConfigStatus.success &&
        _currentStatus != SmartConfigStatus.timeout) {
      _emit(SmartConfigStatus.idle);
    }
  }

  void dispose() {
    stopSmartConfig();
    _statusController?.close();
    _statusController = null;
  }
}
