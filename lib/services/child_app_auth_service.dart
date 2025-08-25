import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';

/// Child App Authentication Service - handles Google Sign-in for family members
class ChildAppAuthService {
  static final ChildAppAuthService _instance = ChildAppAuthService._internal();
  factory ChildAppAuthService() => _instance;
  ChildAppAuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Sign in with Google (Child App)
  Future<User?> signInWithGoogle() async {
    try {
      AppLogger.info('Starting Google Sign-in for Child App', tag: 'ChildAppAuth');

      // Trigger Google Sign-in flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        AppLogger.info('User cancelled Google Sign-in', tag: 'ChildAppAuth');
        return null;
      }

      // Get Google auth credentials
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create Firebase credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with Google credential
      final UserCredential result = await _auth.signInWithCredential(credential);
      final User? user = result.user;

      if (user != null) {
        AppLogger.info('Child app Google Sign-in successful: ${user.uid}', tag: 'ChildAppAuth');
        
        // Create or update user profile
        await _createUserProfile(user);
        
        return user;
      }

      return null;
    } catch (e) {
      AppLogger.error('Child app Google Sign-in failed: $e', tag: 'ChildAppAuth');
      return null;
    }
  }

  /// Join family using connection code (Child App specific)
  Future<Map<String, dynamic>> joinFamilyWithCode(String connectionCode) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {
          'success': false,
          'error': 'User not authenticated'
        };
      }

      AppLogger.info('Child app joining family with code: $connectionCode', tag: 'ChildAppAuth');

      // Step 1: Resolve family ID from connection code
      final connectionDoc = await _firestore
          .collection('connection_codes')
          .doc(connectionCode)
          .get();

      if (!connectionDoc.exists) {
        return {
          'success': false,
          'error': 'Invalid connection code'
        };
      }

      final connectionData = connectionDoc.data()!;
      final familyId = connectionData['familyId'] as String;

      // Step 2: Get family information for display/approval
      final familyDoc = await _firestore
          .collection('families')
          .doc(familyId)
          .get();

      if (!familyDoc.exists) {
        return {
          'success': false,
          'error': 'Family not found'
        };
      }

      final familyData = familyDoc.data()!;
      
      // Step 3: Check if user is already a member
      final memberIds = List<String>.from(familyData['memberIds'] ?? []);
      if (memberIds.contains(user.uid)) {
        return {
          'success': true,
          'alreadyMember': true,
          'familyId': familyId,
          'familyData': familyData
        };
      }

      // Step 4: Add user to family (this triggers approval workflow)
      await _firestore.collection('families').doc(familyId).update({
        'memberIds': FieldValue.arrayUnion([user.uid]),
        'approved': null, // Reset approval status for new member
        'pendingApproval': {
          'userId': user.uid,
          'userEmail': user.email,
          'userName': user.displayName,
          'joinedAt': FieldValue.serverTimestamp(),
        }
      });

      AppLogger.info('Child app successfully joined family: $familyId', tag: 'ChildAppAuth');

      return {
        'success': true,
        'familyId': familyId,
        'familyData': familyData,
        'requiresApproval': true
      };

    } catch (e) {
      AppLogger.error('Failed to join family: $e', tag: 'ChildAppAuth');
      return {
        'success': false,
        'error': 'Failed to join family: $e'
      };
    }
  }

  /// Create or update user profile in Firestore
  Future<void> _createUserProfile(User user) async {
    try {
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'provider': 'google',
        'role': 'child',
        'createdAt': FieldValue.serverTimestamp(),
        'lastSignIn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      AppLogger.info('User profile created/updated for: ${user.uid}', tag: 'ChildAppAuth');
    } catch (e) {
      AppLogger.error('Failed to create user profile: $e', tag: 'ChildAppAuth');
    }
  }

  /// Sign out (Child App)
  Future<void> signOut() async {
    try {
      await Future.wait([
        _googleSignIn.signOut(),
        _auth.signOut(),
      ]);
      AppLogger.info('Child app sign out successful', tag: 'ChildAppAuth');
    } catch (e) {
      AppLogger.error('Child app sign out failed: $e', tag: 'ChildAppAuth');
    }
  }

  /// Get current user
  User? get currentUser => _auth.currentUser;
  
  /// Check if user is signed in
  bool get isSignedIn => _auth.currentUser != null;
  
  /// Listen to auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();
}