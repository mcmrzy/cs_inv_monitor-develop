import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest excludes unused high-risk permissions', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(manifest, isNot(contains('android.permission.SEND_SMS')));
    expect(manifest, isNot(contains('android.permission.SCHEDULE_EXACT_ALARM')));
  });

  test('platform display names use the concise product name', () {
    final androidManifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();

    expect(androidManifest, contains('android:label="辰烁光伏逆变"'));
    expect(iosInfo, contains('<string>辰烁光伏逆变</string>'));
  });

  test('iOS orientation declarations match the portrait-only app policy', () {
    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();

    expect(iosInfo, contains('UIInterfaceOrientationPortrait'));
    expect(iosInfo, contains('UIInterfaceOrientationPortraitUpsideDown'));
    expect(iosInfo, isNot(contains('UIInterfaceOrientationLandscapeLeft')));
    expect(iosInfo, isNot(contains('UIInterfaceOrientationLandscapeRight')));
  });

  test('app does not force-disable the operating system text scale', () {
    final appSource = File('lib/main.dart').readAsStringSync();

    expect(appSource, isNot(contains('TextScaler.linear(1.0)')));
  });
}
