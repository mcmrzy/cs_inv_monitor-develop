/// Prevents one QR payload from starting multiple bind flows at the same time.
class QrScanGuard {
  String? _lastPayload;
  bool _locked = false;

  /// Acquires the guard for a new payload.
  ///
  /// A payload remains rejected while the current bind route is open. The
  /// caller must release the guard after returning from that route.
  bool tryAcquire(String payload) {
    if (_locked || payload == _lastPayload) return false;
    _locked = true;
    _lastPayload = payload;
    return true;
  }

  /// Releases the current flow. Reset the payload when a new scan should be
  /// allowed to bind the same device again.
  void release({bool resetPayload = false}) {
    _locked = false;
    if (resetPayload) _lastPayload = null;
  }
}
