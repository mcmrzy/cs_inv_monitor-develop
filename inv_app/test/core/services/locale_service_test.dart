import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/core/services/locale_service.dart';

import '../../helpers/mock_providers.dart';

void main() {
  late LocaleService localeService;
  late MockStorageService mockStorageService;

  setUp(() {
    mockStorageService = MockStorageService();
    localeService = LocaleService(
      mockStorageService,
      systemLocale: () => const Locale('zh', 'CN'),
    );
  });

  tearDown(() {
    localeService.dispose();
  });

  // ---------------------------------------------------------------------------
  // currentLocale
  // ---------------------------------------------------------------------------
  group('currentLocale', () {
    test('returns saved locale when available', () {
      when(() => mockStorageService.getLocaleSync()).thenReturn('en');

      final locale = localeService.currentLocale;
      expect(locale, const Locale('en', 'US'));
    });

    test('returns zh locale when saved locale is zh', () {
      when(() => mockStorageService.getLocaleSync()).thenReturn('zh');

      final locale = localeService.currentLocale;
      expect(locale, const Locale('zh', 'CN'));
    });

    test('returns default locale (zh) when no saved locale', () {
      when(() => mockStorageService.getLocaleSync()).thenReturn(null);

      final locale = localeService.currentLocale;
      expect(locale, const Locale('zh', 'CN'));
    });

    test('uses a supported system locale when no locale was saved', () {
      when(() => mockStorageService.getLocaleSync()).thenReturn(null);
      final service = LocaleService(
        mockStorageService,
        systemLocale: () => const Locale('en', 'GB'),
      );

      expect(service.currentLocale, const Locale('en', 'US'));
      service.dispose();
    });

    test('returns default locale (zh) for unknown locale code', () {
      when(() => mockStorageService.getLocaleSync()).thenReturn('fr');

      final locale = localeService.currentLocale;
      expect(locale, const Locale('zh', 'CN'));
    });
  });

  // ---------------------------------------------------------------------------
  // switchLocale
  // ---------------------------------------------------------------------------
  group('switchLocale', () {
    test('saves locale and emits to stream', () async {
      when(() => mockStorageService.saveLocale(any())).thenAnswer((_) async {});

      final completer = Completer<Locale>();
      final sub = localeService.localeStream.listen((locale) {
        if (!completer.isCompleted) completer.complete(locale);
      });

      await localeService.switchLocale(const Locale('en', 'US'));

      final emitted = await completer.future.timeout(
        const Duration(seconds: 1),
      );
      expect(emitted, const Locale('en', 'US'));
      verify(() => mockStorageService.saveLocale('en')).called(1);

      await sub.cancel();
    });

    test('saves zh locale correctly', () async {
      when(() => mockStorageService.saveLocale(any())).thenAnswer((_) async {});

      final completer = Completer<Locale>();
      final sub = localeService.localeStream.listen((locale) {
        if (!completer.isCompleted) completer.complete(locale);
      });

      await localeService.switchLocale(const Locale('zh', 'CN'));

      final emitted = await completer.future.timeout(
        const Duration(seconds: 1),
      );
      expect(emitted, const Locale('zh', 'CN'));
      verify(() => mockStorageService.saveLocale('zh')).called(1);

      await sub.cancel();
    });
  });

  // ---------------------------------------------------------------------------
  // localeStream
  // ---------------------------------------------------------------------------
  group('localeStream', () {
    test('is a broadcast stream', () {
      expect(localeService.localeStream.isBroadcast, true);
    });
  });
}
