import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/ota/presentation/models/local_ota_presentation.dart';

void main() {
  group('local OTA device model compatibility', () {
    test('accepts the same normalized firmware and connected-device model', () {
      expect(
        checkLocalOtaDeviceCompatibility(
          firmwareModel: ' cs-l10-6k2 ',
          deviceInfo: const {'model': 'CS-L10-6K2'},
        ),
        LocalOtaDeviceCompatibility.compatible,
      );
    });

    test('reads model from nested device info payload', () {
      expect(
        checkLocalOtaDeviceCompatibility(
          firmwareModel: 'CS-L10-6K2',
          deviceInfo: const {
            'device': {'device_model': 'cs-l10-6k2'},
          },
        ),
        LocalOtaDeviceCompatibility.compatible,
      );
    });

    test('fails closed when firmware model is missing', () {
      expect(
        checkLocalOtaDeviceCompatibility(
          firmwareModel: null,
          deviceInfo: const {'model': 'CS-L10-6K2'},
        ),
        LocalOtaDeviceCompatibility.missingFirmwareModel,
      );
    });

    test('fails closed when connected device model is missing', () {
      expect(
        checkLocalOtaDeviceCompatibility(
          firmwareModel: 'CS-L10-6K2',
          deviceInfo: const {'sn': 'TEST001'},
        ),
        LocalOtaDeviceCompatibility.missingDeviceModel,
      );
    });

    test('treats device placeholder model as missing', () {
      expect(
        checkLocalOtaDeviceCompatibility(
          firmwareModel: 'CS-L10-6K2',
          deviceInfo: const {'model': 'unknown'},
        ),
        LocalOtaDeviceCompatibility.missingDeviceModel,
      );
    });

    test('rejects a firmware built for another device model', () {
      expect(
        checkLocalOtaDeviceCompatibility(
          firmwareModel: 'CS-L10-6K2',
          deviceInfo: const {'model_name': 'CS-L10-8K'},
        ),
        LocalOtaDeviceCompatibility.mismatch,
      );
    });
  });

  group('normalizeLocalOtaProgress', () {
    test('keeps valid progress unchanged', () {
      expect(normalizeLocalOtaProgress(0), 0);
      expect(normalizeLocalOtaProgress(0.42), 0.42);
      expect(normalizeLocalOtaProgress(1), 1);
    });

    test('uses zero and reports progress outside the indicator range', () {
      final invalidValues = <double>[];
      expect(normalizeLocalOtaProgress(-0.1), 0);
      expect(
        normalizeLocalOtaProgress(1.2, onInvalid: invalidValues.add),
        0,
      );
      expect(invalidValues, <double>[1.2]);
    });

    test('uses zero for non-finite progress', () {
      expect(normalizeLocalOtaProgress(double.nan), 0);
      expect(normalizeLocalOtaProgress(double.infinity), 0);
      expect(normalizeLocalOtaProgress(double.negativeInfinity), 0);
    });
  });

  group('localOtaStatusKind', () {
    test('maps device aliases to the same presentation status', () {
      expect(localOtaStatusKind('idle'), LocalOtaStatusKind.idle);
      expect(localOtaStatusKind('downloading'), LocalOtaStatusKind.downloading);
      expect(localOtaStatusKind('uploading'), LocalOtaStatusKind.uploading);
      expect(localOtaStatusKind('receiving'), LocalOtaStatusKind.uploading);
      expect(localOtaStatusKind('accepted'), LocalOtaStatusKind.uploading);
      expect(localOtaStatusKind('done'), LocalOtaStatusKind.done);
      expect(localOtaStatusKind('succeeded'), LocalOtaStatusKind.done);
      expect(localOtaStatusKind('error'), LocalOtaStatusKind.failure);
      expect(localOtaStatusKind('failed'), LocalOtaStatusKind.failure);
      expect(localOtaStatusKind('rolled_back'), LocalOtaStatusKind.failure);
      expect(localOtaStatusKind('cancelled'), LocalOtaStatusKind.failure);
      expect(localOtaStatusKind('installing'), LocalOtaStatusKind.installing);
      expect(localOtaStatusKind('rebooting'), LocalOtaStatusKind.installing);
    });

    test('does not hide non-canonical wire values', () {
      expect(localOtaStatusKind('VERIFYING'), LocalOtaStatusKind.unknown);
      expect(localOtaStatusKind(' verifying '), LocalOtaStatusKind.unknown);
    });

    test('preserves unknown status as unknown', () {
      expect(
        localOtaStatusKind('custom_device_state'),
        LocalOtaStatusKind.unknown,
      );
    });
  });
}
