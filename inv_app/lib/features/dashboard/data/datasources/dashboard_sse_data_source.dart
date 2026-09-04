import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// SSE数据源 - 实现实时数据更新
class DashboardSSEDataSource {
  final Dio dio;
  StreamController<Map<String, dynamic>>? _controller;
  StreamSubscription<List<int>>? _responseSubscription;
  CancelToken? _requestCancelToken;
  bool _isConnected = false;
  bool _stopped = true;
  int _generation = 0;
  Timer? _heartbeatTimer;
  Timer? _stabilityTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  static const Duration heartbeatInterval = Duration(seconds: 30);
  static const Duration reconnectDelay = Duration(seconds: 5);

  DashboardSSEDataSource(this.dio);

  /// 连接到SSE流
  Stream<Map<String, dynamic>> connectToSSE() {
    final generation = ++_generation;
    _stopped = false;
    _cancelConnectionResources();
    _closeController();
    _reconnectAttempts = 0;
    _controller = StreamController<Map<String, dynamic>>.broadcast();
    _connect(generation);
    return _controller!.stream;
  }

  /// 断开SSE连接
  void disconnect() {
    _stopped = true;
    _generation++;
    _cancelConnectionResources();
    _closeController();
  }

  /// 检查连接状态
  bool get isConnected => _isConnected;

  Future<void> _connect(int generation) async {
    if (!_isCurrentGeneration(generation) || _isConnected) return;

    final cancelToken = CancelToken();
    _requestCancelToken = cancelToken;
    try {
      final response = await dio.get<ResponseBody>(
        '/dashboard/sse',
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: null, // SSE 长连接不设超时
          headers: {
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
          },
        ),
      );

      if (!_isCurrentGeneration(generation)) {
        _discardResponse(response);
        return;
      }

      _isConnected = true;

      _startHeartbeat(generation);
      _listenToStream(response, generation);
    } catch (e) {
      final isCancellation = e is DioException && CancelToken.isCancel(e);
      if (_isCurrentGeneration(generation) && !isCancellation) {
        _handleConnectionError(e, generation);
      }
    }
  }

  void _listenToStream(
    Response<ResponseBody> response,
    int generation,
  ) {
    final Stream<List<int>>? responseStream = response.data?.stream;
    if (responseStream == null) return;

    final subscription = responseStream.listen(
      (data) {
        if (!_isCurrentGeneration(generation)) return;
        final String chunk = utf8.decode(data);
        _processSSEData(chunk);
      },
      onDone: () {
        if (_isCurrentGeneration(generation)) {
          _handleDisconnection(generation);
        }
      },
      onError: (error) {
        if (_isCurrentGeneration(generation)) {
          _handleConnectionError(error, generation);
        }
      },
    );

    if (_isCurrentGeneration(generation)) {
      _responseSubscription = subscription;
      _startStabilityTimer(generation);
    } else {
      unawaited(subscription.cancel());
    }
  }

  void _processSSEData(String chunk) {
    final lines = chunk.split('\n');

    for (final line in lines) {
      if (line.startsWith('data: ')) {
        final data = line.substring(6).trim();
        if (data.isNotEmpty) {
          try {
            final jsonData = json.decode(data) as Map<String, dynamic>;
            _reconnectAttempts = 0;
            _controller?.add(jsonData);
          } catch (e) {
            // 忽略解析错误
          }
        }
      } else if (line.startsWith('event: ')) {
        // 处理事件类型
        // 可以根据事件类型做特殊处理
      } else if (line.startsWith('id: ')) {
        // 处理事件ID
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

  void _startHeartbeat(int generation) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (timer) {
      if (!_isCurrentGeneration(generation) || !_isConnected) {
        timer.cancel();
        return;
      }
      // 发送心跳检测
      _sendHeartbeat();
    });
  }

  void _startStabilityTimer(int generation) {
    _stabilityTimer?.cancel();
    _stabilityTimer = Timer(heartbeatInterval, () {
      if (_isCurrentGeneration(generation) && _isConnected) {
        _reconnectAttempts = 0;
      }
    });
  }

  void _sendHeartbeat() {
    // 心跳检测 - 可以发送一个空注释或特定格式的数据
    // 这里简单处理，实际可能需要发送特定格式
  }

  void _handleConnectionError(dynamic error, int generation) {
    if (!_isCurrentGeneration(generation)) return;
    _cancelActiveTransport();

    if (_reconnectAttempts < maxReconnectAttempts) {
      _reconnectAttempts++;
      final delay = reconnectDelay * _reconnectAttempts;

      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(delay, () {
        if (_isCurrentGeneration(generation)) {
          _connect(generation);
        }
      });
    } else {
      _controller?.addError(error);
    }
  }

  void _handleDisconnection(int generation) {
    if (!_isCurrentGeneration(generation)) return;
    _cancelActiveTransport();

    if (_reconnectAttempts < maxReconnectAttempts) {
      _reconnectAttempts++;
      final delay = reconnectDelay * _reconnectAttempts;

      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(delay, () {
        if (_isCurrentGeneration(generation)) {
          _connect(generation);
        }
      });
    }
  }

  bool _isCurrentGeneration(int generation) {
    return !_stopped && generation == _generation;
  }

  void _cancelConnectionResources() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cancelActiveTransport();
  }

  void _cancelActiveTransport() {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _stabilityTimer?.cancel();
    _stabilityTimer = null;

    _requestCancelToken?.cancel('Dashboard SSE connection stopped');
    _requestCancelToken = null;

    final subscription = _responseSubscription;
    _responseSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }

  void _discardResponse(Response<ResponseBody> response) {
    final Stream<List<int>>? responseStream = response.data?.stream;
    if (responseStream == null) return;

    final subscription = responseStream.listen(
      (_) {},
      onError: (_) {},
    );
    unawaited(subscription.cancel());
  }

  void _closeController() {
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) {
      unawaited(controller.close());
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
