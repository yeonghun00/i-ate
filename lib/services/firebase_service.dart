import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  String? _familyId;
  String? _familyCode;
  String? _elderlyName;
  
  // Initialize Firebase and check for existing family code
  Future<bool> initialize() async {
    try {
      // Sign in anonymously for Firebase Auth
      try {
        if (_auth.currentUser == null) {
          await _auth.signInAnonymously();
        }
      } catch (authError) {
        print('Firebase Auth failed, continuing without auth: $authError');
      }
      
      // Check if family code exists locally with retry logic
      SharedPreferences? prefs;
      int retryCount = 0;
      const maxRetries = 3;
      
      while (prefs == null && retryCount < maxRetries) {
        try {
          prefs = await SharedPreferences.getInstance();
        } catch (e) {
          print('SharedPreferences attempt ${retryCount + 1} failed: $e');
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
        print('SharedPreferences failed completely, using in-memory storage');
        // If SharedPreferences fails, we'll continue without local storage
        // The app will still work but won't persist the family code
      }
      
      return _familyCode != null;
    } catch (e) {
      print('Firebase initialization failed: $e');
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
      final query = await _firestore.collection('families')
          .where('connectionCode', isEqualTo: code)
          .limit(1)
          .get();
      isUnique = query.docs.isEmpty;
    } while (!isUnique);
    
    return code;
  }
  
  // Generate a unique family ID
  String _generateFamilyId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(99999);
    return 'family_${timestamp}_$random';
  }
  
  // Set up family code (called by family member)
  Future<String?> setupFamilyCode(String elderlyName) async {
    try {
      final connectionCode = await _generateConnectionCode();
      final familyId = _generateFamilyId();
      
      final success = await _setupFamilyDocument(familyId, connectionCode, elderlyName);
      if (success) {
        return connectionCode;
      }
      return null;
    } catch (e) {
      print('Failed to setup family code: $e');
      return null;
    }
  }

  // Set up family document with unique ID and connection code
  Future<bool> _setupFamilyDocument(String familyId, String connectionCode, String elderlyName) async {
    try {
      // Create family document with unique ID
      await _firestore.collection('families').doc(familyId).set({
        'familyId': familyId,
        'connectionCode': connectionCode,
        'elderlyName': elderlyName,
        'createdAt': FieldValue.serverTimestamp(),
        'deviceInfo': 'Android Device',
        'isActive': true,
        'lastActivity': FieldValue.serverTimestamp(),
        'approved': null, // null = pending, true = approved, false = rejected
        'settings': {
          'survivalSignalEnabled': false,
          'familyContact': '',
          'alertHours': 12,
        },
        'survivalAlert': {
          'isActive': false,
          'timestamp': null,
          'message': '',
        },
        'foodAlert': {
          'isActive': false,
          'timestamp': null,
          'message': '',
          'elderlyName': '',
          'lastFoodIntake': null,
          'hoursWithoutFood': null,
        },
        'lastFoodIntake': {
          'timestamp': null,
          'todayCount': 0,
        },
        'todayMealCount': 0,
        'location': {
          'latitude': null,
          'longitude': null,
          'timestamp': null,
          'address': '',
        },
      });
      
      // Save locally with retry logic
      SharedPreferences? prefs;
      int retryCount = 0;
      const maxRetries = 3;
      
      while (prefs == null && retryCount < maxRetries) {
        try {
          prefs = await SharedPreferences.getInstance();
        } catch (e) {
          print('SharedPreferences setup attempt ${retryCount + 1} failed: $e');
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
      print('Failed to setup family document: $e');
      return false;
    }
  }
  
  // Verify family code exists (for family members)
  Future<Map<String, dynamic>?> getFamilyInfo(String connectionCode) async {
    try {
      final query = await _firestore.collection('families')
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1)
          .get();
      
      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        final data = doc.data();
        data['familyId'] = doc.id; // Add document ID for reference
        return data;
      }
      return null;
    } catch (e) {
      print('Failed to get family info: $e');
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
        print('No family code or ID available');
        return false;
      }
      
      // Get today's date string
      final today = DateTime.now();
      final dateString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      // Create meal record with unique ID to prevent duplicates
      final mealId = '${timestamp.millisecondsSinceEpoch}_${mealNumber}';
      final mealData = {
        'mealId': mealId,
        'timestamp': timestamp.toIso8601String(),
        'mealNumber': mealNumber,
        'elderlyName': _elderlyName,
        'createdAt': timestamp.toIso8601String(), // Use regular timestamp instead of serverTimestamp
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
        'lastUpdated': FieldValue.serverTimestamp(),
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
      
      // Update family document with actual count from meals collection
      await _firestore.collection('families').doc(_familyId).update({
        'lastActive': FieldValue.serverTimestamp(),
        'lastMealTime': timestamp.toIso8601String(),
        'todayMealCount': currentMealCount, // Set actual count, don't increment
      });
      
      return true;
      
    } catch (e) {
      print('Failed to save meal record: $e');
      return false;
    }
  }
  
  // Get today's meal count with fallback to family document
  Future<int> getTodayMealCount() async {
    try {
      if (_familyCode == null || _familyId == null) return 0;
      
      final today = DateTime.now();
      final dateString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      // Try to get from meal document first
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
      
      // Fallback to family document
      final familyDoc = await _firestore
          .collection('families')
          .doc(_familyId)
          .get();
      
      if (familyDoc.exists) {
        final data = familyDoc.data();
        final todayCount = data?['todayMealCount'] as int?;
        return todayCount ?? 0;
      }
      
      return 0;
    } catch (e) {
      print('Failed to get today\'s meal count: $e');
      return 0;
    }
  }
  
  // CRITICAL: Method for child app to resolve family ID from connection code
  Future<String?> getFamilyIdFromConnectionCode(String connectionCode) async {
    try {
      final query = await _firestore.collection('families')
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1)
          .get();
      
      if (query.docs.isNotEmpty) {
        return query.docs.first.id; // This is the actual familyId
      }
      return null;
    } catch (e) {
      print('Failed to resolve family ID from connection code: $e');
      return null;
    }
  }
  
  // Enhanced method for child app to get family data with proper ID resolution
  Future<Map<String, dynamic>?> getFamilyDataForChild(String connectionCode) async {
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
      print('Failed to get family data for child: $e');
      return null;
    }
  }
  
  // Child app method to get meals for a specific date
  Future<List<Map<String, dynamic>>> getMealsForDate(
    String connectionCode, 
    DateTime date
  ) async {
    try {
      final familyId = await getFamilyIdFromConnectionCode(connectionCode);
      if (familyId == null) return [];
      
      final dateString = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      
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
      print('Failed to get meals for date: $e');
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
        print('Cannot update family settings: no family ID');
        return false;
      }
      
      print('Updating family settings for ID: $_familyId');
      print('Settings: survivalSignal=$survivalSignalEnabled, alertHours=${alertHours ?? 12}');
      
      // Update individual fields instead of replacing the entire settings object
      await _firestore.collection('families').doc(_familyId).update({
        'settings.survivalSignalEnabled': survivalSignalEnabled,
        'settings.familyContact': familyContact,
        'settings.alertHours': alertHours ?? 12,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      
      print('Family settings updated successfully');
      return true;
    } catch (e) {
      print('Failed to update family settings: $e');
      return false;
    }
  }

  // Delete family code from Firebase
  Future<bool> deleteFamilyCode(String connectionCode) async {
    try {
      // Find family by connection code
      final query = await _firestore.collection('families')
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
      print('Failed to delete family code: $e');
      return false;
    }
  }

  // Listen for approval status changes
  Stream<bool?> listenForApproval(String connectionCode) async* {
    print('Setting up Firebase listener for connection code: $connectionCode');
    
    // First find the family document by connection code
    final query = await _firestore.collection('families')
        .where('connectionCode', isEqualTo: connectionCode)
        .limit(1)
        .get();
    
    if (query.docs.isEmpty) {
      print('No family found with connection code: $connectionCode');
      yield null;
      return;
    }
    
    final familyId = query.docs.first.id;
    print('Found family ID: $familyId for connection code: $connectionCode');
    
    // Listen to the family document by ID
    await for (final snapshot in _firestore
        .collection('families')
        .doc(familyId)
        .snapshots(includeMetadataChanges: true)) {
      
      print('Firebase snapshot received for family ID $familyId: exists=${snapshot.exists}, fromCache=${snapshot.metadata.isFromCache}');
      
      if (snapshot.exists) {
        final data = snapshot.data();
        final approved = data?['approved'] as bool?;
        print('Approval status in Firebase: $approved');
        yield approved;
      } else {
        print('Family document does not exist');
        yield null;
      }
    }
  }

  // Set approval status (for child app)
  Future<bool> setApprovalStatus(String connectionCode, bool approved) async {
    try {
      // Find family by connection code
      final query = await _firestore.collection('families')
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1)
          .get();
      
      if (query.docs.isEmpty) {
        print('No family found with connection code: $connectionCode');
        return false;
      }
      
      final familyId = query.docs.first.id;
      await _firestore.collection('families').doc(familyId).update({
        'approved': approved,
        'approvedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('Failed to set approval status: $e');
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
        'survivalAlert': {
          'timestamp': FieldValue.serverTimestamp(),
          'elderlyName': elderlyName,
          'message': message,
          'isActive': true,
        }
      });
      
      print('Survival alert sent to family: $familyCode');
      return true;
    } catch (e) {
      print('Failed to send survival alert: $e');
      return false;
    }
  }

  // Clear survival alert
  Future<bool> clearSurvivalAlert() async {
    try {
      if (_familyId == null) return false;
      
      await _firestore.collection('families').doc(_familyId).update({
        'survivalAlert.isActive': false,
        'survivalAlert.clearedAt': FieldValue.serverTimestamp(),
      });
      
      print('Survival alert cleared');
      return true;
    } catch (e) {
      print('Failed to clear survival alert: $e');
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
        print('Cannot send food alert: no family ID');
        return false;
      }
      
      await _firestore.collection('families').doc(_familyId).update({
        'foodAlert': {
          'timestamp': FieldValue.serverTimestamp(),
          'elderlyName': elderlyName,
          'message': message,
          'isActive': true,
          'lastFoodIntake': lastFoodIntake?.toIso8601String(),
          'hoursWithoutFood': hoursWithoutFood,
        }
      });
      
      print('Food alert sent to family: $message');
      return true;
    } catch (e) {
      print('Failed to send food alert: $e');
      return false;
    }
  }

  // Clear food alert
  Future<bool> clearFoodAlert() async {
    try {
      if (_familyId == null) return false;
      
      await _firestore.collection('families').doc(_familyId).update({
        'foodAlert.isActive': false,
        'foodAlert.clearedAt': FieldValue.serverTimestamp(),
      });
      
      print('Food alert cleared');
      return true;
    } catch (e) {
      print('Failed to clear food alert: $e');
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
        print('Cannot update food intake: no family ID');
        return false;
      }
      
      await _firestore.collection('families').doc(_familyId).update({
        'lastFoodIntake': {
          'timestamp': FieldValue.serverTimestamp(),
          'todayCount': todayCount,
        },
        'foodAlert.isActive': false, // Clear any active food alerts
      });
      
      print('Food intake updated: $timestamp, count: $todayCount');
      return true;
    } catch (e) {
      print('Failed to update food intake: $e');
      return false;
    }
  }

  // Update location information
  Future<bool> updateLocation({
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    try {
      if (_familyId == null) {
        print('Cannot update location: no family ID');
        return false;
      }
      
      await _firestore.collection('families').doc(_familyId).update({
        'location': {
          'latitude': latitude,
          'longitude': longitude,
          'timestamp': FieldValue.serverTimestamp(),
          'address': address ?? '',
        }
      });
      
      print('Location updated: $latitude, $longitude');
      return true;
    } catch (e) {
      print('Failed to update location: $e');
      return false;
    }
  }

  // Getters
  String? get familyId => _familyId;
  String? get familyCode => _familyCode;
  String? get elderlyName => _elderlyName;
  bool get isSetup => _familyCode != null && _familyId != null;
}