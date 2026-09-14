import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('packaged raster assets contain real image bytes', () {
    final roots = <Directory>[
      Directory('assets'),
      Directory('android/app/src/main/res'),
      Directory('ios/Runner/Assets.xcassets'),
    ];
    final invalidFiles = <String>[];

    for (final root in roots) {
      if (!root.existsSync()) continue;

      for (final entity in root.listSync(recursive: true, followLinks: false)) {
        if (entity is! File || !_isRasterAsset(entity.path)) continue;

        final bytes = entity.readAsBytesSync();
        if (!_hasKnownRasterSignature(bytes)) {
          invalidFiles.add(entity.path);
        }
      }
    }

    expect(
      invalidFiles,
      isEmpty,
      reason: 'Raster assets must be real PNG/JPEG/WebP files, not Git LFS '
          'pointers or other text placeholders.',
    );
  });

  test('primary brand and empty-state assets exist', () {
    const primaryAssets = <String>[
      CsergyAssets.avatarDefault,
      CsergyAssets.emptyStation,
      CsergyAssets.emptyDevice,
      CsergyAssets.emptyAlarm,
      CsergyAssets.emptyRecord,
    ];

    expect(
      primaryAssets.where((path) => !File(path).existsSync()),
      isEmpty,
      reason: 'CsergyAssets must not reference missing packaged files.',
    );
  });

  test('quiet-energy page illustrations are packaged', () async {
    const illustrationAssets = <String>[
      CsergyAssets.onboardingEnergyOverview,
      CsergyAssets.onboardingStatusAlerts,
      CsergyAssets.onboardingLocalService,
      CsergyAssets.networkConnectionFailed,
      CsergyAssets.localUpgradeConnection,
      CsergyAssets.provisioningCompanionBottom,
    ];

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(
      illustrationAssets.where((path) => manifest.getAssetVariants(path) == null),
      isEmpty,
      reason: 'Quiet-energy illustrations must be registered in pubspec.yaml.',
    );

    for (final path in illustrationAssets) {
      final bytes = await rootBundle.load(path);
      expect(bytes.lengthInBytes, greaterThan(1024), reason: path);
      expect(_hasKnownRasterSignature(bytes.buffer.asUint8List()), isTrue,
          reason: path);
    }
  });
}

bool _isRasterAsset(String path) {
  final lowerPath = path.toLowerCase();
  return lowerPath.endsWith('.png') ||
      lowerPath.endsWith('.jpg') ||
      lowerPath.endsWith('.jpeg') ||
      lowerPath.endsWith('.webp');
}

bool _hasKnownRasterSignature(List<int> bytes) {
  if (bytes.length < 12) return false;

  final isPng = bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A;
  final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
  final isWebp = bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50;

  return isPng || isJpeg || isWebp;
}
