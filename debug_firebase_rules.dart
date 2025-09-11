import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Debug script to test Firebase rules and authentication
Future<void> main() async {
  try {
    // Initialize Firebase
    await Firebase.initializeApp();
    
    print('🔍 Starting Firebase Rules Debug');
    
    // Test authentication
    final auth = FirebaseAuth.instance;
    await auth.signInAnonymously();
    
    final user = auth.currentUser;
    print('✅ Authentication successful');
    print('   User ID: ${user?.uid}');
    print('   Is Anonymous: ${user?.isAnonymous}');
    
    final firestore = FirebaseFirestore.instance;
    
    // Test 1: Check connection_codes collection access
    print('\n🧪 Test 1: Connection codes access');
    try {
      final testCode = '9999';
      await firestore.collection('connection_codes').doc(testCode).set({
        'familyId': 'test-family-id',
        'elderlyName': 'Test Name',
        'createdAt': FieldValue.serverTimestamp(),
      });
      print('✅ Connection code creation: SUCCESS');
      
      // Try to read it back
      final doc = await firestore.collection('connection_codes').doc(testCode).get();
      if (doc.exists) {
        print('✅ Connection code read: SUCCESS');
        print('   Data: ${doc.data()}');
      } else {
        print('❌ Connection code read: FAILED - Document not found');
      }
      
      // Clean up
      await firestore.collection('connection_codes').doc(testCode).delete();
      print('✅ Connection code cleanup: SUCCESS');
      
    } catch (e) {
      print('❌ Connection code test: FAILED - $e');
    }
    
    // Test 2: Check families collection access
    print('\n🧪 Test 2: Families collection access');
    try {
      final testFamilyId = 'test-family-${DateTime.now().millisecondsSinceEpoch}';
      final testData = {
        'familyId': testFamilyId,
        'connectionCode': '1234',
        'elderlyName': 'Test Elder',
        'createdAt': FieldValue.serverTimestamp(),
        'deviceInfo': 'Debug Device',
        'isActive': true,
        'approved': null,
        'createdBy': user?.uid,
        'members': [user?.uid], // Using 'members' field
        'settings': {
          'survivalSignalEnabled': false,
          'familyContact': '',
          'alertHours': 12,
        }
      };
      
      await firestore.collection('families').doc(testFamilyId).set(testData);
      print('✅ Family document creation: SUCCESS');
      print('   Family ID: $testFamilyId');
      print('   Created by: ${user?.uid}');
      print('   Members: ${testData['members']}');
      
      // Try to read it back
      final doc = await firestore.collection('families').doc(testFamilyId).get();
      if (doc.exists) {
        print('✅ Family document read: SUCCESS');
        final data = doc.data() as Map<String, dynamic>;
        print('   Members field: ${data['members']}');
        print('   CreatedBy field: ${data['createdBy']}');
      } else {
        print('❌ Family document read: FAILED - Document not found');
      }
      
      // Test query operations
      print('\n🧪 Test 3: Query operations');
      
      // Test query by connectionCode
      try {
        final query1 = await firestore
            .collection('families')
            .where('connectionCode', isEqualTo: '1234')
            .limit(1)
            .get();
        print('✅ Query by connectionCode: SUCCESS');
        print('   Found ${query1.docs.length} documents');
      } catch (e) {
        print('❌ Query by connectionCode: FAILED - $e');
      }
      
      // Test query by isActive
      try {
        final query2 = await firestore
            .collection('families')
            .where('isActive', isEqualTo: true)
            .limit(1)
            .get();
        print('✅ Query by isActive: SUCCESS');
        print('   Found ${query2.docs.length} documents');
      } catch (e) {
        print('❌ Query by isActive: FAILED - $e');
      }
      
      // Test list operation (get all families)
      try {
        final query3 = await firestore
            .collection('families')
            .limit(5)
            .get();
        print('✅ List families: SUCCESS');
        print('   Found ${query3.docs.length} documents');
      } catch (e) {
        print('❌ List families: FAILED - $e');
      }
      
      // Clean up
      await firestore.collection('families').doc(testFamilyId).delete();
      print('✅ Family document cleanup: SUCCESS');
      
    } catch (e) {
      print('❌ Family document test: FAILED - $e');
      print('   Stack trace: ${StackTrace.current}');
    }
    
    // Test 4: Check current rules version
    print('\n🧪 Test 4: Current Firebase Rules Analysis');
    print('Rules should allow:');
    print('- Connection codes: read, create for authenticated users');
    print('- Families: read, write, list for authenticated users (current rules)');
    print('- Expected field: "members" array with user IDs');
    
    print('\n✅ Debug completed successfully');
    
  } catch (e) {
    print('❌ Debug failed: $e');
    print('   Stack trace: ${StackTrace.current}');
  }
}