import 'package:thanks_everyday/core/utils/app_logger.dart';

class ActivityBatcher {
  static const Duration _batchInterval = Duration(hours: 2);
  static const Duration _longInactivityThreshold = Duration(hours: 8);
  
  DateTime? _lastBatch;
  DateTime? _lastScreenActivity;

  bool shouldBatchUpdate({bool forceImmediate = false}) {
    final now = DateTime.now();
    _lastScreenActivity = now;
    
    // Always send immediately if forced or first activity
    if (forceImmediate || _lastBatch == null) {
      return false;
    }
    
    final timeSinceLastBatch = now.difference(_lastBatch!);
    
    // Send immediately if breaking long inactivity
    if (timeSinceLastBatch >= _longInactivityThreshold) {
      AppLogger.info('Breaking long inactivity - sending immediate update', tag: 'ActivityBatcher');
      return false;
    }
    
    // Send immediately if batch interval exceeded
    if (timeSinceLastBatch >= _batchInterval) {
      return false;
    }
    
    // Otherwise, batch the update
    AppLogger.debug('Batching activity update', tag: 'ActivityBatcher');
    return true;
  }

  void recordBatch() {
    _lastBatch = DateTime.now();
  }

  bool get isFirstActivity => _lastBatch == null;
}