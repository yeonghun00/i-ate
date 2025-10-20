import 'package:encrypt/encrypt.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';

/// Service for encrypting sensitive data like GPS coordinates
/// Uses AES-256-GCM for symmetric encryption
///
/// SECURITY: Encryption key is DERIVED from familyId, NOT stored in Firestore
/// This prevents hackers from accessing both the key and encrypted data
class EncryptionService {
  /// Secret salt for key derivation (KEEP THIS SECRET!)
  /// In production, move this to environment variables or secure config
  static const String _keySalt = 'thanks_everyday_secure_salt_v1_2025';

  /// Derive a 256-bit encryption key from familyId
  ///
  /// Uses PBKDF2-like approach with SHA-256
  /// Both parent and child apps can derive the same key from familyId
  ///
  /// [familyId] The unique family identifier
  /// Returns base64-encoded 256-bit key
  static String deriveEncryptionKey(String familyId) {
    // Combine familyId with secret salt
    final input = '$familyId:$_keySalt';

    // Hash multiple times for better security (key stretching)
    var hash = sha256.convert(utf8.encode(input)).bytes;

    // Additional rounds of hashing (PBKDF2-like)
    for (int i = 0; i < 10000; i++) {
      hash = sha256.convert(hash).bytes;
    }

    // Take first 32 bytes (256 bits) for AES-256
    final keyBytes = Uint8List.fromList(hash.sublist(0, 32));

    return base64.encode(keyBytes);
  }

  /// Encrypt location data before storing in Firestore
  ///
  /// [latitude] GPS latitude coordinate
  /// [longitude] GPS longitude coordinate
  /// [address] Optional address string
  /// [base64Key] Base64-encoded 256-bit encryption key
  ///
  /// Returns map with 'encrypted' and 'iv' fields (both base64-encoded)
  static Map<String, String> encryptLocation({
    required double latitude,
    required double longitude,
    required String address,
    required String base64Key,
  }) {
    try {
      // Prepare data to encrypt
      final locationData = {
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
      };
      final plainText = json.encode(locationData);

      // Setup encryption
      final key = Key(base64.decode(base64Key));
      final iv = IV.fromSecureRandom(16); // Random IV for each encryption
      final encrypter = Encrypter(AES(key, mode: AESMode.gcm));

      // Encrypt
      final encrypted = encrypter.encrypt(plainText, iv: iv);

      return {
        'encrypted': encrypted.base64,
        'iv': iv.base64,
      };
    } catch (e) {
      print('⚠️ Encryption error: $e');
      rethrow;
    }
  }

  /// Decrypt location data (for testing purposes in parent app)
  /// Child app should implement its own decryption service
  ///
  /// [encryptedData] Base64-encoded encrypted data
  /// [ivBase64] Base64-encoded initialization vector
  /// [base64Key] Base64-encoded 256-bit encryption key
  ///
  /// Returns map with 'latitude', 'longitude', and 'address' fields
  static Map<String, dynamic> decryptLocation({
    required String encryptedData,
    required String ivBase64,
    required String base64Key,
  }) {
    try {
      // Setup decryption
      final key = Key(base64.decode(base64Key));
      final iv = IV.fromBase64(ivBase64);
      final encrypter = Encrypter(AES(key, mode: AESMode.gcm));

      // Decrypt
      final decrypted = encrypter.decrypt64(encryptedData, iv: iv);

      // Parse JSON
      final locationData = json.decode(decrypted) as Map<String, dynamic>;

      return {
        'latitude': locationData['latitude'] as double,
        'longitude': locationData['longitude'] as double,
        'address': locationData['address'] as String,
      };
    } catch (e) {
      print('⚠️ Decryption error: $e');
      rethrow;
    }
  }
}
