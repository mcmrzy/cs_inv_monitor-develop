import 'package:dio/dio.dart';
import 'package:inv_app/core/errors/exceptions.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:dartz/dartz.dart';

class ApiService {
  final Dio _dio;

  ApiService(this._dio);

  Future<Either<Failure, T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    try {
      final response = await _dio.get(path, queryParameters: queryParameters);
      return _handleResponse(response, fromJson);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    try {
      final response = await _dio.post(path, data: data, queryParameters: queryParameters);
      return _handleResponse(response, fromJson);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    try {
      final response = await _dio.put(path, data: data, queryParameters: queryParameters);
      return _handleResponse(response, fromJson);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    try {
      final response = await _dio.delete(path, data: data, queryParameters: queryParameters);
      return _handleResponse(response, fromJson);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Either<Failure, T> _handleResponse<T>(
    Response response,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = response.data;
      if (data is Map<String, dynamic>) {
        if (data['code'] == 0) {
          return Right(fromJson(data['data'] ?? {}));
        } else {
          final code = data['code'];
          final msg = data['message'] ?? 'Unknown error';
          // 将错误码和消息一起传递，方便 translateError 按 code 查找
          return Left(ServerFailure(code != null ? '[$code] $msg' : msg));
        }
      }
      return Left(ServerFailure('Invalid response format'));
    }
    return Left(ServerFailure('HTTP ${response.statusCode}'));
  }

  Failure _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure('Connection timeout');
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        if (statusCode == 401) {
          return UnauthorizedFailure('Unauthorized');
        } else if (statusCode == 403) {
          return ForbiddenFailure('Forbidden');
        } else if (statusCode == 404) {
          return NotFoundFailure('Not found');
        }
        return ServerFailure('Server error: $statusCode');
      case DioExceptionType.cancel:
        return NetworkFailure('Request cancelled');
      case DioExceptionType.connectionError:
        return NetworkFailure('No internet connection');
      default:
        return NetworkFailure('Network error');
    }
  }
}

class ApiServiceImpl extends ApiService {
  ApiServiceImpl(super.dio);
}
