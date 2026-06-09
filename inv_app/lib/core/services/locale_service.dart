import 'dart:async';
import 'package:flutter/material.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/storage_service.dart';

class LocaleService {
  final StorageService _storageService;
  final StreamController<Locale> _localeController = StreamController<Locale>.broadcast();

  LocaleService(this._storageService);

  Locale get currentLocale {
    final saved = _storageService.getLocaleSync();
    if (saved != null) {
      return _parseLocale(saved);
    }
    return _parseLocale(AppConfig.defaultLocale);
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
        return const Locale('zh', 'CN');
    }
  }

  void dispose() {
    _localeController.close();
  }
}
