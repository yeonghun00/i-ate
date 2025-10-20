import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:thanks_everyday/services/fcm_v1_service.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';
import 'package:thanks_everyday/services/auth/firebase_auth_manager.dart';
import 'package:thanks_everyday/services/storage/local_storage_manager.dart';
import 'package:thanks_everyday/services/family/family_id_generator.dart';
import 'package:thanks_everyday/services/family/family_data_manager.dart';
import 'package:thanks_everyday/services/location/location_throttler.dart';
import 'package:thanks_everyday/services/activity/activity_batcher.dart';
import 'package:thanks_everyday/services/encryption_service.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuthManager _authManager = FirebaseAuthManager();
  final LocalStorageManager _storage = LocalStorageManager();
  final FamilyDataManager _familyData = FamilyDataManager();
  final LocationThrottler _locationThrottler = LocationThrottler();
  final ActivityBatcher _activityBatcher = ActivityBatcher();

  String? _familyId;
  String? _familyCode;
  String? _elderlyName;
  String? _cachedEncryptionKey;

  Future<bool> initialize() async {
    try {
      // Initialize FCM v1 service
      await FCMv1Service.initialize();

      // Authenticate using manager
      await _authManager.ensureAuthenticated();

      // Load family data from local storage
      _familyId = await _storage.getString('family_id');
      _familyCode = await _storage.getString('family_code');
      _elderlyName = await _storage.getString('elderly_name');

      return _familyCode != null;
    } catch (e) {
      AppLogger.error('Firebase initialization failed: $e', tag: 'FirebaseService');
      return false;
    }
  }

  Future<String> _generateConnectionCode() async {
    String code;
    bool isUnique = false;
    int attempts = 0;
    const maxAttempts = 100; // Failsafe to prevent infinite loop

    do {
      code = FamilyIdGenerator.generateConnectionCode();

      // Check the PUBLIC connection_codes collection, not the private families collection
      final docRef = _firestore.collection('connection_codes').doc(code);
      final docSnapshot = await docRef.get();

      isUnique = !docSnapshot.exists;
      attempts++;

      if (attempts >= maxAttempts && !isUnique) {
        throw Exception('Failed to generate unique connection code after $maxAttempts attempts');
      }
    } while (!isUnique);

    return code;
  }

  // Recovery code generation removed - using name + connection code only

  // Set up family code (called by family member)
  Future<String?> setupFamilyCode(String elderlyName) async {
    try {
      final connectionCode = await _generateConnectionCode();
      final familyId = await _generateUniqueFamilyId();

      final success = await _setupFamilyDocument(
        familyId,
        connectionCode,
        elderlyName,
      );
      if (success) {
        return connectionCode;
      }
      return null;
    } catch (e) {
      AppLogger.error('Failed to setup family code: $e', tag: 'FirebaseService');
      return null;
    }
  }
  
  Future<String> _generateUniqueFamilyId() async {
    String familyId;
    bool isUnique = false;
    int attempts = 0;
    const maxAttempts = 100; // Increased attempts for better reliability

    do {
      familyId = FamilyIdGenerator.generateFamilyId();

      // Use connection_codes collection to check family ID uniqueness
      // Since we create the connection_codes document first, we can check if familyId already exists there
      final query = await _firestore
          .collection('connection_codes')
          .where('familyId', isEqualTo: familyId)
          .limit(1)
          .get();
      isUnique = query.docs.isEmpty;

      attempts++;
      if (attempts >= maxAttempts && !isUnique) {
        throw Exception('Failed to generate unique family ID after $maxAttempts attempts');
      }
    } while (!isUnique);

    return familyId;
  }

  // Set up family document with unique ID and connection code
  Future<bool> _setupFamilyDocument(
    String familyId,
    String connectionCode,
    String elderlyName,
  ) async {
    try {
      // Ensure user is authenticated
      await _authManager.ensureAuthenticated();

      final currentUserId = _authManager.currentUserId;
      if (currentUserId == null || currentUserId.isEmpty) {
        AppLogger.error('No valid user ID available', tag: 'FirebaseService');
        return false;
      }

      AppLogger.info('Creating family document with user ID: $currentUserId', tag: 'FirebaseService');

      // Create connection code lookup document for secure family joining
      // IMPORTANT: Using .add() instead of .doc() to generate random document ID
      // Child app expects 'code' as a FIELD, not document ID
      await _firestore.collection('connection_codes').add({
        'code': connectionCode,        // Child app queries by this field
        'familyId': familyId,
        'elderlyName': elderlyName,
        'isActive': true,              // Required by child app, set to false after first use
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Create family document with unique ID
      // NOTE: Encryption key is DERIVED from familyId, NOT stored in Firestore
      await _firestore.collection('families').doc(familyId).set({
        'familyId': familyId,
        'connectionCode': connectionCode,
        'elderlyName': elderlyName,
        'createdAt': FieldValue.serverTimestamp(),
        'deviceInfo': 'Android Device',
        'isActive': true,
        'approved': null, // null = pending, true = approved, false = rejected
        // Security fields for Firebase rules
        'createdBy': currentUserId,
        'memberIds': [currentUserId],
        'settings': {
          'survivalSignalEnabled': false,
          'familyContact': '',
          'alertHours': 12,
        },
        'alerts': {
          'survival': null,  // timestamp when active, null when inactive
          'food': null       // timestamp when active, null when inactive
        },
        'lastMeal': {
          'timestamp': null,
          'count': 0,
          'number': null
        },
        'location': {
          'encrypted': null,
          'iv': null,
          'timestamp': null,
        },
        'lastPhoneActivity': null, // Initialize field for phone activity tracking
      });

      // Save locally using storage manager
      await _storage.setString('family_id', familyId);
      await _storage.setString('family_code', connectionCode);
      await _storage.setString('elderly_name', elderlyName);

      _familyId = familyId;
      _familyCode = connectionCode;
      _elderlyName = elderlyName;

      return true;
    } catch (e) {
      AppLogger.error('Failed to setup family document: $e', tag: 'FirebaseService');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getFamilyInfo(String connectionCode) async {
    final data = await _familyData.getFamilyInfo(connectionCode);
    
    // Update local storage if we don't have family ID
    if (data != null && _familyId == null) {
      _familyId = data['familyId'] as String;
      await _storage.setString('family_id', _familyId!);
    }
    
    return data;
  }

  // Save meal record with simplified approach
  Future<bool> saveMealRecord({
    required DateTime timestamp,
    required int mealNumber,
  }) async {
    try {
      if (_familyCode == null || _familyId == null) {
        AppLogger.error('CRITICAL: No family code or ID available - familyCode: $_familyCode, familyId: $_familyId', tag: 'FirebaseService');
        return false;
      }
      
      AppLogger.info('Meal recording with familyId: $_familyId, familyCode: $_familyCode', tag: 'FirebaseService');

      // Ensure authentication
      if (!await _authManager.ensureAuthenticated()) {
        AppLogger.error('Authentication failed', tag: 'FirebaseService');
        return false;
      }

      // CRITICAL FIX: Force immediate activity update before meal recording
      AppLogger.info('Forcing immediate activity update before meal recording', tag: 'FirebaseService');
      await updatePhoneActivity(forceImmediate: true);

      // Get today's date string
      final today = DateTime.now();
      final dateString =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      // Create meal record with unique ID to prevent duplicates
      final mealId = '${timestamp.millisecondsSinceEpoch}_$mealNumber';
      final mealData = {
        'mealId': mealId,
        'timestamp': timestamp.toIso8601String(),
        'mealNumber': mealNumber,
        'elderlyName': _elderlyName,
        'createdAt': timestamp
            .toIso8601String(), // Use regular timestamp instead of serverTimestamp
      };

      // Use simpler approach with FieldValue.arrayUnion
      await _firestore
          .collection('families')
          .doc(_familyId)
          .collection('meals')
          .doc(dateString)
          .set({
            'meals': FieldValue.arrayUnion([mealData]),
            'date': dateString,
            'elderlyName': _elderlyName,
          }, SetOptions(merge: true));

      // Get current meal count from the document we just updated
      final updatedDoc = await _firestore
          .collection('families')
          .doc(_familyId)
          .collection('meals')
          .doc(dateString)
          .get();

      final currentMealCount = updatedDoc.exists
          ? (updatedDoc.data()?['meals'] as List<dynamic>?)?.length ?? 0
          : 0;

      // Update family document with simplified meal structure
      await _firestore.collection('families').doc(_familyId).update({
        'lastMeal': {
          'timestamp': FieldValue.serverTimestamp(),
          'count': currentMealCount,
          'number': mealNumber,
        },
      });

      // Send FCM notification to child app
      try {
        await FCMv1Service.sendMealNotification(
          familyId: _familyId!,
          elderlyName: _elderlyName ?? '부모님',
          timestamp: timestamp,
          mealNumber: mealNumber,
        );
        AppLogger.info('FCM meal notification sent successfully', tag: 'FirebaseService');
      } catch (e) {
        AppLogger.error('Failed to send FCM meal notification: $e', tag: 'FirebaseService');
        // Don't fail the entire meal recording if FCM fails
      }

      AppLogger.info('Meal recording completed, activity updated in Firebase', tag: 'FirebaseService');
      return true;
    } catch (e) {
      AppLogger.error('Failed to save meal record: $e', tag: 'FirebaseService');
      return false;
    }
  }

  // Get today's meal count from subcollection only
  Future<int> getTodayMealCount() async {
    try {
      if (_familyCode == null || _familyId == null) return 0;

      final today = DateTime.now();
      final dateString =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      // Get count from meals subcollection only (single source of truth)
      final mealDoc = await _firestore
          .collection('families')
          .doc(_familyId)
          .collection('meals')
          .doc(dateString)
          .get();

      if (mealDoc.exists) {
        final data = mealDoc.data();
        final meals = data?['meals'] as List<dynamic>?;
        return meals?.length ?? 0;
      }

      return 0; // No meals recorded today
    } catch (e) {
      AppLogger.error('Failed to get today\'s meal count: $e', tag: 'FirebaseService');
      return 0;
    }
  }

  Future<String?> getFamilyIdFromConnectionCode(String connectionCode) async {
    return await _familyData.getFamilyIdFromConnectionCode(connectionCode);
  }

  Future<Map<String, dynamic>?> getFamilyDataForChild(String connectionCode) async {
    return await _familyData.getFamilyDataForChild(connectionCode);
  }

  // Child app method to get meals for a specific date
  Future<List<Map<String, dynamic>>> getMealsForDate(
    String connectionCode,
    DateTime date,
  ) async {
    try {
      final familyId = await getFamilyIdFromConnectionCode(connectionCode);
      if (familyId == null) return [];

      final dateString =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      final doc = await _firestore
          .collection('families')
          .doc(familyId)
          .collection('meals')
          .doc(dateString)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final meals = data?['meals'] as List<dynamic>? ?? [];
        return meals.map((meal) => Map<String, dynamic>.from(meal)).toList();
      }

      return [];
    } catch (e) {
      AppLogger.error('Failed to get meals for date: $e', tag: 'FirebaseService');
      return [];
    }
  }

  // Update family settings
  Future<bool> updateFamilySettings({
    required bool survivalSignalEnabled,
    required String familyContact,
    int? alertHours,
    Map<String, dynamic>? sleepTimeSettings,
  }) async {
    if (_familyId == null) {
      AppLogger.warning('Cannot update family settings: no family ID', tag: 'FirebaseService');
      return false;
    }

    return await _familyData.updateFamilySettings(
      _familyId!,
      survivalSignalEnabled: survivalSignalEnabled,
      familyContact: familyContact,
      alertHours: alertHours,
      sleepTimeSettings: sleepTimeSettings,
    );
  }

  // Delete family code from Firebase
  Future<bool> deleteFamilyCode(String connectionCode) async {
    try {
      // Find family by connection code
      final query = await _firestore
          .collection('families')
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        await doc.reference.delete();

        // Clear local storage if this was our code
        if (_familyCode == connectionCode) {
          await _storage.remove('family_id');
          await _storage.remove('family_code');
          await _storage.remove('elderly_name');
          _familyId = null;
          _familyCode = null;
          _elderlyName = null;
        }

        return true;
      }

      return false;
    } catch (e) {
      AppLogger.error('Failed to delete family code: $e', tag: 'FirebaseService');
      return false;
    }
  }

  Stream<bool?> listenForApproval(String connectionCode) {
    return _familyData.listenForApproval(connectionCode);
  }

  Future<bool> setApprovalStatus(String connectionCode, bool approved) async {
    await _authManager.ensureAuthenticated();
    final userId = _authManager.currentUserId;
    
    if (userId == null) {
      AppLogger.error('User not authenticated', tag: 'FirebaseService');
      return false;
    }

    return await _familyData.setApprovalStatus(connectionCode, approved, userId);
  }

  // Force immediate activity update (for survival signal activation)
  Future<bool> forceActivityUpdate() async {
    try {
      if (_familyId == null) {
        AppLogger.warning('Cannot force activity update: no family ID', tag: 'FirebaseService');
        return false;
      }
      
      await _firestore.collection('families').doc(_familyId).update({
        'lastPhoneActivity': FieldValue.serverTimestamp(),
        'lastActivityType': 'survival_signal_activation',
        'updateTimestamp': FieldValue.serverTimestamp(),
      });
      
      _activityBatcher.recordBatch();
      AppLogger.info('Forced activity update sent to Firebase', tag: 'FirebaseService');
      return true;
    } catch (e) {
      AppLogger.error('Failed to force activity update: $e', tag: 'FirebaseService');
      return false;
    }
  }
  
  // Send survival alert to family
  Future<bool> sendSurvivalAlert({
    required String familyCode,
    required String elderlyName,
    required String message,
  }) async {
    try {
      // familyCode parameter should actually be familyId for this method
      // since it's called internally with the stored familyId
      await _firestore.collection('families').doc(familyCode).update({
        'alerts.survival': FieldValue.serverTimestamp(),
      });

      // Send FCM notification for survival alert
      try {
        // Extract hours from message (assumes format like "12시간 이상...")
        final hoursMatch = RegExp(r'(\d+)시간').firstMatch(message);
        final hoursInactive = hoursMatch != null
            ? int.parse(hoursMatch.group(1)!)
            : 12;

        await FCMv1Service.sendSurvivalAlert(
          familyId: familyCode,
          elderlyName: elderlyName,
          hoursInactive: hoursInactive,
        );
        AppLogger.info('FCM survival alert notification sent', tag: 'FirebaseService');
      } catch (e) {
        AppLogger.error('Failed to send FCM survival alert notification: $e', tag: 'FirebaseService');
        // Don't fail the entire alert if FCM fails
      }

      AppLogger.info('Survival alert sent to family: $familyCode', tag: 'FirebaseService');
      return true;
    } catch (e) {
      AppLogger.error('Failed to send survival alert: $e', tag: 'FirebaseService');
      return false;
    }
  }

  // Clear survival alert
  Future<bool> clearSurvivalAlert() async {
    try {
      if (_familyId == null) return false;

      await _firestore.collection('families').doc(_familyId).update({
        'alerts.survival': null,
      });

      AppLogger.info('Survival alert cleared', tag: 'FirebaseService');
      return true;
    } catch (e) {
      AppLogger.error('Failed to clear survival alert: $e', tag: 'FirebaseService');
      return false;
    }
  }

  // Send food alert to family
  Future<bool> sendFoodAlert({
    required String elderlyName,
    required String message,
    DateTime? lastFoodIntake,
    int? hoursWithoutFood,
  }) async {
    try {
      if (_familyId == null) {
        AppLogger.warning('Cannot send food alert: no family ID', tag: 'FirebaseService');
        return false;
      }

      await _firestore.collection('families').doc(_familyId).update({
        'alerts.food': FieldValue.serverTimestamp(),
      });

      // Send FCM notification for food alert
      try {
        await FCMv1Service.sendFoodAlert(
          familyId: _familyId!,
          elderlyName: elderlyName,
          hoursWithoutFood: hoursWithoutFood ?? 8,
        );
        AppLogger.info('FCM food alert notification sent', tag: 'FirebaseService');
      } catch (e) {
        AppLogger.error('Failed to send FCM food alert notification: $e', tag: 'FirebaseService');
        // Don't fail the entire alert if FCM fails
      }

      AppLogger.info('Food alert sent to family: $message', tag: 'FirebaseService');
      return true;
    } catch (e) {
      AppLogger.error('Failed to send food alert: $e', tag: 'FirebaseService');
      return false;
    }
  }

  // Clear food alert
  Future<bool> clearFoodAlert() async {
    try {
      if (_familyId == null) return false;

      await _firestore.collection('families').doc(_familyId).update({
        'alerts.food': null,
      });

      AppLogger.info('Food alert cleared', tag: 'FirebaseService');
      return true;
    } catch (e) {
      AppLogger.error('Failed to clear food alert: $e', tag: 'FirebaseService');
      return false;
    }
  }

  // Update food intake information
  Future<bool> updateFoodIntake({
    required DateTime timestamp,
    required int todayCount,
  }) async {
    try {
      if (_familyId == null) {
        AppLogger.warning('Cannot update food intake: no family ID', tag: 'FirebaseService');
        return false;
      }

      await _firestore.collection('families').doc(_familyId).update({
        'lastMeal': {
          'timestamp': FieldValue.serverTimestamp(),
          'count': todayCount,
          'number': null, // Unknown meal number when called from this method
        },
        'alerts.food': null, // Clear any active food alerts
      });

      AppLogger.info('Food intake updated: $timestamp, count: $todayCount', tag: 'FirebaseService');
      return true;
    } catch (e) {
      AppLogger.error('Failed to update food intake: $e', tag: 'FirebaseService');
      return false;
    }
  }

  Future<bool> updatePhoneActivity({bool forceImmediate = false}) async {
    try {
      if (_familyId == null) {
        AppLogger.error('CRITICAL: Cannot update phone activity - familyId: $_familyId', tag: 'FirebaseService');
        return false;
      }
      
      AppLogger.info('Activity update - familyId: $_familyId, forceImmediate: $forceImmediate', tag: 'FirebaseService');
      
      // Check if we should batch this update
      if (_activityBatcher.shouldBatchUpdate(forceImmediate: forceImmediate)) {
        AppLogger.debug('Batching activity update', tag: 'FirebaseService');
        return true;
      }
      
      // Send update to Firebase
      await _firestore.collection('families').doc(_familyId).update({
        'lastPhoneActivity': FieldValue.serverTimestamp(),
        'lastActivityType': _activityBatcher.isFirstActivity ? 'first_activity' : 'batched_activity',
        'updateTimestamp': FieldValue.serverTimestamp(),
      });
      
      _activityBatcher.recordBatch();
      AppLogger.info('Activity update sent to Firebase', tag: 'FirebaseService');
      return true;
    } catch (e) {
      AppLogger.error('Failed to update phone activity: $e', tag: 'FirebaseService');
      return false;
    }
  }

  Future<bool> updateLocation({
    required double latitude,
    required double longitude,
    String? address,
    bool forceUpdate = false,
  }) async {
    try {
      if (_familyId == null) {
        AppLogger.warning('Cannot update location: no family ID', tag: 'FirebaseService');
        return false;
      }
      
      // Check if location update should be throttled
      if (!forceUpdate && _locationThrottler.shouldThrottleUpdate(latitude, longitude)) {
        AppLogger.debug('Location update throttled', tag: 'FirebaseService');
        return true;
      }

      // Get encryption key
      final encryptionKey = await _getEncryptionKey();

      // Encrypt location data
      final encryptedData = EncryptionService.encryptLocation(
        latitude: latitude,
        longitude: longitude,
        address: address ?? '',
        base64Key: encryptionKey,
      );

      await _firestore.collection('families').doc(_familyId).update({
        'location': {
          'encrypted': encryptedData['encrypted'],
          'iv': encryptedData['iv'],
          'timestamp': FieldValue.serverTimestamp(),
        },
      });

      _locationThrottler.recordUpdate(latitude, longitude);
      AppLogger.info('Encrypted location updated in Firebase: $latitude, $longitude', tag: 'FirebaseService');
      return true;
    } catch (e) {
      AppLogger.error('Failed to update location: $e', tag: 'FirebaseService');
      return false;
    }
  }

  Future<bool> forceLocationUpdate({
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    return await updateLocation(
      latitude: latitude,
      longitude: longitude,
      address: address,
      forceUpdate: true,
    );
  }

  // Update alert settings in Firebase for Functions to use
  Future<bool> updateAlertSettings({required int alertMinutes}) async {
    try {
      if (_familyId == null) {
        AppLogger.warning('Cannot update alert settings: no family ID', tag: 'FirebaseService');
        return false;
      }

      await _firestore.collection('families').doc(_familyId).update({
        'settings': {
          'alertHours': alertMinutes / 60.0, // Convert minutes to hours for consistency
        },
      });

      AppLogger.info('Alert settings updated: ${alertMinutes} minutes (${alertMinutes/60.0} hours)', tag: 'FirebaseService');
      return true;
    } catch (e) {
      AppLogger.error('Failed to update alert settings: $e', tag: 'FirebaseService');
      return false;
    }
  }

  // Data Recovery Methods for App Reinstallation

  // 8-digit recovery code method removed - use name + connection code instead

  // NEW: Name + Connection Code Recovery System
  
  // Attempt to recover account using name and connection code
  Future<Map<String, dynamic>?> recoverAccountWithNameAndCode({
    required String name,
    required String connectionCode,
  }) async {
    try {
      AppLogger.info('Attempting account recovery with name: $name, connection code: $connectionCode', tag: 'FirebaseService');
      
      // First, get all families with the given connection code
      final query = await _firestore
          .collection('families')
          .where('connectionCode', isEqualTo: connectionCode)
          .get();

      if (query.docs.isEmpty) {
        AppLogger.warning('No family found with connection code: $connectionCode', tag: 'FirebaseService');
        return {
          'success': false, 
          'error': 'connection_code_not_found',
          'message': '연결 코드를 찾을 수 없습니다. 코드를 다시 확인해주세요.'
        };
      }

      // Check name matching with fuzzy logic
      final candidates = <Map<String, dynamic>>[];
      
      for (final doc in query.docs) {
        final data = doc.data();
        final elderlyName = data['elderlyName'] as String? ?? '';
        final familyId = doc.id;
        
        final matchScore = _calculateNameMatchScore(name, elderlyName);
        
        if (matchScore >= 0.7) { // 70% similarity threshold
          candidates.add({
            'familyId': familyId,
            'data': data,
            'matchScore': matchScore,
            'elderlyName': elderlyName,
          });
        }
      }

      if (candidates.isEmpty) {
        AppLogger.warning('No name match found for: $name', tag: 'FirebaseService');
        return {
          'success': false,
          'error': 'name_not_match',
          'message': '이름이 일치하지 않습니다. 등록된 이름을 다시 확인해주세요.'
        };
      }

      if (candidates.length > 1) {
        // Multiple matches - return them for user to choose
        AppLogger.info('Multiple name matches found: ${candidates.length}', tag: 'FirebaseService');
        return {
          'success': false,
          'error': 'multiple_matches',
          'message': '여러 개의 일치하는 계정이 발견되었습니다.',
          'candidates': candidates.map((c) => {
            'familyId': c['familyId'],
            'elderlyName': c['elderlyName'],
            'matchScore': c['matchScore'],
          }).toList(),
        };
      }

      // Single match found - proceed with recovery
      final bestMatch = candidates.first;
      final familyId = bestMatch['familyId'] as String;
      final data = bestMatch['data'] as Map<String, dynamic>;
      
      // Restore local data
      await _restoreLocalData(
        familyId: familyId,
        connectionCode: data['connectionCode'],
        elderlyName: data['elderlyName'],
        // recoveryCode removed - using name + connection code only
      );
      
      AppLogger.info('Name + connection code recovery successful for: ${data['elderlyName']}', tag: 'FirebaseService');
      return {
        'success': true,
        'familyId': familyId,
        'connectionCode': data['connectionCode'],
        'elderlyName': data['elderlyName'],
        // recoveryCode field removed from recovery data
        'mealCount': (data['lastMeal'] as Map?)?['count'] ?? 0,
        'matchScore': bestMatch['matchScore'],
      };
    } catch (e) {
      AppLogger.error('Name + connection code recovery failed: $e', tag: 'FirebaseService');
      return {'success': false, 'error': 'recovery_failed', 'message': '복구 중 오류가 발생했습니다: $e'};
    }
  }
  
  // Fuzzy Korean name matching with various Korean name patterns
  double _calculateNameMatchScore(String inputName, String storedName) {
    if (inputName.isEmpty || storedName.isEmpty) return 0.0;
    
    // Normalize names (remove spaces and convert to lowercase)
    final normalizedInput = inputName.replaceAll(' ', '').toLowerCase();
    final normalizedStored = storedName.replaceAll(' ', '').toLowerCase();
    
    // Exact match
    if (normalizedInput == normalizedStored) return 1.0;
    
    // Check if one contains the other (for cases like "김할머니" vs "김○○")
    if (normalizedStored.contains(normalizedInput) || normalizedInput.contains(normalizedStored)) {
      final minLength = [normalizedInput.length, normalizedStored.length].reduce((a, b) => a < b ? a : b);
      final maxLength = [normalizedInput.length, normalizedStored.length].reduce((a, b) => a > b ? a : b);
      return minLength / maxLength;
    }
    
    // Korean name pattern matching
    final koreanPatterns = [
      // Handle cases like "김할머니" -> "김○○할머니", "김○○"
      _handleKoreanSurnamePatterns(normalizedInput, normalizedStored),
      // Handle honorific suffixes (할머니, 할아버지, 어머니, 아버지, etc.)
      _handleHonorificPatterns(normalizedInput, normalizedStored),
      // Handle middle character variations (김철수 vs 김○수)
      _handleMiddleCharacterPatterns(normalizedInput, normalizedStored),
    ];
    
    double maxScore = 0.0;
    for (final score in koreanPatterns) {
      if (score > maxScore) maxScore = score;
    }
    
    // Fallback to Levenshtein distance for general similarity
    if (maxScore < 0.5) {
      maxScore = _calculateLevenshteinSimilarity(normalizedInput, normalizedStored);
    }
    
    return maxScore;
  }
  
  // Handle Korean surname patterns (김할머니 vs 김○○)
  double _handleKoreanSurnamePatterns(String input, String stored) {
    final koreanSurnamePattern = RegExp(r'^[가-힣]');
    
    if (!koreanSurnamePattern.hasMatch(input) || !koreanSurnamePattern.hasMatch(stored)) {
      return 0.0;
    }
    
    // Extract first character (surname)
    final inputSurname = input.substring(0, 1);
    final storedSurname = stored.substring(0, 1);
    
    if (inputSurname != storedSurname) return 0.0;
    
    // Handle patterns like "김○○" or "김**"
    if (stored.contains('○') || stored.contains('*') || stored.contains('◯')) {
      return 0.8; // High confidence for masked names
    }
    
    if (input.contains('○') || input.contains('*') || input.contains('◯')) {
      return 0.8;
    }
    
    return 0.0;
  }
  
  // Handle honorific patterns (할머니, 할아버지, etc.)
  double _handleHonorificPatterns(String input, String stored) {
    final honorifics = ['할머니', '할아버지', '어머니', '아버지', '엄마', '아빠', '부모님'];
    
    String inputBase = input;
    String storedBase = stored;
    bool foundHonorific = false;
    
    // Remove honorifics to get base names
    for (final honorific in honorifics) {
      if (input.endsWith(honorific)) {
        inputBase = input.substring(0, input.length - honorific.length);
        foundHonorific = true;
      }
      if (stored.endsWith(honorific)) {
        storedBase = stored.substring(0, stored.length - honorific.length);
        foundHonorific = true;
      }
    }
    
    if (!foundHonorific) return 0.0;
    
    // Compare base names
    if (inputBase == storedBase) return 0.9;
    if (inputBase.isNotEmpty && storedBase.isNotEmpty) {
      return _calculateLevenshteinSimilarity(inputBase, storedBase) * 0.8;
    }
    
    return 0.0;
  }
  
  // Handle middle character variations (김철수 vs 김○수)
  double _handleMiddleCharacterPatterns(String input, String stored) {
    if (input.length != stored.length || input.length < 2) return 0.0;
    
    int matchCount = 0;
    int totalChars = input.length;
    
    for (int i = 0; i < totalChars; i++) {
      final inputChar = input[i];
      final storedChar = stored[i];
      
      if (inputChar == storedChar) {
        matchCount++;
      } else if (storedChar == '○' || storedChar == '*' || storedChar == '◯' ||
                inputChar == '○' || inputChar == '*' || inputChar == '◯') {
        matchCount++; // Treat wildcards as matches
      }
    }
    
    return matchCount / totalChars;
  }
  
  // Calculate Levenshtein distance similarity
  double _calculateLevenshteinSimilarity(String s1, String s2) {
    if (s1.isEmpty) return s2.isEmpty ? 1.0 : 0.0;
    if (s2.isEmpty) return 0.0;
    
    final matrix = List.generate(
      s1.length + 1,
      (_) => List.filled(s2.length + 1, 0),
    );
    
    // Initialize first row and column
    for (int i = 0; i <= s1.length; i++) matrix[i][0] = i;
    for (int j = 0; j <= s2.length; j++) matrix[0][j] = j;
    
    // Fill matrix
    for (int i = 1; i <= s1.length; i++) {
      for (int j = 1; j <= s2.length; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,      // deletion
          matrix[i][j - 1] + 1,      // insertion
          matrix[i - 1][j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    
    final maxLength = [s1.length, s2.length].reduce((a, b) => a > b ? a : b);
    return 1.0 - (matrix[s1.length][s2.length] / maxLength);
  }
  
  // Auto-detect existing accounts by searching for potential matches
  Future<List<Map<String, dynamic>>> autoDetectExistingAccounts() async {
    try {
      AppLogger.info('Starting auto-detection of existing accounts...', tag: 'FirebaseService');
      
      // Get all families to check for potential matches
      // In a real scenario, you might want to limit this or use better indexing
      final query = await _firestore
          .collection('families')
          .where('isActive', isEqualTo: true)
          .limit(50) // Reasonable limit for auto-detection
          .get();

      if (query.docs.isEmpty) {
        AppLogger.info('No active families found for auto-detection', tag: 'FirebaseService');
        return [];
      }

      final candidates = <Map<String, dynamic>>[];
      
      // Look for families that might belong to this device
      for (final doc in query.docs) {
        final data = doc.data();
        final familyId = doc.id;
        
        // Check various criteria for potential matches
        final confidence = _calculateAutoDetectionConfidence(data);
        
        if (confidence >= 0.3) { // 30% confidence threshold for auto-detection
          candidates.add({
            'familyId': familyId,
            'elderlyName': data['elderlyName'],
            'connectionCode': data['connectionCode'],
            'confidence': confidence,
            'lastActivity': data['lastPhoneActivity'],
            'mealCount': (data['lastMeal'] as Map?)?['count'] ?? 0,
          });
        }
      }

      // Sort by confidence score
      candidates.sort((a, b) => (b['confidence'] as double).compareTo(a['confidence'] as double));
      
      AppLogger.info('Auto-detection found ${candidates.length} potential matches', tag: 'FirebaseService');
      return candidates.take(5).toList(); // Return top 5 candidates
    } catch (e) {
      AppLogger.error('Auto-detection failed: $e', tag: 'FirebaseService');
      return [];
    }
  }
  
  // Calculate auto-detection confidence based on various factors
  double _calculateAutoDetectionConfidence(Map<String, dynamic> data) {
    double confidence = 0.0;
    
    // Check recent activity (higher confidence for recently active accounts)
    final lastActivity = data['lastPhoneActivity'];
    if (lastActivity != null) {
      final lastActivityTime = lastActivity is Timestamp 
          ? lastActivity.toDate() 
          : DateTime.tryParse(lastActivity.toString());
      
      if (lastActivityTime != null) {
        final daysSinceActivity = DateTime.now().difference(lastActivityTime).inDays;
        if (daysSinceActivity <= 7) {
          confidence += 0.5; // Recent activity within a week
        } else if (daysSinceActivity <= 30) {
          confidence += 0.3; // Activity within a month
        }
      }
    }
    
    // Check if account has meal records (indicates active usage)
    final mealCount = (data['lastMeal'] as Map?)?['count'] ?? 0;
    if (mealCount > 0) {
      confidence += 0.2;
    }
    
    // Check if survival signal is enabled (indicates setup completion)
    final survivalEnabled = data['settings']?['survivalSignalEnabled'] ?? false;
    if (survivalEnabled) {
      confidence += 0.2;
    }
    
    // Check if account is approved by child app
    final approved = data['approved'];
    if (approved == true) {
      confidence += 0.3;
    }
    
    return confidence.clamp(0.0, 1.0);
  }
  
  // Get connection codes for child app recovery helper
  Future<List<Map<String, dynamic>>> getConnectionCodesForRecovery() async {
    try {
      AppLogger.info('Getting connection codes for recovery helper...', tag: 'FirebaseService');
      
      // Get active families (this would typically be called from child app)
      final query = await _firestore
          .collection('families')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

      final codes = <Map<String, dynamic>>[];
      
      for (final doc in query.docs) {
        final data = doc.data();
        codes.add({
          'connectionCode': data['connectionCode'],
          'elderlyName': data['elderlyName'],
          'familyId': doc.id,
          'approved': data['approved'],
          'lastActivity': data['lastPhoneActivity'],
          'createdAt': data['createdAt'],
        });
      }
      
      AppLogger.info('Retrieved ${codes.length} connection codes for recovery', tag: 'FirebaseService');
      return codes;
    } catch (e) {
      AppLogger.error('Failed to get connection codes for recovery: $e', tag: 'FirebaseService');
      return [];
    }
  }

  Future<void> _restoreLocalData({
    required String familyId,
    required String connectionCode,
    required String elderlyName,
  }) async {
    try {
      await _storage.setString('family_id', familyId);
      await _storage.setString('family_code', connectionCode);
      await _storage.setString('elderly_name', elderlyName);
      await _storage.setBool('setup_complete', true);
      
      // Update instance variables
      _familyId = familyId;
      _familyCode = connectionCode;
      _elderlyName = elderlyName;
      
      AppLogger.info('Local data restored successfully', tag: 'FirebaseService');
    } catch (e) {
      AppLogger.error('Failed to restore local data: $e', tag: 'FirebaseService');
      throw e;
    }
  }

  // Recovery code display removed - using name + connection code only

  Future<bool> hasExistingAccountData() async {
    final familyCode = await _storage.getString('family_code');
    return familyCode != null;
  }

  // Getters
  String? get familyId => _familyId;
  String? get familyCode => _familyCode;
  String? get elderlyName => _elderlyName;
  bool get isSetup => _familyCode != null && _familyId != null;

  // Recovery code getter removed - using name + connection code only

  // Helper method to get and cache encryption key
  // SECURITY: Key is DERIVED from familyId, NOT fetched from Firestore
  Future<String> _getEncryptionKey() async {
    if (_cachedEncryptionKey != null) {
      return _cachedEncryptionKey!;
    }

    if (_familyId == null) {
      throw Exception('Cannot derive encryption key: no family ID');
    }

    try {
      // Derive key from familyId (same key will be derived by child app)
      _cachedEncryptionKey = EncryptionService.deriveEncryptionKey(_familyId!);
      AppLogger.debug('Encryption key derived and cached from familyId', tag: 'FirebaseService');
      return _cachedEncryptionKey!;
    } catch (e) {
      AppLogger.error('Failed to derive encryption key: $e', tag: 'FirebaseService');
      rethrow;
    }
  }
}
