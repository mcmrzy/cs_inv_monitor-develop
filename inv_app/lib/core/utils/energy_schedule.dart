bool isEnergySchedulePayload(dynamic value) =>
    value is Map<String, dynamic> &&
    value['periods'] is List &&
    (value['periods'] as List)
        .every((period) => period is Map<String, dynamic>);

List<Map<String, dynamic>> normalizeSchedulePeriods(dynamic periods) {
  if (periods is! List ||
      !periods.every((period) => period is Map<String, dynamic>)) {
    throw const FormatException('schedule periods must be a list of objects');
  }
  return periods
      .cast<Map<String, dynamic>>()
      .map(Map<String, dynamic>.from)
      .toList();
}

int _findPeriodIndex(
  List<Map<String, dynamic>> periods,
  Map<String, dynamic> target,
) {
  final targetID = target['id'];
  return periods.indexWhere((period) {
    if (identical(period, target)) return true;
    if (targetID != null && period['id'] == targetID) return true;
    return period['start_time'] == target['start_time'] &&
        period['end_time'] == target['end_time'] &&
        period['mode'] == target['mode'];
  });
}

List<Map<String, dynamic>> replaceSchedulePeriod(
  List<Map<String, dynamic>> periods,
  Map<String, dynamic> target,
  Map<String, dynamic> replacement,
) {
  final result = periods.map(Map<String, dynamic>.from).toList();
  final index = _findPeriodIndex(periods, target);
  if (index < 0) {
    throw const FormatException('schedule period to edit was not found');
  }
  result[index] = Map<String, dynamic>.from(replacement);
  return result;
}

List<Map<String, dynamic>> removeSchedulePeriod(
  List<Map<String, dynamic>> periods,
  Map<String, dynamic> target,
) {
  final result = periods.map(Map<String, dynamic>.from).toList();
  final index = _findPeriodIndex(periods, target);
  if (index < 0) {
    throw const FormatException('schedule period to delete was not found');
  }
  result.removeAt(index);
  return result;
}
