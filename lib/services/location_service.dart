import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:thanks_everyday/core/utils/app_logger.dart';

class LocationService {
  static const String _locationEnabledKey = 'flutter.location_tracking_enabled';
  // _lastLocationKey removed - not currently used
  static const MethodChannel _channel = MethodChannel('com.thousandemfla.thanks_everyday/screen_monitor');
  
  static final FirebaseService _firebaseService = FirebaseService();
  // _locationTimer removed - location updates now handled via native code
  static Position? _lastKnownPosition;
  
  // Initialize location service
  static Future<void> initialize() async {
    // Set up method call handler for native location updates
    _channel.setMethodCallHandler((MethodCall call) async {
      try {
        switch (call.method) {
          case 'onLocationUpdate':
            await _handleLocationUpdate(call.arguments);
            break;
        }
      } catch (e) {
        AppLogger.error('Error handling location method call: $e', tag: 'LocationService');
      }
    });
    
    if (await isLocationTrackingEnabled()) {
      await _startNativeLocationTracking();
    }
    AppLogger.info('Location service initialized', tag: 'LocationService');
  }
  
  // Check if location tracking is enabled
  static Future<bool> isLocationTrackingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_locationEnabledKey) ?? false;
  }
  
  // Enable/disable location tracking
  static Future<void> setLocationTrackingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_locationEnabledKey, enabled);
    
    if (enabled) {
      // Reset throttle for immediate first update
      await _resetLocationThrottle();
      await _startNativeLocationTracking();
    } else {
      await _stopNativeLocationTracking();
    }
  }
  
  // Reset location update throttle
  static Future<void> _resetLocationThrottle() async {
    try {
      await _channel.invokeMethod('resetThrottleTimer');
      AppLogger.info('Location throttle reset - next update will be immediate', tag: 'LocationService');
    } catch (e) {
      AppLogger.error('Failed to reset location throttle: $e', tag: 'LocationService');
    }
  }
  
  // Check location permissions
  static Future<bool> checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      AppLogger.info('Location service is disabled', tag: 'LocationService');
      return false;
    }
    
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        AppLogger.warning('Location permission denied', tag: 'LocationService');
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      AppLogger.warning('Location permission denied forever', tag: 'LocationService');
      return false;
    }
    
    // For background location tracking, we need "always" permission
    if (permission == LocationPermission.whileInUse) {
      AppLogger.warning('Location permission granted but only for "while in use" - background tracking may be limited', tag: 'LocationService');
      AppLogger.info('For continuous background tracking, "Always allow" permission is recommended', tag: 'LocationService');
    }
    
    return true;
  }

  // Check for "Always allow" background location permission
  static Future<bool> hasBackgroundLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always;
  }

  // Check additional permissions for background location
  static Future<bool> checkBackgroundLocationPermission() async {
    // Check for "Always allow" location permission
    final hasAlwaysPermission = await hasBackgroundLocationPermission();
    if (!hasAlwaysPermission) {
      AppLogger.warning('Background location permission not granted - tracking may stop when app is closed', tag: 'LocationService');
      AppLogger.info('Please enable "Always allow" location permission for continuous background tracking', tag: 'LocationService');
    }
    
    // Check battery optimization (recommended for better background tracking)
    final ignoreBatteryOptimizations = await Permission.ignoreBatteryOptimizations.status;
    if (!ignoreBatteryOptimizations.isGranted) {
      AppLogger.warning('Battery optimization permission not granted', tag: 'LocationService');
      final result = await Permission.ignoreBatteryOptimizations.request();
      if (!result.isGranted) {
        AppLogger.warning('Battery optimization permission denied - location tracking may be limited', tag: 'LocationService');
        return false;
      }
    }
    
    return hasAlwaysPermission;
  }
  
  // Get current location
  static Future<Position?> getCurrentLocation() async {
    try {
      if (!await checkLocationPermission()) {
        return null;
      }
      
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      
      _lastKnownPosition = position;
      await _updateLocationInFirebase(position);
      
      return position;
    } catch (e) {
      AppLogger.error('Failed to get current location: $e', tag: 'LocationService');
      return null;
    }
  }
  
  // Start native location tracking (survives app kills)
  static Future<void> _startNativeLocationTracking() async {
    if (!await checkLocationPermission()) {
      AppLogger.warning('Location permission not granted', tag: 'LocationService');
      return;
    }
    
    try {
      await _channel.invokeMethod('startLocationTracking');
      AppLogger.info('Native location tracking started - survives app kills', tag: 'LocationService');
    } on PlatformException catch (e) {
      AppLogger.error('Failed to start native location tracking: ${e.message}', tag: 'LocationService');
    }
  }
  
  // Stop native location tracking
  static Future<void> _stopNativeLocationTracking() async {
    try {
      await _channel.invokeMethod('stopLocationMonitoring');
      AppLogger.info('Native location tracking stopped', tag: 'LocationService');
    } on PlatformException catch (e) {
      AppLogger.error('Failed to stop native location tracking: ${e.message}', tag: 'LocationService');
    }
  }
  
  // Update location in Firebase
  static Future<void> _updateLocationInFirebase(Position position) async {
    try {
      await _firebaseService.updateLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        address: '', // Could be enhanced with geocoding in the future
      );
      
      AppLogger.info('Location updated in Firebase: ${position.latitude}, ${position.longitude}', tag: 'LocationService');
    } catch (e) {
      AppLogger.error('Failed to update location in Firebase: $e', tag: 'LocationService');
    }
  }
  
  // Get last known location
  static Position? getLastKnownLocation() {
    return _lastKnownPosition;
  }

  // Handle native location updates
  static Future<void> _handleLocationUpdate(dynamic args) async {
    try {
      final latitude = args['latitude'] as double;
      final longitude = args['longitude'] as double;
      final timestamp = args['timestamp'] as int;
      final accuracy = args['accuracy'] as double;
      
      AppLogger.debug('Native location update: $latitude, $longitude (accuracy: ${accuracy}m)', tag: 'LocationService');
      
      // Create Position object
      _lastKnownPosition = Position(
        latitude: latitude,
        longitude: longitude,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
        accuracy: accuracy,
        altitude: 0.0,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      );
      
      // Update Firebase
      await _updateLocationInFirebase(_lastKnownPosition!);
      
    } catch (e) {
      AppLogger.error('Failed to handle native location update: $e', tag: 'LocationService');
    }
  }
  
  // Get location tracking status info
  static Future<Map<String, dynamic>> getLocationTrackingStatus() async {
    final isEnabled = await isLocationTrackingEnabled();
    final hasLocationPermission = await checkLocationPermission();
    final hasBatteryOptimization = await checkBackgroundLocationPermission();
    
    return {
      'enabled': isEnabled,
      'locationPermission': hasLocationPermission,
      'batteryOptimization': hasBatteryOptimization,
      'lastLocation': _lastKnownPosition,
      'isActivelyTracking': true, // Native service is always active when enabled
    };
  }
  
  // Format location for display
  static String formatLocation(Position position) {
    return '위도: ${position.latitude.toStringAsFixed(6)}, 경도: ${position.longitude.toStringAsFixed(6)}';
  }
  
  // Calculate distance between two positions
  static double calculateDistance(Position pos1, Position pos2) {
    return Geolocator.distanceBetween(
      pos1.latitude,
      pos1.longitude,
      pos2.latitude,
      pos2.longitude,
    );
  }
  
  /// Test location service debugging
  static Future<void> testLocationUpdate() async {
    AppLogger.debug('TESTING LOCATION SERVICE', tag: 'LocationService');
    
    try {
      // Check if location is enabled
      final isEnabled = await isLocationTrackingEnabled();
      AppLogger.debug('Location tracking enabled: $isEnabled', tag: 'LocationService');
      
      // Check permissions
      final hasPermission = await checkLocationPermission();
      AppLogger.debug('Has location permission: $hasPermission', tag: 'LocationService');
      
      // Try to get current location manually
      AppLogger.debug('Attempting to get current location...', tag: 'LocationService');
      final position = await getCurrentLocation();
      if (position != null) {
        AppLogger.debug('Got location: ${position.latitude}, ${position.longitude}', tag: 'LocationService');
      } else {
        AppLogger.error('Failed to get location', tag: 'LocationService');
      }
      
    } catch (e) {
      AppLogger.error('Location test failed: $e', tag: 'LocationService');
    }
  }
}