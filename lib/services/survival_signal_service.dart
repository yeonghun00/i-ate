import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class SurvivalSignalService {
  static const String _lastScreenOnKey = 'last_screen_on_timestamp';
  static const String _survivalEnabledKey = 'survival_signal_enabled';
  static const String _familyContactKey = 'family_contact';
  static const String _elderlyNameKey = 'elderly_name';
  static const String taskName = 'survival_signal_check';
  
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Timer? _screenActivityTimer;
  static int _screenOnCount = 0;
  static DateTime? _lastFirebaseUpdate; // Track last Firebase update to avoid duplicates
  
  // Initialize the service
  static Future<void> initialize() async {
    // Start monitoring screen activity if enabled
    if (await isSurvivalSignalEnabled()) {
      await _startScreenMonitoring();
    }
    print('Survival signal service initialized');
  }
  
  // Update last screen activity timestamp
  static Future<void> updateLastActivity() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(_lastScreenOnKey, timestamp);
    
    // Increment screen on count
    _screenOnCount++;
    await prefs.setInt('screen_on_count', _screenOnCount);
    
    print('Updating activity: ${DateTime.now()}');
    
    // Smart Firebase updates - only update if meaningful time has passed
    final familyId = prefs.getString('family_id'); // Use familyId instead of familyCode
    if (familyId != null) {
      final now = DateTime.now();
      
      // Only update Firebase if more than 10 minutes since last update
      if (_lastFirebaseUpdate == null || 
          now.difference(_lastFirebaseUpdate!).inMinutes >= 10) {
        
        try {
          await _firestore.collection('families').doc(familyId).update({
            'lastScreenActivity': FieldValue.serverTimestamp(),
            'lastActivity': FieldValue.serverTimestamp(), // Also update this field
            'screenOnCount': _screenOnCount,
          });
          _lastFirebaseUpdate = now;
          print('Updated Firebase activity for family: $familyId at ${now.toString()}');
        } catch (e) {
          print('Failed to update screen activity in Firebase: $e');
        }
      } else {
        print('Skipping Firebase update - too soon since last update');
      }
    } else {
      print('No family ID found, cannot update Firebase activity');
    }
  }
  
  // Enable/disable survival signal monitoring
  static Future<void> setSurvivalSignalEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_survivalEnabledKey, enabled);
    
    if (enabled) {
      await _startScreenMonitoring();
    } else {
      await _stopScreenMonitoring();
    }
  }
  
  // Check if survival signal is enabled
  static Future<bool> isSurvivalSignalEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_survivalEnabledKey) ?? false;
  }
  
  // Set family contact information
  static Future<void> setFamilyContact(String contact) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_familyContactKey, contact);
  }
  
  // Get family contact information
  static Future<String?> getFamilyContact() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_familyContactKey);
  }
  
  // Start screen activity monitoring
  static Future<void> _startScreenMonitoring() async {
    await updateLastActivity();
    
    // Start a timer to periodically check screen activity
    _screenActivityTimer = Timer.periodic(const Duration(minutes: 15), (timer) async {
      await _checkScreenActivity();
    });
    
    print('Screen activity monitoring started');
  }
  
  // Stop screen activity monitoring
  static Future<void> _stopScreenMonitoring() async {
    _screenActivityTimer?.cancel();
    _screenActivityTimer = null;
    print('Screen activity monitoring stopped');
  }
  
  // Check recent screen activity
  static Future<void> _checkScreenActivity() async {
    final hasRecent = await hasRecentActivity();
    if (!hasRecent) {
      await sendSurvivalAlert();
    }
  }
  
  // Check if there's been recent screen activity
  static Future<bool> hasRecentActivity() async {
    final prefs = await SharedPreferences.getInstance();
    final lastScreenOn = prefs.getInt(_lastScreenOnKey);
    
    if (lastScreenOn == null) return false;
    
    final lastScreenOnTime = DateTime.fromMillisecondsSinceEpoch(lastScreenOn);
    final now = DateTime.now();
    final difference = now.difference(lastScreenOnTime);
    
    // Return true if screen activity within last 12 hours
    return difference.inHours < 12;
  }
  
  // Get screen on count for today
  static Future<int> getTodayScreenOnCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('screen_on_count') ?? 0;
  }
  
  // Send survival signal alert to family
  static Future<void> sendSurvivalAlert() async {
    final prefs = await SharedPreferences.getInstance();
    final familyId = prefs.getString('family_id'); // Use familyId instead of familyCode
    final elderlyName = prefs.getString('elderly_name');
    
    if (familyId == null) return;
    
    try {
      await _firestore.collection('families').doc(familyId).update({
        'survivalAlert': {
          'timestamp': FieldValue.serverTimestamp(),
          'elderlyName': elderlyName,
          'message': '12시간 이상 앱 사용이 없습니다. 안부를 확인해주세요.',
          'isActive': true,
        }
      });
      
      print('Survival alert sent to family');
    } catch (e) {
      print('Failed to send survival alert: $e');
    }
  }
  
  // Clear survival alert
  static Future<void> clearSurvivalAlert() async {
    final prefs = await SharedPreferences.getInstance();
    final familyId = prefs.getString('family_id'); // Use familyId instead of familyCode
    
    if (familyId == null) return;
    
    try {
      await _firestore.collection('families').doc(familyId).update({
        'survivalAlert.isActive': false,
      });
    } catch (e) {
      print('Failed to clear survival alert: $e');
    }
  }
}

// Simplified checking method (can be called manually from family app)
// Background task callback removed for now to avoid build issues