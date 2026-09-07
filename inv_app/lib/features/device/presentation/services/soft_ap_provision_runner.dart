import 'package:inv_app/core/services/provision_service.dart';

typedef SoftApConfigure = Future<ProvisionResult> Function(
  String ssid,
  String password,
);
typedef SoftApCheckStatus = Future<ProvisionResult> Function();
typedef SoftApEnsureWifiRoute = Future<void> Function();
typedef SoftApDelay = Future<void> Function(Duration duration);

Future<void> _defaultSoftApDelay(Duration duration) {
  return Future<void>.delayed(duration);
}

enum SoftApProvisionOutcomeType {
  connected,
  timedOut,
  failed,
  cancelled,
}

class SoftApProvisionOutcome {
  final SoftApProvisionOutcomeType type;
  final String? message;
  final String? ssid;
  final String? ip;

  const SoftApProvisionOutcome._(
    this.type, {
    this.message,
    this.ssid,
    this.ip,
  });

  const SoftApProvisionOutcome.connected({String? ssid, String? ip})
      : this._(
          SoftApProvisionOutcomeType.connected,
          ssid: ssid,
          ip: ip,
        );

  const SoftApProvisionOutcome.timedOut()
      : this._(SoftApProvisionOutcomeType.timedOut);

  const SoftApProvisionOutcome.failed(String message)
      : this._(SoftApProvisionOutcomeType.failed, message: message);

  const SoftApProvisionOutcome.cancelled()
      : this._(SoftApProvisionOutcomeType.cancelled);
}

/// Runs the SoftAP configure-and-poll protocol without owning widget state.
///
/// UI lifecycle is represented by [isActive]. This keeps plugin/network
/// responses from an obsolete page operation from advancing the current flow.
class SoftApProvisionRunner {
  final SoftApConfigure configure;
  final SoftApCheckStatus checkStatus;
  final SoftApEnsureWifiRoute ensureWifiRoute;
  final SoftApDelay delay;
  final int maxPollAttempts;
  final Duration initialPollDelay;
  final Duration pollInterval;

  SoftApProvisionRunner({
    required this.configure,
    required this.checkStatus,
    required this.ensureWifiRoute,
    SoftApDelay? delay,
    this.maxPollAttempts = 15,
    this.initialPollDelay = const Duration(seconds: 2),
    this.pollInterval = const Duration(seconds: 2),
  }) : delay = delay ?? _defaultSoftApDelay;

  Future<SoftApProvisionOutcome> run({
    required String ssid,
    required String password,
    required bool Function() isActive,
    required void Function() onConfigured,
    required void Function(int attempt) onWaiting,
  }) async {
    try {
      if (!isActive()) return const SoftApProvisionOutcome.cancelled();
      await ensureWifiRoute();
      if (!isActive()) return const SoftApProvisionOutcome.cancelled();

      final configureResult = await configure(ssid, password);
      if (!isActive()) return const SoftApProvisionOutcome.cancelled();
      if (!configureResult.success) {
        return SoftApProvisionOutcome.failed(configureResult.message);
      }

      onConfigured();
      await delay(initialPollDelay);
      if (!isActive()) return const SoftApProvisionOutcome.cancelled();

      for (var attempt = 1; attempt <= maxPollAttempts; attempt++) {
        if (!isActive()) return const SoftApProvisionOutcome.cancelled();
        await ensureWifiRoute();
        if (!isActive()) return const SoftApProvisionOutcome.cancelled();

        final status = await checkStatus();
        if (!isActive()) return const SoftApProvisionOutcome.cancelled();
        if (status.success) {
          return SoftApProvisionOutcome.connected(
            ssid: status.ssid,
            ip: status.ip,
          );
        }

        onWaiting(attempt);
        if (attempt == maxPollAttempts) {
          return const SoftApProvisionOutcome.timedOut();
        }
        await delay(pollInterval);
        if (!isActive()) return const SoftApProvisionOutcome.cancelled();
      }
      return const SoftApProvisionOutcome.timedOut();
    } catch (error) {
      if (!isActive()) return const SoftApProvisionOutcome.cancelled();
      return SoftApProvisionOutcome.failed(error.toString());
    }
  }
}
