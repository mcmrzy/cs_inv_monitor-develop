import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/storage_service.dart';

class LocaleService {
  final StorageService _storageService;
  final Locale Function() _systemLocale;
  final StreamController<Locale> _localeController =
      StreamController<Locale>.broadcast();

  LocaleService(
    this._storageService, {
    Locale Function()? systemLocale,
  }) : _systemLocale =
            systemLocale ?? (() => PlatformDispatcher.instance.locale);

  Locale get currentLocale {
    final saved = _storageService.getLocaleSync();
    if (saved != null) {
      return _parseLocale(saved);
    }
    return _parseLocale(_systemLocale().languageCode);
  }

  Stream<Locale> get localeStream => _localeController.stream;

  Future<void> switchLocale(Locale locale) async {
    await _storageService.saveLocale(locale.languageCode);
    _localeController.add(locale);
  }

  Locale _parseLocale(String code) {
    switch (code) {
      case 'zh':
        return const Locale('zh', 'CN');
      case 'en':
        return const Locale('en', 'US');
      default:
        return _parseLocale(AppConfig.defaultLocale);
    }
  }

  void dispose() {
    _localeController.close();
  }
}
