import 'dart:io';
import 'package:dio/dio.dart';
import 'package:inv_app/core/network/api_client.dart';

class StationImageUploadService {
  final ApiClient _apiClient;

  StationImageUploadService(this._apiClient);

  /// 上传电站图片
  /// 返回图片URL
  Future<String> uploadStationImage(File imageFile) async {
    try {
      // 验证文件类型
      final extension = imageFile.path.split('.').last.toLowerCase();
      if (!['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension)) {
        throw Exception('只支持 JPEG、PNG、GIF、WebP 格式的图片');
      }

      // 安全上限检查（image_picker已压缩，此处仅为安全网）
      final fileSize = await imageFile.length();
      if (fileSize > 5 * 1024 * 1024) {
        throw Exception('图片大小不能超过5MB');
      }

      // 创建FormData
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          imageFile.path,
          filename: 'station_${DateTime.now().millisecondsSinceEpoch}.$extension',
        ),
      });

      // 上传文件
      final response = await _apiClient.post(
        '/upload/station-image',
        data: formData,
      );

      if (response.statusCode == 200 && response.data['code'] == 0) {
        return response.data['data']['url'];
      } else {
        throw Exception(response.data['message'] ?? '上传失败');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('请先登录');
      } else if (e.response?.statusCode == 400) {
        throw Exception(e.response?.data['message'] ?? '文件格式不正确');
      } else {
        throw Exception('网络错误，请稍后重试');
      }
    } catch (e) {
      rethrow;
    }
  }
}
