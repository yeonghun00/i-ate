import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:thanks_everyday/core/constants/app_constants.dart';
import 'package:thanks_everyday/core/errors/app_exceptions.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';
import 'package:thanks_everyday/services/fcm_v1_service.dart';
import 'package:thanks_everyday/services/auth/firebase_auth_manager.dart';

class MealTrackingService with AppLogger {
  static final MealTrackingService _instance = MealTrackingService._internal();
  factory MealTrackingService() => _instance;
  MealTrackingService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuthManager _authManager = FirebaseAuthManager();

  Future<Result<bool>> saveMealRecord({
    required String familyId,
    required String elderlyName,
    required DateTime timestamp,
    required int mealNumber,
  }) async {
    try {
      logInfo('Saving meal record - meal $mealNumber for $elderlyName');
      
      // Check authentication
      final authResult = await _ensureAuthentication();
      if (authResult.isFailure) {
        return authResult;
      }

      final today = DateTime.now();
      final dateString = _formatDateString(today);
      final mealId = '${timestamp.millisecondsSinceEpoch}_$mealNumber';
      
      final mealData = {
        'mealId': mealId,
        'timestamp': timestamp.toIso8601String(),
        'mealNumber': mealNumber,
        'elderlyName': elderlyName,
        'createdAt': timestamp.toIso8601String(),
      };

      // Save to meals subcollection
      await _firestore
          .collection(AppConstants.collectionFamilies)
          .doc(familyId)
          .collection(AppConstants.collectionMeals)
          .doc(dateString)
          .set({
            'meals': FieldValue.arrayUnion([mealData]),
            'date': dateString,
            'elderlyName': elderlyName,
          }, SetOptions(merge: true));

      // Update family document with current meal count
      final currentMealCount = await _getCurrentMealCount(familyId, dateString);
      await _updateFamilyMealInfo(familyId, currentMealCount);

      // Send FCM notification
      await _sendMealNotification(familyId, elderlyName, timestamp, mealNumber);

      logInfo('Meal record saved successfully - total count: $currentMealCount');
      return const Success(true);
      
    } catch (e, stackTrace) {
      logError('Failed to save meal record', error: e, stackTrace: stackTrace);
      return Failure(MealRecordException(
        message: AppConstants.errorMealRecordFailed,
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<Result<bool>> _ensureAuthentication() async {
    try {
      logInfo('Ensuring authentication');
      if (await _authManager.ensureAuthenticated()) {
        logInfo('Authentication successful');
        return const Success(true);
      } else {
        logError('Authentication failed');
        return const Failure(AuthenticationException(message: 'Authentication failed'));
      }
      
    } catch (e, stackTrace) {
      logError('Authentication failed', error: e, stackTrace: stackTrace);
      return Failure(FirebaseInitException(
        message: 'Authentication failed: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  String _formatDateString(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<int> _getCurrentMealCount(String familyId, String dateString) async {
    try {
      final mealDoc = await _firestore
          .collection(AppConstants.collectionFamilies)
          .doc(familyId)
          .collection(AppConstants.collectionMeals)
          .doc(dateString)
          .get();

      if (mealDoc.exists) {
        final data = mealDoc.data();
        final meals = data?['meals'] as List<dynamic>?;
        return meals?.length ?? 0;
      }

      return 0;
    } catch (e) {
      logError('Failed to get current meal count', error: e);
      return 0;
    }
  }

  Future<void> _updateFamilyMealInfo(String familyId, int mealCount) async {
    try {
      // Get the latest meal number from the current timestamp context
      final mealNumber = mealCount; // This will be the meal number (1, 2, or 3)
      
      await _firestore.collection(AppConstants.collectionFamilies).doc(familyId).update({
        'lastMeal': {
          'timestamp': FieldValue.serverTimestamp(),
          'count': mealCount,
          'number': mealNumber,
        },
      });
    } catch (e) {
      logError('Failed to update family meal info', error: e);
    }
  }

  Future<void> _sendMealNotification(
    String familyId,
    String elderlyName,
    DateTime timestamp,
    int mealNumber,
  ) async {
    try {
      await FCMv1Service.sendMealNotification(
        familyId: familyId,
        elderlyName: elderlyName,
        timestamp: timestamp,
        mealNumber: mealNumber,
      );
      logInfo('FCM meal notification sent successfully');
    } catch (e) {
      logWarning('Failed to send FCM meal notification: $e');
    }
  }

  Future<Result<int>> getTodayMealCount(String familyId) async {
    try {
      final today = DateTime.now();
      final dateString = _formatDateString(today);

      final mealDoc = await _firestore
          .collection(AppConstants.collectionFamilies)
          .doc(familyId)
          .collection(AppConstants.collectionMeals)
          .doc(dateString)
          .get();

      if (mealDoc.exists) {
        final data = mealDoc.data();
        final meals = data?['meals'] as List<dynamic>?;
        final count = meals?.length ?? 0;
        logDebug('Today\'s meal count: $count');
        return Success(count);
      }

      return const Success(0);
      
    } catch (e, stackTrace) {
      logError('Failed to get today\'s meal count', error: e, stackTrace: stackTrace);
      return Failure(ServiceException(
        message: 'Failed to get today\'s meal count: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<Result<List<Map<String, dynamic>>>> getMealsForDate(
    String familyId,
    DateTime date,
  ) async {
    try {
      final dateString = _formatDateString(date);

      final doc = await _firestore
          .collection(AppConstants.collectionFamilies)
          .doc(familyId)
          .collection(AppConstants.collectionMeals)
          .doc(dateString)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final meals = data?['meals'] as List<dynamic>? ?? [];
        final mealList = meals.map((meal) => Map<String, dynamic>.from(meal)).toList();
        return Success(mealList);
      }

      return const Success([]);
      
    } catch (e, stackTrace) {
      logError('Failed to get meals for date', error: e, stackTrace: stackTrace);
      return Failure(ServiceException(
        message: 'Failed to get meals for date: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<Result<bool>> updateFoodIntake({
    required String familyId,
    required DateTime timestamp,
    required int todayCount,
  }) async {
    try {
      await _firestore.collection(AppConstants.collectionFamilies).doc(familyId).update({
        'lastMeal': {
          'timestamp': FieldValue.serverTimestamp(),
          'count': todayCount,
          'number': null, // Unknown meal number when called from this method
        },
        'foodAlert.isActive': false,
      });

      logInfo('Food intake updated: $timestamp, count: $todayCount');
      return const Success(true);
      
    } catch (e, stackTrace) {
      logError('Failed to update food intake', error: e, stackTrace: stackTrace);
      return Failure(ServiceException(
        message: 'Failed to update food intake: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }
}