import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thanks_everyday/core/constants/app_constants.dart';
import 'package:thanks_everyday/core/errors/app_exceptions.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';
import 'package:thanks_everyday/services/name_matching_service.dart';

class AccountRecoveryService with AppLogger {
  static final AccountRecoveryService _instance = AccountRecoveryService._internal();
  factory AccountRecoveryService() => _instance;
  AccountRecoveryService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NameMatchingService _nameMatchingService = NameMatchingService();

  Future<Result<Map<String, dynamic>>> recoverAccountWithNameAndCode({
    required String name,
    required String connectionCode,
  }) async {
    try {
      logInfo('Attempting account recovery with name: $name, connection code: $connectionCode');
      
      final familiesResult = await _getFamiliesWithConnectionCode(connectionCode);
      if (familiesResult.isFailure) {
        return familiesResult;
      }
      
      final families = familiesResult.data!;
      if (families.isEmpty) {
        return const Failure(AccountRecoveryException(
          message: AppConstants.errorConnectionNotFound,
          errorType: AccountRecoveryErrorType.connectionCodeNotFound,
        ));
      }

      final candidates = _findMatchingCandidates(name, families);
      
      if (candidates.isEmpty) {
        return const Failure(AccountRecoveryException(
          message: AppConstants.errorNameNotMatch,
          errorType: AccountRecoveryErrorType.nameNotMatch,
        ));
      }

      if (candidates.length > 1) {
        return Failure(AccountRecoveryException(
          message: AppConstants.errorMultipleMatches,
          errorType: AccountRecoveryErrorType.multipleMatches,
          // Include candidates data for user selection
        ));
      }

      // Single match found - proceed with recovery
      final match = candidates.first;
      await _restoreLocalData(match);
      
      logInfo('Account recovery successful for: ${match['elderlyName']}');
      return Success(_buildRecoveryResult(match));
      
    } catch (e, stackTrace) {
      logError('Account recovery failed', error: e, stackTrace: stackTrace);
      return Failure(AccountRecoveryException(
        message: '${AppConstants.errorRecoveryFailed}: $e',
        errorType: AccountRecoveryErrorType.recoveryFailed,
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<Result<List<QueryDocumentSnapshot>>> _getFamiliesWithConnectionCode(String connectionCode) async {
    try {
      final query = await _firestore
          .collection(AppConstants.collectionFamilies)
          .where('connectionCode', isEqualTo: connectionCode)
          .get();

      return Success(query.docs);
    } catch (e, stackTrace) {
      logError('Failed to query families with connection code', error: e, stackTrace: stackTrace);
      return Failure(ServiceException(
        message: 'Failed to query families: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  List<Map<String, dynamic>> _findMatchingCandidates(
    String inputName,
    List<QueryDocumentSnapshot> families,
  ) {
    final candidates = <Map<String, dynamic>>[];
    
    for (final doc in families) {
      final data = doc.data() as Map<String, dynamic>;
      final elderlyName = data['elderlyName'] as String? ?? '';
      final familyId = doc.id;
      
      final matchScore = _nameMatchingService.calculateNameMatchScore(inputName, elderlyName);
      
      if (matchScore >= AppConstants.nameMatchThreshold) {
        candidates.add({
          'familyId': familyId,
          'data': data,
          'matchScore': matchScore,
          'elderlyName': elderlyName,
        });
      }
    }
    
    // Sort by match score (highest first)
    candidates.sort((a, b) => (b['matchScore'] as double).compareTo(a['matchScore'] as double));
    
    return candidates;
  }

  Future<void> _restoreLocalData(Map<String, dynamic> match) async {
    try {
      final data = match['data'] as Map<String, dynamic>;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyFamilyId, match['familyId']);
      await prefs.setString(AppConstants.keyFamilyCode, data['connectionCode']);
      await prefs.setString(AppConstants.keyElderlyName, data['elderlyName']);
      await prefs.setBool(AppConstants.keySetupComplete, true);
      
      logInfo('Local data restored successfully');
    } catch (e) {
      logError('Failed to restore local data', error: e);
      throw e;
    }
  }

  Map<String, dynamic> _buildRecoveryResult(Map<String, dynamic> match) {
    final data = match['data'] as Map<String, dynamic>;
    
    return {
      'success': true,
      'familyId': match['familyId'],
      'connectionCode': data['connectionCode'],
      'elderlyName': data['elderlyName'],
      'mealCount': data['todayMealCount'] ?? 0,
      'matchScore': match['matchScore'],
    };
  }

  Future<Result<List<Map<String, dynamic>>>> autoDetectExistingAccounts() async {
    try {
      logInfo('Starting auto-detection of existing accounts');
      
      final query = await _firestore
          .collection(AppConstants.collectionFamilies)
          .where('isActive', isEqualTo: true)
          .limit(AppConstants.maxFamilySearchLimit)
          .get();

      if (query.docs.isEmpty) {
        logInfo('No active families found for auto-detection');
        return const Success([]);
      }

      final candidates = <Map<String, dynamic>>[];
      
      for (final doc in query.docs) {
        final data = doc.data();
        final familyId = doc.id;
        
        final confidence = _calculateAutoDetectionConfidence(data);
        
        if (confidence >= AppConstants.autoDetectionThreshold) {
          candidates.add({
            'familyId': familyId,
            'elderlyName': data['elderlyName'],
            'connectionCode': data['connectionCode'],
            'confidence': confidence,
            'lastActivity': data['lastPhoneActivity'],
            'mealCount': data['todayMealCount'] ?? 0,
          });
        }
      }

      // Sort by confidence score
      candidates.sort((a, b) => (b['confidence'] as double).compareTo(a['confidence'] as double));
      
      final topCandidates = candidates.take(AppConstants.maxAutoDetectionCandidates).toList();
      
      logInfo('Auto-detection found ${topCandidates.length} potential matches');
      return Success(topCandidates);
      
    } catch (e, stackTrace) {
      logError('Auto-detection failed', error: e, stackTrace: stackTrace);
      return Failure(ServiceException(
        message: 'Auto-detection failed: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  double _calculateAutoDetectionConfidence(Map<String, dynamic> data) {
    double confidence = 0.0;
    
    // Check recent activity
    final lastActivity = data['lastPhoneActivity'];
    if (lastActivity != null) {
      final lastActivityTime = lastActivity is Timestamp 
          ? lastActivity.toDate() 
          : DateTime.tryParse(lastActivity.toString());
      
      if (lastActivityTime != null) {
        final daysSinceActivity = DateTime.now().difference(lastActivityTime).inDays;
        if (daysSinceActivity <= 7) {
          confidence += 0.5;
        } else if (daysSinceActivity <= 30) {
          confidence += 0.3;
        }
      }
    }
    
    // Check meal records
    final mealCount = data['todayMealCount'] ?? 0;
    if (mealCount > 0) {
      confidence += 0.2;
    }
    
    // Check survival signal setup
    final survivalEnabled = data['settings']?['survivalSignalEnabled'] ?? false;
    if (survivalEnabled) {
      confidence += 0.2;
    }
    
    // Check approval status
    final approved = data['approved'];
    if (approved == true) {
      confidence += 0.3;
    }
    
    return confidence.clamp(0.0, 1.0);
  }

  Future<Result<List<Map<String, dynamic>>>> getConnectionCodesForRecovery() async {
    try {
      logInfo('Getting connection codes for recovery helper');
      
      final query = await _firestore
          .collection(AppConstants.collectionFamilies)
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(AppConstants.maxRecoveryDisplayLimit)
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
      
      logInfo('Retrieved ${codes.length} connection codes for recovery');
      return Success(codes);
      
    } catch (e, stackTrace) {
      logError('Failed to get connection codes for recovery', error: e, stackTrace: stackTrace);
      return Failure(ServiceException(
        message: 'Failed to get connection codes: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<Result<bool>> hasExistingAccountData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasConnectionCode = prefs.getString(AppConstants.keyFamilyCode) != null;
      return Success(hasConnectionCode);
    } catch (e) {
      logError('Failed to check existing account data', error: e);
      return const Success(false);
    }
  }
}