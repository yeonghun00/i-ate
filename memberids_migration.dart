import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// memberIds Migration Script
/// Run this if any existing families need memberIds structure fixes
/// 
/// This script ensures all families have proper memberIds arrays with their creators
class MemberIdsMigration {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  /// Run the migration process
  Future<void> runMigration() async {
    print('🔄 MEMBERIDS MIGRATION STARTED');
    print('=' * 40);
    
    try {
      await _migrateFamilyMemberIds();
      print('\n✅ MIGRATION COMPLETED SUCCESSFULLY');
    } catch (e) {
      print('\n❌ MIGRATION FAILED: $e');
      rethrow;
    }
  }
  
  /// Migrate family documents to ensure proper memberIds structure
  Future<void> _migrateFamilyMemberIds() async {
    print('📋 Scanning families for memberIds issues...\n');
    
    // Get all active families
    final familiesSnapshot = await _firestore
        .collection('families')
        .where('isActive', isEqualTo: true)
        .get();
    
    if (familiesSnapshot.docs.isEmpty) {
      print('ℹ️  No active families found');
      return;
    }
    
    print('Found ${familiesSnapshot.docs.length} active families to check');
    
    int fixedCount = 0;
    int alreadyCorrectCount = 0;
    int errorCount = 0;
    
    for (final doc in familiesSnapshot.docs) {
      try {
        final familyId = doc.id;
        final data = doc.data();
        
        print('\n🔍 Checking family: $familyId');
        
        final createdBy = data['createdBy'] as String?;
        final currentMemberIds = List<String>.from(data['memberIds'] ?? []);
        
        bool needsUpdate = false;
        List<String> newMemberIds = [...currentMemberIds];
        
        // Check 1: Ensure memberIds field exists
        if (!data.containsKey('memberIds') || currentMemberIds.isEmpty) {
          print('   ⚠️  Missing or empty memberIds field');
          needsUpdate = true;
          
          if (createdBy != null) {
            newMemberIds = [createdBy];
            print('   ✨ Will create memberIds with creator: $createdBy');
          }
        }
        
        // Check 2: Ensure creator is in memberIds
        if (createdBy != null && !currentMemberIds.contains(createdBy)) {
          print('   ⚠️  Creator ($createdBy) not in memberIds');
          needsUpdate = true;
          newMemberIds.add(createdBy);
          print('   ✨ Will add creator to memberIds');
        }
        
        // Check 3: Remove any invalid/empty UIDs
        final validMemberIds = newMemberIds.where((uid) => uid.isNotEmpty && uid.length > 10).toList();
        if (validMemberIds.length != newMemberIds.length) {
          print('   ⚠️  Found invalid UIDs in memberIds');
          needsUpdate = true;
          newMemberIds = validMemberIds;
          print('   ✨ Will clean up invalid UIDs');
        }
        
        if (needsUpdate) {
          print('   🔧 Updating family with fixed memberIds: $newMemberIds');
          
          await _firestore.collection('families').doc(familyId).update({
            'memberIds': newMemberIds,
            'memberIdsMigratedAt': FieldValue.serverTimestamp(),
          });
          
          fixedCount++;
          print('   ✅ Family $familyId updated successfully');
        } else {
          print('   ✅ Family $familyId already has correct memberIds structure');
          alreadyCorrectCount++;
        }
        
      } catch (e) {
        print('   ❌ Error processing family ${doc.id}: $e');
        errorCount++;
      }
    }
    
    print('\n📊 MIGRATION SUMMARY');
    print('   Fixed: $fixedCount families');
    print('   Already correct: $alreadyCorrectCount families');
    print('   Errors: $errorCount families');
    print('   Total processed: ${familiesSnapshot.docs.length} families');
  }
  
