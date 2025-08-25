import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'dart:typed_data';
import 'package:thanks_everyday/core/constants/app_constants.dart';
import 'package:thanks_everyday/core/errors/app_exceptions.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';

/// Secure Family Connection Service - handles family creation and joining with proper authentication
class SecureFamilyConnectionService with AppLogger {
  static final SecureFamilyConnectionService _instance = SecureFamilyConnectionService._internal();
  factory SecureFamilyConnectionService() => _instance;
  SecureFamilyConnectionService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // =======================================================
  // PARENT APP METHODS (Anonymous Auth)
  // =======================================================

  /// Setup family code (Parent App - Anonymous Auth)
  Future<Result<String>> setupFamilyCode(String elderlyName) async {
    try {
      logInfo('Setting up family code for: $elderlyName');

      // Ensure user is authenticated (anonymous for parent app)
      if (_auth.currentUser == null) {
        await _auth.signInAnonymously();
      }

      final connectionCode = await _generateConnectionCode();
      final familyId = await _generateUniqueFamilyId();

      final success = await _setupFamilyDocument(
        familyId,
        connectionCode,
        elderlyName,
      );
      
      if (success) {
        logInfo('Family code setup successful: $connectionCode');
        return Success(connectionCode);
      } else {
        return const Failure(ServiceException(message: 'Failed to setup family document'));
      }
    } catch (e, stackTrace) {
      logError('Failed to setup family code', error: e, stackTrace: stackTrace);
      return Failure(ServiceException(
        message: 'Failed to setup family code: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Setup family document with security fields
  Future<bool> _setupFamilyDocument(
    String familyId,
    String connectionCode,
    String elderlyName,
  ) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        logError('No authenticated user for family creation');
        return false;
      }

      // Create secure connection code lookup
      await _firestore.collection('connection_codes').doc(connectionCode).set({
        'familyId': familyId,
        'elderlyName': elderlyName,
        'createdBy': currentUser.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))), // 30-day expiry
      });

