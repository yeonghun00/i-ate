import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:thanks_everyday/services/firebase_service.dart';

class SmartUsageDetector {
  static const MethodChannel _channel = MethodChannel('thanks_everyday/usage_detector');
  
  final FirebaseService _firebaseService = FirebaseService();
  Timer? _batchUpdateTimer;
  Timer? _usageCheckTimer;
  Timer? _periodicUsageTimer;
  
  // Local state tracking
  DateTime? _lastScreenOn;
  DateTime? _lastScreenOff;
  DateTime? _lastAppUsage;
  DateTime? _lastFirebaseUpdate;
  
  // Usage statistics for 15-minute window
  int _screenOnCount = 0;
  int _appInteractionCount = 0;
  Duration _totalActiveTime = Duration.zero;
  bool _hasSignificantActivity = false;
  
  // Settings
  static const Duration _batchInterval = Duration(minutes: 15);
  static const Duration _usageCheckInterval = Duration(minutes: 15);
  static const int _criticalInactivityHours = 2;
  
  static SmartUsageDetector? _instance;
  static SmartUsageDetector get instance => _instance ??= SmartUsageDetector._();
  
  SmartUsageDetector._();

  /// Initialize the smart usage detection system
  Future<void> initialize() async {
    print('🧠 Initializing Smart Usage Detector...');
    
    try {
      // Set up immediate screen event listeners (simple approach)
      await _setupScreenEventListeners();
      
      // Start periodic usage checker (every 15 minutes)
      _startPeriodicUsageChecker();
      
      // Load previous state
      await _loadLocalState();
      
      print('✅ Smart Usage Detector initialized successfully');
    } catch (e) {
      print('❌ Failed to initialize Smart Usage Detector: $e');
    }
  }