  /// Validate the migration results
  Future<void> validateMigration() async {
    print('\n🔍 VALIDATING MIGRATION RESULTS');
    print('=' * 35);
    
    final familiesSnapshot = await _firestore
        .collection('families')
        .where('isActive', isEqualTo: true)
        .get();
    
    int validFamilies = 0;
    int invalidFamilies = 0;
    
    for (final doc in familiesSnapshot.docs) {
      final data = doc.data();
      final familyId = doc.id;
      final createdBy = data['createdBy'] as String?;
      final memberIds = List<String>.from(data['memberIds'] ?? []);
      
      bool isValid = true;
      List<String> issues = [];
      
      // Validation 1: memberIds exists and not empty
      if (memberIds.isEmpty) {
        issues.add('Empty memberIds');
        isValid = false;
      }
      
      // Validation 2: creator is in memberIds
      if (createdBy != null && !memberIds.contains(createdBy)) {
        issues.add('Creator not in memberIds');
        isValid = false;
      }
      
      // Validation 3: All UIDs are valid format
      for (final uid in memberIds) {
        if (uid.isEmpty || uid.length < 10) {
          issues.add('Invalid UID format: $uid');
          isValid = false;
        }
      }
      
      if (isValid) {
        validFamilies++;
        print('✅ $familyId: Valid (${memberIds.length} members)');
      } else {
        invalidFamilies++;
        print('❌ $familyId: ${issues.join(', ')}');
      }
    }
    
    print('\n📊 VALIDATION SUMMARY');
    print('   Valid families: $validFamilies');
    print('   Invalid families: $invalidFamilies');
    
    if (invalidFamilies == 0) {
      print('   🎉 All families have valid memberIds structure!');
    } else {
      print('   ⚠️  Some families still have issues - manual review needed');
    }
  }
  
  /// Dry run - show what would be changed without making changes
  Future<void> dryRun() async {
    print('🧪 DRY RUN - Showing what would be migrated');
    print('=' * 45);
    print('(No actual changes will be made)\n');
    
    final familiesSnapshot = await _firestore
        .collection('families')
        .where('isActive', isEqualTo: true)
        .get();
    
    if (familiesSnapshot.docs.isEmpty) {
      print('ℹ️  No active families found');
      return;
    }
    
    int wouldFixCount = 0;
    
    for (final doc in familiesSnapshot.docs) {
      final familyId = doc.id;
      final data = doc.data();
      final createdBy = data['createdBy'] as String?;
      final currentMemberIds = List<String>.from(data['memberIds'] ?? []);
      
      bool wouldUpdate = false;
      List<String> proposedMemberIds = [...currentMemberIds];
      
      print('Family: $familyId');
      print('  Current memberIds: $currentMemberIds');
      print('  Creator: $createdBy');
      
      if (!data.containsKey('memberIds') || currentMemberIds.isEmpty) {
        wouldUpdate = true;
        if (createdBy != null) {
          proposedMemberIds = [createdBy];
        }
      }
      
      if (createdBy != null && !currentMemberIds.contains(createdBy)) {
        wouldUpdate = true;
        proposedMemberIds.add(createdBy);
      }
      
      final validMemberIds = proposedMemberIds.where((uid) => uid.isNotEmpty && uid.length > 10).toList();
      if (validMemberIds.length != proposedMemberIds.length) {
        wouldUpdate = true;
        proposedMemberIds = validMemberIds;
      }
      
      if (wouldUpdate) {
        print('  🔧 WOULD UPDATE to: $proposedMemberIds');
        wouldFixCount++;
      } else {
        print('  ✅ No changes needed');
      }
      
      print('');
    }
    
    print('📊 DRY RUN SUMMARY');
    print('   Would fix: $wouldFixCount families');
    print('   Total families: ${familiesSnapshot.docs.length}');
  }
}

/// CLI interface for the migration tool
Future<void> main(List<String> args) async {
  final migration = MemberIdsMigration();
  
  if (args.isEmpty) {
    print('📝 memberIds Migration Tool');
    print('');
    print('Usage:');
    print('  dart memberids_migration.dart dryrun    # Show what would be changed');
    print('  dart memberids_migration.dart migrate   # Run the actual migration');
    print('  dart memberids_migration.dart validate  # Validate migration results');
    return;
  }
  
  final command = args[0].toLowerCase();
  
  switch (command) {
    case 'dryrun':
      await migration.dryRun();
      break;
      
    case 'migrate':
      print('⚠️  This will modify your Firebase data!');
      print('Make sure you have a backup and have tested on a dev environment first.');
      print('');
      
      // In a real implementation, you might want to add a confirmation prompt
      await migration.runMigration();
      break;
      
    case 'validate':
      await migration.validateMigration();
      break;
      
    default:
      print('❌ Unknown command: $command');
      print('Use: dryrun, migrate, or validate');
  }
}