      // Create family document with proper security fields
      await _firestore.collection(AppConstants.collectionFamilies).doc(familyId).set({
        'familyId': familyId,
        'connectionCode': connectionCode,
        'elderlyName': elderlyName,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': currentUser.uid,
        'memberIds': [currentUser.uid], // Parent is first member
        'deviceInfo': 'Android Device',
        'isActive': true,
        'approved': null, // null = pending child approval
        'settings': {
          'survivalSignalEnabled': false,
          'familyContact': '',
          'alertHours': AppConstants.defaultAlertHours,
        },
        'alerts': {
          'survival': null,
          'food': null
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
        'lastPhoneActivity': null,
      });

      await _saveLocalFamilyInfo(familyId, connectionCode, elderlyName);
      return true;
      
    } catch (e) {
      logError('Failed to setup family document', error: e);
      return false;
    }
  }

  // =======================================================
  // CHILD APP METHODS (Google Auth) 
  // =======================================================

  /// Get family info for child app (secure lookup via connection codes)
  Future<Result<Map<String, dynamic>>> getFamilyInfoForChild(String connectionCode) async {
    try {
      logInfo('Child app getting family info for code: $connectionCode');

      // First, resolve family ID from secure connection code lookup
      final connectionDoc = await _firestore
          .collection('connection_codes')
          .doc(connectionCode)
          .get();

      if (!connectionDoc.exists) {
        return const Failure(AccountRecoveryException(
          message: AppConstants.errorConnectionNotFound,
          errorType: AccountRecoveryErrorType.connectionCodeNotFound,
        ));
      }

      final connectionData = connectionDoc.data()!;
      final familyId = connectionData['familyId'] as String;

      // Check if connection code has expired
      final expiresAt = connectionData['expiresAt'] as Timestamp?;
      if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
        return const Failure(ServiceException(message: 'Connection code has expired'));
      }

      // Now get the family document (this will be allowed by security rules for connection code users)
      final familyDoc = await _firestore
          .collection(AppConstants.collectionFamilies)
          .doc(familyId)
          .get();

      if (familyDoc.exists) {
        final data = familyDoc.data()!;
        data['familyId'] = familyDoc.id;
        logInfo('Family info retrieved successfully for child app');
        return Success(data);
      }
      
      return const Failure(AccountRecoveryException(
        message: AppConstants.errorConnectionNotFound,
        errorType: AccountRecoveryErrorType.connectionCodeNotFound,
      ));
      
    } catch (e, stackTrace) {
      logError('Failed to get family info for child', error: e, stackTrace: stackTrace);
      return Failure(ServiceException(
        message: 'Failed to get family info: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Set approval status (Child App with Google Auth)
  Future<Result<bool>> setApprovalStatus(String connectionCode, bool approved) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return const Failure(ServiceException(message: 'User not authenticated'));
      }

      logInfo('Child app setting approval status: $approved for code: $connectionCode');

      // First, get family ID from secure connection code lookup
      final connectionDoc = await _firestore
          .collection('connection_codes')
          .doc(connectionCode)
          .get();

      if (!connectionDoc.exists) {
        logWarning('No family found with connection code: $connectionCode');
        return const Failure(AccountRecoveryException(
          message: AppConstants.errorConnectionNotFound,
          errorType: AccountRecoveryErrorType.connectionCodeNotFound,
        ));
      }

      final connectionData = connectionDoc.data()!;
      final familyId = connectionData['familyId'] as String;

      // Update approval status and add current user as family member
      await _firestore.collection(AppConstants.collectionFamilies).doc(familyId).update({
        'approved': approved,
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': currentUser.uid,
        'memberIds': FieldValue.arrayUnion([currentUser.uid]),
        'childInfo': {
          currentUser.uid: {
            'email': currentUser.email,
            'displayName': currentUser.displayName,
            'photoURL': currentUser.photoURL,
            'joinedAt': FieldValue.serverTimestamp(),
            'role': 'child',
          }
        }
      });
      
      logInfo('Approval status set successfully');
      return const Success(true);
      
    } catch (e, stackTrace) {
      logError('Failed to set approval status', error: e, stackTrace: stackTrace);
      return Failure(ServiceException(
        message: 'Failed to set approval status: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  // =======================================================
  // SHARED METHODS
  // =======================================================

  /// Listen for approval status changes (Parent App)
  Stream<bool?> listenForApproval(String connectionCode) async* {
    try {
      logInfo('Setting up Firebase listener for connection code: $connectionCode');

      // Get family ID from connection code first
      final connectionDoc = await _firestore
          .collection('connection_codes')
          .doc(connectionCode)
          .get();

      if (!connectionDoc.exists) {
        logWarning('No family found with connection code: $connectionCode');
        yield null;
        return;
      }

      final connectionData = connectionDoc.data()!;
      final familyId = connectionData['familyId'] as String;

      logInfo('Found family ID: $familyId for connection code: $connectionCode');

      // Listen to family document changes
      await for (final snapshot in _firestore
          .collection(AppConstants.collectionFamilies)
          .doc(familyId)
          .snapshots(includeMetadataChanges: true)) {
        
        logDebug('Firebase snapshot received for family ID $familyId');

        if (snapshot.exists) {
          final data = snapshot.data();
          final approved = data?['approved'] as bool?;
          logDebug('Approval status in Firebase: $approved');
          yield approved;
        } else {
          logWarning('Family document does not exist');
          yield null;
        }
      }
    } catch (e) {
      logError('Error in approval listener', error: e);
      yield null;
    }
  }

  /// Delete family code (cleanup)
  Future<Result<bool>> deleteFamilyCode(String connectionCode) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return const Failure(ServiceException(message: 'User not authenticated'));
      }

      // Get family ID from connection code
      final connectionDoc = await _firestore
          .collection('connection_codes')
          .doc(connectionCode)
          .get();

      if (!connectionDoc.exists) {
        return const Success(false);
      }

      final connectionData = connectionDoc.data()!;
      final familyId = connectionData['familyId'] as String;

      // Verify user has permission to delete (creator or family member)
      final familyDoc = await _firestore
          .collection(AppConstants.collectionFamilies)
          .doc(familyId)
          .get();

      if (familyDoc.exists) {
        final familyData = familyDoc.data()!;
        final memberIds = List<String>.from(familyData['memberIds'] ?? []);
        final createdBy = familyData['createdBy'] as String?;

        if (currentUser.uid == createdBy || memberIds.contains(currentUser.uid)) {
          // Delete both connection code and family document
          await Future.wait([
            _firestore.collection('connection_codes').doc(connectionCode).delete(),
            _firestore.collection(AppConstants.collectionFamilies).doc(familyId).delete(),
          ]);
          
          await _clearLocalFamilyInfo(connectionCode);
          return const Success(true);
        }
      }

      return const Success(false);
      
    } catch (e, stackTrace) {
      logError('Failed to delete family code', error: e, stackTrace: stackTrace);
      return Failure(ServiceException(
        message: 'Failed to delete family code: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  // =======================================================
  // PRIVATE HELPER METHODS
  // =======================================================

  Future<String> _generateConnectionCode() async {
    String code;
    bool isUnique = false;

    do {
      code = (AppConstants.connectionCodeMin + 
              Random().nextInt(AppConstants.connectionCodeMax - AppConstants.connectionCodeMin))
              .toString();

      final query = await _firestore
          .collection('connection_codes')
          .where('familyId', isEqualTo: 'temp_check_$code') // This will always be empty
          .limit(1)
          .get();

      // Check if connection code document exists
      final existingDoc = await _firestore
          .collection('connection_codes')
          .doc(code)
          .get();
          
      isUnique = !existingDoc.exists;
    } while (!isUnique);

    return code;
  }

  String _generateFamilyId() {
    final random = Random.secure();
    
    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = random.nextInt(256);
    }
    
    // Set version (4) and variant bits according to RFC 4122
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final uuid = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
    
    return 'family_$uuid';
  }

  Future<String> _generateUniqueFamilyId() async {
    String familyId;
    bool isUnique = false;
    int attempts = 0;
    const maxAttempts = 5;
    
    do {
      familyId = _generateFamilyId();
      
      final docSnapshot = await _firestore
          .collection(AppConstants.collectionFamilies)
          .doc(familyId)
          .get();
      isUnique = !docSnapshot.exists;
      
      attempts++;
      if (attempts >= maxAttempts && !isUnique) {
        throw ServiceException(
          message: 'Failed to generate unique family ID after $maxAttempts attempts',
        );
      }
    } while (!isUnique);
    
    return familyId;
  }

  Future<void> _saveLocalFamilyInfo(String familyId, String connectionCode, String elderlyName) async {
    int retryCount = 0;
    
    while (retryCount < AppConstants.maxRetries) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.keyFamilyId, familyId);
        await prefs.setString(AppConstants.keyFamilyCode, connectionCode);
        await prefs.setString(AppConstants.keyElderlyName, elderlyName);
        return;
        
      } catch (e) {
        retryCount++;
        logWarning('SharedPreferences save attempt $retryCount failed: $e');
        if (retryCount < AppConstants.maxRetries) {
          await Future.delayed(AppConstants.retryDelay * retryCount);
        }
      }
    }
  }

  Future<void> _clearLocalFamilyInfo(String connectionCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localFamilyCode = prefs.getString(AppConstants.keyFamilyCode);
      
      if (localFamilyCode == connectionCode) {
        await prefs.remove(AppConstants.keyFamilyId);
        await prefs.remove(AppConstants.keyFamilyCode);
        await prefs.remove(AppConstants.keyElderlyName);
      }
    } catch (e) {
      logError('Failed to clear local family info', error: e);
    }
  }
}