  /// Set up immediate screen event detection (critical for emergency alerts)
  Future<void> _setupScreenEventListeners() async {
    try {
      // Listen for screen on/off events and continuous phone usage
      _channel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'onScreenOn':
            await _handleScreenOn();
            break;
          case 'onScreenOff':
            await _handleScreenOff();
            break;
          case 'onPhoneUsage':
            await _handleContinuousPhoneUsage(call.arguments);
            break;
          case 'onScreenUnlock':
            await _handleScreenUnlock();
            break;
          default:
            print('🤷‍♂️ Unknown method: ${call.method}');
        }
      });
      
      // Register native listeners
      await _channel.invokeMethod('startScreenMonitoring');
      print('📱 Screen event listeners registered');
    } catch (e) {
      print('❌ Failed to setup screen listeners: $e');
    }
  }

  /// Handle immediate screen ON event - Simple approach
  Future<void> _handleScreenOn() async {
    final now = DateTime.now();
    _lastScreenOn = now;
    _screenOnCount++;
    
    print('📱 Screen ON detected at ${now.toIso8601String()}');
    
    // Check if we should update Firebase (every 15 minutes OR after long inactivity)
    final shouldUpdate = _shouldUpdateOnScreenOn(now);
    
    if (shouldUpdate) {
      print('📤 Screen ON - Updating Firebase (15min interval or critical)');
      await _updateFirebaseScreenOn(now);
    } else {
      print('📱 Screen ON - No Firebase update needed yet');
    }
    
    // Update local activity tracking
    _hasSignificantActivity = true;
    await _saveLocalState();
  }
  
  /// Check if we should update Firebase on screen ON
  bool _shouldUpdateOnScreenOn(DateTime now) {
    // Update if it's been 15+ minutes since last Firebase update
    if (_lastFirebaseUpdate == null) return true;
    
    final minutesSinceUpdate = now.difference(_lastFirebaseUpdate!).inMinutes;
    
    // Update every 15 minutes OR if breaking long inactivity
    if (minutesSinceUpdate >= 15) return true;
    
    // Update immediately if breaking long inactivity period
    if (_lastScreenOff != null) {
      final inactiveDuration = now.difference(_lastScreenOff!);
      if (inactiveDuration.inHours >= _criticalInactivityHours) return true;
    }
    
    return false;
  }
  
  /// Update Firebase when screen turns ON
  Future<void> _updateFirebaseScreenOn(DateTime now) async {
    if (!_firebaseService.isSetup) return;
    
    try {
      final minutesSinceLastUpdate = _lastFirebaseUpdate != null 
          ? now.difference(_lastFirebaseUpdate!).inMinutes
          : 999;
      
      final updateData = {
        'lastPhoneActivity': Timestamp.fromDate(now),
        'lastActivityType': 'screen_on_activity',
        'updateTimestamp': Timestamp.fromDate(now),
        'minutesSinceLastUpdate': minutesSinceLastUpdate,
        'screenOnTime': Timestamp.fromDate(now),
      };
      
      await FirebaseFirestore.instance
          .collection('families')
          .doc(_firebaseService.familyId)
          .update(updateData);
      
      _lastFirebaseUpdate = now;
      print('✅ Firebase updated on Screen ON - ${minutesSinceLastUpdate} minutes since last update');
      
    } catch (e) {
      print('❌ Failed to update Firebase on screen ON: $e');
    }
  }

  /// Handle immediate screen OFF event
  Future<void> _handleScreenOff() async {
    final now = DateTime.now();
    _lastScreenOff = now;
    
    print('📱 Screen OFF detected at ${now.toIso8601String()}');
    
    // Calculate active session duration
    if (_lastScreenOn != null) {
      final sessionDuration = now.difference(_lastScreenOn!);
      _totalActiveTime = _totalActiveTime + sessionDuration;
      
      print('⏱️ Active session: ${sessionDuration.inMinutes} minutes');
    }
    
    // Always update Firebase for screen off (survival signal logic)
    await _updateFirebaseScreenOff(now);
    
    await _saveLocalState();
  }

  /// Handle screen unlock event (similar to screen on but different trigger)
  Future<void> _handleScreenUnlock() async {
    final now = DateTime.now();
    _lastScreenOn = now; // Treat unlock as screen on
    _screenOnCount++;
    
    print('🔓 Screen UNLOCK detected at ${now.toIso8601String()}');
    
    // Check if we should update Firebase (every 15 minutes OR after long inactivity)
    final shouldUpdate = _shouldUpdateOnScreenOn(now);
    
    if (shouldUpdate) {
      print('📤 Screen UNLOCK - Updating Firebase (15min interval or critical)');
      await _updateFirebaseScreenUnlock(now);
    } else {
      print('🔓 Screen UNLOCK - No Firebase update needed yet');
    }
    
    // Update local activity tracking
    _hasSignificantActivity = true;
    await _saveLocalState();
  }
  
  /// Update Firebase when screen is unlocked
  Future<void> _updateFirebaseScreenUnlock(DateTime now) async {
    if (!_firebaseService.isSetup) return;
    
    try {
      final minutesSinceLastUpdate = _lastFirebaseUpdate != null 
          ? now.difference(_lastFirebaseUpdate!).inMinutes
          : 999;
      
      final updateData = {
        'lastPhoneActivity': Timestamp.fromDate(now),
        'lastActivityType': 'screen_unlock',
        'updateTimestamp': Timestamp.fromDate(now),
        'minutesSinceLastUpdate': minutesSinceLastUpdate,
        'screenUnlockTime': Timestamp.fromDate(now),
      };
      
      await FirebaseFirestore.instance
          .collection('families')
          .doc(_firebaseService.familyId)
          .update(updateData);
      
      _lastFirebaseUpdate = now;
      print('✅ Firebase updated on Screen UNLOCK - ${minutesSinceLastUpdate} minutes since last update');
      
    } catch (e) {
      print('❌ Failed to update Firebase on screen unlock: $e');
    }
  }
  
  /// Update Firebase when screen turns OFF (always update for survival signal)
  Future<void> _updateFirebaseScreenOff(DateTime now) async {
    if (!_firebaseService.isSetup) return;
    
    try {
      final sessionDuration = _lastScreenOn != null 
          ? now.difference(_lastScreenOn!).inMinutes 
          : 0;
      
      final updateData = {
        'lastPhoneActivity': Timestamp.fromDate(now),
        'lastActivityType': 'screen_off',
        'updateTimestamp': Timestamp.fromDate(now),
        'screenOffTime': Timestamp.fromDate(now),
        'sessionDurationMinutes': sessionDuration,
      };
      
      await FirebaseFirestore.instance
          .collection('families')
          .doc(_firebaseService.familyId)
          .update(updateData);
      
      _lastFirebaseUpdate = now;
      print('✅ Firebase updated on Screen OFF - ${sessionDuration} minute session');
      
    } catch (e) {
      print('❌ Failed to update Firebase on screen OFF: $e');
    }
  }

  /// Handle continuous phone usage detected by Android's periodic checks
  Future<void> _handleContinuousPhoneUsage(Map<String, dynamic>? arguments) async {
    if (arguments == null) return;
    
    final now = DateTime.now();
    final phoneUsageTimeMs = arguments['phone_usage_time_ms'] as int? ?? 0;
    final appsUsed = arguments['apps_used'] as int? ?? 0;
    final lastInteractionTime = arguments['last_interaction_time'] as int? ?? 0;
    
    print('📱 Continuous phone usage detected - Apps: $appsUsed, Usage: ${phoneUsageTimeMs}ms');
    
    // Update local tracking
    _lastAppUsage = DateTime.fromMillisecondsSinceEpoch(lastInteractionTime);
    _appInteractionCount += appsUsed;
    _hasSignificantActivity = true;
    
    // Check if we should update Firebase (15+ minutes since last update)
    final shouldUpdate = _shouldUpdateOnContinuousUsage(now);
    
    if (shouldUpdate) {
      print('📤 Continuous usage - Updating Firebase (15min interval reached)');
      await _updateFirebaseContinuousUsage(now, phoneUsageTimeMs, appsUsed);
    } else {
      print('📱 Continuous usage detected - No Firebase update needed yet');
    }
    
    await _saveLocalState();
  }
  
  /// Check if we should update Firebase for continuous usage
  bool _shouldUpdateOnContinuousUsage(DateTime now) {
    // Always update if no previous Firebase update
    if (_lastFirebaseUpdate == null) return true;
    
    final minutesSinceUpdate = now.difference(_lastFirebaseUpdate!).inMinutes;
    
    // Update if it's been 15+ minutes since last Firebase update
    return minutesSinceUpdate >= 15;
  }
  
  /// Update Firebase for continuous phone usage
  Future<void> _updateFirebaseContinuousUsage(DateTime now, int usageTimeMs, int appsUsed) async {
    if (!_firebaseService.isSetup) return;
    
    try {
      final minutesSinceLastUpdate = _lastFirebaseUpdate != null 
          ? now.difference(_lastFirebaseUpdate!).inMinutes
          : 999;
      
      final updateData = {
        'lastPhoneActivity': Timestamp.fromDate(now),
        'lastActivityType': 'continuous_usage',
        'updateTimestamp': Timestamp.fromDate(now),
        'minutesSinceLastUpdate': minutesSinceLastUpdate,
        'phoneUsageTimeMs': usageTimeMs,
        'appsUsedCount': appsUsed,
        'continuousUsageDetected': true,
      };
      
      await FirebaseFirestore.instance
          .collection('families')
          .doc(_firebaseService.familyId)
          .update(updateData);
      
      _lastFirebaseUpdate = now;
      print('✅ Firebase updated for continuous usage - ${minutesSinceLastUpdate} minutes since last update, ${appsUsed} apps used');
      
    } catch (e) {
      print('❌ Failed to update Firebase for continuous usage: $e');
    }
  }

  /// Start periodic usage checker (every 15 minutes)
  void _startPeriodicUsageChecker() {
    _periodicUsageTimer?.cancel();
    _periodicUsageTimer = Timer.periodic(const Duration(minutes: 15), (timer) async {
      await _checkPeriodicUsage();
    });
    print('⏰ Started 15-minute periodic usage checker');
  }

  /// Check if we should update Firebase every 15 minutes (even without screen events)
  Future<void> _checkPeriodicUsage() async {
    try {
      final now = DateTime.now();
      
      // Check if Firebase needs updating (15+ minutes since last update)
      final shouldUpdate = _lastFirebaseUpdate == null || 
          now.difference(_lastFirebaseUpdate!).inMinutes >= 15;
      
      if (shouldUpdate) {
        // Check if phone is currently being used (screen is on)
        final isScreenOn = await _isScreenCurrentlyOn();
        
        if (isScreenOn) {
          print('📱 Periodic check: Phone in use, updating Firebase');
          await _updateFirebasePeriodicUsage(now);
        } else {
          print('📱 Periodic check: Phone not in use, skipping update');
        }
      } else {
        print('📱 Periodic check: Recent update exists, skipping');
      }
      
    } catch (e) {
      print('❌ Error during periodic usage check: $e');
    }
  }

  /// Check if screen is currently ON
  Future<bool> _isScreenCurrentlyOn() async {
    try {
      // Try native Android check first (most reliable)
      final result = await _channel.invokeMethod('isScreenCurrentlyOn');
      if (result != null) {
        print('📱 Native screen state check: ${result ? "ON" : "OFF"}');
        return result as bool;
      }
      
      // Fallback to timestamp-based heuristic
      if (_lastScreenOn != null && _lastScreenOff != null) {
        final isOn = _lastScreenOn!.isAfter(_lastScreenOff!);
        print('📱 Fallback screen state check: ${isOn ? "ON" : "OFF"}');
        return isOn;
      } else if (_lastScreenOn != null && _lastScreenOff == null) {
        print('📱 Fallback screen state check: ON (never turned off)');
        return true; // Screen was turned on but never off
      }
      
      print('📱 Fallback screen state check: OFF (no data)');
      return false;
    } catch (e) {
      print('⚠️ Error checking screen state: $e');
      return false;
    }
  }

  /// Update Firebase during periodic check
  Future<void> _updateFirebasePeriodicUsage(DateTime now) async {
    if (!_firebaseService.isSetup) return;
    
    try {
      final minutesSinceLastUpdate = _lastFirebaseUpdate != null 
          ? now.difference(_lastFirebaseUpdate!).inMinutes
          : 999;
      
      final updateData = {
        'lastPhoneActivity': Timestamp.fromDate(now),
        'lastActivityType': 'periodic_usage_check',
        'updateTimestamp': Timestamp.fromDate(now),
        'minutesSinceLastUpdate': minutesSinceLastUpdate,
        'detectionMethod': 'periodic_timer',
      };
      
      await FirebaseFirestore.instance
          .collection('families')
          .doc(_firebaseService.familyId)
          .update(updateData);
      
      _lastFirebaseUpdate = now;
      print('✅ Periodic Firebase update completed - ${minutesSinceLastUpdate} minutes since last update');
      
    } catch (e) {
      print('❌ Failed periodic Firebase update: $e');
    }
  }

  /// Save local state to SharedPreferences
  Future<void> _saveLocalState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (_lastScreenOn != null) {
        await prefs.setString('last_screen_on', _lastScreenOn!.toIso8601String());
      }
      if (_lastScreenOff != null) {
        await prefs.setString('last_screen_off', _lastScreenOff!.toIso8601String());
      }
      if (_lastAppUsage != null) {
        await prefs.setString('last_app_usage', _lastAppUsage!.toIso8601String());
      }
      if (_lastFirebaseUpdate != null) {
        await prefs.setString('last_firebase_update', _lastFirebaseUpdate!.toIso8601String());
      }
      
    } catch (e) {
      print('⚠️ Failed to save local state: $e');
    }
  }

  /// Load previous state from SharedPreferences
  Future<void> _loadLocalState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final lastScreenOnStr = prefs.getString('last_screen_on');
      if (lastScreenOnStr != null) {
        _lastScreenOn = DateTime.parse(lastScreenOnStr);
      }
      
      final lastScreenOffStr = prefs.getString('last_screen_off');
      if (lastScreenOffStr != null) {
        _lastScreenOff = DateTime.parse(lastScreenOffStr);
      }
      
      final lastAppUsageStr = prefs.getString('last_app_usage');
      if (lastAppUsageStr != null) {
        _lastAppUsage = DateTime.parse(lastAppUsageStr);
      }
      
      final lastFirebaseUpdateStr = prefs.getString('last_firebase_update');
      if (lastFirebaseUpdateStr != null) {
        _lastFirebaseUpdate = DateTime.parse(lastFirebaseUpdateStr);
      }
      
      print('📂 Local state loaded successfully');
    } catch (e) {
      print('⚠️ Failed to load local state: $e');
    }
  }

  /// Stop all monitoring
  Future<void> stop() async {
    _periodicUsageTimer?.cancel();
    
    try {
      await _channel.invokeMethod('stopScreenMonitoring');
    } catch (e) {
      print('⚠️ Error stopping native monitoring: $e');
    }
    
    print('🛑 Smart Usage Detector stopped');
  }

  /// Get current usage statistics
  Map<String, dynamic> getCurrentStats() {
    return {
      'lastScreenOn': _lastScreenOn?.toIso8601String(),
      'lastScreenOff': _lastScreenOff?.toIso8601String(),
      'lastAppUsage': _lastAppUsage?.toIso8601String(),
      'lastFirebaseUpdate': _lastFirebaseUpdate?.toIso8601String(),
      'currentWindow': {
        'screenOnCount': _screenOnCount,
        'appInteractions': _appInteractionCount,
        'totalActiveMinutes': _totalActiveTime.inMinutes,
        'hasSignificantActivity': _hasSignificantActivity,
      },
    };
  }
}