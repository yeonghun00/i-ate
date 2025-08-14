import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'dart:typed_data';
import 'package:thanks_everyday/core/constants/app_constants.dart';
import 'package:thanks_everyday/core/errors/app_exceptions.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';

class FamilyConnectionService with AppLogger {
  static final FamilyConnectionService _instance = FamilyConnectionService._internal();
  factory FamilyConnectionService() => _instance;
  FamilyConnectionService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Result<String>> setupFamilyCode(String elderlyName) async {
    try {
      logInfo('Setting up family code for: $elderlyName');
      
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

  Future<String> _generateConnectionCode() async {
    String code;
    bool isUnique = false;

    do {
      code = (AppConstants.connectionCodeMin + 
              Random().nextInt(AppConstants.connectionCodeMax - AppConstants.connectionCodeMin))
              .toString();

      final query = await _firestore
          .collection(AppConstants.collectionFamilies)
          .where('connectionCode', isEqualTo: code)
          .limit(1)
          .get();
      isUnique = query.docs.isEmpty;
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

  Future<bool> _setupFamilyDocument(
    String familyId,
    String connectionCode,
    String elderlyName,
  ) async {
    try {
      await _firestore.collection(AppConstants.collectionFamilies).doc(familyId).set({
        'familyId': familyId,
        'connectionCode': connectionCode,
        'elderlyName': elderlyName,
        'createdAt': FieldValue.serverTimestamp(),
        'deviceInfo': 'Android Device',
        'isActive': true,
        'approved': null,
        'settings': {
          'survivalSignalEnabled': false,
          'familyContact': '',
          'alertHours': AppConstants.defaultAlertHours,
        },
        'survivalAlert': {'isActive': false, 'timestamp': null, 'message': ''},
        'foodAlert': {
          'isActive': false,
          'timestamp': null,
          'message': '',
          'elderlyName': '',
          'lastFoodIntake': null,
          'hoursWithoutFood': null,
        },
        'lastFoodIntake': {'timestamp': null, 'todayCount': 0},
        'lastMealTime': null,
        'todayMealCount': 0,
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

  Future<Result<Map<String, dynamic>>> getFamilyInfo(String connectionCode) async {
    try {
      final query = await _firestore
          .collection(AppConstants.collectionFamilies)
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        final data = doc.data();
        data['familyId'] = doc.id;
        return Success(data);
      }
      
      return const Failure(AccountRecoveryException(
        message: AppConstants.errorConnectionNotFound,
        errorType: AccountRecoveryErrorType.connectionCodeNotFound,
      ));
      
    } catch (e, stackTrace) {
      logError('Failed to get family info', error: e, stackTrace: stackTrace);
      return Failure(ServiceException(
        message: 'Failed to get family info: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<Result<bool>> deleteFamilyCode(String connectionCode) async {
    try {
      final query = await _firestore
          .collection(AppConstants.collectionFamilies)
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        await doc.reference.delete();
        
        await _clearLocalFamilyInfo(connectionCode);
        return const Success(true);
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

  Stream<bool?> listenForApproval(String connectionCode) async* {
    try {
      logInfo('Setting up Firebase listener for connection code: $connectionCode');

      final query = await _firestore
          .collection(AppConstants.collectionFamilies)
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        logWarning('No family found with connection code: $connectionCode');
        yield null;
        return;
      }

      final familyId = query.docs.first.id;
      logInfo('Found family ID: $familyId for connection code: $connectionCode');

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

  Future<Result<bool>> setApprovalStatus(String connectionCode, bool approved) async {
    try {
      final query = await _firestore
          .collection(AppConstants.collectionFamilies)
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        logWarning('No family found with connection code: $connectionCode');
        return const Failure(AccountRecoveryException(
          message: AppConstants.errorConnectionNotFound,
          errorType: AccountRecoveryErrorType.connectionCodeNotFound,
        ));
      }

      final familyId = query.docs.first.id;
      await _firestore.collection(AppConstants.collectionFamilies).doc(familyId).update({
        'approved': approved,
        'approvedAt': FieldValue.serverTimestamp(),
      });
      
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
}