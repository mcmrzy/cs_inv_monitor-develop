import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum SmartConfigStatus { idle, scanning, configuring, success, timeout, error }

class SmartConfigService {
  static const int _broadcastPort = 7001;
  static const Duration _sendInterval = Duration(milliseconds: 500);

  RawDatagramSocket? _socket;
  Timer? _sendTimer;
  Timer? _timeoutTimer;
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

      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket!.broadcastEnabled = true;
      _socket!.multicastLoopback = false;

      _emit(SmartConfigStatus.configuring);

      final payload = jsonEncode({'ssid': ssid, 'password': password});
      final data = utf8.encode(payload);
      final address = InternetAddress('255.255.255.255');

      _sendTimer = Timer.periodic(_sendInterval, (_) {
        _socket!.send(data, address, _broadcastPort);
      });

      final completer = Completer<bool>();

      _timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          stopSmartConfig();
          _emit(SmartConfigStatus.timeout);
          completer.complete(false);
        }
      });

      final subscription = _socket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram != null) {
            try {
              final response = utf8.decode(datagram.data);
              final json = jsonDecode(response) as Map<String, dynamic>;
              if (json['result'] == 'ok' || json['status'] == 'connected') {
                if (!completer.isCompleted) {
                  stopSmartConfig();
                  _emit(SmartConfigStatus.success);
                  completer.complete(true);
                }
              }
            } catch (_) {}
          }
        }
      });

      final result = await completer.future;
      await subscription.cancel();
      return result;
    } catch (e) {
      stopSmartConfig();
      _emit(SmartConfigStatus.error);
      return false;
    }
  }

  void stopSmartConfig() {
    _running = false;
    _sendTimer?.cancel();
    _sendTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _socket?.close();
    _socket = null;
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
