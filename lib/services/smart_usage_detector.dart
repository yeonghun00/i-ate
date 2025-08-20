import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';

class SmartUsageDetector {
  static const MethodChannel _channel = MethodChannel('thanks_everyday/usage_detector');
  
  final FirebaseService _firebaseService = FirebaseService();
  // _batchUpdateTimer removed - batch updates now handled differently
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
    AppLogger.info('Initializing Smart Usage Detector...', tag: 'SmartUsageDetector');
    
    try {
      // Set up immediate screen event listeners (simple approach)
      await _setupScreenEventListeners();
      
      // Start periodic usage checker (every 15 minutes)
      _startPeriodicUsageChecker();
      
      // Load previous state
      await _loadLocalState();
      
      AppLogger.info('Smart Usage Detector initialized successfully', tag: 'SmartUsageDetector');
    } catch (e) {
      AppLogger.error('Failed to initialize Smart Usage Detector: $e', tag: 'SmartUsageDetector');
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
            AppLogger.warning('Unknown method: ${call.method}', tag: 'SmartUsageDetector');
        }
      });
      
      // Register native listeners
      await _channel.invokeMethod('startScreenMonitoring');
      AppLogger.info('Screen event listeners registered', tag: 'SmartUsageDetector');
    } catch (e) {
      AppLogger.error('Failed to setup screen listeners: $e', tag: 'SmartUsageDetector');
    }
  }

  /// Handle immediate screen ON event - Simple approach
  Future<void> _handleScreenOn() async {
    final now = DateTime.now();
    _lastScreenOn = now;
    _screenOnCount++;
    
    AppLogger.debug('Screen ON detected at ${now.toIso8601String()}', tag: 'SmartUsageDetector');
    
    // Check if we should update Firebase (every 15 minutes OR after long inactivity)
    final shouldUpdate = _shouldUpdateOnScreenOn(now);
    
    if (shouldUpdate) {
      AppLogger.debug('Screen ON - Updating Firebase (15min interval or critical)', tag: 'SmartUsageDetector');
      await _updateFirebaseScreenOn(now);
    } else {
      AppLogger.debug('Screen ON - No Firebase update needed yet', tag: 'SmartUsageDetector');
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
      
      // Use batched activity update instead of direct Firebase writes
      await _firebaseService.updatePhoneActivity();
      _lastFirebaseUpdate = now;
      AppLogger.debug('Firebase updated on Screen ON - ${minutesSinceLastUpdate} minutes since last update', tag: 'SmartUsageDetector');
      
    } catch (e) {
      AppLogger.error('Failed to update Firebase on screen ON: $e', tag: 'SmartUsageDetector');
    }
  }

  /// Handle immediate screen OFF event
  Future<void> _handleScreenOff() async {
    final now = DateTime.now();
    _lastScreenOff = now;
    
    AppLogger.debug('Screen OFF detected at ${now.toIso8601String()}', tag: 'SmartUsageDetector');
    
    // Calculate active session duration
    if (_lastScreenOn != null) {
      final sessionDuration = now.difference(_lastScreenOn!);
      _totalActiveTime = _totalActiveTime + sessionDuration;
      
      AppLogger.debug('Active session: ${sessionDuration.inMinutes} minutes', tag: 'SmartUsageDetector');
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
    
    AppLogger.debug('Screen UNLOCK detected at ${now.toIso8601String()}', tag: 'SmartUsageDetector');
    
    // Check if we should update Firebase (every 15 minutes OR after long inactivity)
    final shouldUpdate = _shouldUpdateOnScreenOn(now);
    
    if (shouldUpdate) {
      AppLogger.debug('Screen UNLOCK - Updating Firebase (15min interval or critical)', tag: 'SmartUsageDetector');
      await _updateFirebaseScreenUnlock(now);
    } else {
      AppLogger.debug('Screen UNLOCK - No Firebase update needed yet', tag: 'SmartUsageDetector');
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
      
      // Use batched activity update instead of direct Firebase writes
      await _firebaseService.updatePhoneActivity();
      _lastFirebaseUpdate = now;
      AppLogger.debug('Firebase updated on Screen UNLOCK - ${minutesSinceLastUpdate} minutes since last update', tag: 'SmartUsageDetector');
      
    } catch (e) {
      AppLogger.error('Failed to update Firebase on screen unlock: $e', tag: 'SmartUsageDetector');
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
      
      // Use batched activity update instead of direct Firebase writes
      await _firebaseService.updatePhoneActivity();
      _lastFirebaseUpdate = now;
      AppLogger.debug('Firebase updated on Screen OFF - ${sessionDuration} minute session', tag: 'SmartUsageDetector');
      
    } catch (e) {
      AppLogger.error('Failed to update Firebase on screen OFF: $e', tag: 'SmartUsageDetector');
    }
  }

  /// Handle continuous phone usage detected by Android's periodic checks
  Future<void> _handleContinuousPhoneUsage(Map<String, dynamic>? arguments) async {
    if (arguments == null) return;
    
    final now = DateTime.now();
    final phoneUsageTimeMs = arguments['phone_usage_time_ms'] as int? ?? 0;
    final appsUsed = arguments['apps_used'] as int? ?? 0;
    final lastInteractionTime = arguments['last_interaction_time'] as int? ?? 0;
    
    AppLogger.debug('Continuous phone usage detected - Apps: $appsUsed, Usage: ${phoneUsageTimeMs}ms', tag: 'SmartUsageDetector');
    
    // Update local tracking
    _lastAppUsage = DateTime.fromMillisecondsSinceEpoch(lastInteractionTime);
    _appInteractionCount += appsUsed;
    _hasSignificantActivity = true;
    
    // Check if we should update Firebase (15+ minutes since last update)
    final shouldUpdate = _shouldUpdateOnContinuousUsage(now);
    
    if (shouldUpdate) {
      AppLogger.debug('Continuous usage - Updating Firebase (15min interval reached)', tag: 'SmartUsageDetector');
      await _updateFirebaseContinuousUsage(now, phoneUsageTimeMs, appsUsed);
    } else {
      AppLogger.debug('Continuous usage detected - No Firebase update needed yet', tag: 'SmartUsageDetector');
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
      
      // Use batched activity update instead of direct Firebase writes
      await _firebaseService.updatePhoneActivity();
      _lastFirebaseUpdate = now;
      AppLogger.debug('Firebase updated for continuous usage - ${minutesSinceLastUpdate} minutes since last update, ${appsUsed} apps used', tag: 'SmartUsageDetector');
      
    } catch (e) {
      AppLogger.error('Failed to update Firebase for continuous usage: $e', tag: 'SmartUsageDetector');
    }
  }

  /// Start periodic usage checker (every 15 minutes)
  void _startPeriodicUsageChecker() {
    _periodicUsageTimer?.cancel();
    _periodicUsageTimer = Timer.periodic(const Duration(minutes: 15), (timer) async {
      await _checkPeriodicUsage();
    });
    AppLogger.info('Started 15-minute periodic usage checker', tag: 'SmartUsageDetector');
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
          AppLogger.debug('Periodic check: Phone in use, updating Firebase', tag: 'SmartUsageDetector');
          await _updateFirebasePeriodicUsage(now);
        } else {
          AppLogger.debug('Periodic check: Phone not in use, skipping update', tag: 'SmartUsageDetector');
        }
      } else {
        AppLogger.debug('Periodic check: Recent update exists, skipping', tag: 'SmartUsageDetector');
      }
      
    } catch (e) {
      AppLogger.error('Error during periodic usage check: $e', tag: 'SmartUsageDetector');
    }
  }

  /// Check if screen is currently ON
  Future<bool> _isScreenCurrentlyOn() async {
    try {
      // Try native Android check first (most reliable)
      final result = await _channel.invokeMethod('isScreenCurrentlyOn');
      if (result != null) {
        AppLogger.debug('Native screen state check: ${result ? "ON" : "OFF"}', tag: 'SmartUsageDetector');
        return result as bool;
      }
      
      // Fallback to timestamp-based heuristic
      if (_lastScreenOn != null && _lastScreenOff != null) {
        final isOn = _lastScreenOn!.isAfter(_lastScreenOff!);
        AppLogger.debug('Fallback screen state check: ${isOn ? "ON" : "OFF"}', tag: 'SmartUsageDetector');
        return isOn;
      } else if (_lastScreenOn != null && _lastScreenOff == null) {
        AppLogger.debug('Fallback screen state check: ON (never turned off)', tag: 'SmartUsageDetector');
        return true; // Screen was turned on but never off
      }
      
      AppLogger.debug('Fallback screen state check: OFF (no data)', tag: 'SmartUsageDetector');
      return false;
    } catch (e) {
      AppLogger.error('Error checking screen state: $e', tag: 'SmartUsageDetector');
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
      
      // Use batched activity update instead of direct Firebase writes
      await _firebaseService.updatePhoneActivity();
      _lastFirebaseUpdate = now;
      AppLogger.debug('Periodic Firebase update completed - ${minutesSinceLastUpdate} minutes since last update', tag: 'SmartUsageDetector');
      
    } catch (e) {
      AppLogger.error('Failed periodic Firebase update: $e', tag: 'SmartUsageDetector');
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
      AppLogger.error('Failed to save local state: $e', tag: 'SmartUsageDetector');
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
      
      AppLogger.debug('Local state loaded successfully', tag: 'SmartUsageDetector');
    } catch (e) {
      AppLogger.error('Failed to load local state: $e', tag: 'SmartUsageDetector');
    }
  }

  /// Stop all monitoring
  Future<void> stop() async {
    _periodicUsageTimer?.cancel();
    
    try {
      await _channel.invokeMethod('stopScreenMonitoring');
    } catch (e) {
      AppLogger.error('Error stopping native monitoring: $e', tag: 'SmartUsageDetector');
    }
    
    AppLogger.info('Smart Usage Detector stopped', tag: 'SmartUsageDetector');
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