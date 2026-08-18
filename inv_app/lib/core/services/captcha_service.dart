import 'package:dio/dio.dart';

/// 滑块验证码挑战（后端 /captcha/generate 返回）
///
/// [bgImage] / [puzzleImage] 为去掉 dataURL 前缀后的纯 base64 PNG 数据，
/// 图片原始尺寸为 320x160，拼图块 60px。
class CaptchaChallenge {
  final String challengeId;
  final String bgImage;
  final String puzzleImage;

  const CaptchaChallenge({
    required this.challengeId,
    required this.bgImage,
    required this.puzzleImage,
  });
}

/// 滑块验证码服务
///
/// 对接后端 /captcha/generate 与 /captcha/verify 接口，
/// 验证通过后返回 verifyToken，调用发验证码接口时通过
/// X-Captcha-Token 请求头携带。
class CaptchaService {
  final Dio _dio;

  CaptchaService(this._dio);

  /// 生成一次滑块验证挑战
  Future<CaptchaChallenge> generate() async {
    final response = await _dio.get('/captcha/generate');
    final data = _requireSuccess(response);
    return CaptchaChallenge(
      challengeId: data['challengeId'] as String,
      bgImage: _stripDataUrl(data['bgUrl'] as String),
      puzzleImage: _stripDataUrl(data['puzzleUrl'] as String),
    );
  }

  /// 校验滑块位置，成功返回 verifyToken（10 分钟有效）
  ///
  /// [x] 为拼图块在 320px 原图坐标系下的横坐标；
  /// [duration] 为用户拖动耗时（毫秒，后端要求 200~120000）。
  Future<String> verify({
    required String challengeId,
    required double x,
    required int duration,
  }) async {
    final response = await _dio.post(
      '/captcha/verify',
      data: {
        'challengeId': challengeId,
        'x': x,
        'duration': duration,
      },
    );
    final data = _requireSuccess(response);
    return data['verifyToken'] as String;
  }

  /// 解析统一响应格式 {code, message, data}，非 0 抛出异常
  Map<String, dynamic> _requireSuccess(Response response) {
    final body = response.data;
    if (response.statusCode == 200 &&
        body is Map &&
        body['code'] == 0 &&
        body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    final message =
        body is Map ? (body['message'] ?? 'captcha error') : 'captcha error';
    throw Exception(message.toString());
  }

  String _stripDataUrl(String value) {
    const prefix = 'data:image/png;base64,';
    if (value.startsWith(prefix)) {
      return value.substring(prefix.length);
    }
    return value;
  }
}
