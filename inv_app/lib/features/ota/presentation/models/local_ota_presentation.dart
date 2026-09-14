/// UI-level status groups used by the local OTA progress presentation.
///
/// Device firmware may report multiple wire values for the same user-visible
/// state. Keeping the aliases here avoids duplicating protocol strings in the
/// page while leaving localization in the widget layer.
enum LocalOtaStatusKind {
  idle,
  downloading,
  uploading,
  verifying,
  done,
  failure,
  installing,
  unknown,
}

/// Result of comparing cached firmware metadata with the device reached over
/// the selected local transport. Missing metadata is deliberately distinct
/// from a mismatch so the UI can explain why the upgrade was blocked.
enum LocalOtaDeviceCompatibility {
  compatible,
  missingFirmwareModel,
  missingDeviceModel,
  mismatch,
}

String? _readDeviceModel(Map<String, dynamic> info) {
  String? read(Map<dynamic, dynamic> source) {
    for (final key in const ['model', 'device_model', 'model_name']) {
      final value = source[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  final direct = read(info);
  if (direct != null) return direct;
  final nested = info['device'];
  return nested is Map ? read(nested) : null;
}

String _normalizeDeviceModel(String? value) {
  final normalized = value?.trim().toUpperCase() ?? '';
  if (const {'', 'UNKNOWN', 'N/A', 'NULL', '--', '—'}.contains(normalized)) {
    return '';
  }
  return normalized;
}

/// Fail-closed model validation used immediately before a local OTA upload.
LocalOtaDeviceCompatibility checkLocalOtaDeviceCompatibility({
  required String? firmwareModel,
  required Map<String, dynamic> deviceInfo,
}) {
  final expected = _normalizeDeviceModel(firmwareModel);
  if (expected.isEmpty) {
    return LocalOtaDeviceCompatibility.missingFirmwareModel;
  }
  final actual = _normalizeDeviceModel(_readDeviceModel(deviceInfo));
  if (actual.isEmpty) {
    return LocalOtaDeviceCompatibility.missingDeviceModel;
  }
  return actual == expected
      ? LocalOtaDeviceCompatibility.compatible
      : LocalOtaDeviceCompatibility.mismatch;
}

/// Converts an arbitrary progress value to the range accepted by Flutter's
/// progress indicators.
double normalizeLocalOtaProgress(
  double value, {
  void Function(double invalidValue)? onInvalid,
}) {
  if (value.isFinite && value >= 0 && value <= 1) return value;
  onInvalid?.call(value);
  return 0;
}

/// Groups the raw device status without translating it.
LocalOtaStatusKind localOtaStatusKind(String rawStatus) {
  switch (rawStatus) {
    case 'idle':
      return LocalOtaStatusKind.idle;
    case 'downloading':
      return LocalOtaStatusKind.downloading;
    case 'uploading':
    case 'receiving':
    case 'accepted':
      return LocalOtaStatusKind.uploading;
    case 'verifying':
      return LocalOtaStatusKind.verifying;
    case 'done':
    case 'succeeded':
      return LocalOtaStatusKind.done;
    case 'error':
    case 'failed':
    case 'rolled_back':
    case 'cancelled':
      return LocalOtaStatusKind.failure;
    case 'installing':
    case 'rebooting':
      return LocalOtaStatusKind.installing;
    default:
      return LocalOtaStatusKind.unknown;
  }
}
