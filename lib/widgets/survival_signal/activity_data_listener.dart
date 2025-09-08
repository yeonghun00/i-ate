import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';

class ActivityDataListener {
  final FirebaseService _firebaseService;
  StreamSubscription? _firestoreSubscription;
  Timer? _updateTimer;

  ActivityDataListener(this._firebaseService);

  Stream<ActivityData> get activityStream async* {
    if (!_firebaseService.isSetup) {
      yield ActivityData.empty();
      return;
    }

    try {
      await for (final snapshot in FirebaseFirestore.instance
          .collection('families')
          .doc(_firebaseService.familyId)
          .snapshots()) {
        
        if (snapshot.exists) {
          final data = snapshot.data()!;
          final lastPhoneActivityTimestamp = data['lastPhoneActivity'] as Timestamp?;
          
          if (lastPhoneActivityTimestamp != null) {
            final lastActivity = lastPhoneActivityTimestamp.toDate();
            final hoursSince = DateTime.now().difference(lastActivity).inHours;
            
            yield ActivityData(
              lastActivity: lastActivity,
              hoursSinceActivity: hoursSince,
              isLoading: false,
            );
          } else {
            yield ActivityData.noData();
          }
        }
      }
    } catch (e) {
      AppLogger.error('Failed to listen to activity data: $e', tag: 'ActivityDataListener');
      yield ActivityData.error();
    }
  }

  void dispose() {
    _firestoreSubscription?.cancel();
    _updateTimer?.cancel();
  }
}

class ActivityData {
  final DateTime? lastActivity;
  final int hoursSinceActivity;
  final bool isLoading;
  final bool hasError;

  ActivityData({
    required this.lastActivity,
    required this.hoursSinceActivity,
    this.isLoading = false,
    this.hasError = false,
  });

  factory ActivityData.empty() => ActivityData(
    lastActivity: null,
    hoursSinceActivity: 0,
    isLoading: true,
  );

  factory ActivityData.noData() => ActivityData(
    lastActivity: null,
    hoursSinceActivity: 999,
    isLoading: false,
  );

  factory ActivityData.error() => ActivityData(
    lastActivity: null,
    hoursSinceActivity: 0,
    isLoading: false,
    hasError: true,
  );
}