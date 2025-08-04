import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class LocationService {
  static const String _locationEnabledKey = 'location_tracking_enabled';
  static const String _lastLocationKey = 'last_location';
  static const MethodChannel _channel = MethodChannel('com.thousandemfla.thanks_everyday/screen_monitor');
  
  static final FirebaseService _firebaseService = FirebaseService();
  static Timer? _locationTimer;
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
        print('Error handling location method call: $e');
      }
    });
    
    if (await isLocationTrackingEnabled()) {
      await _startNativeLocationTracking();
    }
    print('Location service initialized');
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
      print('✅ Location throttle reset - next update will be immediate');
    } catch (e) {
      print('❌ Failed to reset location throttle: $e');
    }
  }
  
  // Check location permissions
  static Future<bool> checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('Location service is disabled');
      return false;
    }
    
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('Location permission denied');
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      print('Location permission denied forever');
      return false;
    }
    
    return true;
  }

  // Check additional permissions for background location
  static Future<bool> checkBackgroundLocationPermission() async {
    // Check battery optimization (recommended for better background tracking)
    final ignoreBatteryOptimizations = await Permission.ignoreBatteryOptimizations.status;
    if (!ignoreBatteryOptimizations.isGranted) {
      print('Battery optimization permission not granted');
      final result = await Permission.ignoreBatteryOptimizations.request();
      if (!result.isGranted) {
        print('Battery optimization permission denied - location tracking may be limited');
        return false;
      }
    }
    
    return true;
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
      print('Failed to get current location: $e');
      return null;
    }
  }
  
  // Start native location tracking (survives app kills)
  static Future<void> _startNativeLocationTracking() async {
    if (!await checkLocationPermission()) {
      print('Location permission not granted');
      return;
    }
    
    try {
      await _channel.invokeMethod('startLocationTracking');
      print('✅ Native location tracking started - survives app kills');
    } on PlatformException catch (e) {
      print('❌ Failed to start native location tracking: ${e.message}');
    }
  }
  
  // Stop native location tracking
  static Future<void> _stopNativeLocationTracking() async {
    try {
      await _channel.invokeMethod('stopLocationMonitoring');
      print('✅ Native location tracking stopped');
    } on PlatformException catch (e) {
      print('❌ Failed to stop native location tracking: ${e.message}');
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
      
      print('Location updated in Firebase: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      print('Failed to update location in Firebase: $e');
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
      
      print('📍 Native location update: $latitude, $longitude (accuracy: ${accuracy}m)');
      
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
      print('❌ Failed to handle native location update: $e');
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
    print('📍 📍 TESTING LOCATION SERVICE 📍 📍');
    
    try {
      // Check if location is enabled
      final isEnabled = await isLocationTrackingEnabled();
      print('Location tracking enabled: $isEnabled');
      
      // Check permissions
      final hasPermission = await checkLocationPermission();
      print('Has location permission: $hasPermission');
      
      // Try to get current location manually
      print('Attempting to get current location...');
      final position = await getCurrentLocation();
      if (position != null) {
        print('✅ Got location: ${position.latitude}, ${position.longitude}');
      } else {
        print('❌ Failed to get location');
      }
      
    } catch (e) {
      print('❌ Location test failed: $e');
    }
  }
}