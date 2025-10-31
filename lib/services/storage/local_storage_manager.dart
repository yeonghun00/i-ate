import 'package:shared_preferences/shared_preferences.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';

class LocalStorageManager {
  static final LocalStorageManager _instance = LocalStorageManager._internal();
  factory LocalStorageManager() => _instance;
  LocalStorageManager._internal();

  Future<SharedPreferences?> _getInstance({int maxRetries = 3}) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await SharedPreferences.getInstance();
      } catch (e) {
        AppLogger.error('SharedPreferences attempt ${attempt + 1} failed: $e', tag: 'LocalStorageManager');
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
    }
    AppLogger.warning('SharedPreferences failed completely', tag: 'LocalStorageManager');
    return null;
  }

  Future<String?> getString(String key) async {
    final prefs = await _getInstance();
    return prefs?.getString(key);
  }

  Future<bool?> getBool(String key) async {
    final prefs = await _getInstance();
    return prefs?.getBool(key);
  }

  Future<int?> getInt(String key) async {
    final prefs = await _getInstance();
    return prefs?.getInt(key);
  }

  Future<bool> setString(String key, String value) async {
    final prefs = await _getInstance();
    if (prefs == null) return false;

    try {
      await prefs.setString(key, value);
      return true;
    } catch (e) {
      AppLogger.error('Failed to set string $key: $e', tag: 'LocalStorageManager');
      return false;
    }
  }

  Future<bool> setBool(String key, bool value) async {
    final prefs = await _getInstance();
    if (prefs == null) return false;

    try {
      await prefs.setBool(key, value);
      return true;
    } catch (e) {
      AppLogger.error('Failed to set bool $key: $e', tag: 'LocalStorageManager');
      return false;
    }
  }

  Future<bool> setInt(String key, int value) async {
    final prefs = await _getInstance();
    if (prefs == null) return false;

    try {
      await prefs.setInt(key, value);
      return true;
    } catch (e) {
      AppLogger.error('Failed to set int $key: $e', tag: 'LocalStorageManager');
      return false;
    }
  }

  Future<bool> remove(String key) async {
    final prefs = await _getInstance();
    if (prefs == null) return false;
    
    try {
      await prefs.remove(key);
      return true;
    } catch (e) {
      AppLogger.error('Failed to remove $key: $e', tag: 'LocalStorageManager');
      return false;
    }
  }

  Future<bool> clear() async {
    final prefs = await _getInstance();
    if (prefs == null) return false;
    
    try {
      await prefs.clear();
      return true;
    } catch (e) {
      AppLogger.error('Failed to clear preferences: $e', tag: 'LocalStorageManager');
      return false;
    }
  }
}