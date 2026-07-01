import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:inv_app/core/config/app_config.dart';

/// SSE 实时通知推送服务（基于 HTTP Chunked Transfer）
class NotificationStreamService {
  static final NotificationStreamService _instance = NotificationStreamService._();
  factory NotificationStreamService() => _instance;
  NotificationStreamService._();

  StreamController<Map<String, dynamic>>? _notificationController;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  http.Client? _httpClient;

  /// 获取通知流
  Stream<Map<String, dynamic>> get notificationStream {
    if (_notificationController == null) {
      _notificationController = StreamController<Map<String, dynamic>>.broadcast();
    }
    return _notificationController!.stream;
  }

  /// 启动 SSE 连接
  Future<void> start({required String token}) async {
    if (_isConnected) {
      debugPrint('[NotificationStream] Already connected, skipping...');
      return;
    }

    try {
      final url = '${AppConfig.apiBaseUrl}/notifications/stream';
      
      debugPrint('[NotificationStream] Connecting to SSE: $url');
      
      _httpClient = http.Client();
      
      // 创建 HTTP 请求，设置 Accept header 为 text/event-stream
      final request = http.Request('GET', Uri.parse(url));
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';
      
      // 发送请求并获取响应流
      final response = await _httpClient!.send(request);
      
      if (response.statusCode != 200) {
        throw Exception('SSE connection failed with status ${response.statusCode}');
      }
      
      _isConnected = true;
      debugPrint('[NotificationStream] Connected successfully');
      
      // 监听响应流
      final stream = response.stream.transform(utf8.decoder);
      String buffer = '';
      
      await for (final chunk in stream) {
        buffer += chunk;
        
        // SSE 消息以 \n\n 分隔
        while (buffer.contains('\n\n')) {
          final index = buffer.indexOf('\n\n');
          final message = buffer.substring(0, index).trim();
          buffer = buffer.substring(index + 2);
          
          if (message.isEmpty) continue;
          
          // 解析 SSE 事件
          final lines = message.split('\n');
          String eventType = 'message';
          String eventData = '';
          
          for (final line in lines) {
            if (line.startsWith(':')) {
              // SSE 注释行（心跳 ping），忽略
              continue;
            } else if (line.startsWith('event:')) {
              eventType = line.substring(6).trim();
            } else if (line.startsWith('data:')) {
              eventData += line.substring(5).trim();
            }
          }
          
          // 如果只有注释行，跳过
          if (eventType == 'message' && eventData.isEmpty) continue;
          
          debugPrint('[NotificationStream] Received event: $eventType');
          
          switch (eventType) {
            case 'connected':
              debugPrint('[NotificationStream] Connection established');
              break;
              
            case 'notification':
              // 解析通知数据
              try {
                final data = json.decode(eventData);
                debugPrint('[NotificationStream] Notification received: $data');
                
                // 发送到流控制器
                if (_notificationController != null && 
                    !_notificationController!.isClosed) {
                  _notificationController!.add(data);
                }
              } catch (e) {
                debugPrint('[NotificationStream] Failed to parse notification: $e');
              }
              break;
              
            default:
              debugPrint('[NotificationStream] Unknown event type: $eventType');
          }
        }
      }
      
      // 流结束，尝试重连
      debugPrint('[NotificationStream] Stream ended, will reconnect in 5s...');
      _isConnected = false;
      Future.delayed(const Duration(seconds: 5), () {
        if (!_isConnected) {
          start(token: token);
        }
      });
      
    } catch (e) {
      debugPrint('[NotificationStream] Failed to connect: $e');
      _isConnected = false;
      // 5秒后重试
      Future.delayed(const Duration(seconds: 5), () {
        if (!_isConnected) {
          start(token: token);
        }
      });
    }
  }

  /// 停止 SSE 连接
  void stop() {
    _isConnected = false;
    _httpClient?.close();
    _httpClient = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    debugPrint('[NotificationStream] Disconnected');
  }

  /// 获取连接状态
  bool get isConnected => _isConnected;

  /// 关闭流控制器
  void dispose() {
    stop();
    _notificationController?.close();
    _notificationController = null;
  }
}
