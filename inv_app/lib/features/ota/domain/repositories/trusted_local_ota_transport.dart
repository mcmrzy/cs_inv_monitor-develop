import 'package:inv_app/core/services/local_communication_service.dart';

/// Implemented only by transports which verify a signed factory identity,
/// a fresh device challenge and a device-bound install authorization.
/// Advertising a capability or reading INFO does not implement this contract.
abstract interface class TrustedLocalOtaTransport {
  Future<TrustedLocalOtaPreflight> preflightTrustedInstall({
    required String deviceSN,
    required int firmwareId,
    required LocalOtaManifest manifest,
    required List<String> firmwareBoardCodes,
  });
}

/// A preflight receipt from the authenticated updater before uploading bytes.
/// The transport must also enforce these identities immediately before write.
class TrustedLocalOtaPreflight {
  const TrustedLocalOtaPreflight({
    required this.deviceSN,
    required this.target,
    required this.boardCode,
    required this.boardUid,
    required this.identityRevision,
    required this.moduleRevision,
    required this.authorizationId,
    required this.firmwareId,
    required this.sha256,
  });

  final String deviceSN;
  final String target;
  final String boardCode;
  final String boardUid;
  final int identityRevision;
  final int moduleRevision;
  final String authorizationId;
  final int firmwareId;
  final String sha256;

  bool matches({
    required String expectedSN,
    required int expectedFirmwareId,
    required LocalOtaManifest manifest,
    required List<String> firmwareBoardCodes,
  }) =>
      deviceSN == expectedSN &&
      target == manifest.target &&
      firmwareId == expectedFirmwareId &&
      sha256 == manifest.sha256 &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) &&
      firmwareBoardCodes.contains(boardCode) &&
      RegExp(r'^[0-9a-f]{16,64}$').hasMatch(boardUid) &&
      boardUid.length.isEven &&
      identityRevision > 0 &&
      moduleRevision > 0 &&
      authorizationId.isNotEmpty;
}
