/// Parses an optional route parameter that must be a positive integer.
///
/// Missing, empty, non-numeric, zero, and negative values are treated as
/// invalid and return `null`.
int? parsePositiveRouteInt(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }

  final parsed = int.tryParse(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

/// Parses a route parameter that must be zero or a positive integer.
///
/// Invalid values preserve the caller's existing fallback semantics.
int parseNonNegativeRouteInt(String? value, {int fallback = 0}) {
  final parsed = int.tryParse(value ?? '');
  return parsed != null && parsed >= 0 ? parsed : fallback;
}

/// Builds the user-facing message for an invalid required route parameter.
String invalidPositiveRouteParameterMessage(String parameterName) {
  return 'Invalid route parameter "$parameterName": '
      'expected a positive integer.';
}
