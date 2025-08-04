import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
import 'package:thanks_everyday/services/smart_usage_detector.dart';

class ScreenMonitorService {
  static const MethodChannel _channel = MethodChannel('com.thousandemfla.thanks_everyday/screen_monitor');
  static final FirebaseService _firebaseService = FirebaseService();
  
  static Future<void> initialize() async {
    try {
      // Set up method call handler for native callbacks
      _channel.setMethodCallHandler((MethodCall call) async {
        try {
          switch (call.method) {
            case 'onInactivityAlert':
              await _handleInactivityAlert();
              break;
            case 'onPhoneActivity':
              await _handlePhoneActivity();
              break;
          }
        } catch (e) {
          print('Error handling method call: $e');
        }
      });
      print('ScreenMonitorService method channel initialized');
    } catch (e) {
      print('ScreenMonitorService initialization error: $e');
    }
  }
  
  /// Start monitoring screen activity (now uses SmartUsageDetector)
  static Future<bool> startMonitoring() async {
    try {
      // Check permissions first
      final hasPermissions = await checkPermissions();
      if (!hasPermissions) {
        await requestPermissions();
        return false;
      }
      
      // Use both legacy and new smart detection systems
      await _channel.invokeMethod('startScreenMonitoring');
      
      // Start smart usage detection for enhanced monitoring
      await SmartUsageDetector.instance.initialize();
      
      print('Screen monitoring started (Legacy + Smart Detection)');
      return true;
    } on PlatformException catch (e) {
      print('Failed to start screen monitoring: ${e.message}');
      return false;
    }
  }
  
  /// Stop monitoring screen activity
  static Future<bool> stopMonitoring() async {
    try {
      await _channel.invokeMethod('stopScreenMonitoring');
      
      // Stop smart usage detection as well
      await SmartUsageDetector.instance.stop();
      
      print('Screen monitoring stopped (Legacy + Smart Detection)');
      return true;
    } on PlatformException catch (e) {
      print('Failed to stop screen monitoring: ${e.message}');
      return false;
    }
  }
  
  /// Check if required permissions are granted
  static Future<bool> checkPermissions() async {
    try {
      final result = await _channel.invokeMethod('checkPermissions');
      return result == true;
    } on PlatformException catch (e) {
      print('Failed to check permissions: ${e.message}');
      return false;
    }
  }

  /// Check if usage stats permission is granted
  static Future<bool> checkUsageStatsPermission() async {
    try {
      final result = await _channel.invokeMethod('checkUsageStatsPermission');
      return result == true;
    } on PlatformException catch (e) {
      print('Failed to check usage stats permission: ${e.message}');
      return false;
    }
  }

  /// Check if battery optimization is disabled
  static Future<bool> checkBatteryOptimization() async {
    try {
      final result = await _channel.invokeMethod('checkBatteryOptimization');
      return result == true;
    } on PlatformException catch (e) {
      print('Failed to check battery optimization: ${e.message}');
      return false;
    }
  }

  /// Request usage stats permission
  static Future<void> requestUsageStatsPermission() async {
    try {
      await _channel.invokeMethod('requestUsageStatsPermission');
    } on PlatformException catch (e) {
      print('Failed to request usage stats permission: ${e.message}');
    }
  }

  /// Request battery optimization disable
  static Future<void> requestBatteryOptimizationDisable() async {
    try {
      await _channel.invokeMethod('requestBatteryOptimizationDisable');
    } on PlatformException catch (e) {
      print('Failed to request battery optimization disable: ${e.message}');
    }
  }
  
  /// Request required permissions
  static Future<void> requestPermissions() async {
    try {
      await _channel.invokeMethod('requestPermissions');
    } on PlatformException catch (e) {
      print('Failed to request permissions: ${e.message}');
    }
  }
  
