import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thanks_everyday/services/fcm_v1_service.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';
import 'dart:math' show sin, cos, asin, sqrt, Random;
// dart:convert import removed - not used in current implementation
import 'dart:typed_data';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _familyId;
  String? _familyCode;
  String? _elderlyName;
  
  // Activity batching variables
  DateTime? _lastActivityBatch;
  DateTime? _lastScreenActivity;
  static const Duration _activityBatchInterval = Duration(hours: 2);
  static const Duration _longInactivityThreshold = Duration(hours: 8);
  
  // Location throttling variables
  double? _lastStoredLatitude;
  double? _lastStoredLongitude;
  DateTime? _lastLocationUpdate;
  static const double _significantDistanceKm = 0.5; // Reduced to 500m threshold for better tracking

  // Initialize Firebase and check for existing family code
  Future<bool> initialize() async {
    try {
      // Initialize FCM v1 service
      await FCMv1Service.initialize();

      // Sign in anonymously for Firebase Auth with retry logic
      int authRetryCount = 0;
      const maxAuthRetries = 3;
      
      while (_auth.currentUser == null && authRetryCount < maxAuthRetries) {
        try {
          AppLogger.info('Attempting Firebase Auth (attempt ${authRetryCount + 1}/$maxAuthRetries)', tag: 'FirebaseService');
          await _auth.signInAnonymously();
          AppLogger.info('Firebase Auth successful', tag: 'FirebaseService');
          break;
        } catch (authError) {
          authRetryCount++;
          AppLogger.warning('Firebase Auth attempt $authRetryCount failed: $authError', tag: 'FirebaseService');
          
          if (authRetryCount < maxAuthRetries) {
            await Future.delayed(Duration(milliseconds: 1000 * authRetryCount));
          } else {
            AppLogger.warning('All Firebase Auth attempts failed, continuing without auth', tag: 'FirebaseService');
            // This will cause Firestore operations to fail, but app won't crash
          }
        }
      }

      // Check if family code exists locally with retry logic
      SharedPreferences? prefs;
      int retryCount = 0;
      const maxRetries = 3;

      while (prefs == null && retryCount < maxRetries) {
        try {
          prefs = await SharedPreferences.getInstance();
        } catch (e) {
          AppLogger.error('SharedPreferences attempt ${retryCount + 1} failed: $e', tag: 'FirebaseService');
          retryCount++;
          if (retryCount < maxRetries) {
            await Future.delayed(Duration(milliseconds: 500 * retryCount));
          }
        }
      }

      if (prefs != null) {
        _familyId = prefs.getString('family_id');
        _familyCode = prefs.getString('family_code');
        _elderlyName = prefs.getString('elderly_name');
      } else {
        AppLogger.warning('SharedPreferences failed completely, using in-memory storage', tag: 'FirebaseService');
        // If SharedPreferences fails, we'll continue without local storage
        // The app will still work but won't persist the family code
      }

      return _familyCode != null;
    } catch (e) {
      AppLogger.error('Firebase initialization failed: $e', tag: 'FirebaseService');
      return false;
    }
  }

  // Generate a unique 4-digit connection code
  Future<String> _generateConnectionCode() async {
    String code;
    bool isUnique = false;

    do {
      // Generate 4-digit code
      code = (1000 + Random().nextInt(9000)).toString();

      // Check if connection code already exists
      final query = await _firestore
          .collection('families')
          .where('connectionCode', isEqualTo: code)
          .limit(1)
          .get();
      isUnique = query.docs.isEmpty;
    } while (!isUnique);

    return code;
  }

  // Generate a cryptographically secure unique family ID using UUID v4
  String _generateFamilyId() {
    // Generate a UUID v4 using cryptographically secure random bytes
    final random = Random.secure();
    
    // Generate 16 random bytes for UUID
    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = random.nextInt(256);
    }
    
    // Set version (4) and variant bits according to RFC 4122
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant bits
    
    // Convert to UUID string format
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final uuid = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
    
    return 'family_$uuid';
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
  
  // Generate a unique family ID with collision detection
  Future<String> _generateUniqueFamilyId() async {
    String familyId;
    bool isUnique = false;
    int attempts = 0;
    const maxAttempts = 5;
    
    do {
      familyId = _generateFamilyId();
      
      // Check if family ID already exists in Firestore
      final docSnapshot = await _firestore.collection('families').doc(familyId).get();
      isUnique = !docSnapshot.exists;
      
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
      if (_auth.currentUser == null) {
        AppLogger.info('User not authenticated, attempting to sign in...', tag: 'FirebaseService');
        try {
          await _auth.signInAnonymously();
          AppLogger.info('Anonymous sign-in successful', tag: 'FirebaseService');
        } catch (authError) {
          AppLogger.error('Failed to authenticate: $authError', tag: 'FirebaseService');
          return false;
        }
      }

      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null || currentUserId.isEmpty) {
        AppLogger.error('No valid user ID available', tag: 'FirebaseService');
        return false;
      }

      AppLogger.info('Creating family document with user ID: $currentUserId', tag: 'FirebaseService');

      // Create connection code lookup document for secure family joining
      await _firestore.collection('connection_codes').doc(connectionCode).set({
        'familyId': familyId,
        'elderlyName': elderlyName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Create family document with unique ID
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
          'latitude': null,
          'longitude': null,
          'timestamp': null,
          'address': '',
        },
        'lastPhoneActivity': null, // Initialize field for phone activity tracking
      });

      // Save locally with retry logic
      SharedPreferences? prefs;
      int retryCount = 0;
      const maxRetries = 3;

      while (prefs == null && retryCount < maxRetries) {
        try {
          prefs = await SharedPreferences.getInstance();
        } catch (e) {
          AppLogger.error('SharedPreferences setup attempt ${retryCount + 1} failed: $e', tag: 'FirebaseService');
          retryCount++;
          if (retryCount < maxRetries) {
            await Future.delayed(Duration(milliseconds: 500 * retryCount));
          }
        }
      }

      if (prefs != null) {
        await prefs.setString('family_id', familyId);
        await prefs.setString('family_code', connectionCode);
        await prefs.setString('elderly_name', elderlyName);
      }

      _familyId = familyId;
      _familyCode = connectionCode;
      _elderlyName = elderlyName;

      return true;
    } catch (e) {
      AppLogger.error('Failed to setup family document: $e', tag: 'FirebaseService');
      return false;
    }
  }

  // Verify family code exists (for family members)
  Future<Map<String, dynamic>?> getFamilyInfo(String connectionCode) async {
    try {
      // FIXED: Use connection code lookup instead of direct family access during setup
      AppLogger.info('Getting family info using connection code: $connectionCode', tag: 'FirebaseService');
      
      // First, resolve family ID from secure connection code lookup
      final connectionDoc = await _firestore
          .collection('connection_codes')
          .doc(connectionCode)
          .get();

      if (!connectionDoc.exists) {
        AppLogger.error('No connection code found: $connectionCode', tag: 'FirebaseService');
        return null;
      }

      final connectionData = connectionDoc.data()!;
      final familyId = connectionData['familyId'] as String;
      
      // Now get the family document (this will be allowed by rules during setup)
      final doc = await _firestore.collection('families').doc(familyId).get();
      
      if (doc.exists) {
        final data = doc.data()!;
        data['familyId'] = doc.id; // Add document ID for reference
        
        // Update local storage if we don't have family ID
        if (_familyId == null) {
          _familyId = familyId;
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('family_id', familyId);
          } catch (e) {
            AppLogger.warning('Failed to save family ID locally: $e', tag: 'FirebaseService');
          }
        }
        
        return data;
      } else {
        AppLogger.error('Family document does not exist for ID: $familyId', tag: 'FirebaseService');
        return null;
      }
    } catch (e) {
      AppLogger.error('Failed to get family info: $e', tag: 'FirebaseService');
      return null;
    }
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

      // Check authentication status before proceeding
      if (_auth.currentUser == null) {
        AppLogger.info('No authenticated user, attempting to re-authenticate', tag: 'FirebaseService');
        try {
          await _auth.signInAnonymously();
          AppLogger.info('Re-authentication successful', tag: 'FirebaseService');
        } catch (authError) {
          AppLogger.error('Re-authentication failed: $authError', tag: 'FirebaseService');
          return false;
        }
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

  // CRITICAL: Method for child app to resolve family ID from connection code
  Future<String?> getFamilyIdFromConnectionCode(String connectionCode) async {
    try {
      // Use secure connection code lookup
      final connectionDoc = await _firestore
          .collection('connection_codes')
          .doc(connectionCode)
          .get();

      if (connectionDoc.exists) {
        final data = connectionDoc.data()!;
        return data['familyId'] as String;
      }
      return null;
    } catch (e) {
      AppLogger.error('Failed to resolve family ID from connection code: $e', tag: 'FirebaseService');
      return null;
    }
  }

  // Enhanced method for child app to get family data with proper ID resolution
  Future<Map<String, dynamic>?> getFamilyDataForChild(
    String connectionCode,
  ) async {
    try {
      // First resolve the family ID
      final familyId = await getFamilyIdFromConnectionCode(connectionCode);
      if (familyId == null) return null;

      // Get the family document
      final familyDoc = await _firestore
          .collection('families')
          .doc(familyId)
          .get();

      if (familyDoc.exists) {
        final data = familyDoc.data()!;
        data['familyId'] = familyId; // Include resolved family ID
        return data;
      }

      return null;
    } catch (e) {
      AppLogger.error('Failed to get family data for child: $e', tag: 'FirebaseService');
      return null;
    }
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
  }) async {
    try {
      if (_familyId == null) {
        AppLogger.warning('Cannot update family settings: no family ID', tag: 'FirebaseService');
        return false;
      }

      AppLogger.info('Updating family settings for ID: $_familyId', tag: 'FirebaseService');
      AppLogger.info('Settings: survivalSignal=$survivalSignalEnabled, alertHours=${alertHours ?? 12}', tag: 'FirebaseService');

      // Update individual fields instead of replacing the entire settings object
      await _firestore.collection('families').doc(_familyId).update({
        'settings.survivalSignalEnabled': survivalSignalEnabled,
        'settings.familyContact': familyContact,
        'settings.alertHours': alertHours ?? 12,
      });

      AppLogger.info('Family settings updated successfully', tag: 'FirebaseService');
      return true;
    } catch (e) {
      AppLogger.error('Failed to update family settings: $e', tag: 'FirebaseService');
      return false;
    }
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
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('family_id');
          await prefs.remove('family_code');
          await prefs.remove('elderly_name');
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

  // Listen for approval status changes
  Stream<bool?> listenForApproval(String connectionCode) async* {
    AppLogger.info('Setting up Firebase listener for connection code: $connectionCode', tag: 'FirebaseService');

    // FIXED: Use connection code lookup instead of local family ID
    try {
      // First, resolve family ID from secure connection code lookup
      final connectionDoc = await _firestore
          .collection('connection_codes')
          .doc(connectionCode)
          .get();

      if (!connectionDoc.exists) {
        AppLogger.error('No connection code found: $connectionCode', tag: 'FirebaseService');
        yield null;
        return;
      }

      final connectionData = connectionDoc.data()!;
      final familyId = connectionData['familyId'] as String;
      
      AppLogger.info('Listening for approval on family ID: $familyId', tag: 'FirebaseService');

      // Listen to the family document (this will be allowed by rules during setup)
      await for (final snapshot
          in _firestore
              .collection('families')
              .doc(familyId)
              .snapshots(includeMetadataChanges: true)) {
        AppLogger.debug('Firebase snapshot received for family ID $familyId: exists=${snapshot.exists}, fromCache=${snapshot.metadata.isFromCache}', tag: 'FirebaseService');

        if (snapshot.exists) {
          final data = snapshot.data();
          final approved = data?['approved'] as bool?;
          AppLogger.info('Approval status in Firebase: $approved', tag: 'FirebaseService');
          yield approved;
        } else {
          AppLogger.warning('Family document does not exist', tag: 'FirebaseService');
          yield null;
        }
      }
    } catch (e) {
      AppLogger.error('Error in approval listener: $e', tag: 'FirebaseService');
      yield null;
    }
  }

  // Set approval status (for child app)
  Future<bool> setApprovalStatus(String connectionCode, bool approved) async {
    try {
      // Get family ID from secure connection code lookup
      final familyId = await getFamilyIdFromConnectionCode(connectionCode);
      if (familyId == null) {
        AppLogger.warning('No family found with connection code: $connectionCode', tag: 'FirebaseService');
        return false;
      }

      // Add current user as family member when approving
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        AppLogger.error('User not authenticated', tag: 'FirebaseService');
        return false;
      }

      await _firestore.collection('families').doc(familyId).update({
        'approved': approved,
        'approvedAt': FieldValue.serverTimestamp(),
        'memberIds': FieldValue.arrayUnion([currentUser.uid]),
      });
      return true;
    } catch (e) {
      AppLogger.error('Failed to set approval status: $e', tag: 'FirebaseService');
      return false;
    }
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
      
      _lastActivityBatch = DateTime.now();
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

  // Update general phone activity with smart batching (87% write reduction)
  Future<bool> updatePhoneActivity({bool forceImmediate = false}) async {
    try {
      if (_familyId == null) {
        AppLogger.error('CRITICAL: Cannot update phone activity - familyId: $_familyId, familyCode: $_familyCode', tag: 'FirebaseService');
        return false;
      }
      
      AppLogger.info('Activity update - familyId: $_familyId, forceImmediate: $forceImmediate', tag: 'FirebaseService');
      
      final now = DateTime.now();
      _lastScreenActivity = now;
      
      // CRITICAL FIX: Always send immediately if this is the very first activity update
      final isFirstActivity = _lastActivityBatch == null;
      
      // Check if we should batch this update (unless forced or first activity)
      if (!forceImmediate && !isFirstActivity && _shouldBatchActivityUpdate(now)) {
        AppLogger.debug('Batching activity update - not sending to Firebase yet', tag: 'FirebaseService');
        return true; // Activity recorded locally, will be sent later
      }
      
      // Send update to Firebase (immediate for first activity or when batching interval reached)
      await _firestore.collection('families').doc(_familyId).update({
        'lastPhoneActivity': FieldValue.serverTimestamp(),
        'lastActivityType': isFirstActivity ? 'first_activity' : 'batched_activity',
        'updateTimestamp': FieldValue.serverTimestamp(),
      });
      
      _lastActivityBatch = now;
      AppLogger.info('Activity update sent to Firebase (forced: $forceImmediate, first: $isFirstActivity)', tag: 'FirebaseService');
      return true;
    } catch (e) {
      AppLogger.error('Failed to update phone activity: $e', tag: 'FirebaseService');
      return false;
    }
  }
  
  // Determine if activity update should be batched or sent immediately
  bool _shouldBatchActivityUpdate(DateTime currentTime) {
    // Always send immediately if this is the first activity
    if (_lastActivityBatch == null) {
      return false;
    }
    
    // Send immediately if breaking long inactivity (8+ hours)
    final timeSinceLastBatch = currentTime.difference(_lastActivityBatch!);
    if (timeSinceLastBatch >= _longInactivityThreshold) {
      AppLogger.info('Breaking long inactivity - sending immediate update', tag: 'FirebaseService');
      return false;
    }
    
    // Send immediately if it's been more than 2 hours since last batch
    if (timeSinceLastBatch >= _activityBatchInterval) {
      return false;
    }
    
    // Otherwise, batch the update
    return true;
  }

  // Update location with smart throttling (90% write reduction)
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
      
      // Check if this location update should be throttled
      if (!forceUpdate && _shouldThrottleLocationUpdate(latitude, longitude)) {
        AppLogger.debug('Location update throttled - insufficient change', tag: 'FirebaseService');
        return true; // Location recorded locally, but not sent to Firebase
      }

      await _firestore.collection('families').doc(_familyId).update({
        'location': {
          'latitude': latitude,
          'longitude': longitude,
          'timestamp': FieldValue.serverTimestamp(),
          'address': address ?? '',
        },
      });
      
      // Update throttling state
      _lastStoredLatitude = latitude;
      _lastStoredLongitude = longitude;
      _lastLocationUpdate = DateTime.now();

      AppLogger.info('Location updated in Firebase: $latitude, $longitude', tag: 'FirebaseService');
      return true;
    } catch (e) {
      AppLogger.error('Failed to update location: $e', tag: 'FirebaseService');
      return false;
    }
  }
  
  // Determine if location update should be throttled
  bool _shouldThrottleLocationUpdate(double latitude, double longitude) {
    // Always send the first location update
    if (_lastStoredLatitude == null || _lastStoredLongitude == null) {
      return false;
    }
    
    // Calculate distance from last stored location
    final distanceKm = _calculateDistanceKm(
      _lastStoredLatitude!, _lastStoredLongitude!,
      latitude, longitude,
    );
    
    // Send update if distance exceeds threshold
    if (distanceKm >= _significantDistanceKm) {
      AppLogger.debug('Significant location change: ${distanceKm.toStringAsFixed(2)}km', tag: 'FirebaseService');
      return false;
    }
    
    // CRITICAL FIX: Reduce time threshold to prevent location issues during meal recording
    final now = DateTime.now();
    if (_lastLocationUpdate != null) {
      final hoursSinceUpdate = now.difference(_lastLocationUpdate!).inHours;
      // Reduced from 24 hours to 4 hours for better tracking
      if (hoursSinceUpdate >= 4) {
        AppLogger.debug('4-hour location update (${hoursSinceUpdate}h since last)', tag: 'FirebaseService');
        return false;
      }
    }
    
    // Otherwise, throttle the update
    return true;
  }
  
  // Calculate distance between two GPS coordinates in kilometers
  double _calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    // Simple approximation for short distances
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
  
  // Convert degrees to radians
  double _toRadians(double degrees) {
    return degrees * (3.14159265359 / 180.0);
  }

  // Force immediate location update (bypass throttling)
  Future<bool> forceLocationUpdate({
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    try {
      if (_familyId == null) {
        AppLogger.warning('Cannot force location update: no family ID', tag: 'FirebaseService');
        return false;
      }

      await _firestore.collection('families').doc(_familyId).update({
        'location': {
          'latitude': latitude,
          'longitude': longitude,
          'timestamp': FieldValue.serverTimestamp(),
          'address': address ?? '',
        },
      });
      
      // Update throttling state
      _lastStoredLatitude = latitude;
      _lastStoredLongitude = longitude;
      _lastLocationUpdate = DateTime.now();

      AppLogger.info('Location forcibly updated in Firebase: $latitude, $longitude', tag: 'FirebaseService');
      return true;
    } catch (e) {
      AppLogger.error('Failed to force location update: $e', tag: 'FirebaseService');
      return false;
    }
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

  // Restore local data after successful recovery
  Future<void> _restoreLocalData({
    required String familyId,
    required String connectionCode,
    required String elderlyName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('family_id', familyId);
      await prefs.setString('family_code', connectionCode);
      await prefs.setString('elderly_name', elderlyName);
      await prefs.setBool('setup_complete', true);
      
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

  // Check if user has existing account data (for recovery prompts)
  Future<bool> hasExistingAccountData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasConnectionCode = prefs.getString('family_code') != null;
      return hasConnectionCode;
    } catch (e) {
      AppLogger.error('Failed to check existing account data: $e', tag: 'FirebaseService');
      return false;
    }
  }

  // Getters
  String? get familyId => _familyId;
  String? get familyCode => _familyCode;
  String? get elderlyName => _elderlyName;
  bool get isSetup => _familyCode != null && _familyId != null;
  
  // Recovery code getter removed - using name + connection code only
}
