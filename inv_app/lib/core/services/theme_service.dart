import 'dart:async';

import 'package:flutter/material.dart';
import 'package:inv_app/core/services/storage_service.dart';

/// 主题模式三态服务（系统 / 浅色 / 深色，默认跟随系统）。
/// 与 [LocaleService] 同构：读 StorageService 持久化值 + 广播流通知 MaterialApp。
class ThemeService {
  final StorageService _storageService;
  final StreamController<ThemeMode> _themeController =
      StreamController<ThemeMode>.broadcast();

  ThemeService(this._storageService);

  /// 当前生效的 Flutter 主题模式（未显式设置时跟随系统）
  ThemeMode get currentThemeMode {
    return _toThemeMode(_storageService.getThemeModeSync());
  }

  /// 已保存的主题模式字符串（'system'/'light'/'dark'，未设置返回 'system'）
  String get savedThemeMode {
    return _storageService.getThemeModeSync() ?? 'system';
  }

  Stream<ThemeMode> get themeStream => _themeController.stream;

  Future<void> switchThemeMode(String mode) async {
    await _storageService.saveThemeMode(mode);
    _themeController.add(_toThemeMode(mode));
  }

  ThemeMode _toThemeMode(String? mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  void dispose() {
    _themeController.close();
  }
}
