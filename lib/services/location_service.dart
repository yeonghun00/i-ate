import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class LocationService {
  static const String _locationEnabledKey = 'location_tracking_enabled';
  static const String _lastLocationKey = 'last_location';
  
  static final FirebaseService _firebaseService = FirebaseService();
  static Timer? _locationTimer;
  static Position? _lastKnownPosition;
  
  // Initialize location service
  static Future<void> initialize() async {
    if (await isLocationTrackingEnabled()) {
      await _startLocationTracking();
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
      await _startLocationTracking();
    } else {
      await _stopLocationTracking();
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
  
  // Start location tracking
  static Future<void> _startLocationTracking() async {
    if (!await checkLocationPermission()) {
      print('Location permission not granted');
      return;
    }
    
    // Check background permissions for continuous tracking (optional)
    if (!await checkBackgroundLocationPermission()) {
      print('Battery optimization not granted - tracking may be limited in background');
    }
    
    // Get initial location
    await getCurrentLocation();
    
    // Start periodic location updates (every 30 minutes for optimal battery/cost balance)
    _locationTimer = Timer.periodic(const Duration(minutes: 30), (timer) async {
      await getCurrentLocation();
    });
    
    print('Location tracking started - updates every 30 minutes');
  }
  
  // Stop location tracking
  static Future<void> _stopLocationTracking() async {
    _locationTimer?.cancel();
    _locationTimer = null;
    print('Location tracking stopped');
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
      'isActivelyTracking': _locationTimer?.isActive ?? false,
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
}