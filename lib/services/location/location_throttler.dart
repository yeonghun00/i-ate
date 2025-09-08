import 'dart:math' show sin, cos, asin, sqrt;
import 'package:thanks_everyday/core/utils/app_logger.dart';

class LocationThrottler {
  static const double _significantDistanceKm = 0.1; // Reduced from 0.5km to 0.1km for more sensitive updates
  static const Duration _timeThreshold = Duration(minutes: 30); // Reduced from 4 hours to 30 minutes
  
  double? _lastLatitude;
  double? _lastLongitude;
  DateTime? _lastUpdate;

  bool shouldThrottleUpdate(double latitude, double longitude) {
    // Always send the first location update
    if (_lastLatitude == null || _lastLongitude == null) {
      return false;
    }
    
    // Calculate distance from last stored location
    final distanceKm = _calculateDistanceKm(
      _lastLatitude!, _lastLongitude!,
      latitude, longitude,
    );
    
    // Send update if distance exceeds threshold
    if (distanceKm >= _significantDistanceKm) {
      AppLogger.debug('Significant location change: ${distanceKm.toStringAsFixed(2)}km', tag: 'LocationThrottler');
      return false;
    }
    
    // Check time-based threshold
    if (_lastUpdate != null) {
      final minutesSinceUpdate = DateTime.now().difference(_lastUpdate!).inMinutes;
      if (minutesSinceUpdate >= _timeThreshold.inMinutes) {
        AppLogger.debug('Time-based location update (${minutesSinceUpdate}min since last)', tag: 'LocationThrottler');
        return false;
      }
    }
    
    return true;
  }

  void recordUpdate(double latitude, double longitude) {
    _lastLatitude = latitude;
    _lastLongitude = longitude;
    _lastUpdate = DateTime.now();
  }

  double _calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusKm = 6371.0;
    
    final double deltaLat = _toRadians(lat2 - lat1);
    final double deltaLon = _toRadians(lon2 - lon1);
    
    final double a = 
        sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(deltaLon / 2) * sin(deltaLon / 2);
    
    final double c = 2 * asin(sqrt(a));
    
    return earthRadiusKm * c;
  }
  
  double _toRadians(double degrees) {
    return degrees * (3.14159265359 / 180.0);
  }
}