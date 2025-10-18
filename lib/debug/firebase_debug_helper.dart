import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';

class FirebaseDebugHelper {
  static void enableDetailedLogging() {
    // Enable Firestore debug logging
    FirebaseFirestore.setLoggingEnabled(true);
    AppLogger.info('Firebase detailed logging enabled', tag: 'FirebaseDebug');
  }

  static Future<void> testUserAuthentication() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        AppLogger.info('✅ User authenticated: ${user.uid}', tag: 'FirebaseDebug');
        AppLogger.info('  - Anonymous: ${user.isAnonymous}', tag: 'FirebaseDebug');
        AppLogger.info('  - Provider: ${user.providerData.map((p) => p.providerId).join(", ")}', tag: 'FirebaseDebug');
      } else {
        AppLogger.error('❌ No authenticated user found', tag: 'FirebaseDebug');
      }
    } catch (e) {
      AppLogger.error('❌ Error checking authentication: $e', tag: 'FirebaseDebug');
    }
  }

  static Future<void> testConnectionCodeRead() async {
    try {
      AppLogger.info('🔍 Testing connection_codes read permission...', tag: 'FirebaseDebug');
      
      final doc = await FirebaseFirestore.instance
          .collection('connection_codes')
          .doc('test-code')
          .get();
      
      AppLogger.info('✅ Connection codes read permission OK', tag: 'FirebaseDebug');
    } catch (e) {
      AppLogger.error('❌ Connection codes read failed: $e', tag: 'FirebaseDebug');
    }
  }

  static Future<void> testFamilyPublicWrite() async {
    try {
      AppLogger.info('🔍 Testing family_public write permission...', tag: 'FirebaseDebug');
      
      await FirebaseFirestore.instance
          .collection('family_public')
          .doc('test-family-id')
          .set({
            'familyId': 'test-family-id',
            'connectionCode': 'TEST',
            'elderlyName': 'Test User',
            'createdBy': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
            'createdAt': FieldValue.serverTimestamp(),
          });
      
      AppLogger.info('✅ Family public write permission OK', tag: 'FirebaseDebug');
      
      // Clean up test document
      await FirebaseFirestore.instance
          .collection('family_public')
          .doc('test-family-id')
          .delete();
      
    } catch (e) {
      AppLogger.error('❌ Family public write failed: $e', tag: 'FirebaseDebug');
    }
  }

  static Future<void> runFullDiagnostics() async {
    AppLogger.info('🚀 Starting Firebase diagnostics...', tag: 'FirebaseDebug');
    
    await testUserAuthentication();
    await testConnectionCodeRead();
    await testFamilyPublicWrite();
    
    AppLogger.info('✅ Firebase diagnostics complete', tag: 'FirebaseDebug');
  }
}

