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
  
  Future<void> clearAll();
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
  Future<void> clearAll() async {
    await _secureStorage.deleteAll();
    await _sharedPreferences.clear();
  }
}
