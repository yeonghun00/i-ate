import 'package:shared_preferences/shared_preferences.dart';
// Cloud Firestore import removed - Firebase operations now handled via FirebaseService
import 'package:thanks_everyday/services/firebase_service.dart';
import 'dart:async';
import 'package:thanks_everyday/core/utils/app_logger.dart';

class FoodTrackingService {
  static const String _lastFoodIntakeKey = 'last_food_intake';
  static const String _foodIntakeCountKey = 'food_intake_count';
  static const String _foodAlertThresholdKey = 'food_alert_threshold'; // hours
  
  static final FirebaseService _firebaseService = FirebaseService();
  static Timer? _foodAlertTimer;
  
  // Initialize food tracking service
  static Future<void> initialize() async {
    await _startFoodAlertMonitoring();
    AppLogger.info('Food tracking service initialized', tag: 'FoodTrackingService');
  }
  
  // Record food intake
  static Future<bool> recordFoodIntake() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final timestamp = now.millisecondsSinceEpoch;
      
      // Update local storage
      await prefs.setInt(_lastFoodIntakeKey, timestamp);
      
      // Get today's count
      final today = DateTime(now.year, now.month, now.day);
      final todayKey = '${_foodIntakeCountKey}_${today.millisecondsSinceEpoch}';
      final todayCount = prefs.getInt(todayKey) ?? 0;
      await prefs.setInt(todayKey, todayCount + 1);
      
      // Update Firebase
      await _firebaseService.updateFoodIntake(
        timestamp: now,
        todayCount: todayCount + 1,
      );
      
      AppLogger.info('Food intake recorded: ${now.toIso8601String()}', tag: 'FoodTrackingService');
      return true;
    } catch (e) {
      AppLogger.error('Failed to record food intake: $e', tag: 'FoodTrackingService');
      return false;
    }
  }
  
  // Get last food intake time
  static Future<DateTime?> getLastFoodIntake() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_lastFoodIntakeKey);
      
      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
      return null;
    } catch (e) {
      AppLogger.error('Failed to get last food intake: $e', tag: 'FoodTrackingService');
      return null;
    }
  }
  
  // Get today's food intake count
  static Future<int> getTodayFoodIntakeCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayKey = '${_foodIntakeCountKey}_${todayStart.millisecondsSinceEpoch}';
      
      return prefs.getInt(todayKey) ?? 0;
    } catch (e) {
      AppLogger.error('Failed to get today food intake count: $e', tag: 'FoodTrackingService');
      return 0;
    }
  }
  
  // Set food alert threshold (hours)
  static Future<void> setFoodAlertThreshold(int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_foodAlertThresholdKey, hours);
  }
  
  // Get food alert threshold
  static Future<int> getFoodAlertThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_foodAlertThresholdKey) ?? 8; // Default 8 hours
  }
  
  // Check if food alert should be sent
  static Future<bool> shouldSendFoodAlert() async {
    final lastIntake = await getLastFoodIntake();
    final threshold = await getFoodAlertThreshold();
    
    if (lastIntake == null) {
      return true; // No intake recorded, send alert
    }
    
    final now = DateTime.now();
    final hoursSinceLastIntake = now.difference(lastIntake).inHours;
    
    return hoursSinceLastIntake >= threshold;
  }
  
  // Start food alert monitoring
  static Future<void> _startFoodAlertMonitoring() async {
    // Check every hour for food alerts
    _foodAlertTimer = Timer.periodic(const Duration(hours: 1), (timer) async {
      if (await shouldSendFoodAlert()) {
        await _sendFoodAlert();
      }
    });
    
    AppLogger.info('Food alert monitoring started', tag: 'FoodTrackingService');
  }
  
  // _stopFoodAlertMonitoring method removed - not currently used
  
  // Send food alert to family
  static Future<void> _sendFoodAlert() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final elderlyName = prefs.getString('elderly_name') ?? 'Unknown';
      
      final lastIntake = await getLastFoodIntake();
      final threshold = await getFoodAlertThreshold();
      
      String message;
      int? hoursWithoutFood;
      
      if (lastIntake == null) {
        message = '식사 기록이 없습니다. 안부를 확인해주세요.';
        hoursWithoutFood = null;
      } else {
        hoursWithoutFood = DateTime.now().difference(lastIntake).inHours;
        message = '${threshold}시간 이상 식사하지 않았습니다. (마지막 식사: ${hoursWithoutFood}시간 전)';
      }
      
      await _firebaseService.sendFoodAlert(
        elderlyName: elderlyName,
        message: message,
        lastFoodIntake: lastIntake,
        hoursWithoutFood: hoursWithoutFood,
      );
      
      AppLogger.info('Food alert sent to family: $message', tag: 'FoodTrackingService');
    } catch (e) {
      AppLogger.error('Failed to send food alert: $e', tag: 'FoodTrackingService');
    }
  }
  
  
  // Clear food alert
  static Future<void> clearFoodAlert() async {
    try {
      await _firebaseService.clearFoodAlert();
      AppLogger.info('Food alert cleared', tag: 'FoodTrackingService');
    } catch (e) {
      AppLogger.error('Failed to clear food alert: $e', tag: 'FoodTrackingService');
    }
  }
  
  // Get food intake history for today
  static Future<List<DateTime>> getTodayFoodIntakeHistory() async {
    // This would require more complex storage, for now return empty list
    // In a full implementation, you'd store individual intake times
    return [];
  }
  
  // Format time since last intake
  static String formatTimeSinceLastIntake(DateTime? lastIntake) {
    if (lastIntake == null) {
      return '기록 없음';
    }
    
    final now = DateTime.now();
    final difference = now.difference(lastIntake);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}일 ${difference.inHours % 24}시간 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 ${difference.inMinutes % 60}분 전';
    } else {
      return '${difference.inMinutes}분 전';
    }
  }
}