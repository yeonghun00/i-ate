import 'package:cloud_firestore/cloud_firestore.dart';
// Firebase Storage import removed - not currently used
import 'package:thanks_everyday/core/utils/app_logger.dart';

class ChildAppService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // Firebase Storage removed - not currently used in this service
  
  /// 가족 코드 입력하여 어르신 정보 가져오기
  Future<Map<String, dynamic>?> getFamilyInfo(String familyCode) async {
    try {
      final doc = await _firestore.collection('families').doc(familyCode).get();
      
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      AppLogger.error('Failed to get family info: $e', tag: 'ChildAppService');
      return null;
    }
  }
  
  /// 가족 코드 승인/거부
  Future<bool> approveFamilyCode(String familyCode, bool approved) async {
    try {
      await _firestore.collection('families').doc(familyCode).update({
        'approved': approved,
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': 'Child App', // 누가 승인했는지
      });
      return true;
    } catch (e) {
      AppLogger.error('Failed to approve family code: $e', tag: 'ChildAppService');
      return false;
    }
  }
  
  /// 어르신의 모든 녹음 데이터 가져오기
  Future<List<Map<String, dynamic>>> getAllRecordings(String familyCode) async {
    try {
      final collection = await _firestore
          .collection('families')
          .doc(familyCode)
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
  
  /// 특정 날짜의 녹음 데이터 가져오기
  Future<List<Map<String, dynamic>>> getRecordingsByDate(
    String familyCode, 
    String date
  ) async {
    try {
      final doc = await _firestore
          .collection('families')
          .doc(familyCode)
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
  
  /// 실시간으로 새 녹음 듣기
  Stream<List<Map<String, dynamic>>> listenToNewRecordings(String familyCode) {
    return _firestore
        .collection('families')
        .doc(familyCode)
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
  
  /// 생존 신호 상태 확인
  Future<Map<String, dynamic>?> getSurvivalStatus(String familyCode) async {
    try {
      final doc = await _firestore.collection('families').doc(familyCode).get();
      
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
  
  /// 생존 신호 알람 해제
  Future<bool> clearSurvivalAlert(String familyCode) async {
    try {
      await _firestore.collection('families').doc(familyCode).update({
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
  
  /// 실시간 생존 신호 모니터링
  Stream<Map<String, dynamic>> listenToSurvivalStatus(String familyCode) {
    return _firestore
        .collection('families')
        .doc(familyCode)
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
  
  /// 통계 데이터 가져오기
  Future<Map<String, dynamic>> getStatistics(String familyCode) async {
    try {
      // 지난 30일간의 녹음 데이터 분석
      final collection = await _firestore
          .collection('families')
          .doc(familyCode)
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