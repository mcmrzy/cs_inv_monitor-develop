import 'package:flutter/material.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/presentation/pages/device_firmware_detail_page.dart';

/// Compatibility landing for older `/ota/:sn` links.
///
/// Package/main-version OTA is retired. Old links now enter the same
/// independent module flow as every current customer-facing CTA.
class OTAPage extends StatelessWidget {
  const OTAPage({
    super.key,
    required this.deviceSN,
    this.deviceRepository,
    this.otaRepository,
  });

  final String deviceSN;
  final DeviceRepository? deviceRepository;
  final OtaRepository? otaRepository;

  @override
  Widget build(BuildContext context) => DeviceFirmwareDetailPage(
        deviceSN: deviceSN,
        deviceRepository: deviceRepository,
        otaRepository: otaRepository,
      );
}
