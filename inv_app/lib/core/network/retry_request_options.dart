import 'package:dio/dio.dart';

const String tokenRefreshRetryKey = 'token_refresh_retried';

String? normalizeTokenValue(String? token) {
  final normalized = token?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

bool isTokenRefreshRetry(RequestOptions options) {
  return options.extra[tokenRefreshRetryKey] == true;
}

/// Handles a 401 returned by the one-shot request made after token refresh.
///
/// A second refresh would loop indefinitely. At this point the refreshed
/// session is unusable, so the caller must terminate it and return the 401 to
/// the original request.
bool handleRetriedUnauthorized(
  RequestOptions options, {
  required void Function() onLogoutRequested,
}) {
  if (!isTokenRefreshRetry(options)) return false;
  onLogoutRequested();
  return true;
}

/// Creates a retry request without mutating the failed request.
///
/// Dio's [RequestOptions.copyWith] keeps transport behavior such as response
/// decoding, redirects, validation, cancellation, progress callbacks, and
/// timeouts. Only the access token and the one-shot retry marker are changed.
RequestOptions buildTokenRefreshRetryOptions(
  RequestOptions original, {
  required String accessToken,
}) {
  final normalizedAccessToken = normalizeTokenValue(accessToken);
  if (normalizedAccessToken == null) {
    throw ArgumentError.value(accessToken, 'accessToken', 'must not be blank');
  }

  return original.copyWith(
    data: original.data is FormData
        ? (original.data as FormData).clone()
        : original.data,
    headers: <String, dynamic>{
      ..._deepCopyStringMap(original.headers),
      'Authorization': 'Bearer $normalizedAccessToken',
    },
    extra: <String, dynamic>{
      ..._deepCopyStringMap(original.extra),
      tokenRefreshRetryKey: true,
    },
  );
}

Map<String, dynamic> _deepCopyStringMap(Map<String, dynamic> source) {
  return <String, dynamic>{
    for (final entry in source.entries)
      entry.key: _deepCopyCollection(entry.value),
  };
}

dynamic _deepCopyCollection(dynamic value) {
  if (value is Map<String, dynamic>) {
    return _deepCopyStringMap(value);
  }
  if (value is Map) {
    return <dynamic, dynamic>{
      for (final entry in value.entries)
        entry.key: _deepCopyCollection(entry.value),
    };
  }
  if (value is List) {
    return <dynamic>[
      for (final item in value) _deepCopyCollection(item),
    ];
  }
  if (value is Set) {
    return <dynamic>{
      for (final item in value) _deepCopyCollection(item),
    };
  }
  return value;
}
