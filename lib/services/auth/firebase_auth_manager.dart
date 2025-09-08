import 'package:firebase_auth/firebase_auth.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';

class FirebaseAuthManager {
  static final FirebaseAuthManager _instance = FirebaseAuthManager._internal();
  factory FirebaseAuthManager() => _instance;
  FirebaseAuthManager._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<bool> ensureAuthenticated({int maxRetries = 3}) async {
    if (_auth.currentUser != null) return true;

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        AppLogger.info('Firebase Auth attempt ${attempt + 1}/$maxRetries', tag: 'FirebaseAuthManager');
        await _auth.signInAnonymously();
        AppLogger.info('Firebase Auth successful', tag: 'FirebaseAuthManager');
        return true;
      } catch (e) {
        AppLogger.warning('Firebase Auth attempt ${attempt + 1} failed: $e', tag: 'FirebaseAuthManager');
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(milliseconds: 1000 * (attempt + 1)));
        }
      }
    }
    
    AppLogger.warning('All Firebase Auth attempts failed', tag: 'FirebaseAuthManager');
    return false;
  }

  User? get currentUser => _auth.currentUser;
  String? get currentUserId => _auth.currentUser?.uid;
}