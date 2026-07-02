import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';

/// SSE数据源 - 实现实时数据更新
class DashboardSSEDataSource {
  final Dio dio;
  StreamController<Map<String, dynamic>>? _controller;
  Response<ResponseBody>? _response;
  bool _isConnected = false;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  static const Duration heartbeatInterval = Duration(seconds: 30);
  static const Duration reconnectDelay = Duration(seconds: 5);

  DashboardSSEDataSource(this.dio);

  /// 连接到SSE流
  Stream<Map<String, dynamic>> connectToSSE() {
    _controller = StreamController<Map<String, dynamic>>.broadcast();
    _connect();
    return _controller!.stream;
  }

  /// 断开SSE连接
  void disconnect() {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _controller?.close();
    _controller = null;
  }

  /// 检查连接状态
  bool get isConnected => _isConnected;

  Future<void> _connect() async {
    if (_isConnected) return;

    try {
      final response = await dio.get<ResponseBody>(
        '/dashboard/sse',
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: null, // SSE 长连接不设超时
          headers: {
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
          },
        ),
      );

      _response = response;
      _isConnected = true;
      _reconnectAttempts = 0;

      _startHeartbeat();
      _listenToStream();
    } catch (e) {
      _handleConnectionError(e);
    }
  }

  void _listenToStream() {
    _response?.data?.stream.listen(
      (data) {
        final String chunk = utf8.decode(data);
        _processSSEData(chunk);
      },
      onDone: () {
        _handleDisconnection();
      },
      onError: (error) {
        _handleConnectionError(error);
      },
    );
  }

  void _processSSEData(String chunk) {
    final lines = chunk.split('\n');
    
    for (final line in lines) {
      if (line.startsWith('data: ')) {
        final data = line.substring(6).trim();
        if (data.isNotEmpty) {
          try {
            final jsonData = json.decode(data) as Map<String, dynamic>;
            _controller?.add(jsonData);
          } catch (e) {
            // 忽略解析错误
          }
        }
      } else if (line.startsWith('event: ')) {
        // 处理事件类型
        final eventType = line.substring(7).trim();
        // 可以根据事件类型做特殊处理
      } else if (line.startsWith('id: ')) {
        // 处理事件ID
        final eventId = line.substring(4).trim();
        // 可以用于断线重连
      } else if (line.startsWith('retry: ')) {
        // 处理重连时间
        final retryTime = int.tryParse(line.substring(7).trim());
        if (retryTime != null) {
          // 可以用于设置重连间隔
        }
      }
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (timer) {
      if (!_isConnected) {
        timer.cancel();
        return;
      }
      // 发送心跳检测
      _sendHeartbeat();
    });
  }

  void _sendHeartbeat() {
    // 心跳检测 - 可以发送一个空注释或特定格式的数据
    // 这里简单处理，实际可能需要发送特定格式
  }

  void _handleConnectionError(dynamic error) {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    
    if (_reconnectAttempts < maxReconnectAttempts) {
      _reconnectAttempts++;
      final delay = reconnectDelay * _reconnectAttempts;
      
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(delay, () {
        _connect();
      });
    } else {
      _controller?.addError(error);
    }
  }

  void _handleDisconnection() {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    
    if (_reconnectAttempts < maxReconnectAttempts) {
      _reconnectAttempts++;
      final delay = reconnectDelay * _reconnectAttempts;
      
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(delay, () {
        _connect();
      });
    }
  }

  /// 重置重连计数
  void resetReconnectAttempts() {
    _reconnectAttempts = 0;
  }
}

/// SSE事件类型
class SSEEventType {
  static const String dashboardUpdate = 'dashboard_update';
  static const String alarmUpdate = 'alarm_update';
  static const String deviceUpdate = 'device_update';
  static const String heartbeat = 'heartbeat';
}

/// SSE事件数据
class SSEEvent {
  final String type;
  final Map<String, dynamic> data;
  final String? id;
  final DateTime timestamp;

  SSEEvent({
    required this.type,
    required this.data,
    this.id,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory SSEEvent.fromJson(Map<String, dynamic> json) {
    return SSEEvent(
      type: json['type'] as String? ?? '',
      data: json['data'] as Map<String, dynamic>? ?? {},
      id: json['id'] as String?,
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
  }
}