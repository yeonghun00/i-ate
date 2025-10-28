import 'package:flutter/services.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';

/// Service for getting battery information from native Android code
class BatteryService {
  static const MethodChannel _channel =
      MethodChannel('com.thousandemfla.thanks_everyday/screen_monitor');

  /// Get current battery information
  /// Returns a map with:
  /// - batteryLevel: int (0-100)
  /// - isCharging: bool
  /// - batteryHealth: String ("GOOD", "OVERHEAT", "DEAD", etc.)
  /// - batteryTemperature: double (in Celsius)
  /// - timestamp: int (milliseconds since epoch)
  static Future<Map<String, dynamic>?> getBatteryInfo() async {
    try {
      final result = await _channel.invokeMethod('getBatteryInfo');

      if (result != null && result is Map) {
        AppLogger.debug(
          'Battery info: ${result["batteryLevel"]}%, charging: ${result["isCharging"]}',
          tag: 'BatteryService',
        );
        return Map<String, dynamic>.from(result);
      }

      AppLogger.warning('Failed to get battery info: null result', tag: 'BatteryService');
      return null;
    } on PlatformException catch (e) {
      AppLogger.error(
        'Failed to get battery info: ${e.message}',
        tag: 'BatteryService',
      );
      return null;
    } catch (e) {
      AppLogger.error(
        'Unexpected error getting battery info: $e',
        tag: 'BatteryService',
      );
      return null;
    }
  }

  /// Get battery emoji based on percentage and charging status
  static String getBatteryEmoji(int batteryLevel, bool isCharging) {
    if (batteryLevel == 0) {
      return ''; // No emoji for 0% - will show text instead
    }

    if (isCharging) {
      return '🔌';
    }

    if (batteryLevel >= 50) {
      return '🔋';
    }

    if (batteryLevel >= 20) {
      return '🪫';
    }

    return '🔴';
  }

  /// Format battery display string for child app
  /// Returns: "🔋 85%" or "(0% - Phone Off)"
  static String formatBatteryDisplay(int batteryLevel, bool isCharging) {
    if (batteryLevel == 0) {
      return '(0% - Phone Off)';
    }

    final emoji = getBatteryEmoji(batteryLevel, isCharging);
    return '$emoji $batteryLevel%';
  }
}
