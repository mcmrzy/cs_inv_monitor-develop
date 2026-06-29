import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class StorageService {
  Future<String?> getToken();
  Future<void> saveToken(String token);
  Future<void> deleteToken();
  
  Future<String?> getRefreshToken();
  Future<void> saveRefreshToken(String token);
  Future<void> deleteRefreshToken();
  
  Future<int?> getUserId();
  Future<void> saveUserId(int userId);
  Future<void> deleteUserId();
  
  Future<String?> getUserPhone();
  Future<void> saveUserPhone(String phone);
  Future<void> deleteUserPhone();
  
  Future<int?> getUserRole();
  Future<void> saveUserRole(int role);
  Future<void> deleteUserRole();
  
  Future<bool> getRememberPassword();
  Future<void> saveRememberPassword(bool value);
  
  Future<String?> getSavedPhone();
  Future<void> saveSavedPhone(String phone);
  
  Future<String?> getSavedPassword();
  Future<void> saveSavedPassword(String password);
  
  Future<bool> getIsDarkMode();
  Future<void> saveIsDarkMode(bool value);
  
  Future<String?> getServerUrl();
  Future<void> saveServerUrl(String url);
  
  Future<bool> getIsLocalMode();
  Future<void> saveIsLocalMode(bool value);
  
  Future<String?> getLocale();
  Future<void> saveLocale(String locale);
  String? getLocaleSync();

  Future<String?> getTimezone();
  Future<void> saveTimezone(String timezone);

  Future<String?> getStationCache();
  Future<void> saveStationCache(String json);
  Future<void> deleteStationCache();

  Future<bool> getNotifyPush();
  Future<void> saveNotifyPush(bool value);
  Future<bool> getNotifyAlert();
  Future<void> saveNotifyAlert(bool value);
  Future<bool> getNotifyOffline();
  Future<void> saveNotifyOffline(bool value);
  Future<bool> getNotifySystem();
  Future<void> saveNotifySystem(bool value);
  Future<String?> getNotifyDndStart();
  Future<void> saveNotifyDndStart(String value);
  Future<String?> getNotifyDndEnd();
  Future<void> saveNotifyDndEnd(String value);
  Future<bool> getNotifyDndEnabled();
  Future<void> saveNotifyDndEnabled(bool value);

  Future<void> clearAll();

  Future<String?> getString(String key);
  Future<void> saveString(String key, String value);
}

class StorageServiceImpl implements StorageService {
  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _sharedPreferences;

  StorageServiceImpl(this._secureStorage, this._sharedPreferences);

  static const String _keyToken = 'auth_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyUserId = 'user_id';
  static const String _keyUserPhone = 'user_phone';
  static const String _keyUserRole = 'user_role';
  static const String _keyRememberPassword = 'remember_password';
  static const String _keySavedPhone = 'saved_phone';
  static const String _keySavedPassword = 'saved_password';
  static const String _keyIsDarkMode = 'is_dark_mode';
  static const String _keyServerUrl = 'server_url';
  static const String _keyIsLocalMode = 'is_local_mode';
  static const String _keyLocale = 'app_locale';
  static const String _keyTimezone = 'user_timezone';
  static const String _keyStationCache = 'station_cache';
  static const String _keyNotifyPush = 'notify_push';
  static const String _keyNotifyAlert = 'notify_alert';
  static const String _keyNotifyOffline = 'notify_offline';
  static const String _keyNotifySystem = 'notify_system';
  static const String _keyNotifyDndStart = 'notify_dnd_start';
  static const String _keyNotifyDndEnd = 'notify_dnd_end';
  static const String _keyNotifyDndEnabled = 'notify_dnd_enabled';

  @override
  Future<String?> getToken() async {
    return await _secureStorage.read(key: _keyToken);
  }

