import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/ota/presentation/models/local_ota_presentation.dart';

void main() {
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
