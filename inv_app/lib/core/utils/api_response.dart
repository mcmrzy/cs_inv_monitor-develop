class ApiBusinessException implements Exception {
  final int code;
  final String message;

  const ApiBusinessException(this.code, this.message);

  @override
  String toString() => message;
}

/// Unwraps the API envelope and rejects business failures or malformed data.
///
/// Direct Dio consumers must not turn a missing/wrong `data` field into an
/// empty collection, because that makes server failures indistinguishable from
/// legitimate empty business data.
T unwrapApiResponse<T>(
  dynamic body, {
  required bool Function(dynamic data) validate,
  required String expected,
}) {
  if (body is! Map) {
    throw const FormatException('Response envelope must be an object');
  }

  final rawCode = body['code'];
  final code = rawCode is num ? rawCode.toInt() : null;
  if (code == null) {
    throw const FormatException('Response envelope is missing a numeric code');
  }
  if (code != 0) {
    final rawMessage = body['message'];
    throw ApiBusinessException(
      code,
      rawMessage is String && rawMessage.isNotEmpty
          ? rawMessage
          : 'Request failed (code $code)',
    );
  }
  if (!body.containsKey('data') || !validate(body['data'])) {
    throw FormatException('Response data must be $expected');
  }

  return body['data'] as T;
}
