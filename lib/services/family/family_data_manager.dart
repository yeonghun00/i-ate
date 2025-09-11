import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';

class FamilyDataManager {
  final FirebaseFirestore _firestore;
  
  FamilyDataManager({FirebaseFirestore? firestore}) 
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<Map<String, dynamic>?> getFamilyInfo(String connectionCode) async {
    try {
      AppLogger.info('Getting family info for connection code: $connectionCode', tag: 'FamilyDataManager');
      
      final connectionDoc = await _firestore
          .collection('connection_codes')
          .doc(connectionCode)
          .get();

      if (!connectionDoc.exists) {
        AppLogger.error('No connection code found: $connectionCode', tag: 'FamilyDataManager');
        return null;
      }

      final connectionData = connectionDoc.data()!;
      final familyId = connectionData['familyId'] as String;
      
      final doc = await _firestore.collection('families').doc(familyId).get();
      
      if (doc.exists) {
        final data = doc.data()!;
        data['familyId'] = doc.id;
        return data;
      }
      
      AppLogger.error('Family document not found for ID: $familyId', tag: 'FamilyDataManager');
      return null;
    } catch (e) {
      AppLogger.error('Failed to get family info: $e', tag: 'FamilyDataManager');
      return null;
    }
  }

  Future<String?> getFamilyIdFromConnectionCode(String connectionCode) async {
    try {
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
      AppLogger.error('Failed to resolve family ID from connection code: $e', tag: 'FamilyDataManager');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getFamilyDataForChild(String connectionCode) async {
    try {
      final familyId = await getFamilyIdFromConnectionCode(connectionCode);
      if (familyId == null) return null;

      final familyDoc = await _firestore.collection('families').doc(familyId).get();

      if (familyDoc.exists) {
        final data = familyDoc.data()!;
        data['familyId'] = familyId;
        return data;
      }

      return null;
    } catch (e) {
      AppLogger.error('Failed to get family data for child: $e', tag: 'FamilyDataManager');
      return null;
    }
  }

  Future<bool> updateFamilySettings(String familyId, {
    required bool survivalSignalEnabled,
    required String familyContact,
    int? alertHours,
    Map<String, dynamic>? sleepTimeSettings,
  }) async {
    try {
      AppLogger.info('Updating family settings for ID: $familyId', tag: 'FamilyDataManager');
      
      final updateData = <String, dynamic>{
        'settings.survivalSignalEnabled': survivalSignalEnabled,
        'settings.familyContact': familyContact,
        'settings.alertHours': alertHours ?? 12,
      };
      
      // Add sleep settings if provided
      if (sleepTimeSettings != null) {
        updateData['settings.sleepTimeSettings'] = sleepTimeSettings;
        AppLogger.info('Including sleep time settings in update', tag: 'FamilyDataManager');
      }

      await _firestore.collection('families').doc(familyId).update(updateData);

      AppLogger.info('Family settings updated successfully', tag: 'FamilyDataManager');
      return true;
    } catch (e) {
      AppLogger.error('Failed to update family settings: $e', tag: 'FamilyDataManager');
      return false;
    }
  }

  Future<bool> setApprovalStatus(String connectionCode, bool approved, String userId) async {
    try {
      final familyId = await getFamilyIdFromConnectionCode(connectionCode);
      if (familyId == null) {
        AppLogger.warning('No family found with connection code: $connectionCode', tag: 'FamilyDataManager');
        return false;
      }

      await _firestore.collection('families').doc(familyId).update({
        'approved': approved,
        'approvedAt': FieldValue.serverTimestamp(),
        'memberIds': FieldValue.arrayUnion([userId]),
      });
      
      return true;
    } catch (e) {
      AppLogger.error('Failed to set approval status: $e', tag: 'FamilyDataManager');
      return false;
    }
  }

  Stream<bool?> listenForApproval(String connectionCode) async* {
    try {
      final connectionDoc = await _firestore
          .collection('connection_codes')
          .doc(connectionCode)
          .get();

      if (!connectionDoc.exists) {
        AppLogger.error('No connection code found: $connectionCode', tag: 'FamilyDataManager');
        yield null;
        return;
      }

      final connectionData = connectionDoc.data()!;
      final familyId = connectionData['familyId'] as String;
      
      AppLogger.info('Listening for approval on family ID: $familyId', tag: 'FamilyDataManager');

      await for (final snapshot in _firestore.collection('families').doc(familyId).snapshots()) {
        AppLogger.debug('Firebase snapshot received for family ID $familyId', tag: 'FamilyDataManager');

        if (snapshot.exists) {
          final data = snapshot.data();
          final approved = data?['approved'] as bool?;
          AppLogger.info('Approval status: $approved', tag: 'FamilyDataManager');
          yield approved;
        } else {
          AppLogger.warning('Family document does not exist', tag: 'FamilyDataManager');
          yield null;
        }
      }
    } catch (e) {
      AppLogger.error('Error in approval listener: $e', tag: 'FamilyDataManager');
      yield null;
    }
  }
}