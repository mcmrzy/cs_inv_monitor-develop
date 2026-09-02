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
