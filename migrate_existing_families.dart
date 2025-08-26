import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Data Migration Script for Family Safety App Security Update
/// 
/// This script migrates existing family documents to include the required
/// security fields: createdBy, memberIds, and connection_codes lookup.
/// 
/// IMPORTANT: Run this script BEFORE deploying the new security rules
/// to ensure backward compatibility.

class FamilySecurityMigration {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  /// Run the complete migration process
  Future<void> runMigration() async {
    print('🚀 Starting Family Security Migration...\n');
    
    try {
      // Step 1: Migrate existing family documents
      await _migrateFamilyDocuments();
      
      // Step 2: Create connection_codes collection for existing families
      await _createConnectionCodesLookup();
      
      // Step 3: Validate migration results
      await _validateMigration();
      
      print('\n✅ Migration completed successfully!');
      print('📋 Summary:');
      print('   - All families now have memberIds arrays');
      print('   - All families have createdBy fields');
      print('   - Connection codes lookup collection created');
      print('   - Ready for secure Firestore rules deployment');
      
    } catch (e, stackTrace) {
      print('❌ Migration failed: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  /// Migrate existing family documents to include security fields
  Future<void> _migrateFamilyDocuments() async {
    print('📄 Step 1: Migrating family documents...');
    
    final familiesSnapshot = await _firestore.collection('families').get();
    print('   Found ${familiesSnapshot.docs.length} family documents to migrate');
    
    int migratedCount = 0;
    int skippedCount = 0;
    
    for (final doc in familiesSnapshot.docs) {
      try {
        final data = doc.data();
        final familyId = doc.id;
        
        Map<String, dynamic> updates = {};
        bool needsUpdate = false;
        
        // Check if createdBy field exists
        if (!data.containsKey('createdBy')) {
          // For anonymous parent app users, we can't know the actual UID
          // Use a migration placeholder that can be updated later
          updates['createdBy'] = 'migration_anonymous';
          needsUpdate = true;
          print('   - Adding createdBy to family $familyId');
        }
        
        // Check if memberIds field exists
        if (!data.containsKey('memberIds')) {
          final createdBy = updates['createdBy'] ?? data['createdBy'] ?? 'migration_anonymous';
          updates['memberIds'] = [createdBy];
          needsUpdate = true;
          print('   - Adding memberIds to family $familyId');
        } else {
          // Ensure memberIds is an array and includes createdBy
          final memberIds = data['memberIds'];
          final createdBy = updates['createdBy'] ?? data['createdBy'] ?? 'migration_anonymous';
          
          if (memberIds is! List) {
            updates['memberIds'] = [createdBy];
            needsUpdate = true;
            print('   - Converting memberIds to array for family $familyId');
          } else if (!memberIds.contains(createdBy)) {
            updates['memberIds'] = FieldValue.arrayUnion([createdBy]);
            needsUpdate = true;
            print('   - Adding createdBy to memberIds for family $familyId');
          }
        }
        
        // Add migration timestamp
        if (needsUpdate) {
          updates['migratedAt'] = FieldValue.serverTimestamp();
          updates['migrationVersion'] = '1.0.0';
          
          await doc.reference.update(updates);
          migratedCount++;
          print('   ✅ Migrated family $familyId');
        } else {
          skippedCount++;
          print('   ⏭️  Skipped family $familyId (already migrated)');
        }
        
      } catch (e) {
        print('   ❌ Failed to migrate family ${doc.id}: $e');
        // Continue with other families
      }
    }
    
    print('   📊 Migration results: $migratedCount migrated, $skippedCount skipped\n');
  }
  
  /// Create connection_codes lookup collection for existing families
  Future<void> _createConnectionCodesLookup() async {
    print('🔗 Step 2: Creating connection codes lookup...');
    
    final familiesSnapshot = await _firestore.collection('families').get();
    int createdCount = 0;
    int skippedCount = 0;
    
    for (final doc in familiesSnapshot.docs) {
      try {
        final data = doc.data();
        final familyId = doc.id;
        final connectionCode = data['connectionCode'] as String?;
        final elderlyName = data['elderlyName'] as String?;
        final createdBy = data['createdBy'] as String?;
        
        if (connectionCode == null) {
          print('   ⚠️  Family $familyId has no connection code, skipping');
          skippedCount++;
          continue;
        }
        
        // Check if connection code document already exists
        final connectionDoc = await _firestore
            .collection('connection_codes')
            .doc(connectionCode)
            .get();
            
        if (connectionDoc.exists) {
          print('   ⏭️  Connection code $connectionCode already exists, skipping');
          skippedCount++;
          continue;
        }
        
        // Create connection code lookup document
        await _firestore.collection('connection_codes').doc(connectionCode).set({
          'familyId': familyId,
          'elderlyName': elderlyName ?? 'Unknown',
          'createdBy': createdBy ?? 'migration_anonymous',
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 365)), // 1 year for migrated codes
          ),
          'migrated': true,
          'migrationVersion': '1.0.0',
        });
        
        createdCount++;
        print('   ✅ Created connection code lookup for $connectionCode -> $familyId');
        
      } catch (e) {
        print('   ❌ Failed to create connection code for family ${doc.id}: $e');
        // Continue with other families
      }
    }
    
    print('   📊 Connection codes results: $createdCount created, $skippedCount skipped\n');
  }
  
