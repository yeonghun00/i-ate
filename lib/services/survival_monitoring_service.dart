import 'package:shared_preferences/shared_preferences.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
import 'dart:async';

class SurvivalMonitoringService {
  static const String _lastScreenActivityKey = 'last_screen_activity';
  static const String _survivalAlertThresholdKey = 'survival_alert_threshold'; // hours
  static const String _survivalMonitoringEnabledKey = 'survival_monitoring_enabled';
  
  static final FirebaseService _firebaseService = FirebaseService();
  static Timer? _survivalCheckTimer;
  
  // Initialize survival monitoring service
  static Future<void> initialize() async {
    if (await isSurvivalMonitoringEnabled()) {
      await _startSurvivalMonitoring();
    }
    print('Survival monitoring service initialized');
  }
  
  // Record screen activity (call this when app is used)
  static Future<void> recordScreenActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setInt(_lastScreenActivityKey, now.millisecondsSinceEpoch);
      print('Screen activity recorded: ${now.toIso8601String()}');
    } catch (e) {
      print('Failed to record screen activity: $e');
    }
  }
  
  // Get last screen activity time
  static Future<DateTime?> getLastScreenActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_lastScreenActivityKey);
      
      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
      return null;
    } catch (e) {
      print('Failed to get last screen activity: $e');
      return null;
    }
  }
  
  // Check if survival monitoring is enabled
  static Future<bool> isSurvivalMonitoringEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_survivalMonitoringEnabledKey) ?? false;
  }
  
  // Enable/disable survival monitoring
  static Future<void> setSurvivalMonitoringEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_survivalMonitoringEnabledKey, enabled);
    
    if (enabled) {
      await _startSurvivalMonitoring();
      // Record initial activity
      await recordScreenActivity();
    } else {
      await _stopSurvivalMonitoring();
    }
  }
  
  // Set survival alert threshold (hours)
  static Future<void> setSurvivalAlertThreshold(int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_survivalAlertThresholdKey, hours);
  }
  
  // Get survival alert threshold
  static Future<int> getSurvivalAlertThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_survivalAlertThresholdKey) ?? 12; // Default 12 hours
  }
  
  // Check if survival alert should be sent
  static Future<bool> shouldSendSurvivalAlert() async {
    final lastActivity = await getLastScreenActivity();
    final threshold = await getSurvivalAlertThreshold();
    
    if (lastActivity == null) {
      return true; // No activity recorded, send alert
    }
    
    final now = DateTime.now();
    final hoursSinceLastActivity = now.difference(lastActivity).inHours;
    
    return hoursSinceLastActivity >= threshold;
  }
  
  // Start survival monitoring
  static Future<void> _startSurvivalMonitoring() async {
    // Check every hour for survival alerts
    _survivalCheckTimer = Timer.periodic(const Duration(hours: 1), (timer) async {
      if (await shouldSendSurvivalAlert()) {
        await _sendSurvivalAlert();
      }
    });
    
    print('Survival monitoring started - checking every hour');
  }
  
  // Stop survival monitoring
  static Future<void> _stopSurvivalMonitoring() async {
    _survivalCheckTimer?.cancel();
    _survivalCheckTimer = null;
    print('Survival monitoring stopped');
  }
  
  // Send survival alert to family
  static Future<void> _sendSurvivalAlert() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final elderlyName = prefs.getString('elderly_name') ?? 'Unknown';
      final familyId = _firebaseService.familyId;
      
      if (familyId == null) {
        print('Cannot send survival alert: no family ID');
        return;
      }
      
      final lastActivity = await getLastScreenActivity();
      final threshold = await getSurvivalAlertThreshold();
      
      String message;
      if (lastActivity == null) {
        message = '휴대폰 사용 기록이 없습니다. 안부를 확인해주세요.';
      } else {
        final hoursSinceLastActivity = DateTime.now().difference(lastActivity).inHours;
        message = '${threshold}시간 이상 휴대폰을 사용하지 않았습니다. (마지막 사용: ${hoursSinceLastActivity}시간 전)';
      }
      
      await _firebaseService.sendSurvivalAlert(
        familyCode: familyId, // This is actually familyId in the method
        elderlyName: elderlyName,
        message: message,
      );
      
      print('Survival alert sent to family: $message');
    } catch (e) {
      print('Failed to send survival alert: $e');
    }
  }
  
  // Clear survival alert
  static Future<void> clearSurvivalAlert() async {
    try {
      await _firebaseService.clearSurvivalAlert();
      print('Survival alert cleared');
    } catch (e) {
      print('Failed to clear survival alert: $e');
    }
  }
  
  // Get survival monitoring status
  static Future<Map<String, dynamic>> getSurvivalMonitoringStatus() async {
    final isEnabled = await isSurvivalMonitoringEnabled();
    final lastActivity = await getLastScreenActivity();
    final threshold = await getSurvivalAlertThreshold();
    
    int? hoursSinceLastActivity;
    if (lastActivity != null) {
      hoursSinceLastActivity = DateTime.now().difference(lastActivity).inHours;
    }
    
    return {
      'enabled': isEnabled,
      'threshold': threshold,
      'lastActivity': lastActivity,
      'hoursSinceLastActivity': hoursSinceLastActivity,
      'shouldAlert': await shouldSendSurvivalAlert(),
      'isMonitoring': _survivalCheckTimer?.isActive ?? false,
    };
  }
  
  // Format time since last activity
  static String formatTimeSinceLastActivity(DateTime? lastActivity) {
    if (lastActivity == null) {
      return '기록 없음';
    }
    
    final now = DateTime.now();
    final difference = now.difference(lastActivity);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}일 ${difference.inHours % 24}시간 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 ${difference.inMinutes % 60}분 전';
    } else {
      return '${difference.inMinutes}분 전';
    }
  }
}