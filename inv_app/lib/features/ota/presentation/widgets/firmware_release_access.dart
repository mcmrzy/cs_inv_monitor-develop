import 'dart:async';

import 'package:flutter/material.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/network_status_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// Firmware catalogue reads use the cloud even when the device is on BLE.
mixin FirmwareReleaseAccess<T extends StatefulWidget> on State<T> {
  final _network = getIt.isRegistered<NetworkStatusService>()
      ? getIt<NetworkStatusService>()
      : null;
  final _mode = getIt.isRegistered<ConnectionModeService>()
      ? getIt<ConnectionModeService>()
      : null;
  StreamSubscription<bool>? _networkSubscription;
  StreamSubscription<ConnectionMode>? _modeSubscription;
  bool? _canBrowse;
  int _accessCheck = 0;

  bool get firmwareReleaseAccessChecked => _canBrowse != null;
  bool get canBrowseFirmwareReleases =>
      _canBrowse == true &&
      _network?.isOffline != true &&
      _mode?.isGuestLocalMode != true;

  void onFirmwareReleasesAvailable();

  @override
  void initState() {
    super.initState();
    _networkSubscription = _network?.statusStream.listen(
      (_) => unawaited(_checkFirmwareReleaseAccess()),
    );
    _modeSubscription = _mode?.modeStream.listen(
      (_) => unawaited(_checkFirmwareReleaseAccess()),
    );
    unawaited(_checkFirmwareReleaseAccess());
  }

  Future<void> _checkFirmwareReleaseAccess() async {
    final check = ++_accessCheck;
    final storage = getIt.isRegistered<StorageService>()
        ? getIt<StorageService>()
        : null;
    var allowed = false;
    try {
      allowed = _network?.isOffline != true &&
          _mode?.isGuestLocalMode != true &&
          (storage == null || !await storage.getIsOfflineMode());
    } catch (_) {
      // The cloud interceptor also blocks requests when this setting fails.
    }
    if (!mounted || check != _accessCheck || _canBrowse == allowed) return;
    setState(() => _canBrowse = allowed);
    if (allowed) onFirmwareReleasesAvailable();
  }

  @override
  void dispose() {
    _networkSubscription?.cancel();
    _modeSubscription?.cancel();
    super.dispose();
  }
}

class FirmwareDownloadFirstNotice extends StatelessWidget {
  const FirmwareDownloadFirstNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: AppColor.surfaceHover(context),
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Icon(Icons.download_outlined, color: AppColor.primary(context)),
        title: Text(l10n.str('firmware_download_first')),
        subtitle: Text(l10n.str('firmware_download_first_hint')),
      ),
    );
  }
}