  /// Validate that the migration was successful
  Future<void> _validateMigration() async {
    print('🔍 Step 3: Validating migration...');
    
    // Check families collection
    final familiesSnapshot = await _firestore.collection('families').get();
    int validFamilies = 0;
    int invalidFamilies = 0;
    
    for (final doc in familiesSnapshot.docs) {
      final data = doc.data();
      final hasCreatedBy = data.containsKey('createdBy');
      final hasMemberIds = data.containsKey('memberIds');
      final memberIdsValid = data['memberIds'] is List && (data['memberIds'] as List).isNotEmpty;
      
      if (hasCreatedBy && hasMemberIds && memberIdsValid) {
        validFamilies++;
      } else {
        invalidFamilies++;
        print('   ⚠️  Family ${doc.id} validation failed:');
        print('      - Has createdBy: $hasCreatedBy');
        print('      - Has memberIds: $hasMemberIds');
        print('      - MemberIds valid: $memberIdsValid');
      }
    }
    
    // Check connection_codes collection
    final connectionCodesSnapshot = await _firestore.collection('connection_codes').get();
    
    print('   📊 Validation results:');
    print('      - Valid families: $validFamilies');
    print('      - Invalid families: $invalidFamilies');
    print('      - Connection codes created: ${connectionCodesSnapshot.docs.length}');
    
    if (invalidFamilies > 0) {
      throw Exception('Migration validation failed: $invalidFamilies families are invalid');
    }
    
    print('   ✅ All validations passed!');
  }
}

/// Main migration function - can be called from a script or admin panel
Future<void> main() async {
  // Initialize Firebase (you may need to configure this for your project)
  await Firebase.initializeApp();
  
  print('🔐 Family Safety App - Security Migration Script');
  print('==============================================\n');
  
  // Optionally authenticate as admin user
  // await FirebaseAuth.instance.signInAnonymously();
  
  final migration = FamilySecurityMigration();
  await migration.runMigration();
}

/// Rollback function in case migration needs to be reverted
class FamilyMigrationRollback {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  Future<void> rollbackMigration() async {
    print('🔄 Starting migration rollback...\n');
    
    try {
      // Remove migration fields from families
      await _rollbackFamilyDocuments();
      
      // Delete connection_codes collection
      await _deleteConnectionCodes();
      
      print('\n✅ Rollback completed successfully!');
      
    } catch (e, stackTrace) {
      print('❌ Rollback failed: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  Future<void> _rollbackFamilyDocuments() async {
    print('📄 Rolling back family documents...');
    
    final familiesSnapshot = await _firestore.collection('families').get();
    int rolledBackCount = 0;
    
    for (final doc in familiesSnapshot.docs) {
      try {
        final data = doc.data();
        
        // Only rollback if it was migrated by our script
        if (data.containsKey('migratedAt') && data.containsKey('migrationVersion')) {
          await doc.reference.update({
            'createdBy': FieldValue.delete(),
            'memberIds': FieldValue.delete(),
            'migratedAt': FieldValue.delete(),
            'migrationVersion': FieldValue.delete(),
          });
          
          rolledBackCount++;
          print('   ✅ Rolled back family ${doc.id}');
        }
        
      } catch (e) {
        print('   ❌ Failed to rollback family ${doc.id}: $e');
      }
    }
    
    print('   📊 Rollback results: $rolledBackCount families rolled back\n');
  }
  
  Future<void> _deleteConnectionCodes() async {
    print('🗑️  Deleting connection codes...');
    
    final connectionCodesSnapshot = await _firestore.collection('connection_codes').get();
    int deletedCount = 0;
    
    for (final doc in connectionCodesSnapshot.docs) {
      try {
        final data = doc.data();
        
        // Only delete if it was created by migration
        if (data['migrated'] == true) {
          await doc.reference.delete();
          deletedCount++;
          print('   ✅ Deleted connection code ${doc.id}');
        }
        
      } catch (e) {
        print('   ❌ Failed to delete connection code ${doc.id}: $e');
      }
    }
    
    print('   📊 Deletion results: $deletedCount connection codes deleted\n');
  }
}