  @override
  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _keyToken, value: token);
  }

  @override
  Future<void> deleteToken() async {
    await _secureStorage.delete(key: _keyToken);
  }

  @override
  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: _keyRefreshToken);
  }

  @override
  Future<void> saveRefreshToken(String token) async {
    await _secureStorage.write(key: _keyRefreshToken, value: token);
  }

  @override
  Future<void> deleteRefreshToken() async {
    await _secureStorage.delete(key: _keyRefreshToken);
  }

  @override
  Future<int?> getUserId() async {
    final value = _sharedPreferences.getInt(_keyUserId);
    return value;
  }

  @override
  Future<void> saveUserId(int userId) async {
    await _sharedPreferences.setInt(_keyUserId, userId);
  }

  @override
  Future<void> deleteUserId() async {
    await _sharedPreferences.remove(_keyUserId);
  }

  @override
  Future<String?> getUserPhone() async {
    return _sharedPreferences.getString(_keyUserPhone);
  }

  @override
  Future<void> saveUserPhone(String phone) async {
    await _sharedPreferences.setString(_keyUserPhone, phone);
  }

  @override
  Future<void> deleteUserPhone() async {
    await _sharedPreferences.remove(_keyUserPhone);
  }

  @override
  Future<int?> getUserRole() async {
    return _sharedPreferences.getInt(_keyUserRole);
  }

  @override
  Future<void> saveUserRole(int role) async {
    await _sharedPreferences.setInt(_keyUserRole, role);
  }

  @override
  Future<void> deleteUserRole() async {
    await _sharedPreferences.remove(_keyUserRole);
  }

  @override
  Future<bool> getRememberPassword() async {
    return _sharedPreferences.getBool(_keyRememberPassword) ?? false;
  }

  @override
  Future<void> saveRememberPassword(bool value) async {
    await _sharedPreferences.setBool(_keyRememberPassword, value);
  }

  @override
  Future<String?> getSavedPhone() async {
    return _sharedPreferences.getString(_keySavedPhone);
  }

  @override
  Future<void> saveSavedPhone(String phone) async {
    await _sharedPreferences.setString(_keySavedPhone, phone);
  }

  @override
  Future<String?> getSavedPassword() async {
    return await _secureStorage.read(key: _keySavedPassword);
  }

  @override
  Future<void> saveSavedPassword(String password) async {
    await _secureStorage.write(key: _keySavedPassword, value: password);
  }

  @override
  Future<bool> getIsDarkMode() async {
    return _sharedPreferences.getBool(_keyIsDarkMode) ?? false;
  }

  @override
  Future<void> saveIsDarkMode(bool value) async {
    await _sharedPreferences.setBool(_keyIsDarkMode, value);
  }

  @override
  Future<String?> getServerUrl() async {
    return _sharedPreferences.getString(_keyServerUrl);
  }

  @override
  Future<void> saveServerUrl(String url) async {
    await _sharedPreferences.setString(_keyServerUrl, url);
  }

  @override
  Future<bool> getIsLocalMode() async {
    return _sharedPreferences.getBool(_keyIsLocalMode) ?? false;
  }

  @override
  Future<void> saveIsLocalMode(bool value) async {
    await _sharedPreferences.setBool(_keyIsLocalMode, value);
  }

  @override
  Future<String?> getLocale() async {
    return _sharedPreferences.getString(_keyLocale);
  }

  @override
  Future<void> saveLocale(String locale) async {
    await _sharedPreferences.setString(_keyLocale, locale);
  }

  @override
  String? getLocaleSync() {
    return _sharedPreferences.getString(_keyLocale);
  }

  @override
  Future<String?> getTimezone() async {
    return _sharedPreferences.getString(_keyTimezone);
  }

  @override
  Future<void> saveTimezone(String timezone) async {
    await _sharedPreferences.setString(_keyTimezone, timezone);
  }

  @override
  Future<String?> getStationCache() async {
    return _sharedPreferences.getString(_keyStationCache);
  }

  @override
  Future<void> saveStationCache(String json) async {
    await _sharedPreferences.setString(_keyStationCache, json);
  }

  @override
  Future<void> deleteStationCache() async {
    await _sharedPreferences.remove(_keyStationCache);
  }

  @override
  Future<bool> getNotifyPush() async {
    return _sharedPreferences.getBool(_keyNotifyPush) ?? true;
  }

  @override
  Future<void> saveNotifyPush(bool value) async {
    await _sharedPreferences.setBool(_keyNotifyPush, value);
  }

  @override
  Future<bool> getNotifyAlert() async {
    return _sharedPreferences.getBool(_keyNotifyAlert) ?? true;
  }

  @override
  Future<void> saveNotifyAlert(bool value) async {
    await _sharedPreferences.setBool(_keyNotifyAlert, value);
  }

  @override
  Future<bool> getNotifyOffline() async {
    return _sharedPreferences.getBool(_keyNotifyOffline) ?? true;
  }

  @override
  Future<void> saveNotifyOffline(bool value) async {
    await _sharedPreferences.setBool(_keyNotifyOffline, value);
  }

  @override
  Future<bool> getNotifySystem() async {
    return _sharedPreferences.getBool(_keyNotifySystem) ?? true;
  }

  @override
  Future<void> saveNotifySystem(bool value) async {
    await _sharedPreferences.setBool(_keyNotifySystem, value);
  }

  @override
  Future<String?> getNotifyDndStart() async {
    return _sharedPreferences.getString(_keyNotifyDndStart);
  }

  @override
  Future<void> saveNotifyDndStart(String value) async {
    await _sharedPreferences.setString(_keyNotifyDndStart, value);
  }

  @override
  Future<String?> getNotifyDndEnd() async {
    return _sharedPreferences.getString(_keyNotifyDndEnd);
  }

  @override
  Future<void> saveNotifyDndEnd(String value) async {
    await _sharedPreferences.setString(_keyNotifyDndEnd, value);
  }

  @override
  Future<bool> getNotifyDndEnabled() async {
    return _sharedPreferences.getBool(_keyNotifyDndEnabled) ?? false;
  }

  @override
  Future<void> saveNotifyDndEnabled(bool value) async {
    await _sharedPreferences.setBool(_keyNotifyDndEnabled, value);
  }

  @override
  Future<void> clearAll() async {
    await _secureStorage.deleteAll();
    await _sharedPreferences.clear();
  }

  @override
  Future<String?> getString(String key) async {
    return _sharedPreferences.getString(key);
  }

  @override
  Future<void> saveString(String key, String value) async {
    await _sharedPreferences.setString(key, value);
  }
}