  /// Get current screen on count
  static Future<int> getScreenOnCount() async {
    try {
      final result = await _channel.invokeMethod('getScreenOnCount');
      return result ?? 0;
    } on PlatformException catch (e) {
      print('Failed to get screen on count: ${e.message}');
      return 0;
    }
  }
  
  /// Get last screen activity timestamp
  static Future<DateTime?> getLastScreenActivity() async {
    try {
      final result = await _channel.invokeMethod('getLastScreenActivity');
      if (result != null && result != 0) {
        return DateTime.fromMillisecondsSinceEpoch(result);
      }
      return null;
    } on PlatformException catch (e) {
      print('Failed to get last screen activity: ${e.message}');
      return null;
    }
  }
  
  /// Check if user has been inactive for more than specified hours
  static Future<bool> isInactive({int hours = 12}) async {
    final lastActivity = await getLastScreenActivity();
    if (lastActivity == null) return true;
    
    final now = DateTime.now();
    final difference = now.difference(lastActivity);
    return difference.inHours >= hours;
  }
  
  /// Get detailed activity status
  static Future<Map<String, dynamic>> getActivityStatus() async {
    final lastActivity = await getLastScreenActivity();
    final screenOnCount = await getScreenOnCount();
    final isInactive = await ScreenMonitorService.isInactive();
    
    return {
      'lastActivity': lastActivity?.toIso8601String(),
      'screenOnCount': screenOnCount,
      'isInactive': isInactive,
      'hoursSinceLastActivity': lastActivity != null 
          ? DateTime.now().difference(lastActivity).inHours 
          : null,
    };
  }
  
  /// Enable survival signal monitoring
  static Future<void> enableSurvivalSignal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('flutter.survival_signal_enabled', true);
    print('Survival signal enabled in preferences');
    
    // Check permissions before starting service
    final hasPermissions = await checkPermissions();
    if (!hasPermissions) {
      print('Cannot start survival signal - permissions not granted');
      return;
    }
    
    // Native service will handle timing and throttling internally
    
    // Start monitoring
    final started = await startMonitoring();
    if (started) {
      print('Native screen monitoring enabled successfully');
      print('- Background service: Started');
      print('- WorkManager: Scheduled for periodic checks');
      print('- Screen on/off events: Being monitored');
    } else {
      print('Failed to start screen monitoring');
    }
  }
  
  /// Disable survival signal monitoring
  static Future<void> disableSurvivalSignal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('flutter.survival_signal_enabled', false);
    
    // Stop monitoring
    await stopMonitoring();
    print('Native screen monitoring disabled');
  }
  
  /// Handle inactivity alert from native service
  static Future<void> _handleInactivityAlert() async {
    print('Handling inactivity alert');
    
    try {
      // Send alert to Firebase for family notification
      await _sendSurvivalAlert();
    } catch (e) {
      print('Failed to send survival alert: $e');
    }
  }
  
  /// Handle phone activity from native service
  static Future<void> _handlePhoneActivity() async {
    try {
      // Update Firebase with general phone activity
      await _firebaseService.updatePhoneActivity();
    } catch (e) {
      print('Failed to update Firebase phone activity: $e');
    }
  }
  
  /// Send survival alert to Firebase
  static Future<void> _sendSurvivalAlert() async {
    final prefs = await SharedPreferences.getInstance();
    final familyId = prefs.getString('family_id');
    final elderlyName = prefs.getString('elderly_name');
    
    if (familyId == null) {
      print('No family ID found for survival alert');
      return;
    }
    
    try {
      await _firebaseService.sendSurvivalAlert(
        familyCode: familyId, // Note: parameter name is familyCode but we pass familyId
        elderlyName: elderlyName ?? 'Unknown',
        message: '12시간 이상 휴대폰 사용이 없습니다. 안부를 확인해주세요.',
      );
      
      print('Survival alert sent to family');
    } catch (e) {
      print('Failed to send survival alert to Firebase: $e');
    }
  }
}