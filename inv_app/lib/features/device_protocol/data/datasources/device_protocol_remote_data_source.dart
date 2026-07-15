import 'package:dio/dio.dart';

abstract class DeviceProtocolRemoteDataSource {
  Future<Response<dynamic>> getAlarmEvents(
    String sn, {
    int page = 1,
    int pageSize = 20,
  });

  Future<Response<dynamic>> getParallelState(String sn);

  Future<Response<dynamic>> getThreePhase(
    String sn, {
    int page = 1,
    int pageSize = 20,
  });
}

class DeviceProtocolRemoteDataSourceImpl
    implements DeviceProtocolRemoteDataSource {
  const DeviceProtocolRemoteDataSourceImpl(this.dio);

  final Dio dio;

  @override
  Future<Response<dynamic>> getAlarmEvents(
    String sn, {
    int page = 1,
    int pageSize = 20,
  }) {
    return dio.get<dynamic>(
      '/devices/$sn/alarm-events',
      queryParameters: {'page': page, 'page_size': pageSize},
    );
  }

  @override
  Future<Response<dynamic>> getParallelState(String sn) {
    return dio.get<dynamic>('/devices/$sn/parallel-state');
  }

  @override
  Future<Response<dynamic>> getThreePhase(
    String sn, {
    int page = 1,
    int pageSize = 20,
  }) {
    return dio.get<dynamic>(
      '/devices/$sn/three-phase',
      queryParameters: {'page': page, 'page_size': pageSize},
    );
  }
}
