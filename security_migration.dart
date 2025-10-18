// SECURITY MIGRATION SCRIPT
// This script migrates existing families to the new secure architecture
// by creating family_public documents for existing families.
//
// CRITICAL: This script is for the Firebase security vulnerability fix
// that separates public and private family data.

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class SecurityMigration {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  /// Migrate existing families to new secure architecture
  /// Creates family_public documents from existing families collection
  Future<void> migrateFamiliesToSecureArchitecture() async {
    try {
      print('🔒 STARTING SECURITY MIGRATION');
      print('This will create family_public documents for existing families');
      print('to fix the critical security vulnerability.\n');
      
      // Get all existing families
      final familiesQuery = await _firestore.collection('families').get();
      
      if (familiesQuery.docs.isEmpty) {
        print('✅ No families found to migrate.');
        return;
      }
      
      print('📊 Found ${familiesQuery.docs.length} families to migrate\n');
      
      int successCount = 0;
      int errorCount = 0;
      final errors = <String>[];
      
      // Process each family
      for (final familyDoc in familiesQuery.docs) {
        final familyId = familyDoc.id;
        final familyData = familyDoc.data();
        
        try {
          print('🔄 Processing family: $familyId (${familyData['elderlyName']})');
          
          // Check if family_public document already exists
          final publicDoc = await _firestore
              .collection('family_public')
              .doc(familyId)
              .get();
          
          if (publicDoc.exists) {
            print('   ⚠️  Public document already exists, skipping...');
            continue;
          }
          
          // Extract safe public data only
          final publicData = {
            'familyId': familyId,
            'elderlyName': familyData['elderlyName'] ?? 'Unknown',
            'createdAt': familyData['createdAt'] ?? FieldValue.serverTimestamp(),
            'isActive': familyData['isActive'] ?? true,
            'createdBy': familyData['createdBy'] ?? '',
          };
          
          // Create family_public document
          await _firestore
              .collection('family_public')
              .doc(familyId)
              .set(publicData);
          
          print('   ✅ Successfully created public document');
          successCount++;
          
        } catch (e) {
          print('   ❌ Error processing family $familyId: $e');
          errors.add('Family $familyId (${familyData['elderlyName']}): $e');
          errorCount++;
        }
      }
      
      // Print summary
      print('\n📋 MIGRATION SUMMARY:');
      print('✅ Successfully migrated: $successCount families');
      print('❌ Errors: $errorCount families');
      
      if (errors.isNotEmpty) {
        print('\n❌ ERROR DETAILS:');
        for (final error in errors) {
          print('   • $error');
        }
      }
      
      print('\n🔒 SECURITY STATUS:');
      if (errorCount == 0) {
        print('✅ All families successfully migrated to secure architecture');
        print('✅ Ready to deploy new Firebase rules');
      } else {
        print('⚠️  Some families failed to migrate');
        print('⚠️  Review errors before deploying new rules');
      }
      
    } catch (e) {
      print('💥 CRITICAL ERROR during migration: $e');
      rethrow;
    }
  }
  
  /// Verify migration integrity
  /// Checks that all families have corresponding public documents
  Future<void> verifyMigrationIntegrity() async {
    try {
      print('\n🔍 VERIFYING MIGRATION INTEGRITY...\n');
      
      // Get all families
      final familiesQuery = await _firestore.collection('families').get();
      final familyPublicQuery = await _firestore.collection('family_public').get();
      
      final familyIds = familiesQuery.docs.map((doc) => doc.id).toSet();
      final publicIds = familyPublicQuery.docs.map((doc) => doc.id).toSet();
      
      print('📊 Families count: ${familyIds.length}');
      print('📊 Public families count: ${publicIds.length}');
      
      // Check for missing public documents
      final missingPublic = familyIds.difference(publicIds);
      if (missingPublic.isNotEmpty) {
        print('\n❌ MISSING PUBLIC DOCUMENTS:');
        for (final familyId in missingPublic) {
          final familyDoc = await _firestore.collection('families').doc(familyId).get();
          final elderlyName = familyDoc.data()?['elderlyName'] ?? 'Unknown';
          print('   • $familyId ($elderlyName)');
        }
        print('\n⚠️  Migration is INCOMPLETE. Do not deploy new rules yet.');
        return;
      }
      
      // Check for orphaned public documents
      final orphanedPublic = publicIds.difference(familyIds);
      if (orphanedPublic.isNotEmpty) {
        print('\n⚠️  ORPHANED PUBLIC DOCUMENTS:');
        for (final familyId in orphanedPublic) {
          final publicDoc = await _firestore.collection('family_public').doc(familyId).get();
          final elderlyName = publicDoc.data()?['elderlyName'] ?? 'Unknown';
          print('   • $familyId ($elderlyName)');
        }
        print('   Note: These public documents have no corresponding private family data.');
      }
      
      // Verify data consistency
      print('\n🔍 VERIFYING DATA CONSISTENCY...');
      int consistentCount = 0;
      int inconsistentCount = 0;
      
      for (final familyId in familyIds) {
        final familyDoc = await _firestore.collection('families').doc(familyId).get();
        final publicDoc = await _firestore.collection('family_public').doc(familyId).get();
        
        if (!publicDoc.exists) continue;
        
        final familyData = familyDoc.data()!;
        final publicData = publicDoc.data()!;
        
        // Check key fields match
        final familyElderlyName = familyData['elderlyName'];
        final publicElderlyName = publicData['elderlyName'];
        
        if (familyElderlyName == publicElderlyName) {
          consistentCount++;
        } else {
          inconsistentCount++;
          print('   ⚠️  Data mismatch for $familyId: "$familyElderlyName" vs "$publicElderlyName"');
        }
      }
      
      print('✅ Consistent documents: $consistentCount');
      print('❌ Inconsistent documents: $inconsistentCount');
      
      // Final assessment
      if (missingPublic.isEmpty && inconsistentCount == 0) {
        print('\n🎉 MIGRATION VERIFICATION PASSED');
        print('✅ All families have corresponding public documents');
        print('✅ Data consistency verified');
        print('✅ Safe to deploy new Firebase rules');
      } else {
        print('\n⚠️  MIGRATION VERIFICATION FAILED');
        print('❌ Issues detected - fix before deploying new rules');
      }
      
    } catch (e) {
      print('💥 ERROR during verification: $e');
      rethrow;
    }
  }
  
  /// Print security status and next steps
  void printSecurityGuidance() {
    print('\n🔒 SECURITY DEPLOYMENT GUIDANCE:');
    print('');
    print('1. ✅ Run migration: dart security_migration.dart migrate');
    print('2. ✅ Verify integrity: dart security_migration.dart verify');
    print('3. 🚀 Deploy new rules: firebase deploy --only firestore:rules');
    print('4. 🧪 Test functionality: Verify app continues working');
    print('5. 🔍 Monitor logs: Check for any security rule violations');
    print('');
    print('⚠️  CRITICAL: Deploy rules immediately after migration');
    print('   The current rules have || true vulnerability!');
    print('');
    print('📁 NEW COLLECTIONS STRUCTURE:');
    print('   • family_public/{familyId} - Safe joining info (readable by all)');
    print('   • families/{familyId} - Sensitive data (members only)');
    print('   • connection_codes/{code} - Unchanged (maps to familyIds)');
    print('');
    print('🔒 RULES FILE TO DEPLOY:');
    print('   Use: firestore_secure_fixed.rules');
    print('');
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('🔒 FIREBASE SECURITY MIGRATION TOOL');
    print('');
    print('This tool fixes the critical security vulnerability in Firebase rules');
    print('by migrating to a secure architecture with separated collections.');
    print('');
    print('Usage:');
    print('  dart security_migration.dart migrate   - Run the migration');
    print('  dart security_migration.dart verify    - Verify migration integrity');
    print('  dart security_migration.dart guidance  - Show deployment guidance');
    return;
  }

  try {
    // Initialize Firebase
    await Firebase.initializeApp();
    
    final migration = SecurityMigration();
    final command = args[0].toLowerCase();
    
    switch (command) {
      case 'migrate':
        await migration.migrateFamiliesToSecureArchitecture();
        break;
        
      case 'verify':
        await migration.verifyMigrationIntegrity();
        break;
        
      case 'guidance':
        migration.printSecurityGuidance();
        break;
        
      default:
        print('❌ Unknown command: $command');
        print('Available commands: migrate, verify, guidance');
        exit(1);
    }
    
  } catch (e) {
    print('💥 FATAL ERROR: $e');
    exit(1);
  }
}