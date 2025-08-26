import 'package:cloud_firestore/cloud_firestore.dart';
// Firebase Storage import removed - not currently used
import 'package:thanks_everyday/core/utils/app_logger.dart';
import 'package:thanks_everyday/services/secure_family_connection_service.dart';

class ChildAppService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SecureFamilyConnectionService _secureService = SecureFamilyConnectionService();
  // Firebase Storage removed - not currently used in this service
  
  /// Helper method to resolve family ID from connection code
  Future<String?> _resolveFamilyId(String connectionCode) async {
    try {
      final result = await _secureService.getFamilyInfoForChild(connectionCode);
      return result.fold(
        (error) => null,
        (familyInfo) => familyInfo['familyId'] as String?,
      );
    } catch (e) {
      AppLogger.error('Failed to resolve family ID: $e', tag: 'ChildAppService');
      return null;
    }
  }
  
  /// 가족 코드 입력하여 어르신 정보 가져오기 (보안 강화)
  Future<Map<String, dynamic>?> getFamilyInfo(String connectionCode) async {
    try {
      final result = await _secureService.getFamilyInfoForChild(connectionCode);
      return result.fold(
        (error) {
          AppLogger.error('Failed to get family info: ${error.message}', tag: 'ChildAppService');
          return null;
        },
        (familyInfo) => familyInfo,
      );
    } catch (e) {
      AppLogger.error('Failed to get family info: $e', tag: 'ChildAppService');
      return null;
    }
  }
  
  /// 가족 코드 승인/거부 (보안 강화)
  Future<bool> approveFamilyCode(String connectionCode, bool approved) async {
    try {
      final result = await _secureService.setApprovalStatus(connectionCode, approved);
      return result.fold(
        (error) {
          AppLogger.error('Failed to approve family code: ${error.message}', tag: 'ChildAppService');
          return false;
        },
        (success) => success,
      );
    } catch (e) {
      AppLogger.error('Failed to approve family code: $e', tag: 'ChildAppService');
      return false;
    }
  }
  
  /// 어르신의 모든 녹음 데이터 가져오기 (보안 강화)
  Future<List<Map<String, dynamic>>> getAllRecordings(String connectionCode) async {
    try {
      final familyId = await _resolveFamilyId(connectionCode);
      if (familyId == null) {
        AppLogger.error('Failed to resolve family ID for connection code: $connectionCode', tag: 'ChildAppService');
        return [];
      }
      
      final collection = await _firestore
          .collection('families')
          .doc(familyId)
          .collection('recordings')
          .orderBy(FieldPath.documentId, descending: true) // 최신 날짜순
          .get();
      
      List<Map<String, dynamic>> allRecordings = [];
      
      for (var doc in collection.docs) {
        final data = doc.data();
        final recordings = data['recordings'] as List<dynamic>? ?? [];
        
        for (var recording in recordings) {
          allRecordings.add({
            'date': doc.id, // 날짜 (YYYY-MM-DD)
            'audioUrl': recording['audioUrl'],
            'photoUrl': recording['photoUrl'],
            'timestamp': recording['timestamp'],
            'elderlyName': recording['elderlyName'],
          });
        }
      }
      
      // 시간순으로 정렬
      allRecordings.sort((a, b) => 
          DateTime.parse(b['timestamp']).compareTo(DateTime.parse(a['timestamp']))
      );
      
      return allRecordings;
    } catch (e) {
      AppLogger.error('Failed to get recordings: $e', tag: 'ChildAppService');
      return [];
    }
  }
  
  /// 특정 날짜의 녹음 데이터 가져오기 (보안 강화)
  Future<List<Map<String, dynamic>>> getRecordingsByDate(
    String connectionCode, 
    String date
  ) async {
    try {
      final familyId = await _resolveFamilyId(connectionCode);
      if (familyId == null) {
        AppLogger.error('Failed to resolve family ID for connection code: $connectionCode', tag: 'ChildAppService');
        return [];
      }
      
      final doc = await _firestore
          .collection('families')
          .doc(familyId)
          .collection('recordings')
          .doc(date)
          .get();
      
      if (doc.exists) {
        final data = doc.data();
        final recordings = data?['recordings'] as List<dynamic>? ?? [];
        
        return recordings.map((recording) => {
          'date': date,
          'audioUrl': recording['audioUrl'],
          'photoUrl': recording['photoUrl'],
          'timestamp': recording['timestamp'],
          'elderlyName': recording['elderlyName'],
        }).toList();
      }
      
      return [];
    } catch (e) {
      AppLogger.error('Failed to get recordings by date: $e', tag: 'ChildAppService');
      return [];
    }
  }
  
  /// 실시간으로 새 녹음 듣기 (보안 강화) - connectionCode를 familyId로 변환 필요
  Stream<List<Map<String, dynamic>>> listenToNewRecordings(String familyId) {
    // Note: This method now requires familyId directly, not connectionCode
    // Call _resolveFamilyId() before using this method
    return _firestore
        .collection('families')
        .doc(familyId)
        .collection('recordings')
        .snapshots()
        .map((snapshot) {
      List<Map<String, dynamic>> allRecordings = [];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final recordings = data['recordings'] as List<dynamic>? ?? [];
        
        for (var recording in recordings) {
          allRecordings.add({
            'date': doc.id,
            'audioUrl': recording['audioUrl'],
            'photoUrl': recording['photoUrl'],
            'timestamp': recording['timestamp'],
            'elderlyName': recording['elderlyName'],
          });
        }
      }
      
      // 최신순 정렬
      allRecordings.sort((a, b) => 
          DateTime.parse(b['timestamp']).compareTo(DateTime.parse(a['timestamp']))
      );
      
      return allRecordings;
    });
  }
  
  /// 생존 신호 상태 확인 (보안 강화)
  Future<Map<String, dynamic>?> getSurvivalStatus(String connectionCode) async {
    try {
      final familyId = await _resolveFamilyId(connectionCode);
      if (familyId == null) {
        AppLogger.error('Failed to resolve family ID for connection code: $connectionCode', tag: 'ChildAppService');
        return null;
      }
      
      final doc = await _firestore.collection('families').doc(familyId).get();
      
      if (doc.exists) {
        final data = doc.data()!;
        return {
          'lastActivity': data['lastActivity'],
          'survivalAlert': data['survivalAlert'],
          'isActive': data['isActive'],
          'alertHours': data['settings']?['alertHours'] ?? 12,
        };
      }
      return null;
    } catch (e) {
      AppLogger.error('Failed to get survival status: $e', tag: 'ChildAppService');
      return null;
    }
  }
  
  /// 생존 신호 알람 해제 (보안 강화)
  Future<bool> clearSurvivalAlert(String connectionCode) async {
    try {
      final familyId = await _resolveFamilyId(connectionCode);
      if (familyId == null) {
        AppLogger.error('Failed to resolve family ID for connection code: $connectionCode', tag: 'ChildAppService');
        return false;
      }
      
      await _firestore.collection('families').doc(familyId).update({
        'survivalAlert.isActive': false,
        'survivalAlert.clearedAt': FieldValue.serverTimestamp(),
        'survivalAlert.clearedBy': 'Child App',
      });
      return true;
    } catch (e) {
      AppLogger.error('Failed to clear survival alert: $e', tag: 'ChildAppService');
      return false;
    }
  }
  
  /// 실시간 생존 신호 모니터링 (보안 강화) - familyId 직접 사용 필요
  Stream<Map<String, dynamic>> listenToSurvivalStatus(String familyId) {
    // Note: This method now requires familyId directly, not connectionCode
    // Call _resolveFamilyId() before using this method
    return _firestore
        .collection('families')
        .doc(familyId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data()!;
        return {
          'lastActivity': data['lastActivity'],
          'survivalAlert': data['survivalAlert'],
          'isActive': data['isActive'],
          'elderlyName': data['elderlyName'],
          'alertHours': data['settings']?['alertHours'] ?? 12,
        };
      }
      return {};
    });
  }
  
  /// 통계 데이터 가져오기 (보안 강화)
  Future<Map<String, dynamic>> getStatistics(String connectionCode) async {
    try {
      final familyId = await _resolveFamilyId(connectionCode);
      if (familyId == null) {
        AppLogger.error('Failed to resolve family ID for connection code: $connectionCode', tag: 'ChildAppService');
        return {};
      }
      
      // 지난 30일간의 녹음 데이터 분석
      final collection = await _firestore
          .collection('families')
          .doc(familyId)
          .collection('recordings')
          .get();
      
      int totalRecordings = 0;
      int daysWithRecordings = collection.docs.length;
      Map<String, int> dailyCounts = {};
      
      for (var doc in collection.docs) {
        final data = doc.data();
        final recordings = data['recordings'] as List<dynamic>? ?? [];
        totalRecordings += recordings.length;
        dailyCounts[doc.id] = recordings.length;
      }
      
      return {
        'totalRecordings': totalRecordings,
        'daysWithRecordings': daysWithRecordings,
        'dailyCounts': dailyCounts,
        'averagePerDay': daysWithRecordings > 0 ? totalRecordings / daysWithRecordings : 0,
      };
    } catch (e) {
      AppLogger.error('Failed to get statistics: $e', tag: 'ChildAppService');
      return {};
    }
  }
}