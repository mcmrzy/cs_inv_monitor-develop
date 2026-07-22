import 'package:dio/dio.dart';

class NotificationRemoteDataSource {
  final Dio dio;

  NotificationRemoteDataSource(this.dio);

  Future<Response> getList({int page = 1, int pageSize = 50}) async {
    return await dio.get(
      '/notifications',
      queryParameters: {
        'page': page,
        'page_size': pageSize,
      },
    );
  }

  Future<Response> getStats() async {
    return await dio.get('/notifications/stats');
  }

  Future<Response> delete(int id) async {
    return await dio.delete('/notifications/$id');
  }

  Future<Response> clearAll() async {
    return await dio.delete('/notifications/clear');
  }
}
